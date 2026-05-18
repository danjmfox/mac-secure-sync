#!/usr/bin/env bash
# sync-cloud.sh — Sync registered local directories to configured cloud remotes via rclone
#
# Reads config.yaml v2 and rclone-syncs each directory to its configured cloud remote.
# Triggered by launchd StartInterval or invoked manually.
#
# Usage:
#   CONFIG_FILE=/path/to/config.yaml ./sync-cloud.sh
#
# Exit codes:
#   0 — all syncs succeeded
#   2 — one or more cloud syncs failed
#   4 — config error (missing file, invalid YAML, schema mismatch)

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONFIG_FILE="${CONFIG_FILE:-${HOME}/.config/securelocal/config.yaml}"
MAX_RETRIES=2

# ---------------------------------------------------------------------------
# Logging — YYYY-MM-DDTHH:MM:SS LEVEL sync-cloud DIR MESSAGE
# ---------------------------------------------------------------------------
log_info() {
    local dir="${1:-}"
    local message="${2:-}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${ts} INFO sync-cloud ${dir} ${message}" | tee -a "${LOG_FILE:-/dev/null}"
}

log_error() {
    local dir="${1:-}"
    local message="${2:-}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${ts} ERROR sync-cloud ${dir} ${message}" | tee -a "${LOG_FILE:-/dev/null}" >&2
}

# ---------------------------------------------------------------------------
# load_config — parse config.yaml with python3, emit KEY=value pairs
# Exits 4 on missing file, invalid YAML, or schema_version != 2
# ---------------------------------------------------------------------------
load_config() {
    local config_path="$1"

    if [[ ! -f "${config_path}" ]]; then
        echo "ERROR sync-cloud - config file not found: ${config_path}" >&2
        exit 4
    fi

    python3 - "${config_path}" <<'PYEOF'
import yaml, sys

config_path = sys.argv[1]
try:
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict):
        sys.exit(4)
    if cfg.get("schema_version") != 2:
        sys.exit(4)
    print(f"LOG_FILE='{cfg['log_file']}'")
    print(f"RCLONE_BIN='{cfg.get('rclone_bin','')}'")
    dirs = cfg.get("directories", [])
    print(f"DIR_COUNT={len(dirs)}")
    for i, d in enumerate(dirs):
        local_path = d.get('local_path', '')
        print(f"DIR_{i}_LOCAL_PATH='{local_path}'")
        cloud_remote = d.get('cloud_remote', '')
        print(f"DIR_{i}_CLOUD_REMOTE='{cloud_remote}'")
        usb_devs = " ".join(d.get("usb_devices", []))
        print(f"DIR_{i}_USB_DEVICES='{usb_devs}'")
    usb_devices = cfg.get("usb_devices", [])
    print(f"USB_DEVICE_COUNT={len(usb_devices)}")
    for i, dev in enumerate(usb_devices):
        print(f"USB_DEVICE_{i}_ID='{dev.get('id','')}'")
        print(f"USB_DEVICE_{i}_LABEL='{dev.get('label','')}'")
except SystemExit:
    raise
except Exception:
    sys.exit(4)
PYEOF
}

# ---------------------------------------------------------------------------
# sync_to_cloud — rclone sync local dir to cloud remote, retry once after 30s
# Returns 0 on success, 1 on failure after retries
# ---------------------------------------------------------------------------
sync_to_cloud() {
    local local_path="$1"
    local cloud_remote="$2"
    local dir_label="$3"
    local attempt=1

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log_info "${dir_label}" "cloud sync attempt ${attempt} of ${MAX_RETRIES}: ${local_path} -> ${cloud_remote}"

        if "${RCLONE_BIN}" sync "${local_path}" "${cloud_remote}" --log-file "${LOG_FILE}" --log-level INFO; then
            log_info "${dir_label}" "cloud sync successful"
            return 0
        else
            log_error "${dir_label}" "cloud sync failed on attempt ${attempt}"
            if [[ ${attempt} -lt ${MAX_RETRIES} ]]; then
                log_info "${dir_label}" "Waiting 30s before retry..."
                sleep 30
            fi
        fi
        ((attempt++))
    done

    return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    local config_output
    config_output=$(load_config "${CONFIG_FILE}") || exit 4
    eval "${config_output}"

    log_info "-" "cloud sync job started"

    local sync_failed=false
    local dir_idx=0

    while [[ ${dir_idx} -lt ${DIR_COUNT:-0} ]]; do
        local path_var="DIR_${dir_idx}_LOCAL_PATH"
        local remote_var="DIR_${dir_idx}_CLOUD_REMOTE"
        local local_path="${!path_var:-}"
        local cloud_remote="${!remote_var:-}"
        local dir_label
        dir_label=$(basename "${local_path}")

        if ! sync_to_cloud "${local_path}" "${cloud_remote}" "${dir_label}"; then
            log_error "${dir_label}" "cloud sync failed for ${local_path} -> ${cloud_remote}"
            sync_failed=true
        fi

        ((dir_idx++))
    done

    if [[ "${sync_failed}" == "true" ]]; then
        log_error "-" "one or more cloud syncs failed"
        exit 2
    fi

    log_info "-" "cloud sync job completed successfully"
    exit 0
}

main "$@"
