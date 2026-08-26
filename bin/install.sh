#!/bin/bash
# install.sh — set up secureLocal sync automation (macOS)

set -euo pipefail

# Allow CONFIG_FILE and HOME to be overridden via environment (for tests)
CONFIG_DIR="${HOME}/.config/securelocal"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/config.yaml}"
LOG_FILE="${HOME}/Library/Logs/securelocal-sync.log"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
USB_PLIST_FILE="${LAUNCH_AGENTS_DIR}/com.securelocal.usb-sync.plist"
CLOUD_PLIST_FILE="${LAUNCH_AGENTS_DIR}/com.securelocal.cloud-sync.plist"
OLD_PLIST_FILE="${LAUNCH_AGENTS_DIR}/com.securelocal.sync.plist"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_USB_SCRIPT="${INSTALL_DIR}/bin/sync-usb.sh"
SYNC_CLOUD_SCRIPT="${INSTALL_DIR}/bin/sync-cloud.sh"
NON_INTERACTIVE=false

mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${CONFIG_FILE}")" "${LAUNCH_AGENTS_DIR}"

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
# Write Config (YAML v2)
# --------------------------------------------------------------------
write_config_file() {
    local rclone_bin
    rclone_bin=$(command -v rclone 2>/dev/null || echo "/usr/local/bin/rclone")

    cat > "${CONFIG_FILE}" <<YAML
schema_version: 2
log_file: ${LOG_FILE}
rclone_bin: ${rclone_bin}
sync_interval_seconds: 3600
directories:
  - local_path: ${HOME}/secureLocal
    cloud_remote: "${RCLONE_REMOTE}"
    usb_devices:
      - ${USB_UUID}
usb_devices:
  - id: ${USB_UUID}
    label: ${VOL_NAME}
YAML
    log_ok "Wrote configuration to ${CONFIG_FILE}"
}

# --------------------------------------------------------------------
# Create Launchd Agents (USB-sync + Cloud-sync)
# --------------------------------------------------------------------
create_launch_agent() {
    local sync_interval=3600
    if [[ -f "${CONFIG_FILE}" ]]; then
        local parsed_interval
        parsed_interval=$(python3 -c "
import sys
try:
    import yaml
    with open('${CONFIG_FILE}') as f:
        cfg = yaml.safe_load(f)
    print(cfg.get('sync_interval_seconds', 3600))
except Exception:
    print(3600)
" 2>/dev/null || echo "3600")
        sync_interval="${parsed_interval}"
    fi

    # Remove old single-plist if present (upgrade path)
    if [[ -f "${OLD_PLIST_FILE}" ]]; then
        launchctl unload "${OLD_PLIST_FILE}" >/dev/null 2>&1 || true
        rm -f "${OLD_PLIST_FILE}"
        log_info "Removed legacy plist: com.securelocal.sync"
    fi

    # Install USB-sync plist (WatchPaths /Volumes)
    cat > "${USB_PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key> <string>com.securelocal.usb-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${SYNC_USB_SCRIPT}</string>
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
</dict>
</plist>
EOF

    # Install cloud-sync plist (StartInterval timer)
    cat > "${CLOUD_PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key> <string>com.securelocal.cloud-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${SYNC_CLOUD_SCRIPT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CONFIG_FILE</key> <string>${CONFIG_FILE}</string>
  </dict>
  <key>StartInterval</key> <integer>${sync_interval}</integer>
  <key>StandardOutPath</key> <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key> <string>${LOG_FILE}</string>
</dict>
</plist>
EOF

    launchctl unload "${USB_PLIST_FILE}" >/dev/null 2>&1 || true
    launchctl load "${USB_PLIST_FILE}"
    launchctl unload "${CLOUD_PLIST_FILE}" >/dev/null 2>&1 || true
    launchctl load "${CLOUD_PLIST_FILE}"

    log_ok "LaunchAgent installed: com.securelocal.usb-sync"
    log_ok "LaunchAgent installed: com.securelocal.cloud-sync"
    log_info "USB sync trigger: /Volumes change (USB plug/unplug)"
    log_info "Cloud sync interval: ${sync_interval}s"
    log_info "Log file: ${LOG_FILE}"
}

# --------------------------------------------------------------------
# add-device subcommand
# Usage: install.sh add-device --volume <path> --label <name>
# --------------------------------------------------------------------
cmd_add_device() {
    local volume_path=""
    local label=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --volume) volume_path="$2"; shift 2 ;;
            --label)  label="$2";       shift 2 ;;
            *) log_err "Unknown add-device option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "${volume_path}" ]] || [[ -z "${label}" ]]; then
        log_err "add-device requires --volume <path> and --label <name>"
        exit 1
    fi

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_err "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi

    # Extract UUID via diskutil
    local uuid
    uuid=$(diskutil info "${volume_path}" 2>/dev/null | awk -F': +' '/Volume UUID/{print $2}')
    if [[ -z "${uuid}" ]]; then
        log_err "Could not retrieve UUID for ${volume_path}"
        exit 1
    fi

    # Check for duplicate UUID and append atomically using python3
    python3 - <<PYEOF
import sys
import os

config_path = "${CONFIG_FILE}"
new_uuid = "${uuid}"
new_label = "${label}"

try:
    import yaml
except ImportError:
    print("ERROR: python3 yaml module not available", file=sys.stderr)
    sys.exit(1)

with open(config_path) as f:
    cfg = yaml.safe_load(f)

usb_devices = cfg.get('usb_devices', [])
existing_ids = [d.get('id', '') for d in usb_devices if isinstance(d, dict)]

if new_uuid in existing_ids:
    print(f"ERROR: UUID {new_uuid} is already registered", file=sys.stderr)
    sys.exit(2)

# Append to usb_devices section
usb_devices.append({'id': new_uuid, 'label': new_label})
cfg['usb_devices'] = usb_devices

# Append UUID to each directory's usb_devices list
directories = cfg.get('directories', [])
for directory in directories:
    dir_usb = directory.get('usb_devices', [])
    if new_uuid not in dir_usb:
        dir_usb.append(new_uuid)
    directory['usb_devices'] = dir_usb
cfg['directories'] = directories

# Atomic write: write to .tmp then rename
tmp_path = config_path + ".tmp"
with open(tmp_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)
os.rename(tmp_path, config_path)
print(f"Registered device: {new_label} ({new_uuid})")
PYEOF
    local py_exit=$?
    exit ${py_exit}
}

# --------------------------------------------------------------------
# remove-device subcommand
# Usage: install.sh remove-device --label <name> | --uuid <id>
# --------------------------------------------------------------------
cmd_remove_device() {
    local label=""
    local uuid=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            --uuid) uuid="$2"; shift 2 ;;
            *) log_err "Unknown remove-device option: $1"; exit 1 ;;
        esac
    done

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_err "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi

    python3 - <<PYEOF
import sys
import os

config_path = "${CONFIG_FILE}"
target_label = "${label}"
target_uuid = "${uuid}"
match_field = 'id' if target_uuid else 'label'
match_value = target_uuid if target_uuid else target_label

try:
    import yaml
except ImportError:
    print("ERROR: python3 yaml module not available", file=sys.stderr)
    sys.exit(1)

with open(config_path) as f:
    cfg = yaml.safe_load(f)

# Step 1: compute the mutated config, separable from the write step so a
# future story can insert a step between compute and write (OQ-004).
def compute_mutated_config(cfg, match_field, match_value):
    usb_devices = cfg.get('usb_devices', [])
    removed_ids = [d.get('id') for d in usb_devices if d.get(match_field) == match_value]
    remaining = [d for d in usb_devices if d.get(match_field) != match_value]
    cfg['usb_devices'] = remaining

    directories = cfg.get('directories', [])
    for directory in directories:
        dir_usb = directory.get('usb_devices', [])
        directory['usb_devices'] = [uuid for uuid in dir_usb if uuid not in removed_ids]
    cfg['directories'] = directories

    return cfg, len(remaining)

mutated_cfg, remaining_count = compute_mutated_config(cfg, match_field, match_value)

# Step 2: atomic write — write to .tmp then rename.
tmp_path = config_path + ".tmp"
with open(tmp_path, 'w') as f:
    yaml.dump(mutated_cfg, f, default_flow_style=False, allow_unicode=True)
os.rename(tmp_path, config_path)
print(f"{remaining_count} devices remain registered")
PYEOF
    local py_exit=$?
    exit ${py_exit}
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
main() {
    # Parse global flags
    local args=()
    for arg in "$@"; do
        case "${arg}" in
            --non-interactive) NON_INTERACTIVE=true ;;
            *) args+=("${arg}") ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    # Dispatch subcommands before the main installer flow
    if [[ "${1:-}" == "add-device" ]]; then
        shift
        cmd_add_device "$@"
        exit $?
    fi

    if [[ "${1:-}" == "remove-device" ]]; then
        shift
        cmd_remove_device "$@"
        exit $?
    fi

    # RED-scaffold stub (usb-device-lifecycle, US-102): subcommand not yet
    # implemented. Prevents falling through to the interactive install flow
    # (which would block on `read -rp` in tests). DELIVER replaces this with
    # cmd_list_devices().
    if [[ "${1:-}" == "list-devices" ]]; then
        log_err "list-devices: not yet implemented"
        exit 2
    fi

    log_section "SecureLocal Installer Started"

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        # Non-interactive mode: install plists using existing config
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            log_err "Config file not found: ${CONFIG_FILE} — required for --non-interactive"
            exit 1
        fi
        create_launch_agent
        log_section "Installation Summary (non-interactive)"
        log_info "Config: ${CONFIG_FILE}"
        log_ok "Installation complete."
        return
    fi

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
    log_info "LaunchAgents: com.securelocal.usb-sync, com.securelocal.cloud-sync"
    log_ok "Installation complete."
}

main "$@"
