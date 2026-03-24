-- Assigns countries to a chunk of notes by their IDs.
-- Used for parallel processing of note country assignment.
--
-- Parameters:
--   ${NOTE_IDS} - Comma-separated list of note IDs (e.g., "123,456,789")
--
-- Returns:
--   COUNT(*) of notes that were successfully assigned a country
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-03-23

-- noqa: disable=all
WITH target AS (
  SELECT UNNEST(string_to_array('${NOTE_IDS}', ','))::BIGINT AS note_id
),
updated AS (
  UPDATE notes AS n
  SET id_country = get_country(n.longitude, n.latitude, n.note_id)
  FROM target t
  WHERE n.note_id = t.note_id
  AND (n.id_country IS NULL OR n.id_country < 0)
  RETURNING n.note_id
)
SELECT COUNT(*) FROM updated;
-- noqa: enable=all

