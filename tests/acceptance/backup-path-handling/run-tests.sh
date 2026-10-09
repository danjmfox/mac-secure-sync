#!/usr/bin/env bash
# run-tests.sh — Acceptance test runner for backup-path-handling
#
# Corresponds to: tests/acceptance/backup-path-handling/*.feature
# Sources multi-usb-sync/helpers.sh unchanged. Drives the real
# backup_rclone_config (install.sh is sourced; main does not run) with a
# temp HOME and cwd, so nothing outside the temp tree is touched.
#
# Run with:
#   bash tests/acceptance/backup-path-handling/run-tests.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL="${REPO_ROOT}/bin/install.sh"

# shellcheck source=../multi-usb-sync/helpers.sh
source "${REPO_ROOT}/tests/acceptance/multi-usb-sync/helpers.sh"

# run_backup <stdin_text>
# Runs backup_rclone_config with HOME=${FAKE_HOME}, cwd=${FAKE_CWD}.
# Sets OUTPUT and RC.
run_backup() {
    OUTPUT=$(cd "${FAKE_CWD}" && HOME="${FAKE_HOME}" INSTALL="${INSTALL}" \
        bash -c 'source "${INSTALL}" && backup_rclone_config' <<< "$1" 2>&1)
    RC=$?
}

setup_backup_env() {
    setup_test_env
    FAKE_HOME="${TEST_DIR}/home"
    FAKE_CWD="${TEST_DIR}/cwd"
    mkdir -p "${FAKE_HOME}/.config/rclone" "${FAKE_CWD}"
    echo "[remote]" > "${FAKE_HOME}/.config/rclone/rclone.conf"
    TODAY=$(date +%Y%m%d)
}

test_tilde_path_expands_to_home() {
    setup_backup_env
    run_backup $'y\n~/crypt-backup'
    assert_file_exists "${FAKE_HOME}/crypt-backup/rclone.conf.backup-${TODAY}" \
        "tilde path: backup lands under HOME"
    assert_file_not_exists "${FAKE_CWD}/~" \
        "tilde path: no '~' directory created in cwd"
    teardown_test_env
}

test_tilde_path_expands_to_home

test_relative_path_is_rejected() {
    setup_backup_env
    run_backup $'y\nx/y\n'
    assert_file_not_exists "${FAKE_CWD}/x" \
        "relative path: nothing created in cwd"
    assert_log_contains <(echo "${OUTPUT}") "must be absolute" \
        "relative path: installer explains the path must be absolute"
    assert_log_contains <(echo "${OUTPUT}") "Skipped backup" \
        "relative path: loop ends on empty input with backup skipped"
    teardown_test_env
}

test_relative_path_is_rejected

test_absolute_path_still_works() {
    setup_backup_env
    run_backup $'y\n'"${TEST_DIR}/abs-backup"
    assert_file_exists "${TEST_DIR}/abs-backup/rclone.conf.backup-${TODAY}" \
        "absolute path: backup lands at the typed location"
    teardown_test_env
}

test_absolute_path_still_works

test_backup_is_private() {
    setup_backup_env
    chmod 644 "${FAKE_HOME}/.config/rclone/rclone.conf"
    run_backup $'y\n~/a/b/c'
    local bad="" d
    for d in a a/b a/b/c; do
        [[ "$(stat -f %Lp "${FAKE_HOME}/${d}")" == "700" ]] || bad+=" ${d}"
    done
    if [[ -z "${bad}" ]]; then
        pass "private backup: every created directory is mode 700"
    else
        fail "private backup: every created directory is mode 700" "not 700:${bad}"
    fi
    local mode
    mode=$(stat -f %Lp "${FAKE_HOME}/a/b/c/rclone.conf.backup-${TODAY}")
    if [[ "${mode}" == "600" ]]; then
        pass "private backup: backup file is mode 600"
    else
        fail "private backup: backup file is mode 600" "got ${mode}"
    fi
    teardown_test_env
}

test_backup_is_private

print_summary
