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
#   3 — completed with skips (dataless files skipped or rsync partial transfer)
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
# shellcheck source=lib/dataless.sh
source "${SCRIPT_DIR}/lib/dataless.sh"

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

log_warn() {
    local dir="${1:-}"
    local message="${2:-}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${ts} WARN sync-usb ${dir} ${message}" | tee -a "${LOG_FILE:-/dev/null}" >&2
}

# ---------------------------------------------------------------------------
# load_config — parse config.yaml with python3, write NUL-delimited fields to
# output_file in a fixed order. Exits 4 on missing file, invalid YAML, or
# schema_version != 2. Never a syntax-sensitive bash string: no config-derived
# value is passed through eval, source, or command substitution in a
# syntax-sensitive position (security-fix-03, mirrors install.sh's
# cmd_list_devices()).
# ---------------------------------------------------------------------------
load_config() {
    local config_path="$1"
    local output_file="$2"

    if [[ ! -f "${config_path}" ]]; then
        echo "ERROR sync-usb - config file not found: ${config_path}" >&2
        exit 4
    fi

    python3 - "${config_path}" > "${output_file}" <<'PYEOF'
import yaml, sys

config_path = sys.argv[1]

def emit(value):
    sys.stdout.write(str(value))
    sys.stdout.write('\0')

try:
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict):
        sys.exit(4)
    if cfg.get("schema_version") != 2:
        sys.exit(4)
    emit(cfg['log_file'])
    emit(cfg.get('rclone_bin', ''))
    dirs = cfg.get("directories", [])
    emit(len(dirs))
    for d in dirs:
        emit(d.get('local_path', ''))
        emit(" ".join(d.get("usb_devices", [])))
    usb_devices = cfg.get("usb_devices", [])
    emit(len(usb_devices))
    for dev in usb_devices:
        emit(dev.get('id', ''))
        emit(dev.get('label', ''))
except SystemExit:
    raise
except Exception:
    sys.exit(4)
PYEOF
    local py_exit=$?
    if [[ ${py_exit} -ne 0 ]]; then
        rm -f "${output_file}"
        exit 4
    fi
}

# ---------------------------------------------------------------------------
# sync_to_usb — rsync source dir to USB mount, retry once after 30s on fail.
# Dataless files are excluded up front and logged at WARN. rsync exit 23/24
# (partial transfer / vanished files) counts as completed with skips.
# Returns 0 on success, 3 on completed with skips, 1 on failure after retries.
# Sets SYNC_SKIPPED_FILES (dataless files skipped) and SYNC_PARTIAL (0 or 1).
# ---------------------------------------------------------------------------
sync_to_usb() {
    local source_dir="$1"
    local usb_mount="$2"
    local dir_label="$3"

    local source_basename
    source_basename=$(basename "${source_dir}")
    local usb_target="${usb_mount}/${source_basename}"
    local attempt=1
    local exclude_file rc rel

    SYNC_SKIPPED_FILES=0
    SYNC_PARTIAL=0
    mkdir -p "${usb_target}"
    exclude_file=$(mktemp)
    local paths_file
    paths_file=$(mktemp)

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log_info "${dir_label}" "USB sync attempt ${attempt} of ${MAX_RETRIES}: ${source_dir} -> ${usb_target}"

        list_file_flags "${source_dir}" | dataless_relative_paths "${source_dir}" > "${paths_file}"
        escape_rsync_pattern < "${paths_file}" > "${exclude_file}"
        SYNC_SKIPPED_FILES=0
        while IFS= read -r rel; do
            log_warn "${dir_label}" "skipped dataless file: ${rel}"
            SYNC_SKIPPED_FILES=$((SYNC_SKIPPED_FILES + 1))
        done < "${paths_file}"

        rsync -avh --ignore-errors --exclude-from="${exclude_file}" "${source_dir}/" "${usb_target}/"
        rc=$?
        case ${rc} in
            0)
                rm -f "${exclude_file}" "${paths_file}"
                log_info "${dir_label}" "USB sync successful"
                [[ ${SYNC_SKIPPED_FILES} -eq 0 ]] && return 0
                return 3
                ;;
            23|24)
                rm -f "${exclude_file}" "${paths_file}"
                SYNC_PARTIAL=1
                log_warn "${dir_label}" "rsync partial transfer (exit ${rc}); remaining files were synced"
                return 3
                ;;
        esac

        log_error "${dir_label}" "USB sync failed on attempt ${attempt} (rsync exit ${rc})"
        if [[ ${attempt} -lt ${MAX_RETRIES} ]]; then
            log_info "${dir_label}" "Waiting 30s before retry..."
            sleep 30
        fi
        ((attempt++))
    done

    rm -f "${exclude_file}" "${paths_file}"
    return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    # Load config: NUL-delimited fields read directly into named variables —
    # no eval, no source (security-fix-03).
    local config_data_file
    config_data_file=$(mktemp)

    load_config "${CONFIG_FILE}" "${config_data_file}"

    {
        IFS= read -r -d '' LOG_FILE
        IFS= read -r -d '' RCLONE_BIN
        IFS= read -r -d '' DIR_COUNT
        local dir_idx=0
        while [[ ${dir_idx} -lt ${DIR_COUNT} ]]; do
            IFS= read -r -d '' "DIR_${dir_idx}_LOCAL_PATH"
            IFS= read -r -d '' "DIR_${dir_idx}_USB_DEVICES"
            ((dir_idx++))
        done
        IFS= read -r -d '' USB_DEVICE_COUNT
        local dev_idx=0
        while [[ ${dev_idx} -lt ${USB_DEVICE_COUNT} ]]; do
            IFS= read -r -d '' "USB_DEVICE_${dev_idx}_ID"
            IFS= read -r -d '' "USB_DEVICE_${dev_idx}_LABEL"
            ((dev_idx++))
        done
    } < "${config_data_file}"

    rm -f "${config_data_file}"

    log_info "-" "USB sync job started"

    # Scan for registered volumes
    local any_registered_found=false
    local sync_failed=false
    local total_skipped=0
    local total_partial=0
    local sync_rc

    # Space-delimited set of registered UUIDs (bash 3.2 has no associative arrays)
    local registered_uuids=" "
    local idx=0
    while [[ ${idx} -lt ${USB_DEVICE_COUNT:-0} ]]; do
        local uuid_var="USB_DEVICE_${idx}_ID"
        local uuid="${!uuid_var:-}"
        if [[ -n "${uuid}" ]]; then
            registered_uuids="${registered_uuids}${uuid} "
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

        case "${registered_uuids}" in
            *" ${vol_uuid} "*) ;;
            *) continue ;;  # Not a registered UUID — silently ignore
        esac

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
                    sync_to_usb "${local_path}" "${vol_path}" "${dir_label}"
                    sync_rc=$?
                    total_skipped=$((total_skipped + SYNC_SKIPPED_FILES))
                    total_partial=$((total_partial + SYNC_PARTIAL))
                    if [[ ${sync_rc} -eq 1 ]]; then
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

    if [[ $((total_skipped + total_partial)) -gt 0 ]]; then
        log_warn "-" "USB sync job completed with skips: ${total_skipped} dataless file(s) skipped, ${total_partial} partial transfer(s)"
        exit 3
    fi

    log_info "-" "USB sync job completed successfully"
    exit 0
}

main "$@"
