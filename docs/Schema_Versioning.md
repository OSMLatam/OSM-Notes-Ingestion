---
version: "2026-05-01"
---

# Schema Versioning

This project uses a lightweight **schema contract** based on Semantic Versioning
for the PostgreSQL layout that downstream services consume.

## Schema contract vs project release version

Two related but **independent** version lines exist:

### Schema contract

- **What:** SemVer of the **database contract** (component `core`, and any
  future components).
- **Where:** `schema_version` table, `etc/schema_compatibility.sh`, and
  bootstrap/migration SQL.
- **Purpose:** Downstream services (API, WMS, Analytics, Monitoring) declare
  which contract range they support.

### Project release

- **What:** SemVer (or tags) of **this repository** as a deliverable.
- **Where:** Git tags (e.g. `v1.0.0`), `CHANGELOG.md`.
- **Purpose:** Communicates packaged software milestones.

They **may diverge**: a release `v2.5.0` might ship only script fixes (contract
unchanged), or a schema bump might land on `main` before the next tagged
release. **Never assume** `v1.0.0` equals `schema_version.core = 1.0.0`. The tag
documents a repo milestone; `schema_version` documents what the **physical
database** must expose.

**Operational rule:** for deployments, always check **both** the intended Git/tag
and `schema_version` /
`./bin/monitor/checkSchemaCompatibility.sh`.

## The schema_version table

The table `schema_version` stores the active schema contract:

- `component`: schema component identifier (currently `core`)
- `version`: semantic version in format `MAJOR.MINOR.PATCH`
- `updated_at`: timestamp of the last version update

## Current contract version

- `core`: `1.2.0` (durable OSM user identity model; see history below)

## Version history (`core`)

- **`1.2.0`**: Adds durable `osm_user_*` identity storage, linking, suggestion
  tables, views, and backfill path. Existing public tables/columns for existing
  consumers remain valid; new behavior is additive. Defined in bootstrap SQL
  and `sql/process/osm_user_identity_*.sql`.

- **`1.1.0`**: Adds identity-collision support entities:

  - `user_identity_history`
  - `user_identity_conflicts`

  No removal or rename of existing public tables/columns; treated as a
  backward-compatible **MINOR** change.

Earlier `1.0.x` values (if present in older databases) denote the baseline
contract before those additions. **Git tag `v1.0.0`** is a **project release**
label and does not override the meaning of `schema_version.core`.

## SemVer policy

- **MAJOR**: Breaking schema changes for consumers.
  - Example: remove/rename table or column used by API/WMS/Monitoring.
- **MINOR**: Backward-compatible additions.
  - Example: add new table, nullable column, new index.
- **PATCH**: Backward-compatible fixes with no contract expansion.
  - Example: index tuning, constraints fixes that do not alter expected
    external schema usage.

## Diagnostics and operations

- Quick runtime diagnostic:
  `./bin/monitor/checkSchemaCompatibility.sh`
- CI validation command:
  `tests/ci/validate_schema_contracts.sh`
- Operational mismatch steps:
  `docs/Schema_Compatibility_Runbook.md`
