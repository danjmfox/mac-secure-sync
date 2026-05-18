# Story Map: multi-usb-sync

## User: Dan Fox (builder-user)
## Goal: Sensitive directories backed up automatically to any registered USB and to cloud on a timer, with clear evidence of success or failure.

---

## Backbone (User Activities — left to right)

| Register Device | Configure Directories | USB Sync | Cloud Sync | Verify & Recover |
|---|---|---|---|---|
| Register USB-A at setup | Map dir → cloud remote | USB-A mounts → rsync fires | Timer fires → rclone runs | Read log for success/failure |
| Register USB-B (second drive) | Map dir → USB device(s) | USB-B mounts → rsync fires | Retry on network failure | Detect failure from exit code |
| Validate UUID uniqueness | Migrate from config.env | UUID not matched → silent exit | Partial dir failure logged | Rerun cloud sync manually |
| [DESIGN] UUID detection mechanism | Config YAML schema v2 | Partial dir failure → exit 1 | Independent of USB state | Log format grep-friendly |

---

## Walking Skeleton

Thinnest slice that proves end-to-end flow works:

1. **Register**: Config YAML v2 schema exists; USB-A UUID written to `usb_devices`; one directory mapped to USB-A and one cloud remote
2. **USB Sync**: `sync-usb.sh` reads config.yaml; finds UUID-A in `/Volumes`; rsyncs one directory; logs success; exits 0
3. **Cloud Sync**: `sync-cloud.sh` reads config.yaml; reads `cloud_remote` for that directory; runs rclone; logs success; exits 0
4. **Verify**: Log file contains timestamped success entries for both scripts

> Walking skeleton deliberately omits: multiple directories, multiple USB devices, retry logic, error paths, launchd plist wiring, migration from old config. These are Release 1 and Release 2 concerns.

---

### Walking Skeleton Stories

- **US-001**: Config YAML v2 schema (single dir, single USB, single cloud remote)
- **US-002**: USB sync script reads config.yaml and syncs one directory
- **US-003**: Cloud sync script reads config.yaml and syncs one directory to cloud
- **US-004**: Both scripts write structured log entries to shared log file

---

### Release 1: Multi-Device and Multi-Directory (riskiest assumption — config model holds for N devices/dirs)

Outcome target: Dan can add USB-B without touching USB-A config, and all directories sync to both devices.

- **US-005**: Register USB-B alongside USB-A without disrupting USB-A
- **US-006**: Multiple directories sync correctly per USB device on mount
- **US-007**: Cloud sync runs independently for each directory's cloud remote

---

### Release 2: Resilience and Observability

Outcome target: Dan can trust the system is working without actively checking, and diagnose failures in under 2 minutes when they occur.

- **US-008**: Retry logic on USB and cloud failure (30s backoff, 1 retry)
- **US-009**: Structured error logging — grep-friendly, human-readable, exit-code consistent
- **US-010**: launchd plist wiring — USB plist (WatchPaths) + cloud plist (StartInterval)

---

### Release 3: Config Migration (optional, if old config.env users exist)

Outcome target: Dan can migrate from the flat `config.env` schema to config.yaml without re-running install from scratch.

- **US-011**: Migration script converts config.env → config.yaml (technical task, enables smooth upgrade)

---

## Priority Rationale

| Priority | Release | Outcome | Rationale |
|----------|---------|---------|-----------|
| 1 | Walking Skeleton | End-to-end flow confirmed | Validates the config model split (USB vs cloud) actually works before building on top of it |
| 2 | Release 1: Multi-device | USB-B registered without disrupting USB-A | This IS the core user problem (JOB-002). Config model robustness is the riskiest assumption. |
| 3 | Release 2: Resilience | Failures detectable and recoverable | JOB-001 anxiety: "Cloud sync failing silently for weeks." Observability is what makes the guardian trustworthy. |
| 4 | Release 3: Migration | Smooth upgrade path | Lower urgency — Dan is both builder and user; he can re-run install. Deferred. |

---

## Scope Assessment Note

6 core stories (US-001 through US-006) map to the primary jobs. US-007 through US-010 are Release 2 enhancements. US-011 is deferred. All stories are 1-3 days, single bounded context each.

Scope: PASS — right-sized. No splitting required.
