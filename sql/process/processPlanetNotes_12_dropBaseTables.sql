-- Drop base tables and ingestion/monitor auxiliary objects.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-22

-- Set statement timeout to 30 seconds for DROP operations
SET statement_timeout = '30s';

-- Triggers require the table to exist (partially cleaned DB otherwise errors).
DO $drop_triggers$
BEGIN
 IF to_regclass('public.note_comments') IS NOT NULL THEN
  DROP TRIGGER IF EXISTS update_note ON note_comments;
 END IF;
 IF to_regclass('public.notes') IS NOT NULL THEN
  DROP TRIGGER IF EXISTS log_insert_note ON notes;
 END IF;
END
$drop_triggers$;
DROP FUNCTION IF EXISTS update_note CASCADE;
DROP FUNCTION IF EXISTS log_insert_note CASCADE;
DROP PROCEDURE IF EXISTS remove_lock CASCADE;
DROP PROCEDURE IF EXISTS put_lock CASCADE;
DROP TABLE IF EXISTS license CASCADE;
DROP TABLE IF EXISTS properties CASCADE;
DROP TABLE IF EXISTS logs CASCADE;
DROP TABLE IF EXISTS note_comments_text CASCADE;
DROP TABLE IF EXISTS note_comments CASCADE;
DROP TABLE IF EXISTS notes CASCADE;
DROP TABLE IF EXISTS osm_identity_suggestion CASCADE;
DROP TABLE IF EXISTS osm_identity_lifecycle_event CASCADE;
DROP TABLE IF EXISTS osm_user_id_link CASCADE;
DROP TABLE IF EXISTS osm_user_identity CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Schema contract and user-identity tables (created in
-- processPlanetNotes_21_createBaseTables_tables.sql).
DROP TABLE IF EXISTS schema_version CASCADE;
DROP TABLE IF EXISTS user_identity_history CASCADE;
DROP TABLE IF EXISTS user_identity_conflicts CASCADE;

-- Monitor / notesCheckVerifier history and temp tables.
DROP TABLE IF EXISTS missing_comments_history CASCADE;
DROP TABLE IF EXISTS missing_text_comments_history CASCADE;
DROP TABLE IF EXISTS temp_diff_notes_id CASCADE;
DROP TABLE IF EXISTS temp_diff_comments_id CASCADE;
DROP TABLE IF EXISTS temp_diff_notes CASCADE;
DROP TABLE IF EXISTS temp_diff_text_comments_id CASCADE;
DROP TABLE IF EXISTS temp_diff_text_comments CASCADE;
DROP TABLE IF EXISTS temp_diff_note_comments CASCADE;
DROP TABLE IF EXISTS temp_notes_in_main_not_in_check CASCADE;

-- Staging from GDAL/ogr2ogr or other tools (default layer name "import").
DROP TABLE IF EXISTS import CASCADE;

-- Optional backup / dedup tables from ingestion SQL.
DROP TABLE IF EXISTS backup_note_locations CASCADE;
DROP TABLE IF EXISTS backup_countries CASCADE;
DROP TABLE IF EXISTS notes_sync_no_duplicates CASCADE;
DROP TABLE IF EXISTS note_comments_sync_no_duplicates CASCADE;

-- GDPR audit (optional; safe if table was never created).
DROP TABLE IF EXISTS gdpr_audit_log CASCADE;

DROP TYPE IF EXISTS note_event_enum CASCADE;
DROP TYPE IF EXISTS note_status_enum CASCADE;

-- Reset statement timeout
SET statement_timeout = DEFAULT;
