#!/bin/bash
# dataless.sh — detect macOS "dataless" files without reading their contents
#
# A dataless file has been evicted by a cloud file provider; reading it triggers
# a download that can time out. Detection uses file flags from stat only.
# Pure filters read stdin and write stdout. list_file_flags is the one edge.

# ---------------------------------------------------------------------------
# flags_mark_dataless — exit 0 if a `stat -f %Sf` flags string (comma-separated,
# or "-" for none) contains the dataless flag
# ---------------------------------------------------------------------------
flags_mark_dataless() {
    case ",${1}," in
        *,dataless,*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# list_file_flags — print "<flags><TAB><path>" for every regular file under dir.
# find and stat read directory entries and inodes, never file contents.
# ---------------------------------------------------------------------------
list_file_flags() {
    find "$1" -type f -exec stat -f '%Sf%t%N' {} +
}

# ---------------------------------------------------------------------------
# dataless_relative_paths — stdin: "<flags><TAB><path>" lines; stdout: the
# source-root-relative path (leading "/") of each dataless file
# ---------------------------------------------------------------------------
dataless_relative_paths() {
    local root="${1%/}"
    local flags path
    while IFS=$'\t' read -r flags path; do
        if [[ -n "${path}" ]] && flags_mark_dataless "${flags}"; then
            printf '%s\n' "${path#"${root}"}"
        fi
    done
}

# ---------------------------------------------------------------------------
# escape_rsync_pattern — stdin: paths; stdout: the same paths with rsync glob
# metacharacters (\ * ? [ ]) backslash-escaped so each matches only itself
# ---------------------------------------------------------------------------
escape_rsync_pattern() {
    sed -e 's/[][\\*?]/\\&/g'
}
