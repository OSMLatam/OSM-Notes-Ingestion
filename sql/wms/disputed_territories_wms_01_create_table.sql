-- WMS layer: disputed territories (standalone; not used by note ingestion).
-- Refresh with bin/process/updateDisputedTerritoriesWMS.sh (see docs).
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-06

DO $$
BEGIN
  CREATE TYPE disputed_territory_kind AS ENUM (
    'country_maritime_intersection',
    'disputed_tagged',
    'unclaimed_territory'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

COMMENT ON TYPE disputed_territory_kind IS
  'WMS layer: country/maritime intersection, OSM dispute tags, or unclaimed land.';

CREATE TABLE IF NOT EXISTS disputed_territories_wms (
  id BIGSERIAL PRIMARY KEY,
  kind disputed_territory_kind NOT NULL,
  name VARCHAR(256) NOT NULL,
  description TEXT,
  geom GEOMETRY(MULTIPOLYGON, 4326),
  osm_id BIGINT,
  osm_type VARCHAR(8),
  reference_url TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE disputed_territories_wms IS
  'WMS-only layer. Names from data/disputed_territories_wms_names.json.';

COMMENT ON COLUMN disputed_territories_wms.kind IS
  'country_maritime_intersection: overlap of admin polygons; '
  'disputed_tagged: OSM dispute tags; unclaimed_territory: e.g. Bir Tawil.';

COMMENT ON COLUMN disputed_territories_wms.name IS
  'Must match an entry name in data/disputed_territories_wms_names.json for the same kind.';

COMMENT ON COLUMN disputed_territories_wms.geom IS
  'Computed area; SRID 4326. NULL until refresh script runs.';

CREATE UNIQUE INDEX IF NOT EXISTS disputed_territories_wms_kind_name_uidx
  ON disputed_territories_wms (kind, name);

CREATE INDEX IF NOT EXISTS disputed_territories_wms_geom_gist
  ON disputed_territories_wms
  USING GIST (geom)
  WHERE geom IS NOT NULL;

CREATE INDEX IF NOT EXISTS disputed_territories_wms_kind_idx
  ON disputed_territories_wms (kind);

COMMENT ON INDEX disputed_territories_wms_kind_name_uidx IS
  'One row per kind + canonical name for idempotent reloads.';

COMMENT ON INDEX disputed_territories_wms_geom_gist IS
  'Spatial index for WMS.';
