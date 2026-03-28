#!/bin/bash

# Quick diagnostic for schema contract compatibility per consumer.
#
# Usage examples:
#   ./bin/monitor/checkSchemaCompatibility.sh
#   ./bin/monitor/checkSchemaCompatibility.sh --consumer ingestion
#   ./bin/monitor/checkSchemaCompatibility.sh --consumer monitoring --db notes
#
# This is the list of error codes:
# 1) Help message displayed
# 242) Invalid argument
# 255) General error
#
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27
VERSION="2026-03-27"

set -euo pipefail
set -E

declare -r BASENAME="checkSchemaCompatibility"
declare SCRIPT_BASE_DIRECTORY
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
 &> /dev/null && pwd)"
readonly SCRIPT_BASE_DIRECTORY

export PGAPPNAME="${BASENAME}"

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare DBNAME="${DBNAME:-notes}"
declare CONSUMER_FILTER="${SCHEMA_CONSUMER:-all}"

# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/bin/lib/functionsProcess.sh"

# Shows script help.
function __show_help() {
 cat << EOF
Schema compatibility quick diagnostic.

Usage:
  $0 [OPTIONS]

Options:
  --consumer VALUE   Consumer to validate: ingestion, api, wms, analytics, monitoring, all.
                     Default: all
  --db VALUE         Database name. Default: notes
  --verbose          Enable debug logs
  --help             Show this help message

Examples:
  $0
  $0 --consumer ingestion
  $0 --consumer monitoring --db osm_notes
EOF
}

# Parses command-line arguments.
function __parse_arguments() {
 while [[ $# -gt 0 ]]; do
  case "${1}" in
  --consumer)
   shift
   CONSUMER_FILTER="${1:-}"
   ;;
  --db)
   shift
   DBNAME="${1:-}"
   ;;
  --verbose)
   LOG_LEVEL="DEBUG"
   ;;
  --help)
   __show_help
   exit 1
   ;;
  *)
   __loge "ERROR: Unknown parameter '${1}'"
   __show_help
   exit 242
   ;;
  esac
  shift
 done
}

# Resolves current schema version from DB.
function __get_db_schema_version() {
 local COMPONENT="${1}"
 psql -d "${DBNAME}" -Atq -c \
  "SELECT version FROM schema_version WHERE component='${COMPONENT}'" \
  2> /dev/null | head -1 || true
}

# Evaluates one consumer against current DB schema version.
function __check_consumer_contract() {
 local CONSUMER="${1}"
 local RESULT=0

 unset SCHEMA_COMPONENT EXPECTED_SCHEMA_MIN EXPECTED_SCHEMA_MAX
 export SCHEMA_CONSUMER="${CONSUMER}"
 __set_schema_contract_range "${SCHEMA_CONSUMER}"

 local COMPONENT="${SCHEMA_COMPONENT:-core}"
 local MIN_VERSION="${EXPECTED_SCHEMA_MIN:-}"
 local MAX_VERSION="${EXPECTED_SCHEMA_MAX:-}"
 local DB_VERSION
 DB_VERSION="$(__get_db_schema_version "${COMPONENT}")"

 if [[ -z "${DB_VERSION}" ]]; then
  __loge "ERROR: component=${COMPONENT} is missing in schema_version"
  return 1
 fi

 local CMP_MIN
 CMP_MIN=$(__compare_semver "${DB_VERSION}" "${MIN_VERSION}")
 if [[ "${CMP_MIN}" == "-1" ]]; then
  __loge "FAIL: ${CONSUMER} expects >= ${MIN_VERSION}, got ${DB_VERSION}"
  RESULT=1
 fi

 if [[ -n "${MAX_VERSION}" ]]; then
  local EFFECTIVE_MAX="${MAX_VERSION}"
  local EXCLUSIVE_MAX="false"
  if [[ "${MAX_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.[xX]$ ]]; then
   EFFECTIVE_MAX="${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0"
   EXCLUSIVE_MAX="true"
  fi
  local CMP_MAX
  CMP_MAX=$(__compare_semver "${DB_VERSION}" "${EFFECTIVE_MAX}")
  if [[ "${EXCLUSIVE_MAX}" == "true" ]] && [[ "${CMP_MAX}" != "-1" ]]; then
   __loge "FAIL: ${CONSUMER} expects < ${MAX_VERSION}, got ${DB_VERSION}"
   RESULT=1
  elif [[ "${EXCLUSIVE_MAX}" != "true" ]] && [[ "${CMP_MAX}" == "1" ]]; then
   __loge "FAIL: ${CONSUMER} expects <= ${MAX_VERSION}, got ${DB_VERSION}"
   RESULT=1
  fi
 fi

 if [[ "${RESULT}" -eq 0 ]]; then
  __logi "OK: ${CONSUMER} component=${COMPONENT} db=${DB_VERSION}"
  __logi "    Range: min=${MIN_VERSION} max=${MAX_VERSION:-none}"
 fi
 return "${RESULT}"
}

function main() {
 __parse_arguments "$@"
 __log_start
 __logi "Schema compatibility diagnostic"
 __logi "Database: ${DBNAME}"

 if ! psql -d "${DBNAME}" -Atq -c "SELECT 1" > /dev/null 2>&1; then
  __loge "ERROR: Cannot connect to DBNAME=${DBNAME}"
  exit "${ERROR_GENERAL}"
 fi

 local EXIT_CODE=0
 local CONSUMER
 local -a CONSUMERS=("ingestion" "api" "wms" "analytics" "monitoring")
 for CONSUMER in "${CONSUMERS[@]}"; do
  if [[ "${CONSUMER_FILTER}" != "all" ]] && [[ "${CONSUMER}" != "${CONSUMER_FILTER}" ]]; then
   continue
  fi
  local CHECK_EXIT_CODE=0
  # shellcheck disable=SC2310
  __check_consumer_contract "${CONSUMER}" || CHECK_EXIT_CODE=$?
  if [[ "${CHECK_EXIT_CODE}" -ne 0 ]]; then
   EXIT_CODE=1
  fi
 done

 if [[ "${EXIT_CODE}" -ne 0 ]]; then
  __loge "Schema compatibility mismatch detected."
  exit "${EXIT_CODE}"
 fi

 __logi "All requested schema compatibility checks passed."
 __log_finish
}

main "$@"
