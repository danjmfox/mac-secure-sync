---
status: accepted
date: 2026-10-09
feature: launchd-environment
---

# ADR-006: Run under launchd's bash 3.2, and skip dataless files instead of aborting

## Context

launchd starts the sync agents with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and `/bin/bash <script>`. On macOS `/bin/bash` is version 3.2.57. Two defects showed up in real use.

First, `bin/sync-usb.sh` used `declare -A registered_uuids`, an associative array that bash 3.2 does not have. The shell printed `declare: -A: invalid option`, then evaluated the UUID as arithmetic (`value too great for base`). USB sync therefore never ran from launchd. The acceptance suites did not catch it because they execute the scripts through their `#!/usr/bin/env bash` shebang, and the test PATH resolves `bash` to a newer Homebrew bash.

Second, one unreadable file aborted a whole directory. A real run copied about 2.5 of 3.2 GB, then rsync stopped with `mmap: Operation timed out ... exited with status 20` on a "dataless" file. A dataless file has been evicted by a cloud file provider (iCloud Drive and similar); `stat -f %Sf` shows the `dataless` flag, and reading the file triggers a download that can time out. Seventeen such files sat under one subfolder. The existing retry (one retry after 30 s) cannot help, because the file is still unreadable on the second attempt.

## Options Considered

### Bash 3.2 compatibility

- **A (chosen): a space-delimited string of registered UUIDs, tested with `case`.** Needs no new bash features. UUIDs contain no spaces, and the config already stores per-directory device lists space-joined.
- **B (rejected): require Homebrew bash in the launchd plist.** Adds a dependency and a path that differs between Intel and Apple Silicon.

### Dataless files

- **A (chosen): detect before rsync, pass `--exclude-from`.** `find <dir> -type f -exec stat -f '%Sf%t%N' {} +` lists flags and paths without opening any file. A pure filter keeps paths whose flags contain `dataless`. A second pure filter backslash-escapes the rsync glob characters `\ * ? [ ]`. The exclude file holds anchored paths (leading `/`, relative to the source root). Each skipped file is logged at WARN.
- **B (rejected): let rsync fail and parse its output.** the observed rsync exit 20 aborted the transfer, so nothing after the bad file was copied, and a retry hits the same file.
- **C (rejected): `--ignore-errors` alone.** Already present, and it does not help: the failure is a process-level abort, not a per-file I/O error.
- **D (rejected): rsync `--timeout`, or a pre-read with `dd`/`head` to probe readability.** Reading is exactly what triggers the download.

### Reporting

- **A (chosen): a third outcome, "completed with skips", exit code 3.** A partial sync is never reported as clean success, and launchd records a non-zero status. rsync exits 23 (partial transfer) and 24 (source files vanished) map to this outcome and are not retried, because retrying cannot fix them. Exit 20 and every other non-zero code stay failures: retried once after 30 s, then exit 1. Failure outranks skips when both occur.
- **B (rejected): keep exit 0 and rely on the WARN lines.** Hides a partial backup from anything that watches exit status.

### Cloud sync

`bin/sync-cloud.sh` is unchanged apart from being verified under bash 3.2. rclone handles read errors per file: it logs the error, continues with the other files, and exits non-zero at the end, which `sync-cloud.sh` already reports as a failure after its retry. The defect "one file aborts the directory" therefore does not apply, and a partial cloud sync is not reported as success. The cost is that rclone may attempt (and time out on) each dataless file, and may trigger the downloads. That is a behaviour I expect from rclone's design and have not observed against a real provider. If cloud runs prove slow or noisy, the same pure filters can feed `rclone --exclude-from`, with `{ }` added to the escaped set.

## Decision

Adopt the first option in each group. The helpers live in `bin/lib/dataless.sh` (`flags_mark_dataless`, `dataless_relative_paths`, `escape_rsync_pattern` are pure; `list_file_flags` is the single edge that touches the filesystem). `sync_to_usb` scans before each attempt, so a file that becomes dataless between attempts is picked up. `sync-usb.sh` ends with `USB sync job completed with skips: N dataless file(s) skipped, M partial transfer(s)` and exit 3 when `N + M > 0`.

New acceptance suite `tests/acceptance/launchd-environment/` runs the scripts as `env -i HOME=<tmp> PATH=<mock bin>:/usr/bin:/bin:/usr/sbin:/sbin /bin/bash <script>`.

## Exceptions

What the tests do not prove:

- They never see a real dataless file. `stat` is replaced by a PATH mock that reports the `dataless` flag for registered paths; the files stay readable. They prove the script acts on the flag string. They do not prove that macOS reports exactly `dataless` in `stat -f %Sf` for every provider, nor that stat and find never trigger a materialisation on a real provider.
- They do not reproduce the rsync mmap timeout. rsync exits 20, 23 and 24 are simulated with a mock that returns the code.
- A file that turns dataless between the scan and the transfer still fails the transfer. It is reported as a failure and retried, not skipped.
- Exclusion matching is tested with `[`, `]`, `*`, space and a literal name against Apple's openrsync only, not against rsync 3.x.
- A file name containing a newline breaks the line-oriented stat output. Such a line is ignored, so a dataless file with that name is not excluded.
- Dataless directories are not detected; only regular files are.
- Files already on the USB drive are not removed when they later become dataless.
- Exit code 3 was once documented as "both syncs failed" in a superseded design; `docs/features.md` says so. The code now means completed with skips, for `sync-usb.sh` only.
