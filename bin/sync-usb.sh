#!/usr/bin/env bash
# sync-usb.sh — Sync registered local directories to mounted USB drives
#
# Reads config.yaml v2, finds mounted registered USB drives by UUID,
# and rsyncs each mapped directory to the matched drive.
#
# Usage:
#   CONFIG_FILE=/path/to/config.yaml SECURELOCAL_VOLUMES_BASE=/Volumes ./sync-usb.sh
#
# Exit codes:
#   0 — all syncs succeeded (or no registered drive found)
#   1 — one or more USB syncs failed
#   4 — config error (missing file, invalid YAML, schema mismatch)

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONFIG_FILE="${CONFIG_FILE:-${HOME}/.config/securelocal/config.yaml}"
VOLUMES_BASE="${SECURELOCAL_VOLUMES_BASE:-/Volumes}"
MAX_RETRIES=2

# ---------------------------------------------------------------------------
# Shared library (ADR-004)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/usb-common.sh
source "${SCRIPT_DIR}/lib/usb-common.sh"

# ---------------------------------------------------------------------------
# Logging — YYYY-MM-DDTHH:MM:SS LEVEL sync-usb DIR MESSAGE
# ---------------------------------------------------------------------------
log_info() {
    local dir="${1:-}"
    local message="${2:-}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${ts} INFO sync-usb ${dir} ${message}" | tee -a "${LOG_FILE:-/dev/null}"
}

log_error() {
    local dir="${1:-}"
    local message="${2:-}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${ts} ERROR sync-usb ${dir} ${message}" | tee -a "${LOG_FILE:-/dev/null}" >&2
}

# ---------------------------------------------------------------------------
# load_config — parse config.yaml with python3, emit KEY=value pairs
# Exits 4 on missing file, invalid YAML, or schema_version != 2
# ---------------------------------------------------------------------------
load_config() {
    local config_path="$1"

    if [[ ! -f "${config_path}" ]]; then
        echo "ERROR sync-usb - config file not found: ${config_path}" >&2
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
# sync_to_usb — rsync source dir to USB mount, retry once after 30s on fail
# Returns 0 on success, 1 on failure after retries
# ---------------------------------------------------------------------------
sync_to_usb() {
    local source_dir="$1"
    local usb_mount="$2"
    local dir_label="$3"

    local source_basename
    source_basename=$(basename "${source_dir}")
    local usb_target="${usb_mount}/${source_basename}"
    local attempt=1

    mkdir -p "${usb_target}"

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log_info "${dir_label}" "USB sync attempt ${attempt} of ${MAX_RETRIES}: ${source_dir} -> ${usb_target}"

        if rsync -avh --ignore-errors "${source_dir}/" "${usb_target}/"; then
            log_info "${dir_label}" "USB sync successful"
            return 0
        else
            log_error "${dir_label}" "USB sync failed on attempt ${attempt}"
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
    # Load and source config
    local config_output
    config_output=$(load_config "${CONFIG_FILE}") || exit 4
    eval "${config_output}"

    log_info "-" "USB sync job started"

    # Scan for registered volumes
    local any_registered_found=false
    local sync_failed=false

    # Build set of all registered UUIDs from config
    declare -A registered_uuids
    local idx=0
    while [[ ${idx} -lt ${USB_DEVICE_COUNT:-0} ]]; do
        local uuid_var="USB_DEVICE_${idx}_ID"
        local uuid="${!uuid_var:-}"
        if [[ -n "${uuid}" ]]; then
            registered_uuids["${uuid}"]=1
        fi
        ((idx++))
    done

    # Scan volumes base for any mounted volumes
    if [[ ! -d "${VOLUMES_BASE}" ]]; then
        log_info "-" "no registered device found"
        exit 0
    fi

    # For each mounted volume, check if its UUID is registered
    for volume in "${VOLUMES_BASE}"/*/; do
        if [[ ! -d "${volume}" ]]; then
            continue
        fi
        local vol_path="${volume%/}"
        local vol_uuid
        vol_uuid=$(get_volume_uuid "${vol_path}")

        if [[ -z "${vol_uuid}" ]]; then
            continue
        fi

        if [[ -z "${registered_uuids[${vol_uuid}]+_}" ]]; then
            # Not a registered UUID — silently ignore
            continue
        fi

        # This UUID is registered — find all directories that map to it
        any_registered_found=true
        local dir_idx=0
        while [[ ${dir_idx} -lt ${DIR_COUNT:-0} ]]; do
            local path_var="DIR_${dir_idx}_LOCAL_PATH"
            local devs_var="DIR_${dir_idx}_USB_DEVICES"
            local local_path="${!path_var:-}"
            local usb_devices_for_dir="${!devs_var:-}"

            # Check if this directory lists this UUID
            local uuid_found=false
            for dev_uuid in ${usb_devices_for_dir}; do
                if [[ "${dev_uuid}" == "${vol_uuid}" ]]; then
                    uuid_found=true
                    break
                fi
            done

            if [[ "${uuid_found}" == "true" ]]; then
                local dir_label
                dir_label=$(basename "${local_path}")

                if [[ ! -d "${local_path}" ]]; then
                    log_error "${dir_label}" "local directory not found: ${local_path}"
                    sync_failed=true
                else
                    if ! sync_to_usb "${local_path}" "${vol_path}" "${dir_label}"; then
                        log_error "${dir_label}" "USB sync failed for ${local_path} -> ${vol_path}"
                        sync_failed=true
                    fi
                fi
            fi
            ((dir_idx++))
        done
    done

    if [[ "${any_registered_found}" == "false" ]]; then
        log_info "-" "no registered device found"
        exit 0
    fi

    if [[ "${sync_failed}" == "true" ]]; then
        log_error "-" "one or more USB syncs failed"
        exit 1
    fi

    log_info "-" "USB sync job completed successfully"
    exit 0
}

main "$@"
