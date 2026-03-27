# Schema Versioning

This project uses a lightweight schema contract based on Semantic Versioning.

## Table

The table `schema_version` stores the active schema contract:

- `component`: schema component identifier (currently `core`)
- `version`: semantic version in format `MAJOR.MINOR.PATCH`
- `updated_at`: timestamp of the last version update

## Current version

- `core`: `1.1.0`

## SemVer policy

- **MAJOR**: Breaking schema changes for consumers.
  - Example: remove/rename table or column used by API/WMS/Monitoring.
- **MINOR**: Backward-compatible additions.
  - Example: add new table, nullable column, new index.
- **PATCH**: Backward-compatible fixes with no contract expansion.
  - Example: index tuning, constraints fixes that do not alter expected
    external schema usage.

## Why `1.1.0` for this change

The identity-collision work adds new entities:

- `user_identity_history`
- `user_identity_conflicts`

It does not remove or rename existing public tables/columns, so this is
treated as a backward-compatible **MINOR** change.

## Diagnostics and operations

- Quick runtime diagnostic:
  `./bin/monitor/checkSchemaCompatibility.sh`
- CI validation command:
  `tests/ci/validate_schema_contracts.sh`
- Operational mismatch steps:
  `docs/Schema_Compatibility_Runbook.md`
