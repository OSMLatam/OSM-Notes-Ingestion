-- Unit tests: osm_upsert_user_identity and related durable identity rules.
-- Requires: base tables, osm_user_identity_23_createFunctionsAndViews applied.
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-23

BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  m_id_88020 UUID;
  v_id UUID;
  v_id_b UUID;
  m_cnt INTEGER;
  m_sug INTEGER;
BEGIN
  -- Isolated user ids (unlikely to clash with real data in a dev DB)
  INSERT INTO users (user_id, username)
  VALUES
    (88020, 'oi_t88020'),
    (88022, 'oi_hold88022'),
    (88023, 'oi_other88023')
  ON CONFLICT (user_id) DO UPDATE
    SET username = EXCLUDED.username;

  m_id_88020 := osm_upsert_user_identity(
    88020,
    'oi_t88020',
    'osm_user_identity_upsert.test',
    CURRENT_TIMESTAMP
  );
  IF m_id_88020 IS NULL THEN
    RAISE EXCEPTION 'Test failed: first upsert should return identity id';
  END IF;

  SELECT COUNT(*)
   INTO m_cnt
  FROM osm_identity_lifecycle_event
  WHERE identity_id = m_id_88020
   AND event_type IN ('created', 'user_id_link_opened');
  IF m_cnt <> 2 THEN
    RAISE EXCEPTION
      'Test failed: expected 2 bootstrap lifecycle events, got %',
      m_cnt;
  END IF;

  m_id_88020 := osm_upsert_user_identity(
    88020,
    'oi_t88020',
    'osm_user_identity_upsert.test',
    CURRENT_TIMESTAMP
  );
  SELECT COUNT(*)
   INTO m_cnt
  FROM osm_identity_lifecycle_event
  WHERE identity_id = m_id_88020;
  IF m_cnt <> 2 THEN
    RAISE EXCEPTION
      'Test failed: repeat upsert should not add lifecycle rows, count=%',
      m_cnt;
  END IF;

  v_id := osm_upsert_user_identity(
    88022,
    'oi_hold88022',
    'osm_user_identity_upsert.test',
    CURRENT_TIMESTAMP
  );
  v_id_b := osm_upsert_user_identity(
    88023,
    'oi_other88023',
    'osm_user_identity_upsert.test',
    CURRENT_TIMESTAMP
  );
  IF v_id = v_id_b THEN
    RAISE EXCEPTION 'Test failed: distinct users should not share identity';
  END IF;

  PERFORM osm_upsert_user_identity(
    88023,
    'oi_hold88022',
    'osm_user_identity_upsert.test',
    CURRENT_TIMESTAMP
  );
  SELECT COUNT(*)
   INTO m_sug
  FROM osm_identity_suggestion
  WHERE reason = 'username_reused_by_different_user_id'
   AND (identity_id_low = LEAST(v_id, v_id_b)
   AND identity_id_high = GREATEST(v_id, v_id_b));
  IF m_sug < 1 THEN
    RAISE EXCEPTION
      'Test failed: expected username collision suggestion, got %',
      m_sug;
  END IF;

  SELECT COUNT(*)
   INTO m_cnt
  FROM v_osm_user_id_current_with_username
  WHERE user_id = 88020
   AND identity_id = m_id_88020
   AND username = 'oi_t88020';
  IF m_cnt <> 1 THEN
    RAISE EXCEPTION
      'Test failed: v_osm_user_id_current_with_username row missing (%)',
      m_cnt;
  END IF;

  RAISE NOTICE 'osm_user_identity_upsert tests passed';
END
$$;

ROLLBACK;
