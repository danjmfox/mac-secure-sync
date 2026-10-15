---
status: accepted
date: 2026-10-09
feature: usb-retrigger-and-access-errors
route: bug fixes, direct execution (no waves)
---

# ADR-008: Debounce USB sync triggers, and treat "exit 23, nothing transferred, access denied" as a failure

Route: two bug fixes executed directly, without nWave waves. The behaviour is pinned by the acceptance suite `tests/acceptance/usb-retrigger-and-access-errors/`.

## Context

`sync-usb.sh` is started by a launchd agent with `WatchPaths` on `/Volumes`. launchd runs the job whenever anything under `/Volumes` changes. The real log (`~/Library/Logs/securelocal-sync.log`) shows 836 "USB sync job started" lines, one every 35 to 180 seconds through the day, with no drive being plugged in. The likely cause is Time Machine mounting and unmounting snapshot volumes under `/Volumes`, plus the sync's own activity. That cause is not confirmed. Each run scanned every mounted volume and the whole source tree for dataless files, and a run that hit an rsync failure slept 30 seconds before retrying. Each log line also appears twice, because the script writes to the log file itself and launchd sends stdout and stderr to the same file (`StandardOutPath`, `StandardErrorPath`). The duplication is reported here and not changed.

Second defect: when macOS privacy protection (TCC) denies `/bin/bash` access to the source directory, rsync reports "Transfer starting: 0 files" and exits 23. `sync-usb.sh` treated every exit 23 as a partial transfer and logged "rsync partial transfer (exit 23); remaining files were synced", although nothing had been synced. The job then ended as "completed with skips" (exit 3), which hides a backup that never happened.

## Options Considered

### A. Retrigger storm

- **ThrottleInterval only (rejected).** launchd still starts the script after the throttle period, so every trigger still costs a scan. It also cannot tell a real plug-in from noise, so a drive plugged in during the throttle window is delayed.
- **Remove `WatchPaths` and rely on `StartInterval` (rejected).** Ends the storm but loses the sync that starts when a drive is plugged in, which is the point of the USB agent.
- **Filter by `/Volumes` entry name (rejected).** A name filter (skip `.timemachine`, `com.apple.TimeMachine.localsnapshots`) would need a list of noise names that I have not observed first-hand, and it cannot cover the sync's own activity. `WatchPaths` cannot filter in the plist anyway; the script would still start and the filter would run inside it.
- **Signature plus minimum interval (chosen).** The signature is the sorted, unique list of registered device UUIDs that are currently mounted. The script computes it after loading the config and before any scan or rsync. If the signature equals the one stored at the end of the last run, and that run finished less than the minimum interval ago, the script logs one INFO line and exits 0. A different signature (a registered drive appeared or disappeared) always runs. Volumes that are not registered, Time Machine snapshots included, never enter the signature, so they cannot cause a run by themselves.

### Decisions inside the chosen option

- **State location.** `securelocal-usb-sync.state` sits in the directory of the configured `log_file` (`~/Library/Logs` in a real install). `SECURELOCAL_STATE_DIR` overrides it. The log directory was chosen over `~/.local/state` because the config already names it, it exists, and tests that give each case its own temporary log directory get isolated state without touching the real HOME.
- **State format.** Two lines: the finish time in epoch seconds, then the signature. Written to a temporary file and moved into place.
- **Minimum interval.** 600 seconds, overridable with `SECURELOCAL_MIN_INTERVAL` (seconds; a non-numeric value falls back to 600). Ten minutes is a judgement call: short enough that a changed source directory is backed up the same morning, long enough to absorb the observed 35 to 180 second retriggers. The `StartInterval` cloud sync is unaffected.
- **The stamp is written on every completed run, including failures and "completed with skips".** If a failed run left no stamp, a failing job would run the full scan and the 30 second retry sleep on every retrigger, which is the storm again. With the stamp, a failing job retries once the interval has passed. The cost is that after a failure the user waits up to the interval for the next attempt unless the drive set changes. Unplugging and re-plugging the drive changes the signature and runs at once.
- **A skipped trigger does not refresh the stamp.** Otherwise a steady stream of triggers would slide the window forward and the job would never run again.
- **The stamp is written by an `EXIT` trap** installed after the gate passes, so every exit path of `main` records it. A run killed by SIGKILL records nothing; the next trigger then runs, which is the safe direction.
- **Lock.** `mkdir` on `securelocal-usb-sync.lock` with the owner's pid inside. A second run that finds a live owner logs "another USB sync run is in progress, skipping" and exits 0. A lock whose pid is dead is removed and retaken. This also stops overlapping runs, which could previously happen when a long rsync was still going while launchd fired again. If the state directory is not writable, the script runs unlocked and unstamped, as before this change.
- **Purity.** `decide_run` (skip or run from signature, now, last signature, last finish time, interval) and `signature_from_uuids` are pure and live in `bin/lib/run-gate.sh`. State and lock helpers are the filesystem edge. The clock is read in `main`, so the tests control time by writing the state file.

### B. Exit 23 with nothing transferred

- **Keep treating every 23/24 as "completed with skips" (rejected).** Reports a backup that did not happen.
- **Treat every 23/24 as failure (rejected).** One unreadable file among thousands would fail the whole job, which ADR-006 deliberately avoided.
- **Classify from rsync's own `--stats` output (chosen).** `sync-usb.sh` now passes `--stats` (supported by Apple's openrsync, checked with `rsync --help` and a live run) and keeps a copy of the output. `rsync_files_transferred` reads "Number of files transferred: N" (openrsync) or "Number of regular files transferred: N" (rsync 3.x). `rsync_output_has_access_error` looks for "Operation not permitted" or "permission denied", case-insensitively. For exit 23/24: zero transferred and an access error is a failure; anything else stays "completed with skips". A failure logs ERROR with the likely cause (macOS privacy protection, Full Disk Access for `/bin/bash`, see README), is retried once after 30 seconds as before, and ends the job with exit 1.
- The partial-transfer WARN now reads "rsync partial transfer (exit N); K file(s) transferred, the rest were skipped", with the real count in place of the unverified claim.

## Decision

Adopt signature plus minimum interval with the lock for A, and stats-based classification for B. `README.md` gains a "Permissions under launchd" section that states Full Disk Access for `/bin/bash` is a broad grant with security consequences and that granting it is the user's decision. It does not recommend granting access to rsync. This change adds and alters no permission settings.

New files: `bin/lib/run-gate.sh`, `bin/lib/rsync-result.sh`, and the acceptance suite. `sync-usb.sh` sources both libraries.

## Exceptions

What the tests do not prove:

- **Real Time Machine behaviour.** They never see a Time Machine mount. They prove that unchanged registered drives within the interval cause a skip. They do not prove that Time Machine is the trigger, and they do not measure the new trigger rate.
- **Real TCC.** The access-denied case is a mock rsync that prints the strings I expect and exits 23. Neither openrsync's real wording under TCC denial nor TCC itself was exercised. If openrsync words the error differently, the case falls back to "completed with skips".
- **Zero transferred plus an access error also fails a run where every file is already up to date and one file is unreadable.** That is a failure by the rule as specified. It is a persistent per-file permission problem and a retry will not fix it. The alternative, also requiring "Number of files: 0", was not adopted.
- **Config changes inside the interval.** The signature holds device UUIDs only. A new directory mapped to an already mounted drive waits up to the interval for its first sync, unless the drive set changes.
- **Source changes inside the interval.** A file changed in the minute after a run is copied by the next run after the interval, not at the next trigger. This is the intended cost of the debounce.
- **Lock races.** Taking over a stale lock is remove-then-`mkdir`; two runs finding the same dead lock at the same instant could both try, and `mkdir` lets one win. A crash between `mkdir` and writing the pid leaves a lock with no pid, which is treated as held and needs manual removal of the lock directory.
- **Duplicate log lines** (script `tee` plus launchd `StandardOutPath`) are unchanged.
- **PID reuse.** A dead owner whose pid was reused by another live process keeps the lock until that process exits.
