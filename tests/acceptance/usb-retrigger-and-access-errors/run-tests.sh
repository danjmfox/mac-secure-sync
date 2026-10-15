#!/usr/bin/env bash
# run-tests.sh — Acceptance tests for usb-retrigger-and-access-errors (ADR-008)
#
# Same harness as launchd-environment: `env -i`, PATH=<mock bin>:/usr/bin:/bin:
# /usr/sbin:/sbin, `/bin/bash <script>` (bash 3.2 on macOS), temp HOME/config only.
# The state file lives next to the temp LOG_FILE, so nothing touches the real HOME.
#
# Run with:
#   bash tests/acceptance/usb-retrigger-and-access-errors/run-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SYNC_USB="${REPO_ROOT}/bin/sync-usb.sh"

# shellcheck source=../multi-usb-sync/helpers.sh
source "${REPO_ROOT}/tests/acceptance/multi-usb-sync/helpers.sh"

LAUNCHD_PATH_TAIL="/usr/bin:/bin:/usr/sbin:/sbin"

# run_launchd_script <script> [VAR=value...]
# Sets OUTPUT and RC. Extra VAR=value arguments are added to the environment.
run_launchd_script() {
    local script="$1"
    shift
    OUTPUT=$(env -i HOME="${FAKE_HOME}" \
        PATH="${MOCK_BIN_DIR}:${LAUNCHD_PATH_TAIL}" \
        CONFIG_FILE="${CONFIG_FILE}" \
        SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "$@" \
        /bin/bash "${script}" 2>&1)
    RC=$?
}

provide_yaml_python3() {
    if env -i HOME="${FAKE_HOME}" PATH="${LAUNCHD_PATH_TAIL}" python3 -c 'import yaml' 2>/dev/null; then
        return 0
    fi
    local candidate
    for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3)"; do
        if [[ -x "${candidate}" ]] && "${candidate}" -c 'import yaml' 2>/dev/null; then
            printf '#!/bin/sh\nexec "%s" "$@"\n' "${candidate}" > "${MOCK_BIN_DIR}/python3"
            chmod +x "${MOCK_BIN_DIR}/python3"
            return 0
        fi
    done
    echo "no PyYAML-capable python3 found; cannot run tests" >&2
    exit 2
}

setup_launchd_env() {
    setup_test_env
    FAKE_HOME="${TEST_DIR}/home"
    mkdir -p "${FAKE_HOME}"
    provide_yaml_python3
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"
    VOLUME_PATH="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${VOLUME_PATH}"
    create_mock_diskutil_single "${UUID_A}" "${VOLUME_PATH}"
    create_mock_rsync "false"
    STATE_FILE="${TEST_DIR}/securelocal-usb-sync.state"
}

# assert_rsync_runs <n> <message>
# The rsync mock also logs openrsync's internal --server calls; count only the
# invocations made by sync-usb.sh (they start with -avh).
assert_rsync_runs() {
    local n
    n=$(grep -c '^-avh' "${MOCK_BIN_DIR}/rsync-calls.log" || true)
    if [[ "${n}" -eq "$1" ]]; then pass "$2"
    else fail "$2" "expected $1 sync-usb rsync runs, got ${n}"; fi
}

# ---------------------------------------------------------------------------
# Defect A: retrigger storm
# ---------------------------------------------------------------------------

test_unchanged_drive_within_interval_is_skipped() {
    setup_launchd_env
    run_launchd_script "${SYNC_USB}"
    assert_rsync_runs 1 "debounce: first run syncs"

    run_launchd_script "${SYNC_USB}"
    assert_exit_code 0 "${RC}" \
        "debounce: second trigger with unchanged drive exits 0"
    assert_rsync_runs 1 "debounce: second trigger does not run rsync"
    assert_log_contains "${LOG_FILE}" "no change since last run, skipping" \
        "debounce: second trigger logs one INFO skip line"
    teardown_test_env
}

test_unchanged_drive_within_interval_is_skipped

# seed_state <ts> <signature>
seed_state() { printf '%s\n%s\n' "$1" "$2" > "${STATE_FILE}"; }

test_skipped_trigger_is_quiet_and_keeps_the_stamp() {
    setup_launchd_env
    run_launchd_script "${SYNC_USB}"
    local before
    before=$(cat "${STATE_FILE}")
    : > "${LOG_FILE}"
    run_launchd_script "${SYNC_USB}"
    assert_log_not_contains "${LOG_FILE}" "USB sync job started" \
        "quiet skip: no 'job started' line"
    if [[ "$(wc -l < "${LOG_FILE}" | tr -d ' ')" == "1" ]]; then pass "quiet skip: exactly one log line"
    else fail "quiet skip: exactly one log line" "log: $(cat "${LOG_FILE}")"; fi
    if [[ "$(cat "${STATE_FILE}")" == "${before}" ]]; then pass "quiet skip: the stamp is not refreshed"
    else fail "quiet skip: the stamp is not refreshed" "state changed"; fi
    teardown_test_env
}

test_skipped_trigger_is_quiet_and_keeps_the_stamp

test_changed_drive_set_always_runs() {
    setup_launchd_env
    seed_state "$(date +%s)" "SOME-OTHER-UUID"
    run_launchd_script "${SYNC_USB}"
    assert_rsync_runs 1 "changed set: a drive that was not there last time triggers a run"
    seed_state "$(date +%s)" "${UUID_A} SOME-OTHER-UUID"
    run_launchd_script "${SYNC_USB}"
    assert_rsync_runs 2 "changed set: a drive that has gone triggers a run"
    teardown_test_env
}

test_changed_drive_set_always_runs

test_elapsed_interval_runs_again() {
    setup_launchd_env
    seed_state "$(( $(date +%s) - 1000 ))" "${UUID_A}"
    run_launchd_script "${SYNC_USB}"
    assert_rsync_runs 1 "interval: unchanged drive runs again after the default 600 s"
    seed_state "$(( $(date +%s) - 100 ))" "${UUID_A}"
    run_launchd_script "${SYNC_USB}" SECURELOCAL_MIN_INTERVAL=50
    assert_rsync_runs 2 "interval: SECURELOCAL_MIN_INTERVAL overrides the default"
    seed_state "$(( $(date +%s) - 100 ))" "${UUID_A}"
    run_launchd_script "${SYNC_USB}" SECURELOCAL_MIN_INTERVAL=abc
    assert_rsync_runs 2 "interval: a non-numeric override falls back to 600 s"
    teardown_test_env
}

test_elapsed_interval_runs_again

# create_failing_rsync — rsync exits 20 without copying; sleep is mocked.
create_failing_rsync() {
    cat > "${MOCK_BIN_DIR}/rsync" <<SCRIPT
#!/bin/bash
for a in "\$@"; do [[ "\$a" == --server ]] && exec /usr/bin/rsync "\$@"; done
echo "\$@" >> "${MOCK_BIN_DIR}/rsync-calls.log"
exit 20
SCRIPT
    printf '#!/bin/bash\nexit 0\n' > "${MOCK_BIN_DIR}/sleep"
    chmod +x "${MOCK_BIN_DIR}/rsync" "${MOCK_BIN_DIR}/sleep"
}

test_failed_run_is_stamped_and_retried_after_the_interval() {
    setup_launchd_env
    create_failing_rsync
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 1 "${RC}" "failure: a failing run exits 1"
    assert_file_exists "${STATE_FILE}" "failure: a failed run still writes the stamp"
    local runs_after_first
    runs_after_first=$(grep -c '^-avh' "${MOCK_BIN_DIR}/rsync-calls.log")
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 0 "${RC}" "failure: the next trigger inside the interval is skipped"
    assert_rsync_runs "${runs_after_first}" "failure: no rsync inside the interval"
    seed_state "$(( $(date +%s) - 1000 ))" "${UUID_A}"
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 1 "${RC}" "failure: the job retries once the interval has passed"
    assert_rsync_runs "$(( runs_after_first * 2 ))" "failure: rsync ran again after the interval"
    teardown_test_env
}

test_failed_run_is_stamped_and_retried_after_the_interval

test_live_lock_skips_and_stale_lock_is_taken_over() {
    setup_launchd_env
    local lock="${TEST_DIR}/securelocal-usb-sync.lock"
    sleep 30 &
    local holder=$!
    mkdir "${lock}"; echo "${holder}" > "${lock}/pid"
    run_launchd_script "${SYNC_USB}"
    kill "${holder}" 2>/dev/null; wait "${holder}" 2>/dev/null
    assert_exit_code 0 "${RC}" "lock: a run overlapping a live one exits 0"
    assert_rsync_runs 0 "lock: the overlapping run does not sync"
    assert_log_contains "${LOG_FILE}" "another USB sync run is in progress" \
        "lock: the overlap is logged"
    assert_dir_exists "${lock}" "lock: the live holder's lock is left alone"

    echo "999999" > "${lock}/pid"
    run_launchd_script "${SYNC_USB}"
    assert_rsync_runs 1 "lock: a stale lock (dead pid) does not block the run"
    assert_file_not_exists "${lock}/pid" "lock: the lock is released when the run ends"
    teardown_test_env
}

test_live_lock_skips_and_stale_lock_is_taken_over

test_decide_run_is_pure_and_total() {
    # shellcheck source=../../../bin/lib/run-gate.sh
    source "${REPO_ROOT}/bin/lib/run-gate.sh"
    local row sig now last_sig last_ts interval want got bad=""
    # signature now last_signature last_ts interval want
    while IFS='|' read -r sig now last_sig last_ts interval want; do
        got=$(decide_run "${sig}" "${now}" "${last_sig}" "${last_ts}" "${interval}")
        [[ "${got}" == "${want}" ]] || bad="${bad} [${sig}|${now}|${last_sig}|${last_ts}|${interval} -> ${got}, want ${want}]"
    done <<'ROWS'
A|1000|A|900|600|skip
A|1000|A|400|600|run
A|1000|A|401|600|skip
A|1000|A|400|0|run
A|1000|B|900|600|run
|1000||900|600|skip
A|1000|A||600|run
A|1000|A|junk|600|run
A|1000|A|2000|600|run
ROWS
    if [[ -z "${bad}" ]]; then pass "decide_run: skip/run table (boundary, changed set, empty set, bad stamp, clock back)"
    else fail "decide_run: skip/run table" "${bad}"; fi
    if [[ "$(printf 'b\na\nb\n\n' | signature_from_uuids)" == "a b" ]]; then pass "signature: sorted, unique, space-joined"
    else fail "signature: sorted, unique, space-joined" "got '$(printf 'b\na\nb\n\n' | signature_from_uuids)'"; fi
}

test_decide_run_is_pure_and_total

# ---------------------------------------------------------------------------
# Defect B: exit 23 with nothing transferred
# ---------------------------------------------------------------------------

# create_scripted_rsync <exit_code> <stdout_file>
# rsync prints the file's content on stdout and exits with the code; sleep is
# recorded, not waited for.
create_scripted_rsync() {
    : > "${MOCK_BIN_DIR}/rsync-calls.log"
    : > "${MOCK_BIN_DIR}/sleep-calls.log"
    cp "$2" "${MOCK_BIN_DIR}/rsync-output"
    cat > "${MOCK_BIN_DIR}/rsync" <<SCRIPT
#!/bin/bash
for a in "\$@"; do [[ "\$a" == --server ]] && exec /usr/bin/rsync "\$@"; done
echo "\$@" >> "${MOCK_BIN_DIR}/rsync-calls.log"
cat "${MOCK_BIN_DIR}/rsync-output"
exit $1
SCRIPT
    printf '#!/bin/bash\necho "$@" >> "%s/sleep-calls.log"\n' "${MOCK_BIN_DIR}" > "${MOCK_BIN_DIR}/sleep"
    chmod +x "${MOCK_BIN_DIR}/rsync" "${MOCK_BIN_DIR}/sleep"
}

test_exit_23_with_access_denied_and_nothing_transferred_is_a_failure() {
    setup_launchd_env
    local out="${TEST_DIR}/rsync-out"
    cat > "${out}" <<'OUT'
Transfer starting: 0 files
rsync: opendir "/Users/x/secureLocal/Documents": Operation not permitted
Number of files: 0
Number of files transferred: 0
OUT
    create_scripted_rsync 23 "${out}"
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 1 "${RC}" "access denied: job exits 1"
    assert_rsync_runs 2 "access denied: retried once"
    assert_calls_contain "${MOCK_BIN_DIR}/sleep-calls.log" "^30$" \
        "access denied: waited 30s before the retry"
    assert_log_contains "${LOG_FILE}" "ERROR sync-usb secureLocal .*Full Disk Access.*/bin/bash.*README" \
        "access denied: ERROR names the likely cause and points to the README"
    assert_log_contains "${LOG_FILE}" "one or more USB syncs failed" \
        "access denied: final status is failure"
    assert_log_not_contains "${LOG_FILE}" "completed with skips\|remaining files were synced" \
        "access denied: not reported as completed with skips"
    teardown_test_env
}

test_exit_23_with_access_denied_and_nothing_transferred_is_a_failure

test_exit_23_with_transfers_or_without_access_errors_stays_with_skips() {
    local label code body
    for label in "transferred-with-denied-file" "up-to-date-no-access-error"; do
        setup_launchd_env
        local out="${TEST_DIR}/rsync-out"
        if [[ "${label}" == "transferred-with-denied-file" ]]; then
            printf 'rsync: open "x": Operation not permitted\nNumber of files transferred: 3\n' > "${out}"
        else
            printf 'Number of files: 5\nNumber of files transferred: 0\n' > "${out}"
        fi
        create_scripted_rsync 23 "${out}"
        run_launchd_script "${SYNC_USB}"
        assert_exit_code 3 "${RC}" "exit 23 ${label}: exits 3 (completed with skips)"
        assert_rsync_runs 1 "exit 23 ${label}: not retried"
        teardown_test_env
    done
}

test_exit_23_with_transfers_or_without_access_errors_stays_with_skips

test_rsync_result_parsing() {
    # shellcheck source=../../../bin/lib/rsync-result.sh
    source "${REPO_ROOT}/bin/lib/rsync-result.sh"
    local got
    got=$(printf 'Number of files: 9\nNumber of files transferred: 4\n' | rsync_files_transferred)
    [[ "${got}" == "4" ]] && pass "parse: openrsync transferred count" || fail "parse: openrsync transferred count" "got ${got}"
    got=$(printf 'Number of regular files transferred: 7\n' | rsync_files_transferred)
    [[ "${got}" == "7" ]] && pass "parse: rsync 3 transferred count" || fail "parse: rsync 3 transferred count" "got ${got}"
    got=$(printf 'no stats here\n' | rsync_files_transferred)
    [[ "${got}" == "0" ]] && pass "parse: missing stats count as 0" || fail "parse: missing stats count as 0" "got ${got}"
    printf 'x: Permission denied (13)\n' | rsync_output_has_access_error \
        && pass "parse: Permission denied is an access error" || fail "parse: Permission denied is an access error" "not detected"
    printf 'all fine\n' | rsync_output_has_access_error \
        && fail "parse: clean output has no access error" "false positive" || pass "parse: clean output has no access error"
}

test_rsync_result_parsing

print_summary
