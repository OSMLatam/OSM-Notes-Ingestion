---
title: "Base load progress monitoring (Planet --base)"
description: "How to see progress of long-running processPlanetNotes.sh --base steps using logs and SQL"
version: "1.0.0"
last_updated: "2026-04-19"
author: "AngocA"
tags:
  - "operations"
  - "monitoring"
  - "planet"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Ingestion"
status: "active"
---

# Base load progress monitoring (`processPlanetNotes.sh --base`)

A full **Planet base** run can take many hours. Logs do not always flush on every
sub-step, so **combining log tails with database counts** is the most reliable way
to confirm the job is advancing and not stuck.

> **Related:** [Process_Planet.md](./Process_Planet.md) (design),
> [Documentation.md](./Documentation.md) (log paths),
> [Troubleshooting_Guide.md](./Troubleshooting_Guide.md) (incidents).

## 1. Log files (typical locations)

Installation detection may send logs to `/var/...` or fallback under `/tmp/...`:

| Process | Installed mode | Fallback mode |
|---------|----------------|---------------|
| Planet | `/var/log/osm-notes-ingestion/processing/processPlanetNotes.log` | `/tmp/osm-notes-ingestion/logs/processing/processPlanetNotes.log` |
| Countries (invoked from Planet or manually) | same `processing/` dir | `updateCountries.log` in the same `processing/` tree |

Find the newest Planet log:

```bash
find /var/log/osm-notes-ingestion/processing /tmp/osm-notes-ingestion/logs/processing \
  -name "processPlanetNotes.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
  sort -n | tail -1 | awk '{print $2}'
```

`updateCountries` may log to `updateCountries.log` alongside Planet when geographic
data runs as part of the base workflow.

## 2. Long phases and what to look for in logs

Below are the usual **slow** stages and **log cues** (patterns vary slightly by
version; use `grep` case-insensitively when unsure).

| Phase | Log file | Example lines / grep |
|-------|----------|----------------------|
| Planet file download / decompress | `processPlanetNotes.log` | `download`, `bzip2`, `Successfully extracted Planet notes` |
| XML split + parallel parts | `processPlanetNotes.log` | `Splitting`, `parts`, `Processing.*parts in parallel`, `Progress:` (chunk) |
| Load into DB (sync → main) | `processPlanetNotes.log` | `Moved.*main table`, `INSERT`, `Data movement from sync to main tables completed` |
| Country / maritime load (`updateCountries`) | `updateCountries.log` | `Downloading boundary`, `Successfully imported`, `Swap completed`, `BASE SETUP COMPLETED` |
| Note country assignment | `processPlanetNotes.log` | `__getLocationNotes`, `Progress: N/M chunks`, `Notes pending assignment with coordinates` |
| Analyze / vacuum (end) | `processPlanetNotes.log` | `ANALYZE`, `VACUUM`, `Ending process` |

**Tip:** For assignment progress, search for `Progress:` and chunk fractions:

```bash
LATEST_LOG=$(find /var/log/osm-notes-ingestion/processing /tmp/osm-notes-ingestion/logs/processing \
  -name "processPlanetNotes.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
grep -E 'Progress:|getLocationNotes|pending assignment' "${LATEST_LOG}" | tail -20
```

If the log file **mtime** does not change for a long time while CPU/IO and
PostgreSQL are busy, the process may still be inside a **single SQL statement**
or a subprocess whose output is buffered—use **SQL counts** (section 3) and
`pg_stat_activity` (section 4).

## 3. SQL: row counts and assignment progress

Run against your ingestion database (often `notes`). Adjust `DBNAME` if needed.

**Single snapshot (notes, comments, countries, assignment):**

```sql
SELECT
  (SELECT COUNT(*) FROM notes) AS notes_total,
  (SELECT COUNT(*) FROM note_comments) AS note_comments_total,
  (SELECT COUNT(*) FROM note_comments_text) AS note_comments_text_total,
  (SELECT COUNT(*) FROM countries) AS countries_total,
  (SELECT COUNT(*) FROM notes
   WHERE id_country IS NOT NULL AND id_country >= 0) AS notes_with_country,
  (SELECT COUNT(*) FROM notes
   WHERE id_country IS NULL OR id_country < 0) AS notes_country_pending,
  (SELECT COUNT(*) FROM notes
   WHERE (id_country IS NULL OR id_country < 0)
     AND longitude IS NOT NULL AND latitude IS NOT NULL) AS notes_pending_with_coords;
```

**How to interpret during base load:**

- **`notes_total`**: should approach the Planet note count when loading finishes.
- **`note_comments_total` / `note_comments_text_total`**: grow as comments and
  texts are loaded.
- **`countries_total`**: stable after geographic import (hundreds of rows is
  normal; exact number depends on data and failures).
- **`notes_with_country` vs `notes_country_pending`**: during assignment, the
  first should rise and the second fall. If both stop moving for a very long time
  with no DB activity, investigate locks or errors in the log.

## 4. Completion flag in `properties`

After a **successful** full `--base` run, ingestion records:

```text
key = base_load_complete, value = true
```

Check:

```sql
SELECT key, value, updated_at
FROM properties
WHERE key = 'base_load_complete';
```

If the row is missing, the base workflow has not completed successfully (or an
older version of the scripts is deployed). Base tables drops remove this signal
when the schema is recreated.

## 5. PostgreSQL: is work still running?

```sql
SELECT pid, application_name, state,
       NOW() - query_start AS running_for,
       LEFT(query, 120) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
ORDER BY query_start;
```

Active `COPY`, `INSERT`, `UPDATE`, or long `SELECT` rows usually mean the load
is not stuck—only waiting on I/O or CPU.

## 6. What existing docs already covered

- **Tail latest processing log:** [Documentation.md](./Documentation.md)
  (“Following progress” for API; same pattern applies to Planet paths).
- **Download tail / grep:** [Process_Planet.md](./Process_Planet.md) (troubleshooting
  download section).
- **Stuck Planet / tail log:** [Troubleshooting_Guide.md](./Troubleshooting_Guide.md)
  (“Process Planet Conflict”).
- **Assignment performance / SQL examples:** [Country_Assignment_2D_Grid.md](./Country_Assignment_2D_Grid.md),
  `sql/analysis/analyze_country_assignment_performance.sql`.
- **Schema / monitoring consumers:** [Schema_Compatibility_Runbook.md](./Schema_Compatibility_Runbook.md)
  (compatibility checks, not row-level progress).

None of the above consolidates **per-phase progress** for operators; this file is
the dedicated runbook for that.
