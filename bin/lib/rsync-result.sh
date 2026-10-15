#!/usr/bin/env bash
# rsync-result.sh — read what rsync actually did from its --stats output (ADR-008)
#
# Pure filters and classifier: no side effects, no top-level execution.
# Apple's /usr/bin/rsync is openrsync; it prints "Number of files transferred: N".
# rsync 3.x prints "Number of regular files transferred: N". Both are accepted.

# rsync_files_transferred — stdin: rsync output; stdout: the last reported
# transferred-file count, or 0 when none is reported.
rsync_files_transferred() {
    local n
    n=$(sed -n 's/^Number of \(regular \)\{0,1\}files transferred: \([0-9][0-9]*\).*/\2/p' | tail -n 1)
    echo "${n:-0}"
}

# rsync_output_has_access_error — stdin: rsync output; exit 0 when it reports
# macOS denying access ("Operation not permitted") or a permission error.
rsync_output_has_access_error() {
    grep -qiE 'operation not permitted|permission denied'
}

# classify_partial_exit <files_transferred> <access_error: yes|no>
# For rsync exit 23/24. Prints "access-denied" when nothing was transferred and
# access errors were reported, otherwise "skips".
classify_partial_exit() {
    if [[ "$1" == "0" && "$2" == "yes" ]]; then
        echo access-denied
    else
        echo skips
    fi
}
