#!/bin/bash

# Refresh disputed_territories_wms geometries from JSON hints and countries table.
# Standalone WMS layer; not used by note ingestion. Schedule after updateCountries.
# If the table is missing, create + seed run automatically (same as --init SQL); use
# --init to force re-apply those scripts on every run (idempotent).
#
# Reads data/disputed_territories_wms_names.json (or DISPUTED_WMS_JSON_OVERRIDE):
#   - geometry_ewkt: optional hardcoded EWKT (SRID=4326;...). Overrides pair/bbox.
#   - pair_relation_ids [a,b]: ST_Intersection of countries (country_id).
#   - bbox [min_lon,min_lat,max_lon,max_lat]: rectangle for unclaimed_territory.
# disputed_tagged rows without geometry_ewkt stay NULL until Overpass or manual EWKT.
#
# Error codes: 1 help, 241 missing tool, 242 invalid arg, 252 validation, 255 general.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-05-01

VERSION="2026-05-01"

set -u
set -e
set -o pipefail
set -E

declare LOG_LEVEL="${LOG_LEVEL:-INFO}"
# Cron may set LOG_LEVEL=ERROR to suppress INFO; default INFO shows schema steps.
# Narrow contract: countries + WMS layer only (see disputed_wms in
# etc/schema_compatibility.sh). Use SCHEMA_CONSUMER=ingestion if you require 1.2.0+.
declare SCHEMA_CONSUMER="${SCHEMA_CONSUMER:-disputed_wms}"

if [[ -z "${SCRIPT_BASE_DIRECTORY:-}" ]]; then
 declare SCRIPT_BASE_DIRECTORY
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
  &> /dev/null && pwd)"
 readonly SCRIPT_BASE_DIRECTORY
fi

# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"

unset LOG_FILE

declare BASENAME
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME

export PGAPPNAME="${BASENAME}"

declare DISPUTED_WMS_JSON
DISPUTED_WMS_JSON="${DISPUTED_WMS_JSON_OVERRIDE:-${SCRIPT_BASE_DIRECTORY}/data/disputed_territories_wms_names.json}"
readonly DISPUTED_WMS_JSON
declare -r SQL_WMS_DIR="${SCRIPT_BASE_DIRECTORY}/sql/wms"
declare -r SQL_WMS_CREATE="${SQL_WMS_DIR}/disputed_territories_wms_01_create_table.sql"
declare -r SQL_WMS_SEED="${SQL_WMS_DIR}/disputed_territories_wms_02_seed_reference_names.sql"

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"
 echo "${BASENAME} version ${VERSION}"
 echo "Refreshes disputed_territories_wms.geom from JSON hints and countries."
 echo
 echo "Usage:"
 echo "  ${BASENAME}.sh                 # Compute geometries (auto create+seed if table missing)"
 echo "  ${BASENAME}.sh --init          # Always apply create + seed SQL, then compute (idempotent)"
 echo "  ${BASENAME}.sh --dry-run       # Print generated SQL only"
 echo "  ${BASENAME}.sh --help          # This help"
 echo
 echo "JSON: ${DISPUTED_WMS_JSON}"
 echo "Optional: DISPUTED_WMS_JSON_OVERRIDE=/path/to.json for tests."
 echo "Optional: LOG_LEVEL=ERROR for quiet cron (default INFO)."
 echo "Hardcoded geom: geometry_ewkt per entry (see JSON geometry_hints)."
 exit "${ERROR_HELP_MESSAGE:-1}"
fi

# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/bin/lib/pathConfigurationFunctions.sh"
__init_directories "${BASENAME}"

# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

##
# Exports PGHOST, PGPORT, PGUSER, PGPASSWORD from properties when set.
# Parameters: none.
##
function __configure_psql_env() {
 if [[ -n "${DB_HOST:-}" ]]; then
  export PGHOST="${DB_HOST}"
 else
  unset PGHOST
 fi
 if [[ -n "${DB_PORT:-}" ]]; then
  export PGPORT="${DB_PORT}"
 else
  unset PGPORT
 fi
 if [[ -n "${DB_USER:-}" ]]; then
  export PGUSER="${DB_USER}"
 fi
 if [[ -n "${DB_PASSWORD:-}" ]]; then
  export PGPASSWORD="${DB_PASSWORD}"
 else
  unset PGPASSWORD
 fi
}

##
# Escapes a string for use inside a single-quoted SQL literal.
# Parameters:
#   $1 - raw string.
##
function __sql_escape_literal() {
 local S="${1:-}"
 printf '%s' "${S//\'/\'\'}"
}

##
# Writes UPDATE statements (geometry_ewkt, pair_relation_ids, bbox) into OUTPUT_FILE.
# Precedence per entry: geometry_ewkt, else pair (country_maritime only), else bbox
# (unclaimed only).
# Parameters:
#   $1 - path to output .sql file.
#   $2 - path to disputed_territories_wms_names.json.
##
# shellcheck disable=SC2312
function __write_geometry_updates_sql() {
 local OUTPUT_FILE="${1:?}"
 local JSON_FILE="${2:?}"
 local ENTRY
 local KIND
 local NAME_ESC
 local A_ID
 local B_ID
 local MIN_LON
 local MIN_LAT
 local MAX_LON
 local MAX_LAT
 local EWKT_RAW
 local EWKT_ESC

 {
  echo "BEGIN;"
  echo "SET LOCAL statement_timeout = '30min';"
 } >> "${OUTPUT_FILE}"

 while IFS= read -r ENTRY; do
  KIND=$(echo "${ENTRY}" | jq -r '.kind')
  NAME_ESC=$(__sql_escape_literal "$(echo "${ENTRY}" | jq -r '.name')")
  EWKT_RAW=$(echo "${ENTRY}" | jq -r '.geometry_ewkt // ""')
  if [[ -n "${EWKT_RAW}" ]] && [[ "${EWKT_RAW}" != "null" ]]; then
   EWKT_ESC=$(__sql_escape_literal "${EWKT_RAW}")
   cat >> "${OUTPUT_FILE}" << EOF
UPDATE disputed_territories_wms AS d
SET geom = ST_Multi(ST_GeomFromEWKT('${EWKT_ESC}'))::geometry(MULTIPOLYGON,4326),
    updated_at = CURRENT_TIMESTAMP
WHERE d.kind = '${KIND}'::disputed_territory_kind
 AND d.name = '${NAME_ESC}';
EOF
   continue
  fi
  if echo "${ENTRY}" | jq -e '.pair_relation_ids | length == 2' > /dev/null 2>&1; then
   if [[ "${KIND}" != "country_maritime_intersection" ]]; then
    __logw "Skipping pair_relation_ids for entry with kind=${KIND} (expected country_maritime_intersection)."
   else
    A_ID=$(echo "${ENTRY}" | jq -r '.pair_relation_ids[0]')
    B_ID=$(echo "${ENTRY}" | jq -r '.pair_relation_ids[1]')
    cat >> "${OUTPUT_FILE}" << EOF
UPDATE disputed_territories_wms AS d
SET geom = sub.g,
    updated_at = CURRENT_TIMESTAMP
FROM (
 SELECT
  CASE
   WHEN ist IS NULL OR ST_IsEmpty(ist) THEN NULL::geometry(MULTIPOLYGON,4326)
   WHEN ST_Dimension(ist) < 2 THEN NULL::geometry(MULTIPOLYGON,4326)
   ELSE ST_Multi(ST_CollectionExtract(ist, 3))::geometry(MULTIPOLYGON,4326)
  END AS g
 FROM (
  SELECT ST_Intersection(ST_MakeValid(c1.geom), ST_MakeValid(c2.geom)) AS ist
  FROM countries c1
  INNER JOIN countries c2
   ON c1.country_id = LEAST(${A_ID}::integer, ${B_ID}::integer)
  AND c2.country_id = GREATEST(${A_ID}::integer, ${B_ID}::integer)
 ) x
) sub
WHERE d.kind = '${KIND}'::disputed_territory_kind
 AND d.name = '${NAME_ESC}';
EOF
   fi
  fi
  if echo "${ENTRY}" | jq -e '.bbox | length == 4' > /dev/null 2>&1; then
   if [[ "${KIND}" != "unclaimed_territory" ]]; then
    __logw "Skipping bbox for entry with kind=${KIND} (expected unclaimed_territory)."
   else
    MIN_LON=$(echo "${ENTRY}" | jq -r '.bbox[0]')
    MIN_LAT=$(echo "${ENTRY}" | jq -r '.bbox[1]')
    MAX_LON=$(echo "${ENTRY}" | jq -r '.bbox[2]')
    MAX_LAT=$(echo "${ENTRY}" | jq -r '.bbox[3]')
    cat >> "${OUTPUT_FILE}" << EOF
UPDATE disputed_territories_wms AS d
SET geom = ST_Multi(
  ST_MakeEnvelope(${MIN_LON}::double precision, ${MIN_LAT}::double precision,
   ${MAX_LON}::double precision, ${MAX_LAT}::double precision, 4326)
 )::geometry(MULTIPOLYGON,4326),
 updated_at = CURRENT_TIMESTAMP
WHERE d.kind = '${KIND}'::disputed_territory_kind
 AND d.name = '${NAME_ESC}';
EOF
   fi
  fi
 done < <(jq -c '.entries[]' "${JSON_FILE}")

 echo "COMMIT;" >> "${OUTPUT_FILE}"
}

##
# Validates disputed WMS JSON path and structure.
# Parameters: none.
##
function __validate_disputed_wms_json_file() {
 if [[ ! -f "${DISPUTED_WMS_JSON}" ]]; then
  __loge "ERROR: JSON file not found: ${DISPUTED_WMS_JSON}"
  exit "${ERROR_DATA_VALIDATION:-252}"
 fi
 if ! jq -e '.entries' "${DISPUTED_WMS_JSON}" > /dev/null 2>&1; then
  __loge "ERROR: Invalid JSON structure (missing entries array)."
  exit "${ERROR_DATA_VALIDATION:-252}"
 fi
}

##
# Parameters:
#   $1 - table name (public schema).
##
function __table_exists_public() {
 local TBL="${1:?}"
 local EXISTS
 EXISTS=$(PGAPPNAME="${PGAPPNAME}" psql -U "${DB_USER}" -d "${DBNAME}" -Atq -c \
  "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${TBL}');" \
  2> /dev/null || echo "f")
 [[ "${EXISTS}" == "t" ]]
}

##
# Parameters:
#   $1 - table name.
#   $2 - hint shown when missing (human-readable remediation).
##
function __assert_table_exists() {
 local TBL="${1:?}"
 local HINT="${2:?}"
 local EXISTS_RC
 __table_exists_public "${TBL}"
 EXISTS_RC=$?
 if [[ "${EXISTS_RC}" -eq 0 ]]; then
  return 0
 fi
 __loge "ERROR: Table '${TBL}' does not exist. ${HINT}"
 exit "${ERROR_DATA_VALIDATION:-252}"
}

##
# Creates and seeds disputed_territories_wms when absent (first cron run / new DB).
# Parameters: none.
##
function __ensure_disputed_wms_schema() {
 local EXISTS_RC
 __table_exists_public "disputed_territories_wms"
 EXISTS_RC=$?
 if [[ "${EXISTS_RC}" -eq 0 ]]; then
  return 0
 fi
 __logi "Table disputed_territories_wms not found; applying create + seed (first run)"
 __apply_schema_sql
}

##
# Applies schema create + seed scripts.
# Parameters: none.
##
function __apply_schema_sql() {
 if [[ ! -f "${SQL_WMS_CREATE}" ]] || [[ ! -f "${SQL_WMS_SEED}" ]]; then
  __loge "ERROR: Missing SQL under ${SQL_WMS_DIR}"
  exit "${ERROR_MISSING_LIBRARY:-241}"
 fi
 __logi "Applying ${SQL_WMS_CREATE}"
 PGAPPNAME="${PGAPPNAME}" psql -U "${DB_USER}" -d "${DBNAME}" -v ON_ERROR_STOP=1 \
  -f "${SQL_WMS_CREATE}"
 __logi "Applying ${SQL_WMS_SEED}"
 PGAPPNAME="${PGAPPNAME}" psql -U "${DB_USER}" -d "${DBNAME}" -v ON_ERROR_STOP=1 \
  -f "${SQL_WMS_SEED}"
}

##
# Main refresh: generate SQL and execute against the database.
# Parameters: none.
##
function __run_geometry_refresh() {
 __log_start
 local GEN_SQL="${TMP_DIR}/${BASENAME}_geometry_updates.sql"
 __assert_schema_compatible
 __logi "Proceeding with disputed_territories_wms setup and geometry refresh."
 __ensure_disputed_wms_schema
 __assert_table_exists "disputed_territories_wms" \
  "Schema apply failed or table was dropped; run ${BASENAME}.sh --init manually."
 __assert_table_exists "countries" \
  "Load boundaries with updateCountries.sh (e.g. --base on an empty database)."

 if ! : > "${GEN_SQL}" 2> /dev/null; then
  __loge "ERROR: Cannot write temporary geometry SQL file: ${GEN_SQL}"
  exit "${ERROR_GENERAL:-255}"
 fi
 __logi "Writing geometry UPDATE statements to ${GEN_SQL}"
 __write_geometry_updates_sql "${GEN_SQL}" "${DISPUTED_WMS_JSON}"

 __logi "Executing geometry updates (${GEN_SQL})"
 PGAPPNAME="${PGAPPNAME}" psql -U "${DB_USER}" -d "${DBNAME}" -v ON_ERROR_STOP=1 \
  -f "${GEN_SQL}"

 local TAGGED_NULL
 TAGGED_NULL=$(PGAPPNAME="${PGAPPNAME}" psql -U "${DB_USER}" -d "${DBNAME}" -Atq -c \
  "SELECT COUNT(*) FROM disputed_territories_wms WHERE kind = 'disputed_tagged' AND geom IS NULL;" \
  2> /dev/null || echo "0")
 __logi "Rows still without geometry (disputed_tagged expected): ${TAGGED_NULL}"
 __log_finish
}

function main() {
 if [[ "${BASH_DEBUG:-}" == "true" ]] || [[ "${BASH_DEBUG:-}" == "1" ]]; then
  set -xv
 fi

 __configure_psql_env

 local DO_INIT=false
 local DO_DRY=false
 local ARG
 for ARG in "$@"; do
  case "${ARG}" in
  --init)
   DO_INIT=true
   ;;
  --dry-run)
   DO_DRY=true
   ;;
  -*)
   __loge "ERROR: Unknown option: ${ARG}"
   exit "${ERROR_INVALID_ARGUMENT:-242}"
   ;;
  *)
   __loge "ERROR: Unexpected argument: ${ARG}"
   exit "${ERROR_INVALID_ARGUMENT:-242}"
   ;;
  esac
 done

 # Dry-run only needs jq to expand JSON; skip GDAL/psql stack required for refresh.
 if [[ "${DO_DRY}" == "true" ]]; then
  if ! command -v jq > /dev/null 2>&1; then
   __loge "ERROR: jq is required for ${BASENAME} --dry-run."
   exit "${ERROR_MISSING_LIBRARY}"
  fi
 else
  __checkPrereqsCommands
 fi
 __validate_disputed_wms_json_file

 if [[ "${DO_DRY}" == "true" ]]; then
  __log_start
  __logi "Dry-run: geometry SQL only (no database)."
  local GEN_SQL="${TMP_DIR}/${BASENAME}_geometry_updates.sql"
  if ! : > "${GEN_SQL}" 2> /dev/null; then
   __loge "ERROR: Cannot write temporary geometry SQL file: ${GEN_SQL}"
   exit "${ERROR_GENERAL:-255}"
  fi
  __write_geometry_updates_sql "${GEN_SQL}" "${DISPUTED_WMS_JSON}"
  cat "${GEN_SQL}"
  __log_finish
  exit 0
 fi

 __log_start
 __logi "Disputed territories WMS refresh (${VERSION})"

 if [[ "${DO_INIT}" == "true" ]]; then
  __logi "Initializing schema (create + seed)"
  __apply_schema_sql
 fi

 __run_geometry_refresh
 __log_finish
}

main "$@"
