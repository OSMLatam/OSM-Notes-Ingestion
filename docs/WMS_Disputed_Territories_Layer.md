# WMS disputed territories layer (ingestion database)

This repository maintains a **standalone PostGIS table** for a WMS overlay of
canonically named disputed / unclaimed areas. It is **not** used for note
country assignment or ingestion logic.

## What `disputed_tagged` means

In OSM, many conflict areas are mapped with tags such as **`disputed=yes`**,
**`disputed_by=*`**, or **`claimed_by=*`** on boundaries or polygons. The kind
**`disputed_tagged`** in our table means: “we catalogue this place as a named
dispute that is usually represented that way in OSM”, not “we already imported
its geometry”.

Today the refresh script **does not** query Overpass for those features, so
**`geom` stays NULL** for `disputed_tagged` until you add **`geometry_ewkt`** in
the JSON, an import step, or manual SQL. That is different from:

- **`country_maritime_intersection`**: geometry from **`ST_Intersection`** of two
  rows in **`countries`** when you set **`pair_relation_ids`** in the JSON.
- **`unclaimed_territory`**: optional **`bbox`** rectangle in the JSON (e.g. Bir
  Tawil), or **`geometry_ewkt`** for an exact polygon.

So `disputed_tagged` is mainly a **reserved category** for WMS labels and future
automation, aligned with OSM tagging practice.

## Including areas from a personal list (e.g. `fronteras.txt`)

A plain-text note file (like a list of border cases in Spanish) is **not**
read by the pipeline. To add those areas you **copy them into the canonical
JSON** (and keep **`sql/wms/disputed_territories_wms_02_seed_reference_names.sql`**
in sync for the same `kind` + `name`):

1. Add an object under **`entries`** in   **`data/disputed_territories_wms_names.json`** with **`kind`**, **`name`**,
   **`description`**, **`reference_url`**.
2. Choose **`kind`**:
   - If the case is “two country polygons overlap in our DB” → often
     **`country_maritime_intersection`** plus **`pair_relation_ids`** when you
     know the two **`countries.country_id`** values.
   - If it is mainly an OSM-tagged dispute polygon → **`disputed_tagged`** (no
     auto geometry yet).
   - If it is unclaimed land and you only have a rough rectangle →
     **`unclaimed_territory`** plus **`bbox`**.
3. Mirror the new rows in **`disputed_territories_wms_02_seed_reference_names.sql`**
   (same names; use **`ON CONFLICT (kind, name) DO NOTHING`**).
4. Run **`updateDisputedTerritoriesWMS.sh`** so rows with hints get **`geom`** (first run creates/seeds the table if missing); use **`--init`** to force re-apply create/seed SQL.

Do **not** commit private paths like `file:///.../Descargas/fronteras.txt`; keep
the repo’s source of truth as **`disputed_territories_wms_names.json`**.

## Components

| Path | Role |
|------|------|
| `data/disputed_territories_wms_names.json` | Canonical names, descriptions, optional geometry hints |
| `sql/wms/disputed_territories_wms_01_create_table.sql` | Enum + table + indexes |
| `sql/wms/disputed_territories_wms_02_seed_reference_names.sql` | Seed rows (`geom` NULL until refresh) |
| `sql/wms/disputed_territories_wms_03_create_view.sql` | `public.disputed_territories_wms_view` (`geom AS geometry`; GeoServer-friendly) |
| `sql/wms/disputed_territories_wms_99_drop_all.sql` | Drop view + table + enum (used by `cleanupAll.sh`) |
| `bin/process/updateDisputedTerritoriesWMS.sh` | Refresh `geom` from JSON + `countries` |

## Operations

- **First deploy:** After **`countries`** exists, run **`bin/process/updateDisputedTerritoriesWMS.sh`**; it applies create + seed automatically if **`disputed_territories_wms`** is missing, then ensures **`disputed_territories_wms_view`**. **`--init`** optionally forces create/seed SQL every run (idempotent).

- **Periodic refresh:** After `updateCountries.sh` (same DB), so intersections use
  current boundaries. See `examples/crontab-setup.example`.

- **Schema guard:** Default **`SCHEMA_CONSUMER=disputed_wms`** requires
  **`schema_version.core >= 1.1.0`** (this job only uses **`countries`** and the
  WMS table). Full ingestion expects **`1.2.0+`**; upgrade the core schema when
  you migrate note processing (`docs/Schema_Versioning.md`). To enforce the
  ingestion contract here:  
  `SCHEMA_CONSUMER=ingestion bin/process/updateDisputedTerritoriesWMS.sh`

- **Dry run:**  
  `bin/process/updateDisputedTerritoriesWMS.sh --dry-run`  
  prints generated SQL only.

## Geometry hints (JSON)

- **`geometry_ewkt`** (optional): full EWKT string as from PostGIS
  `ST_AsEWKT(geom)` (must include `SRID=4326;`). Works for **any** `kind` and
  **takes precedence** over `pair_relation_ids` and `bbox` for that row. Use this
  when you want a stable, hand-maintained geometry without Overpass.
- **`pair_relation_ids`**: two OSM relation ids that must exist in
  `countries.country_id`. Produces `ST_Intersection` of the two polygons.
- **`bbox`**: `[min_lon, min_lat, max_lon, max_lat]` for `unclaimed_territory`
  (e.g. Bir Tawil rectangle).

See [What `disputed_tagged` means](#what-disputed_tagged-means) above.

Tests may set **`DISPUTED_WMS_JSON_OVERRIDE`** to point at an alternate JSON
file (same `.entries` shape).

## Geometry coverage (after refresh)

| Rows | How `geom` is filled |
|------|----------------------|
| **`country_maritime_intersection`** with **`pair_relation_ids`** | `ST_Intersection` of the two `countries` geometries (both `country_id` must exist). |
| **`unclaimed_territory`** with **`bbox`** | Axis-aligned rectangle in WGS84. |
| **`disputed_tagged`** | **Not** auto-filled today; see **`geometry_requirement`** in the JSON per entry. |
| Any pair missing from **`countries`** | **`geom` stays NULL** (no error). Check Overpass country list vs relation ids. |

**Olivenza** was moved from **`disputed_tagged`** to **`country_maritime_intersection`** with PT/ES
pair. If you already had a DB seeded with the old kind, delete the old row or update kind before
re-seeding:

```sql
DELETE FROM disputed_territories_wms
 WHERE kind = 'disputed_tagged' AND name = 'Olivenza region';
```

Then re-run `disputed_territories_wms_02_seed_reference_names.sql` or `--init` on a test DB.

## WMS publication

GeoServer / MapServer configuration lives in the sibling project
**[OSM-Notes-WMS](https://github.com/OSM-Notes/OSM-Notes-WMS)**. See
`docs/Ingestion_Disputed_Territories_WMS.md` there for using
`public.disputed_territories_wms`.

## Relation to `wms.disputed_and_unclaimed_areas`

OSM-Notes-WMS can build **materialized** disputed/unclaimed geometry from
country overlap gaps. The ingestion table **`disputed_territories_wms`** is a
**curated, named** layer (wiki-aligned labels); the two can coexist.

---
**Author:** Andres Gomez (AngocA)  
**Version:** 2026-04-07 (geometry hints expanded)
