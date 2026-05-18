#!/usr/bin/env bash
# helpers.sh — Shared mock factories and assertion helpers for multi-usb-sync acceptance tests
#
# Usage: source this file from run-tests.sh before running any test function.
# All functions write into TEST_DIR and MOCK_BIN_DIR, which must be set by the caller.

# ---------------------------------------------------------------------------
# Config YAML factories
# ---------------------------------------------------------------------------

# create_mock_config_yaml <config_path> <log_file_path>
# Writes a minimal schema v2 config with one directory, one USB device (UUID-A),
# and one cloud remote. Sufficient for the walking skeleton.
create_mock_config_yaml() {
    local config_path="$1"
    local log_file="$2"
    local local_dir="${3:-${TEST_DIR}/secureLocal}"
    local usb_label="${4:-IronKey-A}"
    local uuid_a="${5:-TEST-UUID-AAAA}"

    cat > "${config_path}" <<YAML
schema_version: 2
log_file: ${log_file}
rclone_bin: ${MOCK_BIN_DIR}/rclone
sync_interval_seconds: 3600
directories:
  - local_path: ${local_dir}
    cloud_remote: remote-crypt:secureLocal
    usb_devices:
      - ${uuid_a}
usb_devices:
  - id: ${uuid_a}
    label: ${usb_label}
YAML
}

# create_mock_config_yaml_multi_dir <config_path> <log_file>
# Writes a schema v2 config with two directories, two USB devices, two cloud remotes.
create_mock_config_yaml_multi_dir() {
    local config_path="$1"
    local log_file="$2"
    local dir_a="${TEST_DIR}/secureLocal"
    local dir_b="${TEST_DIR}/Projects"
    local uuid_a="${UUID_A:-TEST-UUID-AAAA}"
    local uuid_b="${UUID_B:-TEST-UUID-BBBB}"

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
      - ${uuid_a}
      - ${uuid_b}
  - local_path: ${dir_b}
    cloud_remote: remote-crypt:Projects
    usb_devices:
      - ${uuid_a}
      - ${uuid_b}
usb_devices:
  - id: ${uuid_a}
    label: IronKey-A
  - id: ${uuid_b}
    label: IronKey-B
YAML
}

# create_mock_config_yaml_v1 <config_path>
# Writes a v1 config to trigger schema version mismatch.
create_mock_config_yaml_v1() {
    local config_path="$1"
    cat > "${config_path}" <<YAML
schema_version: 1
log_file: ${TEST_DIR}/test.log
usb_uuid: OLD-STYLE-UUID
local_dir: ~/secureLocal
YAML
}

# create_mock_config_yaml_invalid <config_path>
# Writes unparseable content to trigger a config parse failure.
create_mock_config_yaml_invalid() {
    local config_path="$1"
    printf 'not: valid: yaml: [\n  missing: bracket\n' > "${config_path}"
}

# ---------------------------------------------------------------------------
# Mock binary factories
# ---------------------------------------------------------------------------

# create_mock_diskutil_single <uuid> <volume_path>
# Returns UUID only when queried for the specific volume_path.
create_mock_diskutil_single() {
    local uuid="$1"
    local volume_path="$2"
    cat > "${MOCK_BIN_DIR}/diskutil" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "info" ]] && [[ "\$2" == "${volume_path}" ]]; then
    echo "Volume UUID:               ${uuid}"
fi
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/diskutil"
}

# create_mock_diskutil_multi
# Reads UUID-to-volume-path mappings from associative array entries written to a
# flat file at MOCK_BIN_DIR/diskutil-map. Simulates multiple registered volumes.
# Callers register entries by appending "<uuid>:<path>" lines to that map file.
create_mock_diskutil_multi() {
    local map_file="${MOCK_BIN_DIR}/diskutil-map"
    : > "${map_file}"

    # Register: echo "UUID:PATH" >> "${map_file}" in the caller before running scripts.
    cat > "${MOCK_BIN_DIR}/diskutil" <<'SCRIPT'
#!/usr/bin/env bash
MAP_FILE="$(dirname "$0")/diskutil-map"
QUERY_PATH="$2"
if [[ "$1" == "info" ]] && [[ -f "${MAP_FILE}" ]]; then
    while IFS=: read -r uuid path; do
        if [[ "${path}" == "${QUERY_PATH}" ]]; then
            echo "Volume UUID:               ${uuid}"
            exit 0
        fi
    done < "${MAP_FILE}"
fi
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/diskutil"
    echo "${map_file}"  # Return map file path for callers to append entries
}

# register_mock_volume <uuid> <volume_path>
# Appends a UUID:path mapping to the diskutil mock's map file.
# Must be called after create_mock_diskutil_multi.
register_mock_volume() {
    local uuid="$1"
    local volume_path="$2"
    echo "${uuid}:${volume_path}" >> "${MOCK_BIN_DIR}/diskutil-map"
    mkdir -p "${volume_path}"
}

# create_mock_rsync [should_fail]
# Records all rsync invocations to MOCK_BIN_DIR/rsync-calls.log
# and delegates to real rsync so files are actually copied (Strategy C — real I/O).
create_mock_rsync() {
    local should_fail="${1:-false}"
    local calls_log="${MOCK_BIN_DIR}/rsync-calls.log"
    : > "${calls_log}"
    local fail_flag="${MOCK_BIN_DIR}/rsync.fail"
    echo "${should_fail}" > "${fail_flag}"

    cat > "${MOCK_BIN_DIR}/rsync" <<'SCRIPT'
#!/usr/bin/env bash
BIN_DIR="$(dirname "$0")"
echo "$@" >> "${BIN_DIR}/rsync-calls.log"
if [[ "$(cat "${BIN_DIR}/rsync.fail")" == "true" ]]; then
    echo "mock rsync: forced failure" >&2
    exit 1
fi
/usr/bin/rsync "$@"
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/rsync"
}

# create_mock_rclone [should_fail]
# Records all rclone invocations to MOCK_BIN_DIR/rclone-calls.log.
# Does NOT delegate to real rclone (no real cloud access in tests).
create_mock_rclone() {
    local should_fail="${1:-false}"
    local calls_log="${MOCK_BIN_DIR}/rclone-calls.log"
    : > "${calls_log}"
    local fail_flag="${MOCK_BIN_DIR}/rclone.fail"
    echo "${should_fail}" > "${fail_flag}"

    cat > "${MOCK_BIN_DIR}/rclone" <<'SCRIPT'
#!/usr/bin/env bash
BIN_DIR="$(dirname "$0")"
echo "$@" >> "${BIN_DIR}/rclone-calls.log"
if [[ "$(cat "${BIN_DIR}/rclone.fail")" == "true" ]]; then
    echo "mock rclone: forced failure" >&2
    exit 1
fi
exit 0
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/rclone"
}

# create_mock_launchctl
# Records load/unload calls. Exits 0 always. Records to launchctl-calls.log.
create_mock_launchctl() {
    local calls_log="${MOCK_BIN_DIR}/launchctl-calls.log"
    : > "${calls_log}"

    cat > "${MOCK_BIN_DIR}/launchctl" <<'SCRIPT'
#!/usr/bin/env bash
BIN_DIR="$(dirname "$0")"
echo "$@" >> "${BIN_DIR}/launchctl-calls.log"
# Simulate "list" output for grep tests
if [[ "$1" == "list" ]]; then
    grep "securelocal" "${BIN_DIR}/launchctl-loaded.txt" 2>/dev/null || true
fi
exit 0
SCRIPT
    chmod +x "${MOCK_BIN_DIR}/launchctl"
}

# register_launchctl_agent <agent_name>
# Adds a mock entry to the simulated loaded agents list.
register_launchctl_agent() {
    local agent_name="$1"
    echo "-	0	${agent_name}" >> "${MOCK_BIN_DIR}/launchctl-loaded.txt"
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

TESTS_PASSED=0
TESTS_FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    local test_name="$1"
    echo -e "${GREEN}PASS${NC} ${test_name}"
    ((TESTS_PASSED++)) || true
}

fail() {
    local test_name="$1"
    local reason="$2"
    echo -e "${RED}FAIL${NC} ${test_name}"
    echo "     Reason: ${reason}"
    ((TESTS_FAILED++)) || true
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "${expected}" -eq "${actual}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "expected exit code ${expected}, got ${actual}"
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    if [[ -f "${file}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "file not found: ${file}"
    fi
}

assert_dir_exists() {
    local dir="$1"
    local test_name="$2"
    if [[ -d "${dir}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "directory not found: ${dir}"
    fi
}

assert_file_not_exists() {
    local file="$1"
    local test_name="$2"
    if [[ ! -e "${file}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "file should not exist but does: ${file}"
    fi
}

assert_log_contains() {
    local log_file="$1"
    local pattern="$2"
    local test_name="$3"
    if grep -q "${pattern}" "${log_file}" 2>/dev/null; then
        pass "${test_name}"
    else
        fail "${test_name}" "pattern '${pattern}' not found in log '${log_file}'"
    fi
}

assert_log_not_contains() {
    local log_file="$1"
    local pattern="$2"
    local test_name="$3"
    if ! grep -q "${pattern}" "${log_file}" 2>/dev/null; then
        pass "${test_name}"
    else
        fail "${test_name}" "pattern '${pattern}' should not appear in log but does"
    fi
}

# assert_calls_contain <calls_log> <pattern> <test_name>
# Checks that a mock tool's call log contains the expected pattern.
assert_calls_contain() {
    local calls_log="$1"
    local pattern="$2"
    local test_name="$3"
    if grep -q "${pattern}" "${calls_log}" 2>/dev/null; then
        pass "${test_name}"
    else
        fail "${test_name}" "expected call matching '${pattern}' not found in ${calls_log}"
    fi
}

assert_calls_not_contain() {
    local calls_log="$1"
    local pattern="$2"
    local test_name="$3"
    if ! grep -q "${pattern}" "${calls_log}" 2>/dev/null; then
        pass "${test_name}"
    else
        fail "${test_name}" "unexpected call matching '${pattern}' found in ${calls_log}"
    fi
}

assert_call_count() {
    local calls_log="$1"
    local expected_count="$2"
    local test_name="$3"
    local actual_count=0
    if [[ -f "${calls_log}" ]]; then
        actual_count=$(wc -l < "${calls_log}" | tr -d ' ')
    fi
    if [[ "${expected_count}" -eq "${actual_count}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "expected ${expected_count} calls, got ${actual_count}"
    fi
}

# assert_log_lines_all_timestamped <log_file> <test_name>
# Every non-empty line must begin with an ISO 8601 timestamp.
assert_log_lines_all_timestamped() {
    local log_file="$1"
    local test_name="$2"
    local bad_line
    bad_line=$(grep -v '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' "${log_file}" 2>/dev/null | grep -v '^$' | head -1 || true)
    if [[ -z "${bad_line}" ]]; then
        pass "${test_name}"
    else
        fail "${test_name}" "line does not begin with timestamp: ${bad_line}"
    fi
}

# ---------------------------------------------------------------------------
# Environment lifecycle
# ---------------------------------------------------------------------------

UUID_A="TEST-UUID-AAAA"
UUID_B="TEST-UUID-BBBB"

setup_test_env() {
    TEST_DIR=$(mktemp -d)
    MOCK_BIN_DIR="${TEST_DIR}/bin"
    mkdir -p "${MOCK_BIN_DIR}"

    CONFIG_FILE="${TEST_DIR}/config.yaml"
    LOG_FILE="${TEST_DIR}/sync.log"
    LOCAL_DIR="${TEST_DIR}/secureLocal"
    VOLUMES_DIR="${TEST_DIR}/volumes"

    mkdir -p "${LOCAL_DIR}" "${VOLUMES_DIR}"
    echo "test file content" > "${LOCAL_DIR}/file1.txt"
    echo "test file content 2" > "${LOCAL_DIR}/file2.txt"

    # Restrict PATH to mock bin + essential system tools only
    PATH="${MOCK_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH CONFIG_FILE LOG_FILE LOCAL_DIR VOLUMES_DIR TEST_DIR MOCK_BIN_DIR
}

teardown_test_env() {
    if [[ -n "${TEST_DIR:-}" ]] && [[ -d "${TEST_DIR}" ]]; then
        rm -rf "${TEST_DIR}"
    fi
    # Restore PATH
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH
}

print_summary() {
    echo ""
    echo "======================================"
    echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
    if [[ "${TESTS_FAILED}" -eq 0 ]]; then
        echo -e "${GREEN}All tests passed${NC}"
        return 0
    else
        echo -e "${RED}${TESTS_FAILED} test(s) failed${NC}"
        return 1
    fi
}
