<!-- markdownlint-disable MD024 -->
# User Stories: multi-usb-sync

Feature ID: `multi-usb-sync`
Date: 2026-05-15
Analyst: Luna (nw-product-owner)
Jobs traced: JOB-001 (silent-guardian), JOB-002 (multi-device-guardian)

---

## System Constraints

- macOS only; launchd is the automation layer
- Config location: `~/.config/securelocal/config.yaml` (schema v2)
- USB sync semantics: rsync without `--delete` (historical safety net)
- Cloud sync semantics: rclone sync (mirror — cloud reflects current state)
- Exit codes: 0=success, 1=USB fail, 2=cloud fail, 3=both fail, 4=config error
- Log file: `~/Library/Logs/securelocal-sync.log`
- rclone binary: path from config.yaml (resolved by installer)
- UUID validation mandatory before any write or sync

---

## US-001: Config YAML v2 Schema

### Elevator Pitch
- **Before**: Dan's config is a flat `config.env` with one USB UUID and one directory. Adding a second USB means rewriting the whole config. There's no model for "this directory syncs to remote-crypt:Projects."
- **After**: Running `install.sh` produces `~/.config/securelocal/config.yaml` with a `directories` section (each dir carrying its own `cloud_remote` and `usb_devices` list) and a `usb_devices` section (each device with UUID and label). Dan can see exactly what will sync where.
- **Decision enabled**: Dan can confidently register a second USB drive knowing it maps to the same directories without touching the cloud remote config.

### Problem
Dan Fox is a solo developer who is both builder and operator of mac-secure-sync. He finds it brittle to maintain a flat `config.env` where each sync job is a numbered variable (`JOB_1_USB_UUID`, `JOB_2_LOCAL_DIR`). Adding a second USB device requires renumbering entries and risks breaking the first device's config.

### Who
- Dan Fox | macOS, single machine, personal use | Needs a config model that cleanly supports N USB devices and M directories without restructuring on each change

### Solution
A YAML config file (schema v2) where directories are first-class entries, each carrying their own `cloud_remote` and `usb_devices` list. USB devices are named entries with UUID and label. Both sync scripts read from this single source.

### Domain Examples

#### 1: Happy Path — Initial Install
Dan runs `install.sh`, enters his USB volume name "IronKey-A", and confirms rclone remote "remote-crypt:secureLocal". The installer writes `config.yaml` with one directory (`~/secureLocal`) mapped to UUID-A and `remote-crypt:secureLocal`. Dan opens `config.yaml` and the layout is immediately readable.

#### 2: Edge Case — Two Directories, Different Cloud Remotes
Dan adds `~/Projects` to his config manually (or via installer prompt). Each directory carries its own `cloud_remote`. When he reads config.yaml, it is clear that `~/secureLocal` goes to `remote-crypt:secureLocal` and `~/Projects` goes to `remote-crypt:Projects`.

#### 3: Error/Boundary — Schema Version Mismatch
Dan upgrades mac-secure-sync but forgets to re-run the installer. The new sync scripts check `schema_version` and find `1` instead of `2`. They exit 4 with: "Config schema version mismatch — expected 2, found 1. Re-run install.sh to migrate."

### UAT Scenarios (BDD)

#### Scenario: Installer produces a readable config with correct structure
```gherkin
Given Dan runs install.sh and provides USB volume "IronKey-A" and remote "remote-crypt:secureLocal"
When the installer completes
Then ~/.config/securelocal/config.yaml exists
And it contains a "directories" entry for ~/secureLocal with cloud_remote: remote-crypt:secureLocal
And it contains a "usb_devices" entry with the detected UUID and label "IronKey-A"
And schema_version is 2
```

#### Scenario: Config schema version mismatch surfaces a clear error
```gherkin
Given config.yaml exists with schema_version: 1
When sync-usb.sh starts
Then it exits 4
And logs: "Config schema version mismatch — expected 2, found 1. Re-run install.sh."
```

#### Scenario: Multiple directories with independent cloud remotes are valid config
```gherkin
Given config.yaml contains two directory entries:
  - ~/secureLocal with cloud_remote: remote-crypt:secureLocal
  - ~/Projects with cloud_remote: remote-crypt:Projects
When sync-cloud.sh reads the config
Then it resolves two separate rclone targets (not a shared remote)
```

### Acceptance Criteria
- [ ] `~/.config/securelocal/config.yaml` is produced by `install.sh` with correct schema_version: 2
- [ ] Each directory entry in config.yaml has `local_path`, `cloud_remote`, and `usb_devices` fields
- [ ] Each USB device entry in config.yaml has `id` (UUID) and `label` fields
- [ ] Both sync scripts exit 4 with a human-readable message on schema_version mismatch
- [ ] Config is valid YAML (parseable by a standard YAML library without extension)

### Outcome KPIs
- **Who**: Dan (sole operator)
- **Does what**: Opens config.yaml and can immediately understand which directories sync where without consulting documentation
- **By how much**: Zero support questions to himself — config is self-describing
- **Measured by**: Qualitative — can Dan read the config cold and state the sync targets correctly?
- **Baseline**: Current config.env requires Dan to remember the numbered variable scheme

### Technical Notes
- Config schema: `schema_version`, `log_file`, `rclone_bin`, `directories[]`, `usb_devices[]`
- Migration from config.env is out of scope for this story (US-011 if needed)
- [DESIGN] Whether installer prompts for multiple directories or one is a DESIGN wave decision

### job_id: JOB-002

---

## US-002: USB Sync Script — Config-Driven, Multi-Directory

### Elevator Pitch
- **Before**: `sync-to-usb-and-cloud.sh` mixes USB and cloud sync, reads a flat env file, and handles exactly one USB UUID and one directory. Plugging in a second USB does nothing.
- **After**: Running `sync-usb.sh` (or via launchd) reads `config.yaml`, matches the mounted USB by UUID, and rsyncs every registered directory to that device's mount point.
- **Decision enabled**: Dan can trust that plugging in either USB-A or USB-B will sync all his directories to that device, without writing separate scripts.

### Problem
Dan Fox cannot use a second USB device for offsite backup because the current sync script is hardcoded to one UUID and one directory path. Acquiring a second drive (office vs home) means either maintaining two separate scripts or accepting that one drive never syncs automatically.

### Who
- Dan Fox | plugging in USB-A (home) or USB-B (office) | wants all registered directories synced to whichever drive just mounted, without any manual intervention

### Solution
A standalone `sync-usb.sh` script that reads `config.yaml`, scans `/Volumes` for any registered UUID, and rsyncs each directory whose `usb_devices` list includes that UUID. Runs silently via launchd WatchPaths on `/Volumes`.

### Domain Examples

#### 1: Happy Path — USB-A Mounts at Home
Dan plugs in USB-A (UUID: 1A2B-3C4D, label: IronKey-A). launchd fires `sync-usb.sh`. Script finds UUID-A in `/Volumes/IronKey-A`. It rsyncs `~/secureLocal` → `/Volumes/IronKey-A/secureLocal` and `~/Projects` → `/Volumes/IronKey-A/Projects`. Log shows two success entries. Exit 0.

#### 2: Edge Case — USB-B Mounts at Office (Same Directories)
Dan plugs in USB-B (UUID: 5E6F-7A8B, label: IronKey-B). Script finds UUID-B in `/Volumes/IronKey-B`. Rsyncs same source directories to `/Volumes/IronKey-B/secureLocal` and `/Volumes/IronKey-B/Projects`. Devices are fully independent — USB-A and USB-B have no knowledge of each other.

#### 3: Error/Boundary — Unregistered USB Mounts
Dan's colleague plugs in an unrelated USB key (UUID: FFFF-0000) to copy a file. launchd fires `sync-usb.sh`. Script scans `/Volumes`, finds no registered UUID. Logs: "No registered USB device found — exiting." Exit 0. Nothing syncs.

### UAT Scenarios (BDD)

#### Scenario: All registered directories sync when USB-A mounts
```gherkin
Given config.yaml maps USB-A (UUID-A) to [~/secureLocal, ~/Projects]
And USB-A is mounted at /Volumes/IronKey-A
When sync-usb.sh runs
Then ~/secureLocal is rsynced to /Volumes/IronKey-A/secureLocal without --delete
And ~/Projects is rsynced to /Volumes/IronKey-A/Projects without --delete
And the log records a success entry per directory with timestamp
And sync-usb.sh exits 0
```

#### Scenario: USB-B syncs independently of USB-A
```gherkin
Given both USB-A and USB-B are registered in config.yaml
And USB-B is mounted at /Volumes/IronKey-B (USB-A is not mounted)
When sync-usb.sh runs
Then only IronKey-B mount point receives sync (not /Volumes/IronKey-A)
And sync-usb.sh exits 0
```

#### Scenario: Unregistered volume mount does not trigger sync
```gherkin
Given config.yaml contains only UUID-A and UUID-B
And an unregistered USB key (UUID: FFFF-0000) is mounted
When sync-usb.sh runs
Then no rsync operations execute
And the log records "no registered USB device found" at INFO level
And sync-usb.sh exits 0
```

#### Scenario: One directory sync failure does not abort remaining directories
```gherkin
Given USB-A is mounted with 2 registered directories
And ~/Projects fails to rsync (source directory missing)
When sync-usb.sh runs
Then ~/secureLocal syncs successfully
And the log records the ~/Projects failure with the rsync error message
And sync-usb.sh exits 1
```

### Acceptance Criteria
- [ ] Script reads directory list from `config.yaml:directories[*]` filtered by mounted USB UUID
- [ ] rsync runs without `--delete` flag for all matched directories
- [ ] Script exits 0 when all syncs succeed; exits 1 on any partial or full failure
- [ ] Script exits 0 silently when no registered USB is found in /Volumes
- [ ] Each directory sync attempt is logged independently (timestamp + source + target + outcome)
- [ ] Script does not import or call any cloud sync logic

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Plugs in either USB device and finds all directories backed up, without running any command
- **By how much**: 100% of registered directories synced on every USB mount, zero missed syncs
- **Measured by**: Log file entry count per sync session vs registered directory count
- **Baseline**: Current script: one directory, one UUID, cloud and USB coupled

### Technical Notes
- rsync flags: `-avh --ignore-errors` (no `--delete`)
- launchd plist: `com.securelocal.usb-sync.plist` with `WatchPaths: [/Volumes]`
- Target path: `/Volumes/<device_label>/<relative_path_from_local_path>`
- [DESIGN] Whether to create USB target directory if missing is a DESIGN decision

### job_id: JOB-001

---

## US-003: Cloud Sync Script — Timer-Driven, Per-Directory Remote

### Elevator Pitch
- **Before**: Cloud sync only runs when a USB drive mounts (same combined script). If both USBs are at the office, Dan's cloud backup hasn't run in days without him knowing.
- **After**: Running `sync-cloud.sh` (via launchd hourly timer or manually) syncs each directory to its own `cloud_remote` — regardless of whether any USB is connected.
- **Decision enabled**: Dan can trust that cloud backup is running hourly even during stretches where he doesn't use either USB drive.

### Problem
Dan Fox's cloud backup is currently coupled to USB mount events. When neither USB is present — overnight, during travel, or when both drives are at the office — the cloud remote receives no updates. A week of unsynced changes is invisible to Dan until he checks the log.

### Who
- Dan Fox | working or sleeping while launchd fires hourly | wants cloud backup independent of USB presence so data is safe even without physical drives

### Solution
A standalone `sync-cloud.sh` script triggered by a `StartInterval`-based launchd plist (independent of WatchPaths). Reads `config.yaml:directories`, and for each directory runs `rclone sync` to its `cloud_remote`. Retries once on failure.

### Domain Examples

#### 1: Happy Path — Hourly Timer, No USB Present
It is 3am. Dan is asleep. No USB drive is mounted. launchd fires `sync-cloud.sh`. Script reads config.yaml, finds two directories. Rclones `~/secureLocal` → `remote-crypt:secureLocal` (8.1s) and `~/Projects` → `remote-crypt:Projects` (12.4s). Log records both successes. Exit 0.

#### 2: Edge Case — Cloud Sync and USB Sync Run Simultaneously
Dan plugs in USB-A just as the hourly timer fires. Both scripts start within seconds of each other. Each script reads config.yaml independently. rsync and rclone operate on different targets (local disk vs cloud). No lock contention. Both log entries appear in the shared log file with distinct timestamps.

#### 3: Error/Boundary — Network Unavailable, Retry Fails
Dan's WiFi drops at 7am. launchd fires `sync-cloud.sh`. rclone fails ("connection refused"). Script waits 30 seconds, retries. Retry fails again. Log records: "[ERROR] cloud sync failed after 2 attempts — remote-crypt:secureLocal." Exit 2. Dan sees this when he checks the log at 8am and runs `sync-cloud.sh` manually.

### UAT Scenarios (BDD)

#### Scenario: Cloud sync runs hourly regardless of USB state
```gherkin
Given no USB device is mounted
And config.yaml maps [~/secureLocal, ~/Projects] to their respective cloud remotes
When the launchd StartInterval timer fires sync-cloud.sh
Then rclone syncs ~/secureLocal to remote-crypt:secureLocal
And rclone syncs ~/Projects to remote-crypt:Projects
And the log records success for both with timestamps
And sync-cloud.sh exits 0
```

#### Scenario: Cloud sync retries once then logs failure
```gherkin
Given the network is unavailable when sync-cloud.sh fires
When sync-cloud.sh attempts rclone sync for ~/secureLocal
Then the first attempt fails within 60 seconds
And sync-cloud.sh waits 30 seconds
And retries the sync once more
And if the retry fails, logs: "[ERROR] cloud sync failed after 2 attempts — remote-crypt:secureLocal"
And sync-cloud.sh exits 2
```

#### Scenario: Each directory syncs to its own cloud remote
```gherkin
Given config.yaml has:
  - ~/secureLocal → remote-crypt:secureLocal
  - ~/Projects → remote-crypt:Projects
When sync-cloud.sh runs
Then rclone is called separately for each directory with its own remote target
And not a single rclone call syncing both directories to the same remote
```

#### Scenario: Dan can invoke cloud sync manually to recover from a failure
```gherkin
Given sync-cloud.sh exited 2 last night (network failure)
When Dan runs: sync-cloud.sh directly in terminal
Then rclone syncs both directories successfully (network restored)
And the log appends new success entries
And sync-cloud.sh exits 0
```

### Acceptance Criteria
- [ ] `sync-cloud.sh` reads `cloud_remote` per directory from `config.yaml` (not a global remote)
- [ ] rclone sync (mirror semantics) runs per directory independently
- [ ] Script retries once after 30-second wait on failure
- [ ] Script exits 0 (full success), 2 (cloud fail), or 4 (config error) — never exits 1
- [ ] Script does not import or call any USB sync logic
- [ ] Script is invocable manually (stdout output matches `--verbose` format in journey visual)
- [ ] launchd plist uses `StartInterval` (not `WatchPaths`)

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Has cloud backup updated within the last 2 hours at all times, regardless of USB availability
- **By how much**: Cloud sync runs at least once every hour — 24+ sync attempts per day
- **Measured by**: Log file entries timestamped at hourly intervals; zero multi-hour gaps in cloud entries
- **Baseline**: Current: cloud sync runs only on USB mount — could be 0 times/day if USB unused

### Technical Notes
- rclone flags: `sync` (mirror semantics); `--log-file` pointing to config.yaml:log_file
- launchd plist: `com.securelocal.cloud-sync.plist` with `StartInterval: 3600`
- [Q1 resolved]: Manual invocation and launchd timer are both valid; no special mode needed
- rclone binary path from `config.yaml:rclone_bin` (not hardcoded)

### job_id: JOB-001

---

## US-004: Structured Log Output — Grep-Friendly, Human-Readable

### Elevator Pitch
- **Before**: Log entries are informal text strings with no consistent format. Dan cannot quickly grep for failures or know at a glance whether last night's sync worked.
- **After**: Tailing `~/Library/Logs/securelocal-sync.log` shows timestamped, structured lines where `[ERROR]` lines stand out and each directory outcome is on its own line.
- **Decision enabled**: Dan can decide within 30 seconds whether his backup is healthy or needs attention.

### Problem
Dan Fox is the silent guardian's auditor. When something goes wrong, he needs to diagnose quickly. The current log is unstructured — a wall of text where errors are indistinguishable from progress messages, and there is no grep-friendly keyword convention.

### Who
- Dan Fox | checking the log after a sync (or after a suspected failure) | needs to confirm success or locate failure in under 30 seconds

### Solution
Both `sync-usb.sh` and `sync-cloud.sh` write structured log entries following a consistent format: `[TIMESTAMP] [LEVEL] [SCRIPT] [DIRECTORY] [MESSAGE]`. LEVEL is one of: INFO, WARN, ERROR. Both scripts write to the same log file resolved from `config.yaml:log_file`.

### Domain Examples

#### 1: Happy Path — Dan tails the log after a USB sync
Dan runs `tail -20 ~/Library/Logs/securelocal-sync.log` after plugging in USB-A. He sees:
```
2026-05-15T07:32:01 INFO  sync-usb  ~/secureLocal   rsync started
2026-05-15T07:32:04 INFO  sync-usb  ~/secureLocal   rsync complete (3.1s)
2026-05-15T07:32:04 INFO  sync-usb  ~/Projects      rsync started
2026-05-15T07:32:05 INFO  sync-usb  ~/Projects      rsync complete (0.8s)
2026-05-15T07:32:05 INFO  sync-usb  -               USB sync complete — exit 0
```

#### 2: Edge Case — Dan greps for errors after a week away
Dan runs `grep ERROR ~/Library/Logs/securelocal-sync.log`. He sees two cloud sync errors from Wednesday night (network outage). Everything else is INFO. He reruns cloud sync manually — recovers in 5 minutes.

#### 3: Error/Boundary — Concurrent writes from both scripts
USB sync fires at 07:32 and cloud sync fires at 07:32 (both trigger simultaneously). Both scripts write to the same log file. Entries are not interleaved mid-line — each script uses line-atomic writes (append mode, one `echo` per line). The log is readable even under concurrent write.

### UAT Scenarios (BDD)

#### Scenario: Dan verifies last sync succeeded by reading the log
```gherkin
Given sync-usb.sh ran at 07:32 and exited 0
When Dan runs: tail -20 ~/Library/Logs/securelocal-sync.log
Then he sees a timestamped INFO entry per directory synced
And the final line reads "USB sync complete — exit 0"
And no ERROR or WARN lines appear
```

#### Scenario: Dan discovers a cloud failure by grepping for errors
```gherkin
Given sync-cloud.sh exited 2 at 03:00 (network failure)
When Dan runs: grep ERROR ~/Library/Logs/securelocal-sync.log
Then he sees: "2026-05-15T03:00:45 ERROR sync-cloud ~/secureLocal cloud sync failed after 2 attempts — connection refused"
And the grep output contains enough context to identify which directory failed and why
```

#### Scenario: Log entries from concurrent scripts do not interleave mid-line
```gherkin
Given sync-usb.sh and sync-cloud.sh start within 1 second of each other
When both scripts write to the shared log file simultaneously
Then each log line is complete and readable (no partial lines merged together)
And the log file is valid: each line starts with a timestamp
```

### Acceptance Criteria
- [ ] Log entry format: `YYYY-MM-DDTHH:MM:SS LEVEL SCRIPT DIRECTORY MESSAGE` (tab or space separated)
- [ ] LEVEL values: INFO, WARN, ERROR only — no other values
- [ ] Both sync scripts write to `config.yaml:log_file` (not hardcoded path)
- [ ] Each directory operation produces at minimum: start entry and completion/failure entry
- [ ] Concurrent writes produce no partial/interleaved lines (line-atomic append)
- [ ] `grep ERROR <log_file>` returns only genuine error lines

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Determines backup health status from the log in under 30 seconds
- **By how much**: 100% of failure events visible via `grep ERROR <log>`; zero silent failures
- **Measured by**: Qualitative test — can Dan identify last failure within 30s of opening the log?
- **Baseline**: Current log format requires reading all entries to locate errors

### Technical Notes
- Line-atomic writes: use `echo "..." >> $LOG_FILE` (not printf with partial writes)
- No ANSI color codes in log file (terminal color is for stdout only)
- Timestamp: ISO 8601 local time (`date +%Y-%m-%dT%H:%M:%S`)

### job_id: JOB-001

---

## US-005: Register Second USB Device

### Elevator Pitch
- **Before**: Adding USB-B to Dan's setup means editing config manually, getting the UUID right, and hoping the format is correct — with no validation.
- **After**: Dan registers USB-B via the registration mechanism, and config.yaml is updated with UUID-B added to the `usb_devices` list of each relevant directory. USB-A config is provably unchanged.
- **Decision enabled**: Dan can commit to buying a second drive for offsite backup, knowing setup is low-friction and safe.

### Problem
Dan Fox wants to keep USB-B at his office as an independent offsite backup. The current config model requires restructuring the entire config to add a second device. There is no way to verify that adding USB-B does not accidentally corrupt USB-A's configuration.

### Who
- Dan Fox | acquiring USB-B for offsite backup | wants to register it without any risk to the existing USB-A sync setup

### Solution
A registration mechanism (invocable command — mechanism TBD in DESIGN wave) that adds a new USB device entry to `config.yaml:usb_devices` and appends the new UUID to each directory's `usb_devices` list. The mechanism validates the UUID before writing and confirms existing entries are unchanged.

### Domain Examples

#### 1: Happy Path — USB-B Registered Alongside USB-A
Dan runs the registration mechanism for USB-B (UUID-B, label "IronKey-B"). It writes a new entry in `config.yaml:usb_devices`. It appends UUID-B to both `~/secureLocal` and `~/Projects` directory entries. Dan checks config.yaml — UUID-A is still present, unchanged.

#### 2: Edge Case — Registering USB-B with One Directory Excluded (future)
This is out of scope for now (Q2 answer: sync all directories always). If Dan wants selective sync per device, that is a future story. Registration always adds the new UUID to all directories.

#### 3: Error/Boundary — Duplicate UUID Registration Attempt
Dan accidentally tries to register USB-A again. The tool detects UUID-A is already in `config.yaml:usb_devices` and exits with: "UUID 1A2B-3C4D already registered as IronKey-A. No changes made."

### UAT Scenarios (BDD)

#### Scenario: USB-B registered without altering USB-A config
```gherkin
Given USB-A (UUID-A, label: IronKey-A) is registered and syncing correctly
When Dan registers USB-B (UUID-B, label: IronKey-B)
Then config.yaml:usb_devices contains both UUID-A and UUID-B entries
And each directory's usb_devices list contains both UUID-A and UUID-B
And UUID-A's entry in config.yaml is byte-for-byte identical to before registration
```

#### Scenario: After registration, USB-B sync works without additional steps
```gherkin
Given USB-B has just been registered
When Dan mounts USB-B
Then sync-usb.sh syncs all registered directories to /Volumes/IronKey-B
And sync-usb.sh exits 0
```

#### Scenario: Duplicate UUID registration is rejected without modifying config
```gherkin
Given UUID-A is already in config.yaml:usb_devices as IronKey-A
When Dan attempts to register UUID-A again
Then the tool outputs: "UUID already registered as IronKey-A — no changes made"
And config.yaml is not modified
And the tool exits non-zero
```

#### Scenario: UUID written to config matches the actual device UUID
```gherkin
Given Dan uses the registration mechanism for USB-B
When registration completes
Then the UUID in config.yaml:usb_devices matches the output of:
  diskutil info /Volumes/IronKey-B | grep "Volume UUID"
```

### Acceptance Criteria
- [ ] Registration adds new entry to `config.yaml:usb_devices` with `id` and `label`
- [ ] Registration appends new UUID to `usb_devices` list of every directory entry
- [ ] Existing `usb_devices` entries are not modified or reordered
- [ ] Duplicate UUID detected and rejected with a clear message; config unchanged
- [ ] Post-registration: USB-B mount triggers `sync-usb.sh` without any additional config step
- [ ] [DESIGN] UUID detection mechanism is deferred — story describes outcome only

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Registers USB-B and has it syncing automatically the first time it mounts
- **By how much**: Setup time < 5 minutes; zero risk of disrupting USB-A; zero manual YAML edits
- **Measured by**: Time from plugging in USB-B to first confirmed sync log entry
- **Baseline**: Current: manual config restructure, estimated 30+ minutes, high error risk

### Technical Notes
- [DESIGN] Registration mechanism (auto-detect UUID vs manual entry) is a DESIGN wave decision
- Config write must be atomic (write to temp file, then rename) to avoid partial writes
- Validation: UUID format check before writing (not empty, not duplicate)

### job_id: JOB-002

---

## US-006: launchd Automation — Two Independent Plists

### Elevator Pitch
- **Before**: One launchd plist triggers one combined script on USB mount. Cloud sync only happens when a USB plugs in. No timer-based backup exists.
- **After**: Two independent plists are installed: one fires `sync-usb.sh` on `/Volumes` changes; one fires `sync-cloud.sh` every hour. Each plist is loaded and verifiable independently.
- **Decision enabled**: Dan can confirm automation is active for both sync paths and know that cloud backup is running hourly even when he hasn't touched a USB drive in days.

### Problem
Dan Fox's current launchd setup couples both sync types to one trigger (WatchPaths on /Volumes). Cloud backup is accidentally dependent on USB presence. When Dan travels without USB drives, cloud backup stops silently.

### Who
- Dan Fox | having just installed or upgraded mac-secure-sync | wants to confirm that both USB and cloud automation are active and independent

### Solution
Two launchd plists installed by `install.sh`. `com.securelocal.usb-sync.plist`: WatchPaths `/Volumes`, calls `sync-usb.sh`. `com.securelocal.cloud-sync.plist`: StartInterval 3600, calls `sync-cloud.sh`. Both are loaded as LaunchAgents for the current user.

### Domain Examples

#### 1: Happy Path — Post-Install Verification
Dan runs `install.sh`. After completion, he runs `launchctl list | grep securelocal`. He sees two rows: `com.securelocal.usb-sync` and `com.securelocal.cloud-sync`. Both are loaded. He plugs in USB-A — USB sync fires. He waits 1 hour — cloud sync fires (or runs `sync-cloud.sh` manually to verify).

#### 2: Edge Case — Upgrade Replaces Old Combined Plist
Dan upgrades from v1 (one plist: `com.securelocal.sync`). Install.sh detects the old plist, unloads it, removes it, and installs the two new plists. Old plist name no longer appears in `launchctl list`.

#### 3: Error/Boundary — Cloud Plist Not Loaded
Something prevents the cloud plist from loading (e.g., syntax error in plist). `install.sh` detects the load failure and outputs: "Failed to load com.securelocal.cloud-sync.plist — cloud sync will not run automatically." Dan can fix and reload manually.

### UAT Scenarios (BDD)

#### Scenario: Both plists are installed and loaded after install.sh completes
```gherkin
Given Dan runs install.sh on a clean system
When install.sh completes successfully
Then ~/Library/LaunchAgents/com.securelocal.usb-sync.plist exists
And ~/Library/LaunchAgents/com.securelocal.cloud-sync.plist exists
And launchctl list | grep com.securelocal shows two loaded agents
```

#### Scenario: USB sync fires within 5 seconds of USB mount
```gherkin
Given com.securelocal.usb-sync.plist is loaded with WatchPaths: [/Volumes]
When Dan mounts USB-A
Then sync-usb.sh is invoked by launchd within 5 seconds
And a log entry appears confirming the USB sync started
```

#### Scenario: Cloud sync fires on a timer independent of USB state
```gherkin
Given com.securelocal.cloud-sync.plist is loaded with StartInterval: 3600
And no USB device is mounted
When 3600 seconds elapse since last cloud sync invocation
Then sync-cloud.sh is invoked by launchd
And a log entry confirms cloud sync ran without USB dependency
```

#### Scenario: Old combined plist is removed on upgrade
```gherkin
Given com.securelocal.sync.plist (v1) is loaded from a previous install
When Dan runs install.sh (v2)
Then com.securelocal.sync.plist is unloaded and removed
And the two new plists are installed and loaded in its place
```

### Acceptance Criteria
- [ ] `install.sh` installs `com.securelocal.usb-sync.plist` (WatchPaths: [/Volumes])
- [ ] `install.sh` installs `com.securelocal.cloud-sync.plist` (StartInterval: 3600)
- [ ] Both plists are loaded via `launchctl load` during install
- [ ] Install fails with clear message if either plist fails to load
- [ ] Old `com.securelocal.sync.plist` is unloaded and removed if present
- [ ] Post-install verification: `launchctl list | grep com.securelocal` returns two rows

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Confirms both sync paths are active within 30 seconds of install completion
- **By how much**: Zero manual post-install steps required to activate automation
- **Measured by**: `launchctl list | grep com.securelocal | wc -l` == 2 after install
- **Baseline**: Current: one plist, one combined trigger — cloud backup silently stops without USB

### Technical Notes
- launchd plist path: `~/Library/LaunchAgents/` (user-level agent, not system-level)
- StartInterval: 3600 seconds (1 hour) is the default; DESIGN wave may make this configurable
- WatchPaths: `["/Volumes"]` — fires on any /Volumes change, not only registered UUID mounts
- Both plists must reference absolute paths to sync scripts (launchd PATH is minimal)

### job_id: JOB-001

---

## US-007: @infrastructure — Test Harness for Config-Driven Scripts

### Problem
The existing test harness (`test-sync-script.sh`) mocks `diskutil`, `rsync`, and `rclone` for the combined single-UUID script. With two separate scripts reading a YAML config, the test harness must be updated to cover the new config model, UUID matching logic, and per-directory sync behaviour.

### Who
- Dan Fox as builder | running tests before committing changes | needs confidence that config changes do not silently break sync behaviour

### Solution
Update `test-sync-script.sh` (or replace with two test scripts) to mock both scripts against a temp config.yaml. Cover: single USB match, dual USB independence, cloud-only path, partial directory failure, config schema version mismatch, duplicate UUID rejection.

### Domain Examples

#### 1: USB sync test with two registered devices
Test creates temp config.yaml with UUID-A and UUID-B. Mocks `/Volumes` with UUID-A mounted. Runs `sync-usb.sh`. Asserts only UUID-A directories are rsynced. UUID-B directories are not touched.

#### 2: Cloud sync test without USB
Test creates temp config.yaml. Mocks rclone. Runs `sync-cloud.sh` with no `/Volumes` entries. Asserts rclone called twice (once per directory). Exit 0.

#### 3: Schema version mismatch
Test creates config.yaml with `schema_version: 1`. Runs either script. Asserts exit 4 and error message contains "schema version mismatch".

### UAT Scenarios (BDD)

#### Scenario: Test harness confirms USB-A sync does not touch USB-B mount point
```gherkin
Given a test config.yaml with UUID-A and UUID-B registered
And the mock /Volumes contains only UUID-A
When sync-usb.sh runs under the test harness
Then rsync is called only for /Volumes/<UUID-A-label>/* paths
And no rsync call references any UUID-B path
```

#### Scenario: Test harness confirms cloud sync runs without USB
```gherkin
Given a test config.yaml with two directories and cloud remotes
And no mock USB volumes exist
When sync-cloud.sh runs under the test harness
Then mock rclone is called twice (once per directory)
And exit code is 0
```

### Acceptance Criteria
- [ ] Test harness creates isolated temp directory for each test run
- [ ] Mocks: `diskutil`, `rsync`, `rclone`, `launchctl` (for verification tests)
- [ ] Tests cover: single UUID match, dual USB independence, cloud-only, schema version mismatch, duplicate UUID rejection, partial failure exit codes
- [ ] Test harness cleans up temp config and directories after each test
- [ ] `bin/test-sync-script.sh` runs to completion with all tests passing on a clean config

### Technical Notes
- Existing test harness pattern is valid — extend it rather than replace if feasible
- No real USB or cloud access needed
- Runs in CI (no hardware dependency)

### job_id: infrastructure-only
### infrastructure_rationale: Test harness enables US-002 through US-006 to be verified without hardware. No user-facing behavior — pure quality gate for the builder-as-operator persona.
