-- Backfill osm_user_identity / osm_user_id_link for user_ids in users
-- with no current open link (e.g. DB restored from a dump before identity
-- tables existed, or partial migration). Idempotent: safe to re-run.
--
-- Plan (operator):
--  1) Apply schema 1.2.0+ (tables + osm_user_identity_23_createFunctionsAndViews).
--  2) Run in a transaction first: BEGIN; \\i this file; ROLLBACK; verify counts;
--  3) Commit during a maintenance window if satisfied.
--  4) Optional: ANALYZE osm_user_id_link; refresh API pools.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-23

WITH missing AS (
 SELECT u.user_id
 FROM users u
 WHERE NOT EXISTS (
  SELECT 1
  FROM osm_user_id_link l
  WHERE l.user_id = u.user_id
   AND l.valid_to IS NULL
  )
),
paired AS (
 SELECT
  m.user_id,
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
  p.user_id,
  CURRENT_TIMESTAMP,
  NULL,
  'certain',
  'backfill_open_links',
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
  'backfill_open_links',
  jsonb_build_object('user_id', p.user_id)
 FROM paired p
 CROSS JOIN LATERAL (
  VALUES
   ('created'::VARCHAR(64)),
   ('user_id_link_opened'::VARCHAR(64))
 ) AS ev (event_type)
)
SELECT 1;
