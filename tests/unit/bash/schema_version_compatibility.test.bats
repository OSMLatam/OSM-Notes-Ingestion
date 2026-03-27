#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Unit tests for schema version compatibility checks.
# Author: Andres Gomez (AngocA)
# Version: 2026-03-27

load "$(dirname "$BATS_TEST_FILENAME")/../../test_helper.bash"

setup() {
 export SCRIPT_BASE_DIRECTORY="${TEST_BASE_DIR}"
 export TEST_SCHEMA_DB="test_schema_compat_${BATS_TEST_NUMBER}_$$"
}

teardown() {
 psql -d postgres -c "DROP DATABASE IF EXISTS ${TEST_SCHEMA_DB};" \
  > /dev/null 2>&1 || true
}

@test "__compare_semver should compare versions correctly" {
 run bash -c "
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh' >/dev/null 2>&1
  __compare_semver '1.1.0' '1.1.0'
 "
 [ "${status}" -eq 0 ]
 [ "${output}" = "0" ]

 run bash -c "
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh' >/dev/null 2>&1
  __compare_semver '1.1.1' '1.1.0'
 "
 [ "${status}" -eq 0 ]
 [ "${output}" = "1" ]

 run bash -c "
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh' >/dev/null 2>&1
  __compare_semver '1.0.9' '1.1.0'
 "
 [ "${status}" -eq 0 ]
 [ "${output}" = "-1" ]
}

@test "__assert_schema_compatible should accept schema 1.1.x range" {
 if ! command -v psql > /dev/null 2>&1; then
  skip "PostgreSQL client (psql) not available"
 fi
 if ! psql -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
  skip "Cannot connect to PostgreSQL"
 fi

 psql -d postgres -c "CREATE DATABASE ${TEST_SCHEMA_DB};" > /dev/null
 psql -d "${TEST_SCHEMA_DB}" -c "
  CREATE TABLE schema_version (
   component VARCHAR(64) PRIMARY KEY,
   version VARCHAR(16) NOT NULL
  );
  INSERT INTO schema_version(component, version) VALUES ('core', '1.1.7');
 " > /dev/null

 run bash -c "
  export DBNAME='${TEST_SCHEMA_DB}'
  export SCHEMA_COMPONENT='core'
  export EXPECTED_SCHEMA_MIN='1.1.0'
  export EXPECTED_SCHEMA_MAX='1.1.x'
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh'
  __assert_schema_compatible
 "
 [ "${status}" -eq 0 ]
}

@test "__assert_schema_compatible should fail when schema below minimum" {
 if ! command -v psql > /dev/null 2>&1; then
  skip "PostgreSQL client (psql) not available"
 fi
 if ! psql -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
  skip "Cannot connect to PostgreSQL"
 fi

 psql -d postgres -c "CREATE DATABASE ${TEST_SCHEMA_DB};" > /dev/null
 psql -d "${TEST_SCHEMA_DB}" -c "
  CREATE TABLE schema_version (
   component VARCHAR(64) PRIMARY KEY,
   version VARCHAR(16) NOT NULL
  );
  INSERT INTO schema_version(component, version) VALUES ('core', '1.0.9');
 " > /dev/null

 run bash -c "
  export DBNAME='${TEST_SCHEMA_DB}'
  export SCHEMA_COMPONENT='core'
  export EXPECTED_SCHEMA_MIN='1.1.0'
  export EXPECTED_SCHEMA_MAX='1.1.x'
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh'
  __assert_schema_compatible
 "
 [ "${status}" -eq 252 ]
}

@test "__assert_schema_compatible should fail when schema exceeds 1.1.x" {
 if ! command -v psql > /dev/null 2>&1; then
  skip "PostgreSQL client (psql) not available"
 fi
 if ! psql -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
  skip "Cannot connect to PostgreSQL"
 fi

 psql -d postgres -c "CREATE DATABASE ${TEST_SCHEMA_DB};" > /dev/null
 psql -d "${TEST_SCHEMA_DB}" -c "
  CREATE TABLE schema_version (
   component VARCHAR(64) PRIMARY KEY,
   version VARCHAR(16) NOT NULL
  );
  INSERT INTO schema_version(component, version) VALUES ('core', '1.2.0');
 " > /dev/null

 run bash -c "
  export DBNAME='${TEST_SCHEMA_DB}'
  export SCHEMA_COMPONENT='core'
  export EXPECTED_SCHEMA_MIN='1.1.0'
  export EXPECTED_SCHEMA_MAX='1.1.x'
  source '${TEST_BASE_DIR}/lib/osm-common/commonFunctions.sh'
  __assert_schema_compatible
 "
 [ "${status}" -eq 252 ]
}
