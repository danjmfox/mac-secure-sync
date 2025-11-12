#!/bin/bash
# uninstall.sh — remove secureLocal sync automation (macOS)

set -euo pipefail

CONFIG_DIR="${HOME}/.config/securelocal"
CONFIG_FILE="${CONFIG_DIR}/config.env"
LOG_FILE="${HOME}/Library/Logs/securelocal-sync.log"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.securelocal.sync.plist"

# --------------------------------------------------------------------
# Logging Helpers
# --------------------------------------------------------------------
log_section() { echo -e "\n=== $* ===" | tee -a "${LOG_FILE}"; }
log_info() { echo "ℹ️  $*" | tee -a "${LOG_FILE}"; }
log_ok() { echo "✅ $*" | tee -a "${LOG_FILE}"; }
log_warn() { echo "⚠️  $*" | tee -a "${LOG_FILE}"; }
log_err() { echo "❌  $*" | tee -a "${LOG_FILE}" >&2; }

# --------------------------------------------------------------------
# Confirm Action
# --------------------------------------------------------------------
confirm_uninstall() {
	log_section "Uninstall SecureLocal Sync"
	echo "This will remove the LaunchAgent, config, and log files created by install.sh."
	echo "Your ~/secureLocal data and rclone remotes will remain untouched."
	echo
	read -rp "Proceed with uninstall? (y/N): " ANSWER
	[[ ${ANSWER} =~ ^[Yy]$ ]] || {
		log_warn "Cancelled by user."
		exit 0
	}
}

# --------------------------------------------------------------------
# Unload LaunchAgent
# --------------------------------------------------------------------
remove_launch_agent() {
	log_section "Removing LaunchAgent"
	if [[ -f ${PLIST_FILE} ]]; then
		launchctl unload "${PLIST_FILE}" >/dev/null 2>&1 || true
		rm -f "${PLIST_FILE}"
		log_ok "LaunchAgent com.securelocal.sync removed."
	else
		log_info "No LaunchAgent plist found at ${PLIST_FILE}"
	fi
}

# --------------------------------------------------------------------
# Remove Config
# --------------------------------------------------------------------
remove_config() {
	log_section "Removing configuration"
	if [[ -f ${CONFIG_FILE} ]]; then
		rm -f "${CONFIG_FILE}"
		log_ok "Removed ${CONFIG_FILE}"
	else
		log_info "No config file found at ${CONFIG_FILE}"
	fi

	# Remove directory if empty
	if [[ -d ${CONFIG_DIR} ]] && [[ -z "$(ls -A "${CONFIG_DIR}")" ]]; then
		rmdir "${CONFIG_DIR}"
		log_ok "Removed empty config directory ${CONFIG_DIR}"
	fi
}

# --------------------------------------------------------------------
# Remove Log File
# --------------------------------------------------------------------
remove_logs() {
	log_section "Cleaning logs"
	if [[ -f ${LOG_FILE} ]]; then
		read -rp "Delete log file at ${LOG_FILE}? (y/N): " DEL_LOG
		if [[ ${DEL_LOG} =~ ^[Yy]$ ]]; then
			rm -f "${LOG_FILE}"
			log_ok "Deleted log file."
		else
			log_info "Log file retained."
		fi
	else
		log_info "No log file found."
	fi
}

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------
summary() {
	log_section "Uninstall Summary"
	log_info "LaunchAgent:  ${PLIST_FILE}"
	log_info "Config file:  ${CONFIG_FILE}"
	log_info "Logs:         ${LOG_FILE}"
	log_ok "SecureLocal automation removed."
	echo
	echo "You can safely delete ~/secureLocal manually if you wish — this script leaves your data untouched."
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
main() {
	confirm_uninstall
	remove_launch_agent
	remove_config
	remove_logs
	summary
}

main "$@"
