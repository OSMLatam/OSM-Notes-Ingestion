#!/bin/bash

# Validates consumer schema contracts against the target schema version.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27

set -euo pipefail

declare ROOT_DIR
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
declare -r COMPATIBILITY_FILE="${ROOT_DIR}/etc/schema_compatibility.sh"
declare -r SCHEMA_SQL_FILE="${ROOT_DIR}/sql/process/processPlanetNotes_21_createBaseTables_tables.sql"

# Compares two semantic versions (MAJOR.MINOR.PATCH).
# Parameters:
#  $1: version A
#  $2: version B
# Returns:
#  echoes 1 if A > B, -1 if A < B, 0 if A == B
function __compare_semver_local() {
 local VERSION_A="${1}"
 local VERSION_B="${2}"
 local IFS='.'
 local -a PARTS_A PARTS_B
 read -r -a PARTS_A <<< "${VERSION_A}"
 read -r -a PARTS_B <<< "${VERSION_B}"
 local INDEX
 for INDEX in 0 1 2; do
  local VALUE_A="${PARTS_A[${INDEX}]:-0}"
  local VALUE_B="${PARTS_B[${INDEX}]:-0}"
  if ((VALUE_A > VALUE_B)); then
   echo 1
   return 0
  fi
  if ((VALUE_A < VALUE_B)); then
   echo -1
   return 0
  fi
 done
 echo 0
}

# Converts wildcard max version X.Y.x to an exclusive upper bound X.(Y+1).0.
# Parameters:
#  $1: max version expression
# Returns:
#  echoes effective max version
function __effective_max_version() {
 local MAX_VERSION="${1}"
 if [[ "${MAX_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.[xX]$ ]]; then
  echo "${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0"
  return 0
 fi
 echo "${MAX_VERSION}"
}

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

# Validates one consumer contract against target version.
# Parameters:
#  $1: consumer id
#  $2: target schema version
function __validate_consumer_contract() {
 local CONSUMER="${1}"
 local TARGET_VERSION="${2}"

 unset SCHEMA_COMPONENT EXPECTED_SCHEMA_MIN EXPECTED_SCHEMA_MAX
 export SCHEMA_CONSUMER="${CONSUMER}"
 __set_schema_contract_range "${SCHEMA_CONSUMER}"

 local COMPONENT="${SCHEMA_COMPONENT:-}"
 local MIN_VERSION="${EXPECTED_SCHEMA_MIN:-}"
 local MAX_VERSION="${EXPECTED_SCHEMA_MAX:-}"

 if [[ -z "${COMPONENT}" ]] || [[ -z "${MIN_VERSION}" ]]; then
  echo "ERROR: Incomplete contract for consumer=${CONSUMER}" >&2
  return 1
 fi

 local MIN_COMPARISON
 MIN_COMPARISON=$(__compare_semver_local "${TARGET_VERSION}" "${MIN_VERSION}")
 if [[ "${MIN_COMPARISON}" == "-1" ]]; then
  echo "ERROR: ${CONSUMER} requires >= ${MIN_VERSION}, target is ${TARGET_VERSION}" >&2
  return 1
 fi

 if [[ -n "${MAX_VERSION}" ]]; then
  local EFFECTIVE_MAX
  local MAX_COMPARISON
  EFFECTIVE_MAX=$(__effective_max_version "${MAX_VERSION}")
  MAX_COMPARISON=$(__compare_semver_local "${TARGET_VERSION}" "${EFFECTIVE_MAX}")

  if [[ "${MAX_VERSION}" =~ \.[xX]$ ]]; then
   if [[ "${MAX_COMPARISON}" != "-1" ]]; then
    echo "ERROR: ${CONSUMER} max is ${MAX_VERSION}, target is ${TARGET_VERSION}" >&2
    return 1
   fi
  elif [[ "${MAX_COMPARISON}" == "1" ]]; then
   echo "ERROR: ${CONSUMER} max is ${MAX_VERSION}, target is ${TARGET_VERSION}" >&2
   return 1
  fi
 fi

 echo "OK: ${CONSUMER} (${COMPONENT}) supports ${TARGET_VERSION}"
 return 0
}

function main() {
 if [[ ! -f "${COMPATIBILITY_FILE}" ]]; then
  echo "ERROR: Missing file ${COMPATIBILITY_FILE}" >&2
  exit 1
 fi
 if [[ ! -f "${SCHEMA_SQL_FILE}" ]]; then
  echo "ERROR: Missing file ${SCHEMA_SQL_FILE}" >&2
  exit 1
 fi

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
  __validate_consumer_contract "${CONSUMER}" "${TARGET_VERSION}" \
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
