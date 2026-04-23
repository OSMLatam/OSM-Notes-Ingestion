-- Inserts missing comments from check tables into main tables.
-- This script is executed after differences are identified.
-- Before inserting, it saves the missing comments to history table
-- for later analysis.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-23
-- Optimized: Changed NOT IN to LEFT JOIN for better performance with large datasets

-- First, save missing comments to history table BEFORE insertion
SELECT /* Notes-check */ clock_timestamp() AS Processing,
  'Saving missing comments to history table' AS Text;

INSERT INTO missing_comments_history (
  note_id,
  sequence_action,
  event,
  created_at,
  id_user,
  username,
  detected_at,
  inserted
)
SELECT /* Notes-check */
  check_c.note_id,
  check_c.sequence_action,
  check_c.event,
  check_c.created_at,
  check_c.id_user,
  check_c.username,
  CURRENT_TIMESTAMP,
  FALSE
FROM note_comments_check check_c
LEFT JOIN note_comments main_c
  ON check_c.note_id = main_c.note_id
  AND check_c.sequence_action = main_c.sequence_action
WHERE main_c.note_id IS NULL
  AND DATE(check_c.created_at) < CURRENT_DATE
ON CONFLICT (note_id, sequence_action, detected_at) DO NOTHING;

-- Insert missing users from check comments first
SELECT /* Notes-check */ clock_timestamp() AS Processing,
  'Inserting missing users from check comments' AS Text;

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
  'notesCheckVerifier',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM note_comments_check
WHERE id_user IS NOT NULL
  AND username IS NOT NULL
ON CONFLICT (user_id, username) DO UPDATE SET
  last_seen = CURRENT_TIMESTAMP,
  source_process = EXCLUDED.source_process;

INSERT INTO users (user_id, username)
SELECT /* Notes-check */
  id_user,
  MIN(username) AS username
FROM note_comments_check
WHERE id_user IS NOT NULL
  AND username IS NOT NULL
  AND id_user NOT IN (SELECT /* Notes-check */ user_id FROM users)
  AND NOT EXISTS (
    SELECT 1
    FROM users u
    WHERE u.username = note_comments_check.username
      AND u.user_id <> note_comments_check.id_user
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
  || quote_literal(ncc.username)
  || ', incoming_user_id='
  || ncc.id_user
  || ', existing_user_id='
  || u.user_id
FROM note_comments_check ncc
INNER JOIN users u ON u.username = ncc.username
WHERE ncc.id_user IS NOT NULL
  AND ncc.username IS NOT NULL
  AND u.user_id <> ncc.id_user;

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
  ncc.username,
  ncc.id_user,
  u.user_id,
  'notesCheckVerifier',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP,
  1
FROM note_comments_check ncc
INNER JOIN users u ON u.username = ncc.username
WHERE ncc.id_user IS NOT NULL
  AND ncc.username IS NOT NULL
  AND u.user_id <> ncc.id_user
ON CONFLICT (username, incoming_user_id, existing_user_id, source_process)
DO UPDATE SET
  last_seen = CURRENT_TIMESTAMP,
  times_seen = user_identity_conflicts.times_seen + 1;

-- Durable identity (match API/planet).
WITH missing AS (
  SELECT DISTINCT ncc.id_user
  FROM note_comments_check ncc
  WHERE ncc.id_user IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM users uu
      WHERE uu.user_id = ncc.id_user
    )
    AND NOT EXISTS (
      SELECT 1
      FROM osm_user_id_link l
      WHERE l.user_id = ncc.id_user
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
    'notesCheckVerifier',
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
    'notesCheckVerifier',
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
    SELECT DISTINCT ncc.id_user
    FROM note_comments_check ncc
    WHERE ncc.id_user IS NOT NULL
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
  ncc.id_user,
  u.user_id
)
  LEAST(l1.identity_id, l2.identity_id),
  GREATEST(l1.identity_id, l2.identity_id),
  ncc.username,
  ncc.id_user,
  u.user_id,
  'username_reused_by_different_user_id',
  'low',
  'open',
  'notesCheckVerifier',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM note_comments_check ncc
INNER JOIN users u
  ON u.username = ncc.username
 AND u.user_id <> ncc.id_user
INNER JOIN osm_user_id_link l1
  ON l1.user_id = ncc.id_user
 AND l1.valid_to IS NULL
INNER JOIN osm_user_id_link l2
  ON l2.user_id = u.user_id
 AND l2.valid_to IS NULL
WHERE ncc.id_user IS NOT NULL
  AND ncc.username IS NOT NULL
ORDER BY
  LEAST(l1.identity_id, l2.identity_id),
  GREATEST(l1.identity_id, l2.identity_id),
  ncc.id_user,
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

-- Insert missing comments from check to main tables
SELECT /* Notes-check */ clock_timestamp() AS Processing,
  'Inserting missing comments from check tables' AS Text;

-- Insert comments that exist in check but not in main
-- Using LEFT JOIN instead of NOT IN for better performance with large datasets
-- We need to get the id from the sequence first
WITH inserted_comments AS (
  INSERT INTO note_comments (
    id,
    note_id,
    sequence_action,
    event,
    created_at,
    id_user
  )
  SELECT /* Notes-check */
    nextval('note_comments_id_seq'),
    check_c.note_id,
    check_c.sequence_action,
    check_c.event,
    check_c.created_at,
    check_c.id_user
  FROM note_comments_check check_c
  LEFT JOIN note_comments main_c
    ON check_c.note_id = main_c.note_id
    AND check_c.sequence_action = main_c.sequence_action
  WHERE main_c.note_id IS NULL
    AND (check_c.id_user IS NULL OR check_c.id_user IN (
      SELECT /* Notes-check */ user_id FROM users
    ))
  ON CONFLICT DO NOTHING
  RETURNING note_id, sequence_action
)
-- Update history table to mark comments as inserted
UPDATE missing_comments_history mch
SET inserted = TRUE,
    inserted_at = CURRENT_TIMESTAMP
FROM inserted_comments ic
WHERE mch.note_id = ic.note_id
  AND mch.sequence_action = ic.sequence_action
  AND mch.inserted = FALSE;

-- Show count of inserted comments (using LEFT JOIN for performance)
SELECT /* Notes-check */ clock_timestamp() AS Processing,
  COUNT(1) AS Qty,
  'Inserted missing comments' AS Text
FROM note_comments_check check_c
LEFT JOIN note_comments main_c
  ON check_c.note_id = main_c.note_id
  AND check_c.sequence_action = main_c.sequence_action
WHERE main_c.note_id IS NULL;

-- Update statistics
SELECT /* Notes-check */ clock_timestamp() AS Processing,
  'Updating comments statistics' AS Text;
ANALYZE note_comments;

SELECT /* Notes-check */ clock_timestamp() AS Processing,
  'Missing comments insertion completed' AS Text;



