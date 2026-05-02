-- Drops WMS disputed territories layer (standalone; not note ingestion).
-- Invoked by bin/cleanupAll.sh during full base cleanup.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-05-01

DROP VIEW IF EXISTS public.disputed_territories_wms_view CASCADE;

DROP TABLE IF EXISTS disputed_territories_wms CASCADE;

DROP TYPE IF EXISTS disputed_territory_kind CASCADE;
