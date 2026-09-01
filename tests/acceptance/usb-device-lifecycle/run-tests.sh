#!/usr/bin/env bash
# run-tests.sh — Acceptance test runner for usb-device-lifecycle
#
# Corresponds to: tests/acceptance/usb-device-lifecycle/*.feature
# Extends: tests/acceptance/multi-usb-sync (sources its helpers.sh unchanged,
# per DESIGN's Reuse Analysis verdict — no mock factory duplication).
# Walking skeleton strategy: C (Real local) — inherited unchanged from multi-usb-sync.
#
# Run with:
#   bash tests/acceptance/usb-device-lifecycle/run-tests.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL="${REPO_ROOT}/bin/install.sh"
SYNC_USB="${REPO_ROOT}/bin/sync-usb.sh"

# shellcheck source=../multi-usb-sync/helpers.sh
source "${REPO_ROOT}/tests/acceptance/multi-usb-sync/helpers.sh"

# ---------------------------------------------------------------------------
# Local fixtures (usb-device-lifecycle-specific; do not touch the reused
# multi-usb-sync/helpers.sh, per DESIGN's REUSE-unchanged verdict)
# ---------------------------------------------------------------------------

UUID_C="TEST-UUID-CCCC"

# create_three_device_config <config_path> <log_file>
# 3 registered devices (IronKey-A/B/C), 2 directories, each mapped to all three.
# Mirrors DISCUSS Domain Example #1 for US-101.
create_three_device_config() {
    local config_path="$1"
    local log_file="$2"
    local dir_a="${TEST_DIR}/secureLocal"
    local dir_b="${TEST_DIR}/Projects"
    mkdir -p "${dir_a}" "${dir_b}"
    echo "source content A" > "${dir_a}/file-a.txt"
    echo "source content B" > "${dir_b}/file-b.txt"

    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories:
  - local_path: ${dir_a}
    cloud_remote: remote-crypt:secureLocal
    usb_devices:
      - ${UUID_A}
      - ${UUID_B}
      - ${UUID_C}
  - local_path: ${dir_b}
    cloud_remote: remote-crypt:Projects
    usb_devices:
      - ${UUID_A}
      - ${UUID_B}
      - ${UUID_C}
usb_devices:
  - id: ${UUID_A}
    label: IronKey-A
  - id: ${UUID_B}
    label: IronKey-B
  - id: ${UUID_C}
    label: IronKey-C
YAML
}

# create_config_with_lone_directory_device <config_path> <log_file>
# ~/Projects is mapped ONLY to IronKey-C. Mirrors DISCUSS Boundary Example #3.
create_config_with_lone_directory_device() {
    local config_path="$1"
    local log_file="$2"
    local dir_a="${TEST_DIR}/secureLocal"
    local dir_b="${TEST_DIR}/Projects"
    mkdir -p "${dir_a}" "${dir_b}"

    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories:
  - local_path: ${dir_a}
    cloud_remote: remote-crypt:secureLocal
    usb_devices:
      - ${UUID_A}
      - ${UUID_B}
      - ${UUID_C}
  - local_path: ${dir_b}
    cloud_remote: remote-crypt:Projects
    usb_devices:
      - ${UUID_C}
usb_devices:
  - id: ${UUID_A}
    label: IronKey-A
  - id: ${UUID_B}
    label: IronKey-B
  - id: ${UUID_C}
    label: IronKey-C
YAML
}

# create_empty_registry_config <config_path> <log_file>
create_empty_registry_config() {
    local config_path="$1"
    local log_file="$2"
    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories: []
usb_devices: []
YAML
}

# create_config_with_malicious_label <config_path> <log_file> <marker_path>
# Seeds a single registered device whose label carries a double-quote
# breakout payload targeting the config-mutation heredocs (security regression,
# see docs/feature/usb-device-lifecycle/deliver security-fix-01). The payload
# would execute `touch <marker_path>` if the label ever reached raw
# bash-into-Python string interpolation instead of env-var passing.
UUID_INJECT="TEST-UUID-INJECT"
malicious_label_for() {
    local marker_path="$1"
    printf '%s' 'IronKey"; import os; os.system("touch '"${marker_path}"'"); x="'
}
create_config_with_malicious_label() {
    local config_path="$1"
    local log_file="$2"
    local marker_path="$3"
    local label
    label="$(malicious_label_for "${marker_path}")"
    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories: []
usb_devices:
  - id: ${UUID_INJECT}
    label: '${label}'
YAML
}

# create_config_with_single_quote_label <config_path> <log_file> <marker_path>
# Seeds a single registered device whose label carries a single-quote breakout
# payload targeting list-devices' eval-based label rendering (security
# regression, see docs/feature/usb-device-lifecycle/deliver security-fix-02).
# The payload would execute `touch <marker_path>` if the label ever reached
# bash's `eval` as a syntax-sensitive single-quoted assignment.
UUID_INJECT_SQ="TEST-UUID-INJECT-SQ"
single_quote_label_for() {
    local marker_path="$1"
    printf '%s' "IronKey'; touch ${marker_path}; x='"
}
create_config_with_single_quote_label() {
    local config_path="$1"
    local log_file="$2"
    local marker_path="$3"
    local label
    label="$(single_quote_label_for "${marker_path}")"
    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories: []
usb_devices:
  - id: ${UUID_INJECT_SQ}
    label: "${label}"
YAML
}

# create_mock_diskutil_erroring
# Simulates diskutil failing to resolve any volume (subprocess error path).
create_mock_diskutil_erroring() {
    cat > "${MOCK_BIN_DIR}/diskutil" <<'SCRIPT'
#!/usr/bin/env bash
echo "diskutil: mock query failure" >&2
exit 1
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/diskutil"
}

# assert_device_entry_unchanged <before_file> <after_file> <uuid> <test_name>
# Compares the usb_devices[] entry for <uuid> between two config snapshots.
# Observable-outcome assertion over the driving port's on-disk artifact —
# not an internal-state check.
assert_device_entry_unchanged() {
    local before_file="$1"
    local after_file="$2"
    local uuid="$3"
    local test_name="$4"
    local before_entry after_entry
    before_entry=$(python3 -c "
import yaml
with open('${before_file}') as f:
    cfg = yaml.safe_load(f)
for d in cfg.get('usb_devices', []):
    if d.get('id') == '${uuid}':
        print(d)
" 2>/dev/null)
    after_entry=$(python3 -c "
import yaml
with open('${after_file}') as f:
    cfg = yaml.safe_load(f)
for d in cfg.get('usb_devices', []):
    if d.get('id') == '${uuid}':
        print(d)
" 2>/dev/null)
    if [[ -n "${before_entry}" ]] && [[ "${before_entry}" == "${after_entry}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "entry for ${uuid} changed or missing (before='${before_entry}' after='${after_entry}')"
    fi
}

# assert_exit_code_nonzero <actual_exit_code> <test_name>
# Rejection-path commands only guarantee non-zero, not a specific code.
assert_exit_code_nonzero() {
    local actual="$1"
    local test_name="$2"
    if [[ "${actual}" -ne 0 ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "exit code was 0"
    fi
}

# assert_config_unchanged <before> <after> <test_name> [reason]
# Byte-for-byte comparison of a config.yaml snapshot taken before and after
# a rejected mutation attempt.
assert_config_unchanged() {
    local before="$1"
    local after="$2"
    local test_name="$3"
    local reason="${4:-config was modified}"
    if [[ "${before}" == "${after}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "${reason}"
    fi
}

# ---------------------------------------------------------------------------
# remove-device.feature — @US-101
# ---------------------------------------------------------------------------

# @walking_skeleton @real-io @US-101 @driving_port
test_ws_remove_device_by_label_leaves_others_unchanged() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local before_snapshot="${TEST_DIR}/config.before.yaml"
    cp "${CONFIG_FILE}" "${before_snapshot}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[WS @US-101] remove-device exits 0 on successful removal by label"
    assert_log_not_contains "${CONFIG_FILE}" "IronKey-C" \
        "[WS @US-101] usb_devices[] no longer contains IronKey-C"
    assert_device_entry_unchanged "${before_snapshot}" "${CONFIG_FILE}" "${UUID_A}" \
        "[WS @US-101] IronKey-A's entry is byte-for-byte identical to before removal"
    assert_device_entry_unchanged "${before_snapshot}" "${CONFIG_FILE}" "${UUID_B}" \
        "[WS @US-101] IronKey-B's entry is byte-for-byte identical to before removal"
    if echo "${output}" | grep -q "2 devices remain registered"; then
        pass "[WS @US-101] command output confirms '2 devices remain registered'"
    else
        fail "[WS @US-101] command output confirms '2 devices remain registered'" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# @US-101 @driving_port
test_remove_device_strips_uuid_from_every_directory_mapping() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" > /dev/null 2>&1

    assert_log_not_contains "${CONFIG_FILE}" "${UUID_C}" \
        "[@US-101] IronKey-C's UUID no longer appears anywhere in config.yaml"
    assert_log_contains "${CONFIG_FILE}" "secureLocal" \
        "[@US-101] the secureLocal directory entry still exists"
    assert_log_contains "${CONFIG_FILE}" "Projects" \
        "[@US-101] the Projects directory entry still exists"

    teardown_test_env
}

# @US-101 @driving_port
test_remove_device_by_uuid_matches_removal_by_label() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --uuid "${UUID_C}" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-101] remove-device by UUID exits 0"
    assert_log_not_contains "${CONFIG_FILE}" "IronKey-C" \
        "[@US-101] removal by UUID removes the device from usb_devices[]"
    assert_log_not_contains "${CONFIG_FILE}" "${UUID_C}" \
        "[@US-101] removal by UUID strips the UUID from every directory mapping"

    teardown_test_env
}

# @US-101 @boundary @driving_port
test_remove_device_leaves_empty_directory_list_not_error() {
    setup_test_env
    create_config_with_lone_directory_device "${CONFIG_FILE}" "${LOG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-101] removing the only device mapped to a directory exits 0, not an error"
    assert_log_not_contains "${CONFIG_FILE}" "${UUID_C}" \
        "[@US-101] the lone directory's usb_devices list no longer references IronKey-C"

    teardown_test_env
}

# @US-101 @error-path @driving_port
test_remove_device_unknown_label_leaves_config_untouched() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-Z" 2>&1)
    local exit_code=$?
    local config_after
    config_after=$(cat "${CONFIG_FILE}")

    assert_exit_code_nonzero "${exit_code}" \
        "[@US-101] remove-device exits non-zero for an unknown label"
    assert_config_unchanged "${config_before}" "${config_after}" \
        "[@US-101] config.yaml is byte-for-byte unchanged after unknown-label rejection"
    if echo "${output}" | grep -q "list-devices"; then
        pass "[@US-101] error message names list-devices as the recovery step"
    else
        fail "[@US-101] error message names list-devices as the recovery step" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# @US-101 @error-path @driving_port
test_remove_device_unknown_uuid_leaves_config_untouched() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --uuid "FFFF-0000" 2>&1)
    local exit_code=$?
    local config_after
    config_after=$(cat "${CONFIG_FILE}")

    assert_exit_code_nonzero "${exit_code}" \
        "[@US-101] remove-device exits non-zero for an unknown UUID"
    assert_config_unchanged "${config_before}" "${config_after}" \
        "[@US-101] config.yaml is byte-for-byte unchanged after unknown-UUID rejection"
    if echo "${output}" | grep -q "list-devices"; then
        pass "[@US-101] error message names list-devices as the recovery step"
    else
        fail "[@US-101] error message names list-devices as the recovery step" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# @US-101 @error-path @infrastructure-failure @driving_port
test_remove_device_missing_config_exits_config_error() {
    setup_test_env
    # Deliberately do not create the config file

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-101] remove-device exits 4 when config.yaml is missing"

    teardown_test_env
}

# @US-101 @error-path @infrastructure-failure @driving_port
test_remove_device_malformed_config_exits_config_error() {
    setup_test_env
    create_mock_config_yaml_invalid "${CONFIG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-101] remove-device exits 4 on malformed YAML config"

    teardown_test_env
}

# @US-101 @error-path @driving_port
test_remove_device_requires_an_identifier() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device > /dev/null 2>&1
    local exit_code=$?
    local config_after
    config_after=$(cat "${CONFIG_FILE}")

    assert_exit_code_nonzero "${exit_code}" \
        "[@US-101] remove-device with neither --label nor --uuid exits non-zero"
    assert_config_unchanged "${config_before}" "${config_after}" \
        "[@US-101] config.yaml is unchanged when no identifier is given"

    teardown_test_env
}

# @US-101 @error-path @driving_port
test_remove_device_rejects_both_label_and_uuid() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" --uuid "${UUID_C}" > /dev/null 2>&1
    local exit_code=$?
    local config_after
    config_after=$(cat "${CONFIG_FILE}")

    assert_exit_code_nonzero "${exit_code}" \
        "[@US-101] remove-device with both --label and --uuid exits non-zero"
    assert_config_unchanged "${config_before}" "${config_after}" \
        "[@US-101] config.yaml is unchanged when both identifiers are given"

    teardown_test_env
}

# @US-101 @real-io @driving_port
test_remove_device_writes_config_atomically() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "IronKey-C" > /dev/null 2>&1

    assert_file_not_exists "${CONFIG_FILE}.tmp" \
        "[@US-101] no temporary config file remains after remove-device completes"
    assert_file_exists "${CONFIG_FILE}" \
        "[@US-101] the final config.yaml exists and is readable"

    teardown_test_env
}

# @US-101 @security @driving_port
test_remove_device_malicious_label_no_code_execution() {
    setup_test_env
    local marker_path="${TEST_DIR}/pwned-marker"
    local malicious_label
    malicious_label="$(malicious_label_for "${marker_path}")"
    create_config_with_malicious_label "${CONFIG_FILE}" "${LOG_FILE}" "${marker_path}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" remove-device --label "${malicious_label}" 2>&1)
    local exit_code=$?

    assert_file_not_exists "${marker_path}" \
        "[@US-101 @security] a double-quote-breakout label does not execute injected code"
    assert_exit_code 0 "${exit_code}" \
        "[@US-101 @security] remove-device matches the literal malicious label and exits 0"
    if echo "${output}" | grep -q "0 devices remain registered"; then
        pass "[@US-101 @security] the malicious-label device was removed cleanly"
    else
        fail "[@US-101 @security] the malicious-label device was removed cleanly" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# list-devices.feature — @US-102
# ---------------------------------------------------------------------------

# @walking_skeleton @real-io @US-102 @driving_port
test_ws_list_devices_shows_every_registered_device() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices 2>&1)
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[WS @US-102] list-devices exits 0"
    for label_uuid in "IronKey-A:${UUID_A}" "IronKey-B:${UUID_B}" "IronKey-C:${UUID_C}"; do
        local label="${label_uuid%%:*}"
        local uuid="${label_uuid##*:}"
        if echo "${output}" | grep -q "${label}" && echo "${output}" | grep -q "${uuid}"; then
            pass "[WS @US-102] output lists ${label} with its UUID"
        else
            fail "[WS @US-102] output lists ${label} with its UUID" "output was: ${output}"
        fi
    done
    if echo "${output}" | grep -q "3 devices registered"; then
        pass "[WS @US-102] output states '3 devices registered'"
    else
        fail "[WS @US-102] output states '3 devices registered'" "output was: ${output}"
    fi

    teardown_test_env
}

# @US-102 @real-io @driving_port
test_mounted_device_shows_live_mount_path() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local vol_a="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${vol_a}"
    create_mock_diskutil_multi > /dev/null
    register_mock_volume "${UUID_A}" "${vol_a}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${INSTALL}" list-devices 2>&1)

    if echo "${output}" | grep -q "mounted" && echo "${output}" | grep -q "${vol_a}"; then
        pass "[@US-102] IronKey-A's row shows mounted and its live path"
    else
        fail "[@US-102] IronKey-A's row shows mounted and its live path" "output was: ${output}"
    fi

    teardown_test_env
}

# @US-102 @driving_port
test_unmounted_device_shows_not_mounted() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    create_mock_diskutil_multi > /dev/null
    # UUID_C is never registered as mounted

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${INSTALL}" list-devices 2>&1)

    if echo "${output}" | grep -q "IronKey-C" && echo "${output}" | grep -q "not mounted"; then
        pass "[@US-102] IronKey-C's row shows 'not mounted'"
    else
        fail "[@US-102] IronKey-C's row shows 'not mounted'" "output was: ${output}"
    fi

    teardown_test_env
}

# @US-102 @boundary @driving_port
test_list_devices_empty_registry_shows_helpful_message() {
    setup_test_env
    create_empty_registry_config "${CONFIG_FILE}" "${LOG_FILE}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices 2>&1)
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-102] list-devices exits 0 with an empty registry"
    if echo "${output}" | grep -q "No USB devices registered" && echo "${output}" | grep -q "add-device"; then
        pass "[@US-102] empty registry shows an inviting message naming add-device"
    else
        fail "[@US-102] empty registry shows an inviting message naming add-device" "output was: ${output}"
    fi

    teardown_test_env
}

# @US-102 @error-path @infrastructure-failure @driving_port
test_list_devices_missing_config_exits_config_error() {
    setup_test_env
    # Deliberately do not create the config file

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-102] list-devices exits 4 when config.yaml is missing"

    teardown_test_env
}

# @US-102 @error-path @infrastructure-failure @driving_port
test_list_devices_malformed_config_exits_config_error() {
    setup_test_env
    create_mock_config_yaml_invalid "${CONFIG_FILE}"

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices > /dev/null 2>&1
    local exit_code=$?

    assert_exit_code 4 "${exit_code}" \
        "[@US-102] list-devices exits 4 on malformed YAML config"

    teardown_test_env
}

# @US-102 @error-path @infrastructure-failure @driving_port
test_list_devices_handles_unresolvable_mount_query() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    mkdir -p "${VOLUMES_DIR}/SomeDrive"
    create_mock_diskutil_erroring

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${INSTALL}" list-devices 2>&1)
    local exit_code=$?

    assert_exit_code 0 "${exit_code}" \
        "[@US-102] list-devices still exits 0 when the mount query fails"
    if echo "${output}" | grep -q "not mounted"; then
        pass "[@US-102] a device is reported as 'not mounted' rather than crashing when the mount query fails"
    else
        fail "[@US-102] a device is reported as 'not mounted' rather than crashing when the mount query fails" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# @US-102 @property @driving_port
test_list_devices_never_modifies_config() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local config_before
    config_before=$(cat "${CONFIG_FILE}")

    CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices > /dev/null 2>&1

    local config_after
    config_after=$(cat "${CONFIG_FILE}")
    assert_config_unchanged "${config_before}" "${config_after}" \
        "[@US-102] list-devices never modifies config.yaml" "config.yaml was modified"

    teardown_test_env
}

# @US-102 @real-io @adapter-integration @driving_port
test_list_devices_agrees_with_sync_usb_on_mount_state() {
    setup_test_env
    create_three_device_config "${CONFIG_FILE}" "${LOG_FILE}"
    local vol_a="${VOLUMES_DIR}/IronKey-A"
    mkdir -p "${vol_a}"
    create_mock_diskutil_multi > /dev/null
    register_mock_volume "${UUID_A}" "${vol_a}"
    create_mock_rsync "false"

    local list_output
    list_output=$(CONFIG_FILE="${CONFIG_FILE}" SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${INSTALL}" list-devices 2>&1)

    CONFIG_FILE="${CONFIG_FILE}" SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        "${SYNC_USB}" > /dev/null 2>&1

    if echo "${list_output}" | grep -q "${vol_a}"; then
        pass "[@US-102] list-devices reports IronKey-A mounted at ${vol_a}"
    else
        fail "[@US-102] list-devices reports IronKey-A mounted at ${vol_a}" "output was: ${list_output}"
    fi
    assert_calls_contain "${MOCK_BIN_DIR}/rsync-calls.log" "${vol_a}" \
        "[@US-102] sync-usb.sh independently agrees IronKey-A is mounted at ${vol_a}"

    teardown_test_env
}

# @US-102 @security @driving_port
test_list_devices_single_quote_label_no_code_execution() {
    setup_test_env
    local marker_path="${TEST_DIR}/pwned-marker-list"
    create_config_with_single_quote_label "${CONFIG_FILE}" "${LOG_FILE}" "${marker_path}"

    local output
    output=$(CONFIG_FILE="${CONFIG_FILE}" "${INSTALL}" list-devices 2>&1)
    local exit_code=$?

    assert_file_not_exists "${marker_path}" \
        "[@US-102 @security] a single-quote-breakout label does not execute injected code in list-devices"
    assert_exit_code 0 "${exit_code}" \
        "[@US-102 @security] list-devices exits 0 despite the single-quote-breakout label"
    if echo "${output}" | grep -q "1 devices registered"; then
        pass "[@US-102 @security] list-devices still reports the device count correctly"
    else
        fail "[@US-102 @security] list-devices still reports the device count correctly" \
             "output was: ${output}"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Test runner — one scenario enabled at a time (Mandate 5). Only the P1
# walking skeleton (remove-device) runs by default. Uncomment the next test
# once it is GREEN, per the one-at-a-time TDD rhythm.
# ---------------------------------------------------------------------------

echo -e "${YELLOW}Running usb-device-lifecycle acceptance tests...${NC}"
echo ""

# ENABLED — Walking Skeleton (P1, remove-device)
test_ws_remove_device_by_label_leaves_others_unchanged

# ENABLED — step 01-02
test_remove_device_strips_uuid_from_every_directory_mapping

# ENABLED — step 01-03
test_remove_device_by_uuid_matches_removal_by_label

# ENABLED — step 01-04
test_remove_device_leaves_empty_directory_list_not_error

# ENABLED — step 01-05
test_remove_device_unknown_label_leaves_config_untouched

# ENABLED — step 01-05
test_remove_device_unknown_uuid_leaves_config_untouched

# ENABLED — step 01-06
test_remove_device_missing_config_exits_config_error

# ENABLED — step 01-06
test_remove_device_malformed_config_exits_config_error

# ENABLED — step 01-07
test_remove_device_requires_an_identifier

# ENABLED — step 01-07
test_remove_device_rejects_both_label_and_uuid

# ENABLED — step 01-08 (final step of Phase 01, completes US-101)
test_remove_device_writes_config_atomically

# ENABLED — security-fix-01 (heredoc injection regression)
test_remove_device_malicious_label_no_code_execution

# ENABLED — step 02-01 (walking skeleton, list-devices)
test_ws_list_devices_shows_every_registered_device

# ENABLED — step 02-02 (ADR-004 shared usb-common.sh library)
test_mounted_device_shows_live_mount_path

# ENABLED — step 02-03
test_unmounted_device_shows_not_mounted

# ENABLED — step 02-04
test_list_devices_empty_registry_shows_helpful_message

# ENABLED — step 02-05
test_list_devices_missing_config_exits_config_error

# ENABLED — step 02-05
test_list_devices_malformed_config_exits_config_error

# ENABLED — step 02-06
test_list_devices_handles_unresolvable_mount_query

# ENABLED — step 02-07
test_list_devices_never_modifies_config

# ENABLED — step 02-08 (FINAL step — ADR-004 regression probe)
test_list_devices_agrees_with_sync_usb_on_mount_state

# ENABLED — security-fix-02 (eval injection regression)
test_list_devices_single_quote_label_no_code_execution

print_summary
