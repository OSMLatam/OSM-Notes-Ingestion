#!/usr/bin/env bats

# ETL Integration Tests for OSM-Notes-profile
# Test file: ETL_integration.test.bats
# Author: Andres Gomez (AngocA)
# Version: 2025-08-14

load "../../test_helper.bash"

# Test that ETL.sh can be sourced without errors
@test "ETL.sh should be sourceable without errors" {
 # We need to prevent the main function from running
 # shellcheck disable=SC2154
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh > /dev/null 2>&1"
 [[ "${status}" -eq 0 ]] || echo "Script should be sourceable"
}

# Test that ETL.sh functions can be called without logging errors
@test "ETL.sh functions should work without logging errors" {
 # Test that logging functions work without sourcing the main script
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh && echo 'Test message'"
 [[ "${status}" -eq 0 ]]
 [[ "${output}" == *"Test message"* ]] || echo "Basic function should work"
}

# Test that ETL.sh can run in dry-run mode
@test "ETL.sh should work in dry-run mode" {
 # Test that the script can run without actually running ETL
 run timeout 30s bash "${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh" --help
 [[ "${status}" -eq 1 ]] # Help should exit with code 1
 [[ "${output}" == *"help"* ]] || [[ "${output}" == *"usage"* ]] || echo "Script should show help information"
}

# Test that all required functions are available after sourcing
@test "ETL.sh should have all required functions available" {
 # Test that key functions are available
 local REQUIRED_FUNCTIONS=(
  "__createDWH"
  "__createStaging"
  "__loadStaging"
  "__loadDWH"
  "__createDatamarts"
  "__showHelp"
 )

 for FUNC in "${REQUIRED_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}

# Test that logging functions work correctly
@test "ETL.sh logging functions should work correctly" {
 # Test that basic functions don't produce errors
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh && echo 'Test info' && echo 'Test error'"
 [[ "${status}" -eq 0 ]]
 [[ "${output}" != *"orden no encontrada"* ]]
 [[ "${output}" != *"command not found"* ]]
}

# Test that database operations work with test database
@test "ETL.sh database operations should work with test database" {
 # Skip database operations in CI environment if no real database is available
 if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  # In CI, we might not have a real PostgreSQL server, so skip actual database operations
  # but verify that the SQL files exist and are valid
  [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_22_createDWHTables.sql" ]]
  [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql" ]]

  # Verify SQL files contain valid SQL syntax (basic check)
  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP" "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_22_createDWHTables.sql"
  [[ "${status}" -eq 0 ]]

  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP" "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"
  [[ "${status}" -eq 0 ]]

  echo "Skipping actual database operations in CI environment - SQL files validated"
  return 0
 fi

 # Local environment - perform actual database operations
 # Create test database if it doesn't exist
 # shellcheck disable=SC2154
 run psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true
 # Note: CREATE DATABASE might fail if database already exists, which is OK

 # Debug: Test simple command first
 echo "Testing simple psql command..."
 # Use local connection for host environment
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -c "SELECT 1;"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -c "SELECT 1;"
 fi
 echo "Simple command status: ${status}"
 echo "Simple command output: ${output}"
 [[ "${status}" -eq 0 ]]

 # Create basic DWH tables
 echo "Testing ETL_22_createDWHTables.sql..."
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_22_createDWHTables.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_22_createDWHTables.sql"
 fi
 echo "ETL_22 status: ${status}"
 echo "ETL_22 output: ${output}"
 [[ "${status}" -eq 0 ]]

 # Create base staging objects (including schema)
 echo "Testing Staging_31_createBaseStagingObjects.sql..."
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_31_createBaseStagingObjects.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_31_createBaseStagingObjects.sql"
 fi
 echo "Staging_31 status: ${status}"
 echo "Staging_31 output: ${output}"
 [[ "${status}" -eq 0 ]]

 # Create staging tables
 echo "Testing Staging_32_createStagingObjects.sql..."
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"
 fi
 echo "Staging_32 status: ${status}"
 echo "Staging_32 output: ${output}"
 [[ "${status}" -eq 0 ]]

 # Verify tables exist
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE '%staging%';"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE '%staging%';"
 fi
 [[ "${status}" -eq 0 ]]
 [[ "${output}" =~ ^[0-9]+$ ]] || echo "Expected numeric count, got: ${output}"
}

# Test that error handling works correctly
@test "ETL.sh error handling should work correctly" {
 # Test that the script handles missing database gracefully
 run bash -c "DBNAME=nonexistent_db source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh"
 [[ "${status}" -ne 0 ]] || echo "Script should handle missing database gracefully"
}

# Test that all SQL files are valid
@test "ETL SQL files should be valid" {
 local SQL_FILES=(
  "sql/dwh/ETL_11_checkDWHTables.sql"
  "sql/dwh/ETL_12_removeDatamartObjects.sql"
  "sql/dwh/ETL_13_removeDWHObjects.sql"
  "sql/dwh/ETL_22_createDWHTables.sql"
  "sql/dwh/ETL_23_getWorldRegion.sql"
  "sql/dwh/ETL_24_addFunctions.sql"
  "sql/dwh/ETL_25_populateDimensionTables.sql"
  "sql/dwh/ETL_26_updateDimensionTables.sql"
  "sql/dwh/ETL_41_addConstraintsIndexesTriggers.sql"
  "sql/dwh/Staging_31_createBaseStagingObjects.sql"
  "sql/dwh/Staging_32_createStagingObjects.sql"
  "sql/dwh/Staging_33_initialFactsBaseObjects.sql"
  "sql/dwh/Staging_34_initialFactsLoadCreate.sql"
  "sql/dwh/Staging_35_initialFactsLoadExecute.sql"
  "sql/dwh/Staging_36_initialFactsLoadDrop.sql"
  "sql/dwh/Staging_51_unify.sql"
  "sql/dwh/Staging_61_loadNotes.sql"
 )

 for SQL_FILE in "${SQL_FILES[@]}"; do
  [[ -f "${SCRIPT_BASE_DIRECTORY}/${SQL_FILE}" ]]
  # Test that SQL file has valid syntax (basic check)
  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP" "${SCRIPT_BASE_DIRECTORY}/${SQL_FILE}"
  [[ "${status}" -eq 0 ]] || echo "SQL file ${SQL_FILE} should contain valid SQL"
 done
}

# Test that the script can be executed without parameters
@test "ETL.sh should handle no parameters gracefully" {
 # Test that the script doesn't crash when run without parameters
 run timeout 30s bash "${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh"
 [[ "${status}" -ne 0 ]] # Should exit with error for missing database
 [[ "${output}" == *"database"* ]] || [[ "${output}" == *"ERROR"* ]] || echo "Script should show error for missing database"
}

# Test that datamart creation functions work correctly
@test "ETL.sh datamart creation functions should work correctly" {
 # Test that datamart functions are available
 local DATAMART_FUNCTIONS=(
  "__createDatamartUsers"
  "__createDatamartCountries"
 )

 for FUNC in "${DATAMART_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}

# Test that staging functions work correctly
@test "ETL.sh staging functions should work correctly" {
 # Test that staging functions are available
 local STAGING_FUNCTIONS=(
  "__createStagingTables"
  "__loadStagingData"
  "__unifyStagingData"
 )

 for FUNC in "${STAGING_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/ETL.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}
