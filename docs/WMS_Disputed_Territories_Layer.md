# WMS disputed territories layer (ingestion database)

This repository maintains a **standalone PostGIS table** for a WMS overlay of
canonically named disputed / unclaimed areas. It is **not** used for note
country assignment or ingestion logic.

## Components

| Path | Role |
|------|------|
| `data/disputed_territories_wms_names.json` | Canonical names, descriptions, optional geometry hints |
| `sql/wms/disputed_territories_wms_01_create_table.sql` | Enum + table + indexes |
| `sql/wms/disputed_territories_wms_02_seed_reference_names.sql` | Seed rows (`geom` NULL until refresh) |
| `sql/wms/disputed_territories_wms_99_drop_all.sql` | Drop table + enum (used by `cleanupAll.sh`) |
| `bin/process/updateDisputedTerritoriesWMS.sh` | Refresh `geom` from JSON + `countries` |

## Operations

- **First deploy:**  `bin/process/updateDisputedTerritoriesWMS.sh --init`  
  Then use normal refresh (no `--init`) in cron.

- **Periodic refresh:** After `updateCountries.sh` (same DB), so intersections use
  current boundaries. See `examples/crontab-setup.example`.

- **Dry run:**  
  `bin/process/updateDisputedTerritoriesWMS.sh --dry-run`  
  prints generated SQL only.

## Geometry hints (JSON)

- **`pair_relation_ids`**: two OSM relation ids that must exist in
  `countries.country_id`. Produces `ST_Intersection` of the two polygons.
- **`bbox`**: `[min_lon, min_lat, max_lon, max_lat]` for `unclaimed_territory`
  (e.g. Bir Tawil rectangle).

Rows with kind **`disputed_tagged`** stay without geometry until a future
Overpass/import step fills them.

## WMS publication

GeoServer / MapServer configuration lives in the sibling project
**[OSM-Notes-WMS](https://github.com/OSM-Notes/OSM-Notes-WMS)**. See
`docs/Ingestion_Disputed_Territories_WMS.md` there for using
`public.disputed_territories_wms`.

## Relation to `wms.disputed_and_unclaimed_areas`

OSM-Notes-WMS can build **materialized** disputed/unclaimed geometry from
country overlap gaps. The ingestion table **`disputed_territories_wms`** is a
**curated, named** layer (wiki-aligned labels); the two can coexist.
