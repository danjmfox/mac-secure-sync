#!/bin/bash

# test-sync-script.sh
# Unit tests for sync-to-usb-and-cloud.sh

# set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test framework setup
TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""
# Resolve absolute path to this test script’s directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/sync-to-usb-and-cloud.sh"

CONFIG_FILE=""
ORIGINAL_PATH="${PATH}"

write_config() {
	# writes a config.env with the provided key=value pairs; missing keys are omitted to simulate failures
	local file_path="$1"
	shift
	: >"${file_path}" # truncate
	for kv in "$@"; do
		echo "${kv}" >>"${file_path}"
	done
}

use_default_config() {
	CONFIG_FILE="${TEST_DIR}/config.env"
	export CONFIG_FILE
	write_config "${CONFIG_FILE}" \
		"LOCAL_DIR=\"${LOCAL_DIR}\"" \
		"USB_UUID=\"${USB_UUID}\"" \
		"USB_MOUNT_BASE=\"${USB_MOUNT_BASE}\"" \
		"USB_BACKUP_PATH=\"${USB_BACKUP_PATH}\"" \
		"RCLONE_REMOTE=\"${RCLONE_REMOTE}\"" \
		"LOG_FILE=\"${LOG_FILE}\""
}

# Setup test environment
setup() {
	TEST_DIR=$(mktemp -d)
	MOCK_BIN_DIR="${TEST_DIR}/bin"
	mkdir -p "$MOCK_BIN_DIR"

	# Ensure system utilities are always available
	PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

	# Prepend the mock bin directory so mocked commands override system ones
	PATH="${MOCK_BIN_DIR}:${PATH}"
	export PATH

	LOCAL_DIR="${TEST_DIR}/secureLocal"
	USB_MOUNT_BASE="${TEST_DIR}/volumes"
	USB_UUID="TEST-UUID-1234"
	USB_BACKUP_PATH="secureLocal"
	RCLONE_REMOTE="test-remote:secureLocal"
	LOG_FILE="${TEST_DIR}/test.log"

	# Create test directories
	mkdir -p "${LOCAL_DIR}"
	mkdir -p "${USB_MOUNT_BASE}"

	# Create some test files
	echo "test content 1" >"${LOCAL_DIR}/file1.txt"
	echo "test content 2" >"${LOCAL_DIR}/file2.txt"
	mkdir -p "${LOCAL_DIR}/subdir"
	echo "nested content" >"${LOCAL_DIR}/subdir/nested.txt"

	# Create default config file for the sync script
	use_default_config
}

# Teardown test environment
teardown() {
	if [[ -n ${TEST_DIR} ]] && [[ -d ${TEST_DIR} ]]; then
		rm -rf "${TEST_DIR}"
	fi
}

# Test assertion helper
# assert_equals() {
# 	local expected="$1"
# 	local actual="$2"
# 	local test_name="$3"

# 	if [[ ${expected} == "${actual}" ]]; then
# 		echo -e "${GREEN}✓${NC} ${test_name}"
# 		((TESTS_PASSED++))
# 	else
# 		echo -e "${RED}✗${NC} ${test_name}"
# 		echo "  Expected: ${expected}"
# 		echo "  Actual: ${actual}"
# 		((TESTS_FAILED++))
# 	fi
# }

assert_file_exists() {
	local file="$1"
	local test_name="$2"

	if [[ -f ${file} ]]; then
		echo -e "${GREEN}✓${NC} ${test_name}"
		((TESTS_PASSED++))
	else
		echo -e "${RED}✗${NC} ${test_name}"
		echo "  File not found: ${file}"
		((TESTS_FAILED++))
	fi
}

assert_exit_code() {
	local expected="$1"
	local actual="$2"
	local test_name="$3"

	if [[ ${expected} -eq ${actual} ]]; then
		echo -e "${GREEN}✓${NC} ${test_name}"
		((TESTS_PASSED++))
	else
		echo -e "${RED}✗${NC} ${test_name}"
		echo "  Expected exit code: ${expected}"
		echo "  Actual exit code: ${actual}"
		((TESTS_FAILED++))
	fi
}

# Mock diskutil for testing
create_mock_diskutil() {
	mkdir -p "${TEST_DIR}"
	local uuid="$1"
	local mount_point="$2"

	cat >"${MOCK_BIN_DIR}/diskutil" <<EOF
#!/bin/bash
if [[ "\$1" == "info" ]] && [[ "\$2" == "${mount_point}" ]]; then
    echo "Volume UUID: ${uuid}"
fi
EOF
	chmod +x "${MOCK_BIN_DIR}/diskutil"
}

# Mock rsync for testing
create_mock_rsync() {
	local should_fail="${1:-false}"
	local fail_file="${MOCK_BIN_DIR}/rsync.fail"
	cat >"${MOCK_BIN_DIR}/rsync" <<EOF
#!/bin/bash
FAIL_FILE="${fail_file}"
# Force failure if the latest flag says so
if [[ -f "\${FAIL_FILE}" ]] && [[ "\$(cat \${FAIL_FILE})" == "true" ]]; then
    echo "Mock rsync forced to fail" >&2
    exit 1
fi
# Delegate to the real rsync
/usr/bin/rsync "\$@"
EOF
	chmod +x "${MOCK_BIN_DIR}/rsync"
	echo "${should_fail}" >"${fail_file}"
}

# Mock rclone for testing
create_mock_rclone() {
	local should_fail="${1:-false}"
	cat >"${MOCK_BIN_DIR}/rclone" <<EOF
#!/bin/bash
if [ "${should_fail}" = "true" ]; then exit 1; fi
echo "rclone mock: \$@" >> "${LOG_FILE}"
exit 0
EOF
	chmod +x "${MOCK_BIN_DIR}/rclone"
}

# Test 1: Script fails when USB_UUID not set
test_missing_usb_uuid() {
	setup
	# Rewrite config without USB_UUID
	write_config "${CONFIG_FILE}" \
		"LOCAL_DIR=\"${LOCAL_DIR}\"" \
		"USB_MOUNT_BASE=\"${USB_MOUNT_BASE}\"" \
		"USB_BACKUP_PATH=\"${USB_BACKUP_PATH}\"" \
		"RCLONE_REMOTE=\"${RCLONE_REMOTE}\"" \
		"LOG_FILE=\"${LOG_FILE}\""
	"${SCRIPT_PATH}" >/dev/null 2>&1
	exit_code=$?
	assert_exit_code 4 "${exit_code}" "${BOLD}Missing USB_UUID causes exit code 4${NC}"
	teardown
}

# Test 2: Script fails when LOCAL_DIR doesn't exist
test_missing_local_dir() {
	setup
	local missing_dir="${TEST_DIR}/nonexistent"
	write_config "${CONFIG_FILE}" \
		"LOCAL_DIR=\"${missing_dir}\"" \
		"USB_UUID=\"${USB_UUID}\"" \
		"USB_MOUNT_BASE=\"${USB_MOUNT_BASE}\"" \
		"USB_BACKUP_PATH=\"${USB_BACKUP_PATH}\"" \
		"RCLONE_REMOTE=\"${RCLONE_REMOTE}\"" \
		"LOG_FILE=\"${LOG_FILE}\""
	"${SCRIPT_PATH}" >/dev/null 2>&1
	exit_code=$?
	assert_exit_code 4 "${exit_code}" "Missing LOCAL_DIR causes exit code 4"
	teardown
}

# Test 3: Script fails when rclone not found
test_missing_rclone() {
	setup
	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"

	rm -f "${MOCK_BIN_DIR}/rclone"

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 4 "${exit_code}" "Missing rclone causes exit code 4"
	teardown
}

# Test 4: Script fails when USB not found
test_usb_not_found() {
	setup
	create_mock_rclone "false"
	# Don't create USB mount point

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 1 "${exit_code}" "USB not found causes exit code 1"
	teardown
}

# Test 5: USB UUID matching works correctly
test_usb_uuid_matching() {
	setup

	# Create two USB mounts with different UUIDs
	mkdir -p "${USB_MOUNT_BASE}/wrong-usb"
	mkdir -p "${USB_MOUNT_BASE}/correct-usb"

	# Mock diskutil to return different UUIDs
	cat >"${MOCK_BIN_DIR}/diskutil" <<'EOF'
#!/bin/bash
if [[ "$2" == *"wrong-usb"* ]]; then
    echo "Volume UUID: WRONG-UUID"
elif [[ "$2" == *"correct-usb"* ]]; then
    echo "Volume UUID: TEST-UUID-1234"
fi
EOF
	chmod +x "${MOCK_BIN_DIR}/diskutil"

	create_mock_rsync "false"
	create_mock_rclone "false"

	"${SCRIPT_PATH}" >/dev/null 2>&1

	# Check that files were synced to correct USB
	assert_file_exists "${USB_MOUNT_BASE}/correct-usb/secureLocal/file1.txt" "Files synced to correct USB by UUID"

	teardown
}

# Test 6: Successful sync returns exit code 0
test_successful_sync() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "false"
	create_mock_rclone "false"

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 0 "${exit_code}" "Successful sync returns exit code 0"
	teardown
}

# Test 7: USB sync failure returns exit code 1
test_usb_sync_failure() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "true" # Make rsync fail
	create_mock_rclone "false"

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 1 "${exit_code}" "USB sync failure returns exit code 1"
	teardown
}

# Test 8: Cloud sync failure returns exit code 2
test_cloud_sync_failure() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "false"
	create_mock_rclone "true" # Make rclone fail

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 2 "${exit_code}" "Cloud sync failure returns exit code 2"
	teardown
}

# Test 9: Both sync failures return exit code 3
test_both_sync_failures() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "true"  # Make rsync fail
	create_mock_rclone "true" # Make rclone fail

	"${SCRIPT_PATH}" >/dev/null 2>&1
	local exit_code=$?

	assert_exit_code 3 "${exit_code}" "Both sync failures return exit code 3"
	teardown
}

# Test 10: Log file is created
test_log_file_created() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "false"
	create_mock_rclone "false"

	"${SCRIPT_PATH}" >/dev/null 2>&1

	assert_file_exists "${LOG_FILE}" "Log file is created"
	teardown
}

# Test 11: Files are actually copied to USB
test_files_copied_to_usb() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "false"
	create_mock_rclone "false"

	"${SCRIPT_PATH}" >/dev/null 2>&1

	assert_file_exists "${USB_MOUNT_BASE}/test-usb/secureLocal/file1.txt" "file1.txt copied to USB"
	assert_file_exists "${USB_MOUNT_BASE}/test-usb/secureLocal/file2.txt" "file2.txt copied to USB"
	assert_file_exists "${USB_MOUNT_BASE}/test-usb/secureLocal/subdir/nested.txt" "nested.txt copied to USB"
	teardown
}

# Test 12: USB backup path is created if missing
test_usb_backup_path_created() {
	setup

	mkdir -p "${USB_MOUNT_BASE}/test-usb"
	create_mock_diskutil "${USB_UUID}" "${USB_MOUNT_BASE}/test-usb"
	create_mock_rsync "false"
	create_mock_rclone "false"

	# Don't create backup path beforehand
	"${SCRIPT_PATH}" >/dev/null 2>&1

	if [[ -d "${USB_MOUNT_BASE}/test-usb/secureLocal" ]]; then
		echo -e "${GREEN}✓${NC} USB backup path is created if missing"
		((TESTS_PASSED++))
	else
		echo -e "${RED}✗${NC} USB backup path is created if missing"
		((TESTS_FAILED++))
	fi

	teardown
}

# Run all tests
echo -e "${YELLOW}Running sync script tests...${NC}\n"

test_missing_usb_uuid
test_missing_local_dir
test_missing_rclone
test_usb_not_found
test_usb_uuid_matching
test_successful_sync
test_usb_sync_failure
test_cloud_sync_failure
test_both_sync_failures
test_log_file_created
test_files_copied_to_usb
test_usb_backup_path_created

# Summary
echo ""
echo "======================================"
if [[ ${TESTS_FAILED} -eq 0 ]]; then
	echo -e "${GREEN}All tests passed!${NC}"
	echo "Passed: ${TESTS_PASSED}"
	exit 0
else
	echo -e "${RED}Some tests failed${NC}"
	echo "Passed: ${TESTS_PASSED}"
	echo "Failed: ${TESTS_FAILED}"
	exit 1
fi
