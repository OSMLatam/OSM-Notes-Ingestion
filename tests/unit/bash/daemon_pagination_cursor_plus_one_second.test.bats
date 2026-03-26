#!/usr/bin/env bats

# shellcheck disable=SC2154,SC2250,SC2016,SC2034

bats_require_minimum_version 1.5.0

load "$(dirname "$BATS_TEST_FILENAME")/../../test_helper.bash"

setup() {
  local base_dir
  base_dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY="${base_dir}"
  export DAEMON_FILE="${SCRIPT_BASE_DIRECTORY}/bin/process/processAPINotesDaemon.sh"
}

@test "Daemon pagination cursor advances by +1 second" {
  run grep -F -q 'NEXT_CURSOR_PLUS=$(date -u -d' "${DAEMON_FILE}"
  [[ "${status}" -eq 0 ]]

  run grep -F -q '+1 second"' "${DAEMON_FILE}"
  [[ "${status}" -eq 0 ]]
}

@test "Daemon pagination uses order=oldest" {
  run grep -F -q '__download_api_notes_with_dynamic_limit "${API_CURSOR}" "${EFFECTIVE_PAGE_LIMIT}" "oldest"' "${DAEMON_FILE}"
  [[ "${status}" -eq 0 ]]
}

@test "Daemon stops pagination when cursor does not advance" {
  run grep -q 'Pagination cursor did not advance; stopping pagination to avoid loop' "${DAEMON_FILE}"
  [[ "${status}" -eq 0 ]]
}

@test "Cursor risk simulation: partial results in same second can be skipped" {
  # If the API returns only a subset of all notes with updated_at=T on the first page,
  # and the daemon advances the cursor to T+1s, the remaining notes at T can be skipped.
  local CURSOR_TS="2026-03-26T00:00:00Z"

  python3 - <<PY > /dev/null
from datetime import datetime, timedelta, timezone
ts = datetime.strptime("${CURSOR_TS}", "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
print((ts + timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY

  # Model: total notes at the same second T (e.g. updated_at granularity)
  local TOTAL_AT_T=1500

  # First API call with from=T returns only PAGE_LIMIT notes and advances max_note_timestamp to T.
  local FETCHED_PAGE1=1000
  local REMAINING_AT_T=$((TOTAL_AT_T - FETCHED_PAGE1))

  # Daemon advances from=T+1 and will not re-query from=T.
  # So the remaining notes at T are not fetched.
  local FETCHED_PAGE2=0
  local TOTAL_FETCHED=$((FETCHED_PAGE1 + FETCHED_PAGE2))

  [[ "${REMAINING_AT_T}" -gt 0 ]]
  [[ "${TOTAL_FETCHED}" -lt "${TOTAL_AT_T}" ]]
}

@test "Cursor simulation: no loss if all notes at same second fit first page" {
  local CURSOR_TS="2026-03-26T00:00:00Z"

  # Model: total notes at the same second T are <= page limit.
  local TOTAL_AT_T=800

  # First API call returns all.
  local FETCHED_PAGE1="${TOTAL_AT_T}"
  local REMAINING_AT_T=0

  # Daemon moves to T+1; API returns nothing for that second in this model.
  local FETCHED_PAGE2=0
  local TOTAL_FETCHED=$((FETCHED_PAGE1 + FETCHED_PAGE2))

  [[ "${REMAINING_AT_T}" -eq 0 ]]
  [[ "${TOTAL_FETCHED}" -eq "${TOTAL_AT_T}" ]]
}

