#!/usr/bin/env bats

# Tests for bin/process/updateDisputedTerritoriesWMS.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-06

bats_require_minimum_version 1.5.0

load "${BATS_TEST_DIRNAME}/../../test_helper"

setup() {
 export SCRIPT_BASE_DIRECTORY="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
 if declare -f setup_test_properties > /dev/null 2>&1; then
  setup_test_properties
 fi
 export TEST_BASE_DIR="${SCRIPT_BASE_DIRECTORY}"
 export TMP_DIR
 TMP_DIR=$(mktemp -d)
 export LOG_FILENAME="${TMP_DIR}/test.log"
 export LOCK="${TMP_DIR}/test.lock"
 export BASENAME="updateDisputedTerritoriesWMS"
}

teardown() {
 if declare -f restore_properties > /dev/null 2>&1; then
  restore_properties
 fi
 rm -rf "${TMP_DIR}"
}

@test "updateDisputedTerritoriesWMS.sh --help exits with help message" {
 run bash "${SCRIPT_BASE_DIRECTORY}/bin/process/updateDisputedTerritoriesWMS.sh" --help
 [ "$status" -eq 1 ]
 [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage"* ]]
}

@test "updateDisputedTerritoriesWMS.sh --dry-run prints SQL with expected updates" {
 run bash "${SCRIPT_BASE_DIRECTORY}/bin/process/updateDisputedTerritoriesWMS.sh" --dry-run
 [ "$status" -eq 0 ]
 [[ "$output" == *"BEGIN;"* ]]
 [[ "$output" == *"disputed_territories_wms"* ]]
 [[ "$output" == *"Ems-Dollard mouth"* ]]
 [[ "$output" == *"Bir Tawil"* ]]
 [[ "$output" == *"COMMIT;"* ]]
}

@test "disputed_territories_wms_names.json is valid and has entries" {
 run jq -e '.entries | length > 0' \
  "${SCRIPT_BASE_DIRECTORY}/data/disputed_territories_wms_names.json"
 [ "$status" -eq 0 ]
}
