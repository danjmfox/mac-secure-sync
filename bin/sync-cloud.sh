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
        echo "ERROR sync-cloud - config file not found: ${config_path}" >&2
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
        emit(d.get('cloud_remote', ''))
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
            IFS= read -r -d '' "DIR_${dir_idx}_CLOUD_REMOTE"
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
