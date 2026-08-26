#!/usr/bin/env bash
# usb-common.sh — shared USB volume matching library (ADR-004)
#
# Pure query functions only: no main(), no top-level side effects. Safe for
# any script to source without triggering unrelated execution.

# ---------------------------------------------------------------------------
# find_usb_by_uuid — scan volumes_base, return mount path matching uuid
# Returns empty string if not found
# ---------------------------------------------------------------------------
find_usb_by_uuid() {
    local uuid="$1"
    local volumes_base="$2"

    if [[ ! -d "${volumes_base}" ]]; then
        return 0
    fi

    for volume in "${volumes_base}"/*/; do
        if [[ -d "${volume}" ]]; then
            local vol_path="${volume%/}"
            local vol_uuid
            vol_uuid=$(diskutil info "${vol_path}" 2>/dev/null | grep "Volume UUID" | awk '{print $3}' || true)
            if [[ "${vol_uuid}" == "${uuid}" ]]; then
                echo "${vol_path}"
                return 0
            fi
        fi
    done
}
