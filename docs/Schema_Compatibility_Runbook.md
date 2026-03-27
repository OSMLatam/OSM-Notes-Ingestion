# Schema Compatibility Runbook

This runbook explains how to diagnose and resolve schema contract mismatches
between DB schema and service consumers (Ingestion/API/WMS/Monitoring).

## Quick diagnosis

Use the diagnostic command:

```bash
./bin/monitor/checkSchemaCompatibility.sh
```

Validate only one consumer:

```bash
./bin/monitor/checkSchemaCompatibility.sh --consumer ingestion
```

Use a different database:

```bash
./bin/monitor/checkSchemaCompatibility.sh --db osm_notes
```

## Interpret output

- `OK`: consumer range is compatible with current DB schema version.
- `FAIL`: consumer range does not include current DB schema version.
- `component missing`: `schema_version` table has no row for the component.

## Typical mismatch scenarios

### DB too old for consumer

Example:

- consumer expects `>= 1.1.0`
- DB has `1.0.5`

Action:

1. Run schema bootstrap/migration to reach target version.
2. Confirm `schema_version` is updated.
3. Re-run diagnostic command.

### DB too new for consumer range

Example:

- consumer expects `< 1.2.0` (`1.1.x`)
- DB has `1.2.0`

Action:

1. Expand consumer range in `etc/schema_compatibility.sh`.
2. Validate contracts in CI:
   `tests/ci/validate_schema_contracts.sh`
3. Re-run diagnostic command in runtime environment.

### Missing `schema_version` component row

Action:

1. Ensure base schema script was executed:
   `sql/process/processPlanetNotes_21_createBaseTables_tables.sql`
2. Insert or repair the row in `schema_version`.
3. Re-run diagnostic command.

## Preventive controls

- Runtime guard in DB entrypoints: `__assert_schema_compatible`.
- CI validation: `tests/ci/validate_schema_contracts.sh`.
- Central contract definition: `etc/schema_compatibility.sh`.

## Operational checklist

1. Identify failing consumer from logs.
2. Run `checkSchemaCompatibility.sh` against target DB.
3. Compare DB version vs consumer range.
4. Apply schema update or contract-range update.
5. Re-run CI contract validation.
6. Re-run runtime diagnostic and affected pipeline script.
