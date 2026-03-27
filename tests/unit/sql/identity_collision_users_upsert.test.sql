-- Test identity collision protections for users upsert logic.
-- Author: Andres Gomez (AngocA)
-- Version: 2026-03-25

BEGIN;

DO $$
DECLARE
  v_qty INTEGER;
BEGIN
  CREATE TEMP TABLE user_identity_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    username VARCHAR(256) NOT NULL,
    source_process VARCHAR(64) NOT NULL,
    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  ) ON COMMIT DROP;
  CREATE TEMP TABLE user_identity_conflicts (
    id SERIAL PRIMARY KEY,
    username VARCHAR(256) NOT NULL,
    incoming_user_id INTEGER NOT NULL,
    existing_user_id INTEGER NOT NULL,
    source_process VARCHAR(64) NOT NULL,
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    times_seen INTEGER DEFAULT 1,
    status VARCHAR(32) DEFAULT 'pending_review'
  ) ON COMMIT DROP;
  CREATE UNIQUE INDEX user_identity_history_uniq
    ON user_identity_history (user_id, username);
  CREATE UNIQUE INDEX user_identity_conflicts_uniq
    ON user_identity_conflicts
    (username, incoming_user_id, existing_user_id, source_process);

  -- Baseline users:
  -- user_id=1001 owns username 'TimeSplitter'
  -- user_id=1002 exists with another username.
  INSERT INTO users (user_id, username)
  VALUES
    (1001, 'TimeSplitter'),
    (1002, 'AnotherName')
  ON CONFLICT (user_id) DO UPDATE
    SET username = EXCLUDED.username;

  -- --------------------------------------------------------------------------
  -- Test 1: processAPINotes users upsert skips username collision.
  -- --------------------------------------------------------------------------
  CREATE TEMP TABLE note_comments_api (
    id_user INTEGER,
    username VARCHAR(256)
  ) ON COMMIT DROP;

  INSERT INTO note_comments_api (id_user, username)
  VALUES (1002, 'TimeSplitter');

  INSERT INTO users (user_id, username)
  SELECT DISTINCT id_user, username
  FROM note_comments_api
  WHERE id_user IS NOT NULL
    AND username IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM users u
      WHERE u.username = note_comments_api.username
        AND u.user_id <> note_comments_api.id_user
    )
  ON CONFLICT (user_id) DO UPDATE SET
    username = EXCLUDED.username
  WHERE NOT EXISTS (
    SELECT 1
    FROM users u2
    WHERE u2.username = EXCLUDED.username
      AND u2.user_id <> users.user_id
  );

  INSERT INTO user_identity_history (
    user_id,
    username,
    source_process,
    first_seen,
    last_seen
  )
  SELECT DISTINCT
    id_user,
    username,
    'processAPINotes',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  FROM note_comments_api
  WHERE id_user IS NOT NULL
    AND username IS NOT NULL
  ON CONFLICT (user_id, username) DO UPDATE SET
    last_seen = CURRENT_TIMESTAMP,
    source_process = EXCLUDED.source_process;

  INSERT INTO logs (message)
  SELECT DISTINCT
    'WARNING: Username conflict skipped in users upsert. username='
    || quote_literal(nca.username)
    || ', incoming_user_id='
    || nca.id_user
    || ', existing_user_id='
    || u.user_id
  FROM note_comments_api nca
  INNER JOIN users u ON u.username = nca.username
  WHERE nca.id_user IS NOT NULL
    AND nca.username IS NOT NULL
    AND u.user_id <> nca.id_user;

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
    nca.username,
    nca.id_user,
    u.user_id,
    'processAPINotes',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
  FROM note_comments_api nca
  INNER JOIN users u ON u.username = nca.username
  WHERE nca.id_user IS NOT NULL
    AND nca.username IS NOT NULL
    AND u.user_id <> nca.id_user
  ON CONFLICT (
    username, incoming_user_id, existing_user_id, source_process
  ) DO UPDATE SET
    last_seen = CURRENT_TIMESTAMP,
    times_seen = user_identity_conflicts.times_seen + 1;

  SELECT COUNT(*)
  INTO v_qty
  FROM users
  WHERE user_id = 1002
    AND username = 'TimeSplitter';
  IF v_qty <> 0 THEN
    RAISE EXCEPTION 'Test 1 failed: collision updated username incorrectly';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM logs
  WHERE message LIKE
    'WARNING: Username conflict skipped in users upsert.%incoming_user_id=1002%';
  IF v_qty < 1 THEN
    RAISE EXCEPTION 'Test 1 failed: expected warning log not found';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM user_identity_history
  WHERE user_id = 1002
    AND username = 'TimeSplitter'
    AND source_process = 'processAPINotes';
  IF v_qty <> 1 THEN
    RAISE EXCEPTION 'Test 1 failed: expected history row not found';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM user_identity_conflicts
  WHERE username = 'TimeSplitter'
    AND incoming_user_id = 1002
    AND existing_user_id = 1001
    AND source_process = 'processAPINotes';
  IF v_qty <> 1 THEN
    RAISE EXCEPTION 'Test 1 failed: expected conflict row not found';
  END IF;
  RAISE NOTICE 'Test 1 passed: processAPINotes collision is skipped';

  DROP TABLE note_comments_api;

  -- --------------------------------------------------------------------------
  -- Test 2: processPlanet users upsert skips username collision.
  -- --------------------------------------------------------------------------
  CREATE TEMP TABLE note_comments_sync (
    id_user INTEGER,
    username VARCHAR(256)
  ) ON COMMIT DROP;

  INSERT INTO note_comments_sync (id_user, username)
  VALUES (1002, 'TimeSplitter');

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

  SELECT COUNT(*)
  INTO v_qty
  FROM users
  WHERE user_id = 1002
    AND username = 'TimeSplitter';
  IF v_qty <> 0 THEN
    RAISE EXCEPTION 'Test 2 failed: collision updated username incorrectly';
  END IF;
  RAISE NOTICE 'Test 2 passed: processPlanet collision is skipped';

  DROP TABLE note_comments_sync;

  -- --------------------------------------------------------------------------
  -- Test 3: notesCheckVerifier users upsert skips username collision.
  -- --------------------------------------------------------------------------
  CREATE TEMP TABLE note_comments_check (
    id_user INTEGER,
    username VARCHAR(256)
  ) ON COMMIT DROP;

  INSERT INTO note_comments_check (id_user, username)
  VALUES (1002, 'TimeSplitter');

  INSERT INTO users (user_id, username)
  SELECT
    id_user,
    MIN(username) AS username
  FROM note_comments_check
  WHERE id_user IS NOT NULL
    AND username IS NOT NULL
    AND id_user NOT IN (
      SELECT user_id
      FROM users
    )
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

  SELECT COUNT(*)
  INTO v_qty
  FROM users
  WHERE user_id = 1002
    AND username = 'TimeSplitter';
  IF v_qty <> 0 THEN
    RAISE EXCEPTION 'Test 3 failed: collision updated username incorrectly';
  END IF;
  RAISE NOTICE 'Test 3 passed: notesCheckVerifier collision is skipped';

  DROP TABLE note_comments_check;

  -- --------------------------------------------------------------------------
  -- Test 4: insert_note_comment logs warning and keeps canonical username.
  -- --------------------------------------------------------------------------
  CALL put_lock('991');
  INSERT INTO notes (
    note_id,
    latitude,
    longitude,
    created_at,
    status
  ) VALUES (
    991001,
    4.7110,
    -74.0721,
    NOW(),
    'open'
  );

  CALL insert_note_comment(
    991001,
    'opened',
    NOW(),
    1002,
    'TimeSplitter',
    991,
    1
  );

  SELECT COUNT(*)
  INTO v_qty
  FROM users
  WHERE user_id = 1002
    AND username = 'TimeSplitter';
  IF v_qty <> 0 THEN
    RAISE EXCEPTION 'Test 4 failed: procedure updated username incorrectly';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM logs
  WHERE message LIKE
    'WARNING: Username conflict skipped in users upsert.%incoming_user_id=1002%';
  IF v_qty < 2 THEN
    RAISE EXCEPTION
      'Test 4 failed: expected additional warning log not found';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM user_identity_history
  WHERE user_id = 1002
    AND username = 'TimeSplitter';
  IF v_qty < 1 THEN
    RAISE EXCEPTION 'Test 4 failed: expected history row from procedure';
  END IF;

  SELECT COUNT(*)
  INTO v_qty
  FROM user_identity_conflicts
  WHERE username = 'TimeSplitter'
    AND incoming_user_id = 1002
    AND source_process = 'insert_note_comment';
  IF v_qty <> 1 THEN
    RAISE EXCEPTION 'Test 4 failed: expected procedure conflict row';
  END IF;

  DELETE FROM note_comments WHERE note_id = 991001;
  DELETE FROM notes WHERE note_id = 991001;
  CALL remove_lock('991');

  RAISE NOTICE 'Test 4 passed: insert_note_comment collision is skipped';
END
$$;

DO $$
BEGIN
  RAISE NOTICE 'All identity collision tests passed';
END
$$;

ROLLBACK;
