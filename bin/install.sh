#!/bin/bash
# install.sh — set up secureLocal sync automation (macOS)

set -euo pipefail

CONFIG_DIR="${HOME}/.config/securelocal"
CONFIG_FILE="${CONFIG_DIR}/config.env"
LOG_FILE="${HOME}/Library/Logs/securelocal-sync.log"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.securelocal.sync.plist"
SYNC_SCRIPT="${HOME}/secureLocal/bin/sync-to-usb-and-cloud.sh"

mkdir -p "$(dirname "${LOG_FILE}")" "${CONFIG_DIR}"

# --------------------------------------------------------------------
# Logging Helpers
# --------------------------------------------------------------------
log_section() { echo -e "\n=== $* ===" | tee -a "${LOG_FILE}"; }
log_info() { echo "ℹ️  $*" | tee -a "${LOG_FILE}"; }
log_ok() { echo "✅ $*" | tee -a "${LOG_FILE}"; }
log_warn() { echo "⚠️  $*" | tee -a "${LOG_FILE}"; }
log_err() { echo "❌  $*" | tee -a "${LOG_FILE}" >&2; }

# --------------------------------------------------------------------
# Dependency Checks
# --------------------------------------------------------------------
check_dependencies() {
	log_section "Checking dependencies"
	local missing=0
	for cmd in rsync diskutil rclone fdesetup; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			log_err "Missing dependency: ${cmd} (please install and re-run)."
			missing=1
		fi
	done
	((missing)) && exit 1
	log_ok "All dependencies found."
}

# --------------------------------------------------------------------
# FileVault Status
# --------------------------------------------------------------------
check_filevault() {
	log_section "Checking FileVault status"
	local status
	status=$(fdesetup status 2>/dev/null || true)
	if echo "${status}" | grep -q "FileVault is On"; then
		log_ok "FileVault is enabled. Local data is protected at rest."
	else
		log_warn "FileVault appears to be disabled."
		log_info "Enable it in System Settings → Privacy & Security → FileVault."
		log_info "Without FileVault, your ~/secureLocal data is stored unencrypted."
	fi
}

# --------------------------------------------------------------------
# Volume Selection
# --------------------------------------------------------------------
select_usb_volume() {
	log_section "Mounted External Volumes"
	diskutil info -all | awk -v base="/Volumes" '
  /^Device Identifier:/ {dev=$3}
  /Volume Name:/ {vol=$3}
  /Mount Point:/ {mp=$3; if(index(mp,base)==1) printf "  %-10s | %-20s | %s\n", dev, vol, mp}
  ' | sort | tee -a "${LOG_FILE}" || log_warn "Could not list volumes automatically."
	echo
	echo "Example entry for 'IronKey' would appear as:"
	echo "  disk4s2    | IronKey              | /Volumes/IronKey"
	echo

	read -rp "Enter the *volume name* of your IronKey (e.g. IronKey): " VOL_NAME
	VOL_PATH="/Volumes/${VOL_NAME}"

	if [[ ! -d ${VOL_PATH} ]]; then
		log_err "Volume ${VOL_PATH} not found or not mounted. Please check the name and try again."
		exit 1
	fi

	log_ok "Found mounted volume at: ${VOL_PATH}"

	USB_UUID=$(diskutil info "${VOL_PATH}" | awk -F': +' '/Volume UUID/{print $2}')
	if [[ -z ${USB_UUID} ]]; then
		log_err "Could not retrieve UUID for ${VOL_PATH}"
		exit 1
	fi
	log_info "Detected UUID: ${USB_UUID}"
}

# --------------------------------------------------------------------
# Rclone Remote Verification
# --------------------------------------------------------------------
check_rclone_remote() {
	local remote_name="${RCLONE_REMOTE%%:*}" # strip :path part
	log_section "Checking rclone remote: ${remote_name}"

	if ! rclone listremotes | grep -q "^${remote_name}:"; then
		log_err "Rclone remote '${remote_name}' not found."
		log_info "Please create it using 'rclone config' then re-run this installer."
		exit 1
	fi

	if ! rclone lsd "${remote_name}:" >/dev/null 2>&1; then
		log_warn "Remote '${remote_name}' found but not reachable."
		log_info "Verify credentials and network, then retry."
		exit 1
	fi

	log_ok "Verified rclone remote '${remote_name}' exists and is accessible."
}

# --------------------------------------------------------------------
# Offer Config Backup
# --------------------------------------------------------------------
backup_rclone_config() {
	echo
	read -rp "Would you like to back up your rclone config now? (y/n): " BACKUP_CHOICE
	if [[ ${BACKUP_CHOICE} =~ ^[Yy]$ ]]; then
		read -rp "Enter a secure location (e.g. encrypted USB path or FileVault folder): " BACKUP_PATH
		if [[ -n ${BACKUP_PATH} ]]; then
			mkdir -p "${BACKUP_PATH}"
			cp "${HOME}/.config/rclone/rclone.conf" "${BACKUP_PATH}/rclone.conf.backup-$(date +%Y%m%d)"
			log_ok "rclone config backed up to ${BACKUP_PATH}"
		else
			log_warn "Skipped backup (no path provided)."
		fi
	else
		log_warn "Reminder: Back up ~/.config/rclone/rclone.conf separately — loss means loss of decryption key."
	fi
}

# --------------------------------------------------------------------
# Write Config
# --------------------------------------------------------------------
write_config_file() {
	cat >"${CONFIG_FILE}" <<EOF
LOCAL_DIR="${HOME}/secureLocal"
USB_UUID="${USB_UUID}"
USB_MOUNT_BASE="/Volumes"
USB_BACKUP_PATH="secureLocal"
RCLONE_REMOTE="${RCLONE_REMOTE}"
LOG_FILE="${LOG_FILE}"
EOF
	log_ok "Wrote configuration to ${CONFIG_FILE}"
}

# --------------------------------------------------------------------
# Create Launchd Agent
# --------------------------------------------------------------------
create_launch_agent() {
	cat >"${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key> <string>com.securelocal.sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>${SYNC_SCRIPT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CONFIG_FILE</key> <string>${CONFIG_FILE}</string>
  </dict>
  <key>WatchPaths</key>
  <array>
    <string>/Volumes</string>
  </array>
  <key>StandardOutPath</key> <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key> <string>${LOG_FILE}</string>
  <key>RunAtLoad</key> <true/>
</dict>
</plist>
EOF

	launchctl unload "${PLIST_FILE}" >/dev/null 2>&1 || true
	launchctl load "${PLIST_FILE}"

	log_ok "LaunchAgent installed: com.securelocal.sync"
	log_info "Log file: ${LOG_FILE}"
	log_info "Trigger: /Volumes change (USB plug/unplug)"
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
main() {
	log_section "SecureLocal Installer Started"

	check_dependencies
	check_filevault
	select_usb_volume

	read -rp "Enter your rclone remote (default: remote-crypt:secureLocal): " RCLONE_REMOTE
	RCLONE_REMOTE=${RCLONE_REMOTE:-remote-crypt:secureLocal}
	check_rclone_remote

	backup_rclone_config
	write_config_file
	create_launch_agent

	log_section "Installation Summary"
	log_info "Volume:       ${VOL_NAME}"
	log_info "UUID:         ${USB_UUID}"
	log_info "Rclone remote: ${RCLONE_REMOTE}"
	log_info "Config:       ${CONFIG_FILE}"
	log_info "LaunchAgent:  ${PLIST_FILE}"
	log_ok "Installation complete."
}

main "$@"
