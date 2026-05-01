-- Moves data from sync tables to main tables after consolidation.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-23

-- Move notes from sync to main tables
SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 'Moving notes from sync to main tables' AS Text;

INSERT INTO notes (note_id, latitude, longitude, created_at, status, closed_at, id_country)
SELECT note_id, latitude, longitude, created_at, status, closed_at, id_country
FROM notes_sync
ON CONFLICT (note_id) DO UPDATE SET
 latitude = EXCLUDED.latitude,
 longitude = EXCLUDED.longitude,
 created_at = EXCLUDED.created_at,
 status = EXCLUDED.status,
 closed_at = EXCLUDED.closed_at,
 id_country = EXCLUDED.id_country;

SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 COUNT(1) AS Qty,
 'Moved notes to main table' AS Text
FROM notes_sync;

-- Insert missing users first
SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 'Inserting missing users' AS Text;

CREATE TABLE IF NOT EXISTS user_identity_history (
 id SERIAL PRIMARY KEY,
 user_id INTEGER NOT NULL,
 username VARCHAR(256) NOT NULL,
 source_process VARCHAR(64) NOT NULL,
 first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS user_identity_conflicts (
 id SERIAL PRIMARY KEY,
 username VARCHAR(256) NOT NULL,
 incoming_user_id INTEGER NOT NULL,
 existing_user_id INTEGER NOT NULL,
 source_process VARCHAR(64) NOT NULL,
 detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 times_seen INTEGER DEFAULT 1,
 status VARCHAR(32) DEFAULT 'pending_review'
);
CREATE UNIQUE INDEX IF NOT EXISTS user_identity_history_uniq
 ON user_identity_history (user_id, username);
CREATE UNIQUE INDEX IF NOT EXISTS user_identity_conflicts_uniq
 ON user_identity_conflicts
 (username, incoming_user_id, existing_user_id, source_process);

INSERT INTO user_identity_history (
 user_id, username, source_process, first_seen, last_seen
)
SELECT DISTINCT
 id_user,
 username,
 'processPlanetNotes',
 CURRENT_TIMESTAMP,
 CURRENT_TIMESTAMP
FROM note_comments_sync
WHERE id_user IS NOT NULL
 AND username IS NOT NULL
ON CONFLICT (user_id, username) DO UPDATE SET
 last_seen = CURRENT_TIMESTAMP,
 source_process = EXCLUDED.source_process;

INSERT INTO users (user_id, username)
SELECT id_user, MIN(username) AS username
FROM note_comments_sync AS nc
WHERE id_user IS NOT NULL
  AND username IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM users AS u
    WHERE u.user_id = nc.id_user
  )
  AND NOT EXISTS (
    SELECT 1
    FROM users AS u
    WHERE u.username = nc.username
      AND u.user_id <> nc.id_user
  )
GROUP BY id_user
ON CONFLICT (user_id) DO UPDATE SET
 username = EXCLUDED.username
WHERE NOT EXISTS (
  SELECT 1
  FROM users u2
  WHERE u2.username = EXCLUDED.username
    AND u2.user_id <> users.user_id
);

-- Log skipped username conflicts to preserve observability.
INSERT INTO logs (message)
SELECT DISTINCT
  'WARNING: Username conflict skipped in users upsert. username='
  || quote_literal(nc.username)
  || ', incoming_user_id='
  || nc.id_user
  || ', existing_user_id='
  || u.user_id
FROM note_comments_sync nc
INNER JOIN users u ON u.username = nc.username
WHERE nc.id_user IS NOT NULL
  AND nc.username IS NOT NULL
  AND u.user_id <> nc.id_user;

INSERT INTO user_identity_conflicts (
 username,
 incoming_user_id,
 existing_user_id,
 source_process,
 detected_at,
 last_seen,
 times_seen
)
SELECT DISTINCT
 nc.username,
 nc.id_user,
 u.user_id,
 'processPlanetNotes',
 CURRENT_TIMESTAMP,
 CURRENT_TIMESTAMP,
 1
FROM note_comments_sync nc
INNER JOIN users u ON u.username = nc.username
WHERE nc.id_user IS NOT NULL
 AND nc.username IS NOT NULL
 AND u.user_id <> nc.id_user
ON CONFLICT (username, incoming_user_id, existing_user_id, source_process)
 DO UPDATE SET
 last_seen = CURRENT_TIMESTAMP,
 times_seen = user_identity_conflicts.times_seen + 1;

-- Durable identity (match processAPINotes bulk path).
WITH missing AS (
 SELECT DISTINCT nc.id_user
 FROM note_comments_sync nc
 WHERE nc.id_user IS NOT NULL
  AND EXISTS (
   SELECT 1
   FROM users uu
   WHERE uu.user_id = nc.id_user
  )
  AND NOT EXISTS (
   SELECT 1
   FROM osm_user_id_link l
   WHERE l.user_id = nc.id_user
    AND l.valid_to IS NULL
  )
),
paired AS (
 SELECT
  m.id_user,
  gen_random_uuid() AS identity_id
 FROM missing m
),
ins_ident AS (
 INSERT INTO osm_user_identity (identity_id, created_at)
 SELECT p.identity_id, CURRENT_TIMESTAMP
 FROM paired p
),
ins_link AS (
 INSERT INTO osm_user_id_link (
  identity_id,
  user_id,
  valid_from,
  valid_to,
  confidence,
  source_process,
  first_observed_at,
  last_observed_at
 )
 SELECT
  p.identity_id,
  p.id_user,
  CURRENT_TIMESTAMP,
  NULL,
  'certain',
  'processPlanetNotes',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
 FROM paired p
),
ins_life AS (
 INSERT INTO osm_identity_lifecycle_event (
  identity_id,
  event_type,
  event_time,
  source_process,
  details
 )
 SELECT
  p.identity_id,
  ev.event_type,
  CURRENT_TIMESTAMP,
  'processPlanetNotes',
  jsonb_build_object('user_id', p.id_user)
 FROM paired p
 CROSS JOIN LATERAL (
  VALUES
   ('created'::VARCHAR(64)),
   ('user_id_link_opened'::VARCHAR(64))
 ) AS ev (event_type)
)
SELECT 1;

UPDATE osm_user_id_link l
SET last_observed_at = GREATEST(
 l.last_observed_at,
 CURRENT_TIMESTAMP
)
WHERE l.valid_to IS NULL
 AND l.user_id IN (
  SELECT DISTINCT nc.id_user
  FROM note_comments_sync nc
  WHERE nc.id_user IS NOT NULL
 );

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
)
SELECT DISTINCT ON (
 LEAST(l1.identity_id, l2.identity_id),
 GREATEST(l1.identity_id, l2.identity_id),
 nc.id_user,
 u.user_id
)
 LEAST(l1.identity_id, l2.identity_id),
 GREATEST(l1.identity_id, l2.identity_id),
 nc.username,
 nc.id_user,
 u.user_id,
 'username_reused_by_different_user_id',
 'low',
 'open',
 'processPlanetNotes',
 CURRENT_TIMESTAMP,
 CURRENT_TIMESTAMP
FROM note_comments_sync nc
INNER JOIN users u
 ON u.username = nc.username
AND u.user_id <> nc.id_user
INNER JOIN osm_user_id_link l1
 ON l1.user_id = nc.id_user
AND l1.valid_to IS NULL
INNER JOIN osm_user_id_link l2
 ON l2.user_id = u.user_id
AND l2.valid_to IS NULL
WHERE nc.id_user IS NOT NULL
 AND nc.username IS NOT NULL
ORDER BY
 LEAST(l1.identity_id, l2.identity_id),
 GREATEST(l1.identity_id, l2.identity_id),
 nc.id_user,
 u.user_id
ON CONFLICT (
 identity_id_low,
 identity_id_high,
 reason,
 source_process
) DO UPDATE SET
 last_seen_at = CURRENT_TIMESTAMP,
 username = EXCLUDED.username,
 incoming_user_id = EXCLUDED.incoming_user_id,
 existing_user_id = EXCLUDED.existing_user_id;

-- Move comments from sync to main tables
SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 'Moving comments from sync to main tables' AS Text;

INSERT INTO note_comments (id, note_id, sequence_action, event, created_at, id_user)
SELECT id, note_id, sequence_action, event, created_at, id_user
FROM note_comments_sync
WHERE id_user IS NULL OR id_user IN (SELECT user_id FROM users)
ON CONFLICT (id) DO UPDATE SET
 note_id = EXCLUDED.note_id,
 sequence_action = EXCLUDED.sequence_action,
 event = EXCLUDED.event,
 created_at = EXCLUDED.created_at,
 id_user = EXCLUDED.id_user;

SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 COUNT(1) AS Qty,
 'Moved comments to main table' AS Text
FROM note_comments_sync;

-- Move text comments from sync to main tables
SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 'Moving text comments from sync to main tables (with FK validation)' AS Text;

-- Only insert/update text comments if (note_id, sequence_action) exists in note_comments
-- This prevents FK violations when duplicate comments are deduplicated
INSERT INTO note_comments_text (id, note_id, sequence_action, body)
SELECT t.id, t.note_id, t.sequence_action, t.body
FROM note_comments_text_sync t
WHERE EXISTS (
  SELECT 1
  FROM note_comments nc
  WHERE nc.note_id = t.note_id
    AND nc.sequence_action = t.sequence_action
)
ON CONFLICT (id) DO UPDATE SET
 note_id = EXCLUDED.note_id,
 sequence_action = EXCLUDED.sequence_action,
 body = EXCLUDED.body;

SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 COUNT(1) AS Qty,
 'Moved text comments to main table' AS Text
FROM note_comments_text_sync;

-- Update statistics on main tables
ANALYZE notes;
ANALYZE note_comments;
ANALYZE note_comments_text;

SELECT /* Notes-processPlanet */ clock_timestamp() AS Processing,
 'Data movement from sync to main tables completed' AS Text; 