#!/bin/bash
# verify-uninstall.sh — confirm SecureLocal uninstall status

set -euo pipefail

PLIST_FILE="${HOME}/Library/LaunchAgents/com.securelocal.sync.plist"
CONFIG_DIR="${HOME}/.config/securelocal"
CONFIG_FILE="${CONFIG_DIR}/config.env"
LOG_FILE="${HOME}/Library/Logs/securelocal-sync.log"

CLEAN_LOGS=false
[[ ${1-} == "--clean-logs" ]] && CLEAN_LOGS=true

check_file() {
	local path="$1" label="$2"
	if [[ -e ${path} ]]; then
		printf "❌  %-14s  %s exists at %s\n" "${label}" "$(basename "${path}")" "${path}"
		if ${CLEAN_LOGS} && [[ ${path} == "${LOG_FILE}" ]]; then
			rm -f "${LOG_FILE}" && printf "🧹  %-14s  log file removed\n" "${label}"
		fi
		return 1
	else
		printf "✅  %-14s  not found\n" "${label}"
		return 0
	fi
}

check_launchctl() {
	if launchctl list | grep -q securelocal; then
		printf "❌  %-14s  launchctl job still loaded\n" "LaunchAgent"
		return 1
	else
		printf "✅  %-14s  no launchctl job found\n" "LaunchAgent"
		return 0
	fi
}

check_envvar() {
	if [[ -n "$(launchctl getenv CONFIG_FILE || true)" ]]; then
		printf "❌  %-14s  CONFIG_FILE variable still set\n" "Env var"
		return 1
	else
		printf "✅  %-14s  CONFIG_FILE not set\n" "Env var"
		return 0
	fi
}

check_process() {
	if pgrep -f sync-to-usb-and-cloud >/dev/null 2>&1; then
		printf "❌  %-14s  sync process still running\n" "Process"
		return 1
	else
		printf "✅  %-14s  no sync process running\n" "Process"
		return 0
	fi
}

echo "=== SecureLocal Uninstall Verification ==="
${CLEAN_LOGS} && echo "(Running in clean-up mode — will delete log file if present)"
echo

pass=true

check_launchctl || pass=false
check_file "${PLIST_FILE}" "Plist file" || pass=false
check_file "${CONFIG_FILE}" "Config file" || pass=false
check_file "${CONFIG_DIR}" "Config dir" || pass=false
check_file "${LOG_FILE}" "Log file" || pass=false
check_envvar || pass=false
check_process || pass=false

echo
if ${pass}; then
	echo "✅ All SecureLocal automation components removed successfully."
	exit 0
else
	if ${CLEAN_LOGS}; then
		echo
		echo "🔁 Re-running verification after cleaning logs..."
		exec "$0" # rerun script to recheck clean state
	else
		echo "⚠️  Some components still present. Run './verify-uninstall.sh --clean-logs' to remove leftover log file automatically."
		exit 1
	fi
fi
