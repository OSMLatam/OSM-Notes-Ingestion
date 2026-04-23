-- Functions and views for durable OSM user identity.
--
-- Confidence (osm_user_id_link.confidence):
--   certain: mapping observed from ingestion (API/planet path, insert_note_comment).
--   inferred_username_change / inferred_recreation: reserved for future jobs
--     (not auto-set by current pipeline).
--   manual: operator or script after review.
--   rejected: invalid link (kept for audit).
--
-- Suggestions (osm_identity_suggestion) are not canonical; they flag possible
-- same-person links when a username is reused (low confidence).
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-23

CREATE OR REPLACE FUNCTION osm_record_identity_suggestion_if_needed(
  p_my_identity UUID,
  p_my_user_id INTEGER,
  p_username VARCHAR(256),
  p_source VARCHAR(64)
)
RETURNS VOID
LANGUAGE plpgsql
AS $fn$
DECLARE
  m_other_identity UUID;
  m_other_uid INTEGER;
  m_lo UUID;
  m_hi UUID;
BEGIN
  IF p_my_identity IS NULL
   OR p_my_user_id IS NULL
   OR p_username IS NULL
  THEN
    RETURN;
  END IF;

  SELECT
   l2.identity_id,
   u2.user_id
   INTO m_other_identity, m_other_uid
  FROM users AS u2
  INNER JOIN osm_user_id_link AS l2
   ON l2.user_id = u2.user_id
   AND l2.valid_to IS NULL
  WHERE u2.username = p_username
   AND u2.user_id <> p_my_user_id
  LIMIT 1;

  IF m_other_identity IS NULL
   OR m_other_identity = p_my_identity
  THEN
    RETURN;
  END IF;

  m_lo := LEAST(p_my_identity, m_other_identity);
  m_hi := GREATEST(p_my_identity, m_other_identity);

  INSERT INTO osm_identity_suggestion (
   identity_id_low,
   identity_id_high,
   username,
   incoming_user_id,
   existing_user_id,
   reason,
   confidence,
   status,
   source_process,
   created_at,
   last_seen_at
  ) VALUES (
   m_lo,
   m_hi,
   p_username,
   p_my_user_id,
   m_other_uid,
   'username_reused_by_different_user_id',
   'low',
   'open',
   p_source,
   CURRENT_TIMESTAMP,
   CURRENT_TIMESTAMP
  ) ON CONFLICT (
   identity_id_low,
   identity_id_high,
   reason,
   source_process
  ) DO UPDATE SET
   last_seen_at = CURRENT_TIMESTAMP,
   username = EXCLUDED.username,
   incoming_user_id = EXCLUDED.incoming_user_id,
   existing_user_id = EXCLUDED.existing_user_id;
END;
$fn$;
COMMENT ON FUNCTION osm_record_identity_suggestion_if_needed IS
  'If username is bound to another user_id, record a low-confidence merge hint';

CREATE OR REPLACE FUNCTION osm_upsert_user_identity(
  p_user_id INTEGER,
  p_username VARCHAR(256),
  p_source VARCHAR(64),
  p_observed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $fn$
DECLARE
  m_result UUID;
  m_observed TIMESTAMP WITH TIME ZONE;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (
   SELECT 1
   FROM users AS u
   WHERE u.user_id = p_user_id
  ) THEN
    RETURN NULL;
  END IF;

  m_observed := COALESCE(p_observed_at, CURRENT_TIMESTAMP);

  SELECT l.identity_id
   INTO m_result
  FROM osm_user_id_link AS l
  WHERE l.user_id = p_user_id
   AND l.valid_to IS NULL
  LIMIT 1;

  IF m_result IS NOT NULL THEN
    UPDATE osm_user_id_link AS l
    SET last_observed_at = GREATEST(l.last_observed_at, m_observed)
    WHERE l.user_id = p_user_id
     AND l.valid_to IS NULL;

    PERFORM osm_record_identity_suggestion_if_needed(
     m_result,
     p_user_id,
     p_username,
     p_source
    );
    RETURN m_result;
  END IF;

  m_result := gen_random_uuid();
  INSERT INTO osm_user_identity (identity_id, created_at)
  VALUES (m_result, m_observed);

  INSERT INTO osm_user_id_link (
   identity_id,
   user_id,
   valid_from,
   valid_to,
   confidence,
   source_process,
   first_observed_at,
   last_observed_at
  ) VALUES (
   m_result,
   p_user_id,
   m_observed,
   NULL,
   'certain',
   p_source,
   m_observed,
   m_observed
  );

  INSERT INTO osm_identity_lifecycle_event (
   identity_id,
   event_type,
   event_time,
   source_process,
   details
  ) VALUES (
   m_result,
   'created',
   m_observed,
   p_source,
   jsonb_build_object('user_id', p_user_id)
  );

  INSERT INTO osm_identity_lifecycle_event (
   identity_id,
   event_type,
   event_time,
   source_process,
   details
  ) VALUES (
   m_result,
   'user_id_link_opened',
   m_observed,
   p_source,
   jsonb_build_object('user_id', p_user_id)
  );

  PERFORM osm_record_identity_suggestion_if_needed(
   m_result,
   p_user_id,
   p_username,
   p_source
  );
  RETURN m_result;
END;
$fn$;
COMMENT ON FUNCTION osm_upsert_user_identity IS
  'Ensures an identity link for this user_id; records username collision hints';

CREATE OR REPLACE VIEW v_osm_user_id_current_identity AS
SELECT
 l.user_id,
 l.identity_id,
 l.confidence,
 l.first_observed_at,
 l.last_observed_at,
 l.source_process AS link_source_process
FROM osm_user_id_link AS l
WHERE l.valid_to IS NULL;
COMMENT ON VIEW v_osm_user_id_current_identity IS
  'Current OSM user_id to logical identity_id (for API reads)';

CREATE OR REPLACE VIEW v_osm_user_id_current_with_username AS
SELECT
 u.user_id,
 u.username,
 l.identity_id,
 l.confidence,
 l.first_observed_at,
 l.last_observed_at,
 l.link_source_process
FROM users AS u
INNER JOIN v_osm_user_id_current_identity AS l
 ON l.user_id = u.user_id;
COMMENT ON VIEW v_osm_user_id_current_with_username IS
  'users row joined to current identity link; preferred API read surface';
