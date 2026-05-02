-- WMS-friendly view: rows with geometry only (GeoServer / OSM-Notes-WMS).
-- geometry alias matches calculate_bbox_from_table and prepareDatabase conventions.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-05-01

CREATE OR REPLACE VIEW public.disputed_territories_wms_view AS
SELECT
  id,
  kind::text AS kind,
  name,
  description,
  geom AS geometry,
  reference_url,
  updated_at
FROM public.disputed_territories_wms
WHERE geom IS NOT NULL;

COMMENT ON VIEW public.disputed_territories_wms_view IS
  'WMS-friendly view: only rows with geometry (from disputed_territories_wms refresh).';
