#!/bin/bash

# Central schema compatibility contracts by consumer.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27

# Sets schema compatibility variables for a consumer.
# Parameters:
#  $1: consumer id (ingestion, api, wms, monitoring)
function __set_schema_contract_range() {
 local CONSUMER="${1:-${SCHEMA_CONSUMER:-ingestion}}"

 case "${CONSUMER}" in
 ingestion)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.1.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.1.x}"
  ;;
 api)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.1.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.1.x}"
  ;;
 wms)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.1.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.1.x}"
  ;;
 monitoring)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.1.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.1.x}"
  ;;
 *)
  # Safe fallback to ingestion contract.
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.1.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.1.x}"
  ;;
 esac
}
