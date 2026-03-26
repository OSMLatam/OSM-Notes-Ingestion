# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Overpass single-relation timeout**: Configurable `OVERPASS_SINGLE_RELATION_TIMEOUT` (default 600s) for country/maritime boundary downloads; avoids default server timeout on large relations (e.g. Indonesia). Documented in `etc/properties.sh.example` and `bin/Environment_Variables.md`.
- **Swap safety threshold**: `SWAP_MAX_DELETED_THRESHOLD` to cap how many existing countries may be missing in `countries_new` before refusing the swap; effective threshold is max(this value, 5% of current count). Documented in `etc/properties.sh.example` and `docs/Countries_Table_Update_Strategy.md`.

### Changed

- **updateCountries.sh continues on country failures**: Wrapped `__processCountries` in `if ! ... fi` so that when it returns non-zero (e.g. "No successful downloads to import"), the script still runs `__processMaritimes` and the swap instead of exiting due to `set -e`. Fixes the case where data remained only in `countries_new` and swap never ran.
- **Swap regression guard**: Before swapping, the script now checks how many existing `country_id` would be lost (present in `countries` but missing in `countries_new`) and refuses the swap if that count exceeds max(10, 5% of current). Aligns with the "deleted" notion from `compare_all_country_geometries` and allows a few failures (e.g. 3 Indonesia) but not mass loss.
- **Overpass response validation**: After download, require at least one element of type `way` in the Overpass JSON; relation-only (truncated) responses are rejected and the next endpoint is tried when using `OVERPASS_ENDPOINTS`.
- **Documentation**: Installation_Dependencies (full cleanup as DB owner, manual swap reference), Cleanup_Integration (full cleanup in production, manual swap), Countries_Table_Update_Strategy (why automatic swap may not run, manual swap, regression guard), Environment_Variables (OVERPASS_SINGLE_RELATION_TIMEOUT, OVERPASS_ENDPOINTS), properties.sh.example (OVERPASS_ENDPOINTS, OVERPASS_SINGLE_RELATION_TIMEOUT, SWAP_MAX_DELETED_THRESHOLD).
- **2026-03-26 OSM Notes API hardening**: Adaptive `limit` fallback on transient download failures (e.g. `503`/timeouts) to avoid getting stuck on large requests.
- **2026-03-26 OSM Notes API resiliency**: Preserve the last known-good snapshot by preparing/truncating API staging tables only after successful download and XML validation.
- **2026-03-26 OSM Notes API retry tuning**: Exponential backoff with jitter plus clamping `MAX_NOTES` against `/api/0.6/capabilities` (`notes maximum_query_limit`).
- **2026-03-26 OSM Notes API pagination recovery**: Daemon now retrieves backlog via paginated requests (`order=oldest`) using a moving cursor from `max_note_timestamp`, minimizing Planet resync after crashes. Pagination controls: `API_PAGINATION_PAGE_LIMIT` and `API_PAGINATION_MAX_PAGES`.

### Fixed

- **Daemon unbound variables**: When `processPlanetNotes.sh` failed (e.g. during base load), `TMP_DIR`, `LOCK_DIR`, and `LOCK` could be unset in the daemon, causing "unbound variable" errors in later cycles. Fixed by re-initializing these in failure branches and making `__release_lock` / `__daemon_cleanup` defensive when variables are unset (`processAPINotesDaemon.sh`).

#### Country Assignment Bug Fix (2026-01-19)

- **Fixed ambiguous return value in `get_country()` function**:
  - **Issue**: Function returned `-1` for both known international waters and unknown countries, causing notes in countries like Brazil, Venezuela, Chile, etc. to be incorrectly marked as international waters
  - **Root Cause**: Function initialized `m_id_country := -1` and returned `COALESCE(m_id_country, -1)`, meaning unknown countries were marked as international waters
  - **Fix**: 
    - Changed initialization to `m_id_country := -2` for unknown countries
    - Reserved `-1` ONLY for known international waters (from `international_waters` table)
    - Introduced `-2` for unknown/not found countries
    - Added `ST_Intersects` fallback for points on country boundaries
    - Normalized SRID to 4326 for all geometries
  - **Implementation**:
    - Updated `sql/functionsProcess_20_createFunctionToGetCountry.sql` to use `-2` for unknown countries
    - Updated all code references from `id_country = -1` to `id_country < 0` to handle both `-1` and `-2`
    - Enhanced function to use `ST_Intersects` as fallback when `ST_Contains` fails (handles points on edges)
  - **Impact**:
    - Notes in valid countries are now correctly assigned (no longer marked as international waters)
    - Clear distinction between international waters (`-1`) and unknown countries (`-2`)
    - Better handling of points on country boundaries
    - Improved geometry validation with explicit SRID normalization
  - **Files changed**:
    - `sql/functionsProcess_20_createFunctionToGetCountry.sql` (core function fix)
    - `bin/lib/noteProcessingFunctions.sh` (6 occurrences updated)
    - `sql/functionsProcess_31_loadsBackupNoteLocation.sql`
    - `sql/functionsProcess_35_assignCountryToNotesChunk.sql`
    - `sql/functionsProcess_32_assignCountryToNotesChunk.sql`
    - `docs/Country_Assignment_2D_Grid.md` (documentation update)
  - **New tests added**:
    - `tests/unit/sql/get_country_return_values.test.sql` (validates return value semantics)
    - `tests/unit/sql/get_country_partial_failures.test.sql` (detects partial failures)
    - `tests/unit/bash/get_country_return_values.test.bats` (BATS integration tests)
    - `tests/setup_test_countries_for_get_country.sh` (automatic test data setup)

---

## [2026-01-26] - Recent Updates and Improvements

### Added

- **CI/CD Testing Infrastructure**: Added local CI testing scripts and improved test workflows
- **Test Infrastructure**: Enhanced test setup with PostGIS extension support and improved test country configuration

### Changed

- **Documentation**: Comprehensive documentation updates including standardized links, metadata sections, and Mermaid diagrams
- **Code Quality**: Standardized code formatting, improved error handling, and enhanced logging
- **Processing Logic**: Enhanced boundary processing, API notes processing, and country update workflows

### Fixed

- **Error Handling**: Improved error handling and validation across multiple processing scripts
- **Country Assignment**: Enhanced country assignment logic and boundary validation

---
