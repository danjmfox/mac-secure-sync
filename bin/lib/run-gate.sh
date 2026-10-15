#!/usr/bin/env bash
# run-gate.sh — decide whether a sync-usb.sh trigger needs to do any work (ADR-008)
#
# decide_run and signature_from_uuids are pure. The state and lock helpers are
# the filesystem edge. Bash 3.2 compatible; no top-level side effects.

# decide_run <signature> <now> <last_signature> <last_ts> <min_interval>
# Prints "skip" when the drive set is unchanged and the last run finished less
# than min_interval seconds ago. Prints "run" otherwise, including when there is
# no usable last run (empty or non-numeric last_ts) or the clock went backwards.
decide_run() {
    local signature="$1" now="$2" last_signature="$3" last_ts="$4" min_interval="$5"
    case "${last_ts}" in
        ''|*[!0-9]*) echo run; return 0 ;;
    esac
    if [[ "${signature}" != "${last_signature}" ]]; then
        echo run
        return 0
    fi
    local age=$((now - last_ts))
    if [[ ${age} -ge 0 && ${age} -lt ${min_interval} ]]; then
        echo skip
    else
        echo run
    fi
}

# signature_from_uuids — stdin: one UUID per line; stdout: sorted, unique,
# space-joined (no trailing space). Empty input gives an empty signature.
signature_from_uuids() {
    sort -u | grep -v '^$' | tr '\n' ' ' | sed 's/ $//' || true
}

# read_run_state <state_file> — prints "<last_ts>" and "<last_signature>" as two
# lines; two empty lines when the file is absent.
read_run_state() {
    local state_file="$1" ts="" sig=""
    if [[ -f "${state_file}" ]]; then
        { IFS= read -r ts; IFS= read -r sig; } < "${state_file}" || true
    fi
    printf '%s\n%s\n' "${ts}" "${sig}"
}

# write_run_state <state_file> <ts> <signature> — replace atomically.
write_run_state() {
    local state_file="$1" ts="$2" signature="$3" tmp
    mkdir -p "$(dirname "${state_file}")" 2>/dev/null || return 1
    tmp="${state_file}.$$"
    printf '%s\n%s\n' "${ts}" "${signature}" > "${tmp}" 2>/dev/null || return 1
    mv -f "${tmp}" "${state_file}"
}

# acquire_run_lock <lock_dir>
# 0 = acquired (or the state directory is unwritable, so run unlocked)
# 1 = another live run holds it. A lock whose pid is dead is removed and retaken.
acquire_run_lock() {
    local lock_dir="$1" holder
    mkdir -p "$(dirname "${lock_dir}")" 2>/dev/null || return 0
    if mkdir "${lock_dir}" 2>/dev/null; then
        echo "$$" > "${lock_dir}/pid"
        return 0
    fi
    [[ -d "${lock_dir}" ]] || return 0
    holder=$(cat "${lock_dir}/pid" 2>/dev/null || true)
    case "${holder}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if kill -0 "${holder}" 2>/dev/null; then
        return 1
    fi
    rm -rf "${lock_dir}"
    if mkdir "${lock_dir}" 2>/dev/null; then
        echo "$$" > "${lock_dir}/pid"
        return 0
    fi
    return 1
}

release_run_lock() {
    local lock_dir="$1"
    if [[ "$(cat "${lock_dir}/pid" 2>/dev/null || true)" == "$$" ]]; then
        rm -rf "${lock_dir}"
    fi
}
