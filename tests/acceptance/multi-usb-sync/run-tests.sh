#!/usr/bin/env bash
# run-tests.sh — Acceptance test runner for multi-usb-sync
#
# Corresponds to: tests/acceptance/multi-usb-sync/*.feature
# Walking skeleton strategy: C (Real local) — all I/O is local filesystem and mock binaries.
#
# Run with:
#   bash tests/acceptance/multi-usb-sync/run-tests.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SYNC_USB="${REPO_ROOT}/bin/sync-usb.sh"
SYNC_CLOUD="${REPO_ROOT}/bin/sync-cloud.sh"

source "${SCRIPT_DIR}/helpers.sh"

# ---------------------------------------------------------------------------
# Walking Skeleton — @walking_skeleton @real-io @US-001 @US-002
# Scenario: Files are copied to USB drive when a registered drive mounts
# ---------------------------------------------------------------------------
test_ws_usb_sync_copies_directory_to_drive() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local volume_path="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${volume_path}"
    create_mock_diskutil_single "${UUID_A}" "${volume_path}"
    create_mock_rsync "false"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[WS @US-002] USB sync exits 0 when registered drive is connected"
    assert_file_exists "${volume_path}/secureLocal/file1.txt" \
        "[WS @US-002] file1.txt is copied to USB drive mount point"
    assert_file_exists "${volume_path}/secureLocal/file2.txt" \
        "[WS @US-002] file2.txt is copied to USB drive mount point"
    assert_log_contains "${LOG_FILE}" "INFO" \
        "[WS @US-004] log contains an INFO entry after successful sync"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Walking Skeleton — @walking_skeleton @real-io @US-001 @US-003
# Scenario: Files are copied to the cloud on a timer when no USB is present
# ---------------------------------------------------------------------------
test_ws_cloud_sync_runs_without_usb() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"
    # No USB volume created — volumes dir is empty
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_CLOUD}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[WS @US-003] Cloud sync exits 0 with no USB drive present"
    assert_calls_contain "${MOCK_BIN_DIR}/rclone-calls.log" "remote-crypt:secureLocal" \
        "[WS @US-003] rclone is called with the configured cloud destination"
    assert_log_contains "${LOG_FILE}" "INFO" \
        "[WS @US-004] log contains an INFO entry after successful cloud sync"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Walking Skeleton — @walking_skeleton @real-io @US-001 @US-004
# Scenario: Each sync operation produces a readable log entry
# ---------------------------------------------------------------------------
test_ws_log_entry_is_timestamped_and_readable() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local volume_path="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${volume_path}"
    create_mock_diskutil_single "${UUID_A}" "${volume_path}"
    create_mock_rsync "false"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1

    assert_file_exists "${LOG_FILE}" \
        "[WS @US-004] log file is created after sync"
    assert_log_lines_all_timestamped "${LOG_FILE}" \
        "[WS @US-004] every log line begins with an ISO 8601 timestamp"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-001 config-schema — Schema version mismatch exits 4
# ---------------------------------------------------------------------------
test_schema_version_mismatch_usb_exits_4() {
    setup_test_env
    create_mock_config_yaml_v1 "${CONFIG_FILE}"
    create_mock_diskutil_multi > /dev/null
    create_mock_rsync "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-001] USB sync exits 4 on schema version mismatch"

    teardown_test_env
}

test_schema_version_mismatch_cloud_exits_4() {
    setup_test_env
    create_mock_config_yaml_v1 "${CONFIG_FILE}"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_CLOUD}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-001] Cloud sync exits 4 on schema version mismatch"

    teardown_test_env
}

test_missing_config_file_exits_4() {
    setup_test_env
    # Deliberately do not create the config file
    create_mock_diskutil_multi > /dev/null
    create_mock_rsync "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-001] USB sync exits 4 when config file is missing"

    teardown_test_env
}

test_invalid_yaml_config_exits_4() {
    setup_test_env
    create_mock_config_yaml_invalid "${CONFIG_FILE}"
    create_mock_diskutil_multi > /dev/null
    create_mock_rsync "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-001] USB sync exits 4 on malformed YAML config"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-002 usb-sync — UUID matching and isolation
# ---------------------------------------------------------------------------
test_usb_b_does_not_sync_to_usb_a_mount() {
    setup_test_env
    create_mock_config_yaml_multi_dir "${CONFIG_FILE}" "${LOG_FILE}"

    local vol_b="${VOLUMES_DIR}/IronKey-B"
    mkdir -p "${vol_b}"
    create_mock_diskutil_multi > /dev/null
    register_mock_volume "${UUID_B}" "${vol_b}"
    # UUID-A is NOT mounted — no entry for it
    create_mock_rsync "false"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-002] USB sync exits 0 when USB-B is the only connected drive"
    assert_calls_not_contain "${MOCK_BIN_DIR}/rsync-calls.log" "IronKey-A" \
        "[@US-002] No rsync call references the USB-A mount point"
    assert_calls_contain "${MOCK_BIN_DIR}/rsync-calls.log" "IronKey-B" \
        "[@US-002] rsync call references the USB-B mount point"

    teardown_test_env
}

test_unregistered_usb_triggers_no_sync() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local unregistered="${VOLUMES_DIR}/RandomDrive"
    mkdir -p "${unregistered}"
    create_mock_diskutil_multi > /dev/null
    register_mock_volume "FFFF-0000" "${unregistered}"
    create_mock_rsync "false"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-002] Unregistered drive does not cause failure"
    assert_call_count "${MOCK_BIN_DIR}/rsync-calls.log" 0 \
        "[@US-002] No rsync calls made when no registered drive is found"
    assert_log_contains "${LOG_FILE}" "no registered" \
        "[@US-002] Log records that no registered drive was found"

    teardown_test_env
}

test_partial_directory_failure_exits_1() {
    setup_test_env
    create_mock_config_yaml_multi_dir "${CONFIG_FILE}" "${LOG_FILE}"

    local vol_a="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${vol_a}"
    create_mock_diskutil_multi > /dev/null
    register_mock_volume "${UUID_A}" "${vol_a}"
    create_mock_rsync "false"
    create_mock_rclone "false"

    # Remove the second source directory so its sync fails
    rm -rf "${TEST_DIR}/Projects"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 1 "${exit_code}" \
        "[@US-002] Exit code is 1 when one directory fails to sync"
    assert_file_exists "${vol_a}/secureLocal/file-a.txt" \
        "[@US-002] The succeeding directory is still copied despite the failure"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-003 cloud-sync — per-directory remotes, retry behaviour
# ---------------------------------------------------------------------------
test_cloud_sync_calls_rclone_per_directory() {
    setup_test_env
    create_mock_config_yaml_multi_dir "${CONFIG_FILE}" "${LOG_FILE}"
    create_mock_rclone "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_CLOUD}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-003] Cloud sync exits 0 for two directories"
    assert_call_count "${MOCK_BIN_DIR}/rclone-calls.log" 2 \
        "[@US-003] rclone is called once per directory (2 total)"
    assert_calls_contain "${MOCK_BIN_DIR}/rclone-calls.log" "remote-crypt:secureLocal" \
        "[@US-003] rclone called with correct remote for first directory"
    assert_calls_contain "${MOCK_BIN_DIR}/rclone-calls.log" "remote-crypt:Projects" \
        "[@US-003] rclone called with correct remote for second directory"

    teardown_test_env
}

test_cloud_sync_failure_exits_2() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"
    create_mock_rclone "true"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_CLOUD}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 2 "${exit_code}" \
        "[@US-003] Cloud sync exits 2 when rclone fails"
    assert_log_contains "${LOG_FILE}" "ERROR" \
        "[@US-003] Log contains an ERROR entry for the cloud sync failure"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-004 structured-logging — format verification
# ---------------------------------------------------------------------------
test_log_error_entries_match_grep_pattern() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"
    create_mock_rclone "true"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_CLOUD}" > /dev/null 2>&1

    assert_log_contains "${LOG_FILE}" "ERROR" \
        "[@US-004] grep ERROR finds at least one ERROR entry after cloud failure"
    assert_log_not_contains "${LOG_FILE}" "ANSI" \
        "[@US-004] Log contains no ANSI colour codes"
    assert_log_lines_all_timestamped "${LOG_FILE}" \
        "[@US-004] All log lines begin with a timestamp"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-005 device-registration — duplicate UUID rejection
# (Registration subcommand invoked as: install.sh add-device)
# ---------------------------------------------------------------------------
test_duplicate_uuid_registration_rejected() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local vol_a="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${vol_a}"
    create_mock_diskutil_single "${UUID_A}" "${vol_a}"

    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    # This test will go RED until install.sh add-device is implemented:
    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${REPO_ROOT}/bin/install.sh" add-device --volume "${vol_a}" --label "IronKey-A-duplicate" > /dev/null 2>&1
    local exit_code=$?

    local config_after
    config_after=$(cat "${CONFIG_FILE}")

    # Should exit non-zero and leave config unchanged
    if [[ "${exit_code}" -eq 0 ]]; then
        fail "[@US-005] Duplicate UUID registration should exit non-zero but exited 0" \
             "exit code was 0"
    else
        pass "[@US-005] Duplicate UUID registration exits non-zero"
    fi
    if [[ "${config_before}" == "${config_after}" ]]; then
        pass "[@US-005] Config file is unchanged after duplicate UUID rejection"
    else
        fail "[@US-005] Config file is unchanged after duplicate UUID rejection" \
             "config was modified"
    fi

    teardown_test_env
}

test_atomic_write_leaves_no_temp_file() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local vol_b="${VOLUMES_DIR}/IronKey-B"
    mkdir -p "${vol_b}"
    create_mock_diskutil_single "${UUID_B}" "${vol_b}"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${REPO_ROOT}/bin/install.sh" add-device --volume "${vol_b}" --label "IronKey-B" > /dev/null 2>&1

    assert_file_not_exists "${TEST_DIR}/.config/securelocal/config.yaml.tmp" \
        "[@US-005] No temporary config file remains after registration"
    assert_file_not_exists "$(dirname "${CONFIG_FILE}")/config.yaml.tmp" \
        "[@US-005] No .tmp file next to the config after registration"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-006 launchd-automation — plist installation verification
# ---------------------------------------------------------------------------
test_both_plists_recorded_by_launchctl() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"
    create_mock_launchctl

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
    HOME="${TEST_DIR}/home" \
        "${REPO_ROOT}/bin/install.sh" --non-interactive > /dev/null 2>&1 || true

    assert_calls_contain "${MOCK_BIN_DIR}/launchctl-calls.log" "com.securelocal.usb-sync" \
        "[@US-006] install.sh loads the USB sync automation agent"
    assert_calls_contain "${MOCK_BIN_DIR}/launchctl-calls.log" "com.securelocal.cloud-sync" \
        "[@US-006] install.sh loads the cloud sync automation agent"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# @US-007 test-harness — harness isolation verification
# ---------------------------------------------------------------------------
test_mock_rsync_is_invoked_not_real_rsync() {
    setup_test_env
    create_mock_config_yaml "${CONFIG_FILE}" "${LOG_FILE}" "${LOCAL_DIR}" "IronKey-A" "${UUID_A}"

    local vol_a="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${vol_a}"
    create_mock_diskutil_single "${UUID_A}" "${vol_a}"
    create_mock_rsync "false"

    CONFIG_FILE="${CONFIG_FILE}" \
    SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1

    assert_calls_contain "${MOCK_BIN_DIR}/rsync-calls.log" "${LOCAL_DIR}" \
        "[@US-007] Mock rsync records the source path from the sync invocation"

    teardown_test_env
}

test_each_test_gets_isolated_temp_directory() {
    # Run two setup/teardown cycles and confirm the directories differ
    setup_test_env
    local first_dir="${TEST_DIR}"
    teardown_test_env

    setup_test_env
    local second_dir="${TEST_DIR}"
    teardown_test_env

    if [[ "${first_dir}" != "${second_dir}" ]]; then
        pass "[@US-007] Each test setup creates a unique isolated directory"
    else
        fail "[@US-007] Each test setup creates a unique isolated directory" \
             "both setups returned the same directory: ${first_dir}"
    fi
}

# ---------------------------------------------------------------------------
# Test runner — first test enabled (walking skeleton), all others are skip-marked
# in comments per the one-at-a-time mandate. To enable a test, remove the
# 'skip_' prefix from the function call below.
# ---------------------------------------------------------------------------

echo -e "${YELLOW}Running multi-usb-sync acceptance tests...${NC}"
echo ""

# ENABLED — Walking Skeleton (first test)
test_ws_usb_sync_copies_directory_to_drive

# SKIP — enable one at a time after walking skeleton passes
test_ws_cloud_sync_runs_without_usb
test_ws_log_entry_is_timestamped_and_readable
test_schema_version_mismatch_usb_exits_4
test_schema_version_mismatch_cloud_exits_4
test_missing_config_file_exits_4
test_invalid_yaml_config_exits_4
test_usb_b_does_not_sync_to_usb_a_mount
test_unregistered_usb_triggers_no_sync
test_partial_directory_failure_exits_1
test_cloud_sync_calls_rclone_per_directory
test_cloud_sync_failure_exits_2
test_log_error_entries_match_grep_pattern
# test_duplicate_uuid_registration_rejected
# test_atomic_write_leaves_no_temp_file
# test_both_plists_recorded_by_launchctl
test_mock_rsync_is_invoked_not_real_rsync
test_each_test_gets_isolated_temp_directory

print_summary
