#!/bin/bash

# Validates consumer schema contracts against the target schema version.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27

set -euo pipefail

declare ROOT_DIR
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
declare -r COMMON_FUNCTIONS_FILE="${ROOT_DIR}/lib/osm-common/commonFunctions.sh"
declare -r COMPATIBILITY_FILE="${ROOT_DIR}/etc/schema_compatibility.sh"
declare -r SCHEMA_SQL_FILE="${ROOT_DIR}/sql/process/processPlanetNotes_21_createBaseTables_tables.sql"

# Resolves target schema version from base schema SQL file.
# Returns:
#  echoes version value
function __resolve_target_schema_version() {
 local VERSION
 VERSION=$(sed -nE \
  "s/.*\('core',[[:space:]]*'([0-9]+\.[0-9]+\.[0-9]+)'\).*/\1/p" \
  "${SCHEMA_SQL_FILE}" | head -1)
 if [[ -z "${VERSION}" ]]; then
  echo "ERROR: Cannot resolve target schema version from ${SCHEMA_SQL_FILE}" >&2
  exit 1
 fi
 echo "${VERSION}"
}

function main() {
 if [[ ! -f "${COMMON_FUNCTIONS_FILE}" ]]; then
  echo "ERROR: Missing file ${COMMON_FUNCTIONS_FILE}" >&2
  exit 1
 fi
 if [[ ! -f "${COMPATIBILITY_FILE}" ]]; then
  echo "ERROR: Missing file ${COMPATIBILITY_FILE}" >&2
  exit 1
 fi
 if [[ ! -f "${SCHEMA_SQL_FILE}" ]]; then
  echo "ERROR: Missing file ${SCHEMA_SQL_FILE}" >&2
  exit 1
 fi

 # shellcheck disable=SC1090
 source "${COMMON_FUNCTIONS_FILE}"
 # shellcheck disable=SC1090
 source "${COMPATIBILITY_FILE}"

 local TARGET_VERSION
 TARGET_VERSION="$(__resolve_target_schema_version)"
 echo "Target schema version: ${TARGET_VERSION}"

 local EXIT_CODE=0
 local CONSUMER
 for CONSUMER in ingestion api wms monitoring; do
  local VALIDATION_EXIT_CODE=0
  # shellcheck disable=SC2310
  __validate_schema_contract_target "${CONSUMER}" "${TARGET_VERSION}" \
   || VALIDATION_EXIT_CODE=$?
  if [[ "${VALIDATION_EXIT_CODE}" -ne 0 ]]; then
   EXIT_CODE=1
  fi
 done

 if [[ "${EXIT_CODE}" -ne 0 ]]; then
  echo "Schema contract validation failed." >&2
  exit "${EXIT_CODE}"
 fi
 echo "Schema contract validation passed."
}

main "$@"
