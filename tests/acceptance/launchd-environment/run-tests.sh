#!/usr/bin/env bash
# run-tests.sh — Acceptance test runner for launchd-environment
#
# Corresponds to: tests/acceptance/launchd-environment/*.feature
# Sources multi-usb-sync/helpers.sh unchanged. Every script under test runs the
# way launchd runs it: `env -i`, PATH=<mock bin>:/usr/bin:/bin:/usr/sbin:/sbin,
# `/bin/bash <script>` (bash 3.2 on macOS). Temp HOME, config and directories only.
#
# Run with:
#   bash tests/acceptance/launchd-environment/run-tests.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SYNC_USB="${REPO_ROOT}/bin/sync-usb.sh"
SYNC_CLOUD="${REPO_ROOT}/bin/sync-cloud.sh"

# shellcheck source=../multi-usb-sync/helpers.sh
source "${REPO_ROOT}/tests/acceptance/multi-usb-sync/helpers.sh"

LAUNCHD_PATH_TAIL="/usr/bin:/bin:/usr/sbin:/sbin"

# run_launchd_script <script>
# Runs the script under a launchd-like environment. Sets OUTPUT and RC.
run_launchd_script() {
    OUTPUT=$(env -i HOME="${FAKE_HOME}" \
        PATH="${MOCK_BIN_DIR}:${LAUNCHD_PATH_TAIL}" \
        CONFIG_FILE="${CONFIG_FILE}" \
        SECURELOCAL_VOLUMES_BASE="${VOLUMES_DIR}" \
        /bin/bash "$1" 2>&1)
    RC=$?
}

# Apple's /usr/bin/python3 may lack PyYAML. The scripts' config loading is not
# under test, so supply a yaml-capable python3 through the mock bin when needed.
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
    echo "no PyYAML-capable python3 found; cannot run launchd-environment tests" >&2
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
    create_mock_rclone "false"
}

# mark_dataless <absolute_path>...
# Registers paths the stat mock reports with the "dataless" file flag. The files
# stay fully readable on disk: if the script does not exclude them, rsync copies
# them and the tests see it.
mark_dataless() {
    printf '%s\n' "$@" >> "${MOCK_BIN_DIR}/dataless-paths"
}

# create_mock_stat
# `stat -f %Sf%t%N <files>` prints "<flags><TAB><path>" per file, flags being
# "dataless" for registered paths and "-" otherwise. Any other stat call goes
# to the real stat. Never reads file contents.
create_mock_stat() {
    : > "${MOCK_BIN_DIR}/dataless-paths"
    cat > "${MOCK_BIN_DIR}/stat" <<'SCRIPT'
#!/bin/bash
BIN_DIR="$(dirname "$0")"
if [[ "$1" == "-f" && "$2" == '%Sf%t%N' ]]; then
    shift 2
    for f in "$@"; do
        if grep -qxF -- "${f}" "${BIN_DIR}/dataless-paths"; then
            printf 'dataless\t%s\n' "${f}"
        else
            printf -- '-\t%s\n' "${f}"
        fi
    done
    exit 0
fi
exec /usr/bin/stat "$@"
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/stat"
}

test_usb_sync_runs_under_bash_3_2() {
    setup_launchd_env
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 0 "${RC}" \
        "bash 3.2: sync-usb.sh exits 0 for a registered drive"
    assert_file_exists "${VOLUME_PATH}/secureLocal/file1.txt" \
        "bash 3.2: sync-usb.sh copies files to the registered drive"
    assert_log_not_contains <(echo "${OUTPUT}") "invalid option" \
        "bash 3.2: sync-usb.sh emits no 'invalid option' error"
    teardown_test_env
}

test_usb_sync_runs_under_bash_3_2

test_cloud_sync_runs_under_bash_3_2() {
    setup_launchd_env
    run_launchd_script "${SYNC_CLOUD}"
    assert_exit_code 0 "${RC}" \
        "bash 3.2: sync-cloud.sh exits 0"
    assert_calls_contain "${MOCK_BIN_DIR}/rclone-calls.log" "sync ${LOCAL_DIR} remote-crypt:secureLocal" \
        "bash 3.2: sync-cloud.sh reaches rclone for the configured directory"
    assert_log_not_contains <(echo "${OUTPUT}") "invalid option\|syntax error\|unbound variable" \
        "bash 3.2: sync-cloud.sh emits no bash errors"
    teardown_test_env
}

test_cloud_sync_runs_under_bash_3_2

test_installer_list_devices_runs_under_bash_3_2() {
    setup_launchd_env
    OUTPUT=$(env -i HOME="${FAKE_HOME}" PATH="${MOCK_BIN_DIR}:${LAUNCHD_PATH_TAIL}" \
        CONFIG_FILE="${CONFIG_FILE}" /bin/bash "${REPO_ROOT}/bin/install.sh" list-devices 2>&1)
    RC=$?
    assert_exit_code 0 "${RC}" \
        "bash 3.2: install.sh list-devices exits 0"
    assert_log_contains <(echo "${OUTPUT}") "IronKey-A" \
        "bash 3.2: install.sh list-devices shows the registered device"
    teardown_test_env
}

test_installer_list_devices_runs_under_bash_3_2

test_every_script_parses_under_bash_3_2() {
    local script bad=""
    for script in "${REPO_ROOT}"/bin/*.sh "${REPO_ROOT}"/bin/lib/*.sh; do
        /bin/bash -n "${script}" 2>/dev/null || bad="${bad} ${script}"
    done
    if [[ -z "${bad}" ]]; then
        pass "bash 3.2: every script under bin/ parses with /bin/bash -n"
    else
        fail "bash 3.2: every script under bin/ parses with /bin/bash -n" "syntax errors:${bad}"
    fi
}

test_every_script_parses_under_bash_3_2

test_dataless_file_is_skipped_and_reported() {
    setup_launchd_env
    create_mock_stat
    mkdir -p "${LOCAL_DIR}/photos"
    echo "evicted" > "${LOCAL_DIR}/photos/evicted.bin"
    echo "resident" > "${LOCAL_DIR}/photos/resident.bin"
    mark_dataless "${LOCAL_DIR}/photos/evicted.bin"

    run_launchd_script "${SYNC_USB}"

    assert_file_not_exists "${VOLUME_PATH}/secureLocal/photos/evicted.bin" \
        "dataless: the dataless file is not copied"
    assert_file_exists "${VOLUME_PATH}/secureLocal/photos/resident.bin" \
        "dataless: another file in the same subfolder is copied"
    assert_file_exists "${VOLUME_PATH}/secureLocal/file1.txt" \
        "dataless: files in the top directory are copied"
    assert_log_contains "${LOG_FILE}" "WARN sync-usb secureLocal skipped dataless file: /photos/evicted.bin" \
        "dataless: a WARN log line names the skipped file"
    assert_log_contains "${LOG_FILE}" "USB sync job completed with skips: 1 dataless file(s) skipped" \
        "dataless: final status says completed with skips and the count"
    assert_log_not_contains "${LOG_FILE}" "completed successfully" \
        "dataless: final status is not clean success"
    assert_exit_code 3 "${RC}" \
        "dataless: exit code 3 (completed with skips)"
    teardown_test_env
}

test_dataless_file_is_skipped_and_reported

test_names_with_spaces_and_glob_characters() {
    setup_launchd_env
    create_mock_stat
    mkdir -p "${LOCAL_DIR}/odd dir"
    echo "x" > "${LOCAL_DIR}/odd dir/we ird [1] *.bin"
    echo "y" > "${LOCAL_DIR}/odd dir/we ird 1 other.bin"
    echo "z" > "${LOCAL_DIR}/odd dir/we ird [1] keep.bin"
    mark_dataless "${LOCAL_DIR}/odd dir/we ird [1] *.bin"

    run_launchd_script "${SYNC_USB}"

    assert_file_not_exists "${VOLUME_PATH}/secureLocal/odd dir/we ird [1] *.bin" \
        "glob names: the dataless file with spaces, brackets and star is skipped"
    assert_file_exists "${VOLUME_PATH}/secureLocal/odd dir/we ird 1 other.bin" \
        "glob names: a name the unescaped pattern would match is still copied"
    assert_file_exists "${VOLUME_PATH}/secureLocal/odd dir/we ird [1] keep.bin" \
        "glob names: a resident file with brackets is still copied"
    assert_log_contains "${LOG_FILE}" "skipped dataless file: /odd dir/we ird \[1\] \*.bin" \
        "glob names: the WARN line names the file verbatim"
    teardown_test_env
}

test_names_with_spaces_and_glob_characters

# create_exit_code_rsync <code> <copy>
# Runs the real rsync when copy=true, then exits with <code> (when non-zero).
# Also mocks sleep so the 30s retry wait is recorded, not waited for.
create_exit_code_rsync() {
    local code="$1" copy="$2"
    : > "${MOCK_BIN_DIR}/rsync-calls.log"
    : > "${MOCK_BIN_DIR}/sleep-calls.log"
    cat > "${MOCK_BIN_DIR}/rsync" <<SCRIPT
#!/bin/bash
for a in "\$@"; do [[ "\$a" == --server ]] && exec /usr/bin/rsync "\$@"; done
echo "\$@" >> "${MOCK_BIN_DIR}/rsync-calls.log"
if [[ "${copy}" == "true" ]]; then /usr/bin/rsync "\$@"; fi
exit ${code}
SCRIPT
    printf '#!/bin/bash\necho "$@" >> "%s/sleep-calls.log"\n' "${MOCK_BIN_DIR}" > "${MOCK_BIN_DIR}/sleep"
    chmod +x "${MOCK_BIN_DIR}/rsync" "${MOCK_BIN_DIR}/sleep"
}

test_partial_transfer_exit_codes_are_completed_with_skips() {
    local code
    for code in 23 24; do
        setup_launchd_env
        create_exit_code_rsync "${code}" true
        run_launchd_script "${SYNC_USB}"
        assert_exit_code 3 "${RC}" \
            "rsync exit ${code}: job exits 3 (completed with skips)"
        assert_log_contains "${LOG_FILE}" "USB sync job completed with skips: 0 dataless file(s) skipped, 1 partial transfer(s)" \
            "rsync exit ${code}: final status says completed with skips and counts the partial transfer"
        assert_call_count "${MOCK_BIN_DIR}/rsync-calls.log" 1 \
            "rsync exit ${code}: not retried"
        assert_file_exists "${VOLUME_PATH}/secureLocal/file1.txt" \
            "rsync exit ${code}: the files rsync did transfer are present"
        teardown_test_env
    done
}

test_partial_transfer_exit_codes_are_completed_with_skips

test_other_rsync_failures_still_retry_then_fail() {
    setup_launchd_env
    create_exit_code_rsync 20 false
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 1 "${RC}" \
        "rsync exit 20: job exits 1 (failed)"
    assert_call_count "${MOCK_BIN_DIR}/rsync-calls.log" 2 \
        "rsync exit 20: retried once"
    assert_calls_contain "${MOCK_BIN_DIR}/sleep-calls.log" "^30$" \
        "rsync exit 20: waited 30s before the retry"
    assert_log_contains "${LOG_FILE}" "one or more USB syncs failed" \
        "rsync exit 20: final status says failed"
    assert_log_not_contains "${LOG_FILE}" "completed with skips" \
        "rsync exit 20: not reported as completed with skips"
    teardown_test_env
}

test_other_rsync_failures_still_retry_then_fail

test_clean_run_reports_clean_success() {
    setup_launchd_env
    create_mock_stat
    run_launchd_script "${SYNC_USB}"
    assert_exit_code 0 "${RC}" \
        "clean run: exits 0"
    assert_log_contains "${LOG_FILE}" "USB sync job completed successfully" \
        "clean run: final status is clean success"
    assert_log_not_contains "${LOG_FILE}" "WARN" \
        "clean run: no WARN lines"
    teardown_test_env
}

test_clean_run_reports_clean_success

# run_installer <args...>
# Runs install.sh under bash 3.2 with a temp HOME. The installer's launchd
# probe sees the mock bin first through SECURELOCAL_LAUNCHD_PATH, so a mock
# python3 stands in for Apple's. launchctl is mocked. Sets OUTPUT and RC.
run_installer() {
    OUTPUT=$(env -i HOME="${FAKE_HOME}" \
        PATH="${MOCK_BIN_DIR}:${LAUNCHD_PATH_TAIL}" \
        SECURELOCAL_LAUNCHD_PATH="${MOCK_BIN_DIR}:${LAUNCHD_PATH_TAIL}" \
        CONFIG_FILE="${CONFIG_FILE}" \
        /bin/bash "${REPO_ROOT}/bin/install.sh" "$@" </dev/null 2>&1)
    RC=$?
}

# create_python3_without_yaml
# A python3 that cannot import yaml, like Apple's /usr/bin/python3 without PyYAML.
create_python3_without_yaml() {
    cat > "${MOCK_BIN_DIR}/python3" <<'SCRIPT'
#!/bin/sh
echo "ModuleNotFoundError: No module named 'yaml'" >&2
exit 1
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/python3"
}

FIX_COMMAND="/usr/bin/python3 -m pip install --user pyyaml"

test_noninteractive_install_refuses_without_yaml() {
    setup_launchd_env
    create_mock_launchctl
    create_python3_without_yaml
    run_installer --non-interactive
    if [[ "${RC}" -ne 0 ]]; then pass "no yaml: non-interactive install exits non-zero"
    else fail "no yaml: non-interactive install exits non-zero" "exit code was 0"; fi
    assert_log_contains <(echo "${OUTPUT}") "${FIX_COMMAND}" \
        "no yaml: the message names the exact fix command"
    assert_file_not_exists "${FAKE_HOME}/Library/LaunchAgents/com.securelocal.usb-sync.plist" \
        "no yaml: no USB plist is written"
    assert_file_not_exists "${FAKE_HOME}/Library/LaunchAgents/com.securelocal.cloud-sync.plist" \
        "no yaml: no cloud plist is written"
    assert_call_count "${MOCK_BIN_DIR}/launchctl-calls.log" 0 \
        "no yaml: launchctl is never invoked"
    teardown_test_env
}

test_noninteractive_install_refuses_without_yaml

test_noninteractive_install_proceeds_with_yaml() {
    setup_launchd_env
    create_mock_launchctl
    run_installer --non-interactive
    assert_exit_code 0 "${RC}" \
        "with yaml: non-interactive install exits 0"
    assert_file_exists "${FAKE_HOME}/Library/LaunchAgents/com.securelocal.usb-sync.plist" \
        "with yaml: the USB plist is written"
    assert_file_exists "${FAKE_HOME}/Library/LaunchAgents/com.securelocal.cloud-sync.plist" \
        "with yaml: the cloud plist is written"
    teardown_test_env
}

test_noninteractive_install_proceeds_with_yaml

test_interactive_install_refuses_before_any_write() {
    setup_launchd_env
    create_mock_launchctl
    printf '#!/bin/sh\necho "FileVault is On."\n' > "${MOCK_BIN_DIR}/fdesetup"
    chmod +x "${MOCK_BIN_DIR}/fdesetup"
    rm -f "${CONFIG_FILE}"
    create_python3_without_yaml
    run_installer
    if [[ "${RC}" -ne 0 ]]; then pass "no yaml: interactive install exits non-zero"
    else fail "no yaml: interactive install exits non-zero" "exit code was 0"; fi
    assert_log_contains <(echo "${OUTPUT}") "${FIX_COMMAND}" \
        "no yaml: interactive install names the exact fix command"
    assert_file_not_exists "${CONFIG_FILE}" \
        "no yaml: interactive install writes no config"
    assert_file_not_exists "${FAKE_HOME}/Library/LaunchAgents/com.securelocal.usb-sync.plist" \
        "no yaml: interactive install writes no plist"
    teardown_test_env
}

test_interactive_install_refuses_before_any_write

test_add_device_refuses_without_yaml() {
    setup_launchd_env
    create_python3_without_yaml
    local before
    before=$(cat "${CONFIG_FILE}")
    run_installer add-device --volume "${VOLUME_PATH}" --label IronKey-B
    if [[ "${RC}" -ne 0 ]]; then pass "no yaml: add-device exits non-zero"
    else fail "no yaml: add-device exits non-zero" "exit code was 0"; fi
    assert_log_contains <(echo "${OUTPUT}") "${FIX_COMMAND}" \
        "no yaml: add-device names the exact fix command"
    if [[ "$(cat "${CONFIG_FILE}")" == "${before}" ]]; then pass "no yaml: add-device leaves the config unchanged"
    else fail "no yaml: add-device leaves the config unchanged" "config changed"; fi
    teardown_test_env
}

test_add_device_refuses_without_yaml

print_summary
