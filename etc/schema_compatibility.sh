#!/bin/bash

# Central schema compatibility contracts by consumer.
#
# Durable user identity: core schema 1.2.0+ (osm_user_* tables) is owned by
# OSM-Notes-Ingestion. OSM-Notes-API and OSM-Notes-Analytics should expect
# schema_version.core in [EXPECTED_SCHEMA_MIN, EXPECTED_SCHEMA_MAX]; optional
# reads use views in sql/process/osm_user_identity_23_createFunctionsAndViews.sql.
# See also OSM-Notes-Analytics/sql/dwh/ETL_00_ingestion_user_identity_contract.sql
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-23

# Sets schema compatibility variables for a consumer.
# Parameters:
#  $1: consumer id (ingestion, api, wms, analytics, monitoring)
function __set_schema_contract_range() {
 local CONSUMER="${1:-${SCHEMA_CONSUMER:-ingestion}}"

 case "${CONSUMER}" in
 ingestion)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 api)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 wms)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 analytics)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 monitoring)
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 *)
  # Safe fallback to ingestion contract.
  export SCHEMA_COMPONENT="${SCHEMA_COMPONENT:-core}"
  export EXPECTED_SCHEMA_MIN="${EXPECTED_SCHEMA_MIN:-1.2.0}"
  export EXPECTED_SCHEMA_MAX="${EXPECTED_SCHEMA_MAX:-1.2.x}"
  ;;
 esac
}
