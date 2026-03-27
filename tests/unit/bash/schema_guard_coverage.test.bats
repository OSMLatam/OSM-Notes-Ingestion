#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Coverage test to ensure all DB entrypoints validate schema compatibility.
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27

load "$(dirname "$BATS_TEST_FILENAME")/../../test_helper.bash"

@test "all DB entrypoints in bin enforce schema compatibility guard" {
 local ROOT="${TEST_BASE_DIR}"
 local -a ENTRYPOINTS
 local -a MISSING_GUARD
 local -a MISSING_CONTRACT_VARS
 local -a ALL_SCRIPTS
 local SCRIPT

 shopt -s globstar nullglob
 ALL_SCRIPTS=("${ROOT}"/bin/**/*.sh)
 shopt -u globstar

 for SCRIPT in "${ALL_SCRIPTS[@]}"; do
  if [[ "${SCRIPT}" == *"/bin/lib/"* ]]; then
   continue
  fi
  ENTRYPOINTS+=("${SCRIPT}")
 done

 [ "${#ENTRYPOINTS[@]}" -gt 0 ]

 for SCRIPT in "${ENTRYPOINTS[@]}"; do
  # Only analyze executable scripts with shebang (real entrypoints).
  if [[ ! -x "${SCRIPT}" ]]; then
   continue
  fi
  if ! grep -q '^#!' "${SCRIPT}"; then
   continue
  fi

  # DB entrypoint heuristic: script references psql or PGAPPNAME.
  if grep -Eq 'psql|PGAPPNAME' "${SCRIPT}"; then
   if ! grep -q '__assert_schema_compatible' "${SCRIPT}"; then
    MISSING_GUARD+=("${SCRIPT#${ROOT}/}")
   fi

   if ! grep -q 'SCHEMA_CONSUMER' "${SCRIPT}" \
    && { ! grep -q 'SCHEMA_COMPONENT' "${SCRIPT}" \
    || ! grep -q 'EXPECTED_SCHEMA_MIN' "${SCRIPT}" \
    || ! grep -q 'EXPECTED_SCHEMA_MAX' "${SCRIPT}"; }; then
    MISSING_CONTRACT_VARS+=("${SCRIPT#${ROOT}/}")
   fi
  fi
 done

 if [[ "${#MISSING_GUARD[@]}" -gt 0 ]]; then
  echo "Scripts missing __assert_schema_compatible:"
  printf ' - %s\n' "${MISSING_GUARD[@]}"
  false
 fi

 if [[ "${#MISSING_CONTRACT_VARS[@]}" -gt 0 ]]; then
  echo "Scripts missing schema contract vars (SCHEMA_CONSUMER"
  echo "or SCHEMA_COMPONENT + EXPECTED_SCHEMA_MIN/MAX):"
  printf ' - %s\n' "${MISSING_CONTRACT_VARS[@]}"
  false
 fi
}
