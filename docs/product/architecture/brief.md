# Application Architecture — mac-secure-sync

**Feature:** multi-usb-sync
**Wave:** DESIGN
**Date:** 2026-05-15
**Architect:** Morgan (nw-solution-architect)

---

## System Context

mac-secure-sync is a personal macOS automation tool that silently backs up designated local directories to one or more registered USB drives (when mounted) and to an encrypted cloud remote (on a timer). There is no server, no network service, and no user-facing UI — the system is entirely local to one macOS machine, orchestrated by launchd.

**External actors and systems:**

| Actor / System | Role |
|----------------|------|
| Dan (builder-user) | Runs install.sh, registers USB devices, monitors log |
| USB drives (IronKey or equivalent) | Driven: rsync target, identified by Volume UUID |
| rclone remote (encrypted) | Driven: cloud sync target, accessed via rclone binary |
| launchd | Orchestrator: triggers sync scripts on events and timers |
| macOS /Volumes | Driven: mount point filesystem, watched by WatchPaths |
| python3 (system) | Driven: YAML parsing at startup; zero new dependency |

---

## C4 Diagrams

See `docs/product/architecture/c4-diagrams.md` for the full Mermaid source.

---

## Architectural Style

**Pure Core / Imperative Shell** — Bash implementation.

- Pure core: `load_config()` is a pure function. Given a config.yaml path, it emits key=value pairs and has no side effects. All sync logic receives its parameters as arguments — no shared mutable globals between sync scripts.
- Imperative shell: launchd invocations, rsync calls, rclone calls, diskutil reads, log writes, and plist writes are isolated to the top-level main() and adapter functions in each script.
- Dependency inversion: both sync scripts depend on config variables (the port contract), not on the config file format. The `load_config()` function is the adapter between YAML-on-disk and bash variables.

This is the correct default for a single-operator Bash tool. Microservices, event brokers, and service meshes are explicitly rejected (team of 1, no independent deployment requirement, no network boundary).

---

## Component Map

```
install.sh
  ├── check_dependencies()         -- REUSE unchanged
  ├── check_filevault()            -- REUSE unchanged
  ├── select_usb_volume()          -- EXTEND: core of add-device subcommand
  ├── check_rclone_remote()        -- REUSE unchanged
  ├── backup_rclone_config()       -- REUSE unchanged
  ├── write_config_file()          -- REPLACE: writes config.yaml v2 (was config.env)
  ├── create_launch_agent()        -- REPLACE: writes 2 plists, removes old plist
  ├── cmd_add_device()             -- EXTEND select_usb_volume + duplicate UUID check
  │                                   + atomic temp-rename write to config.yaml
  ├── cmd_remove_device()          -- NEW (usb-device-lifecycle, US-101): --label|--uuid
  │                                   match, removes from usb_devices[] + every
  │                                   directories[*].usb_devices, atomic temp-rename write
  │                                   (mirrors cmd_add_device's ADR-003 pattern in reverse)
  ├── cmd_list_devices()           -- NEW (usb-device-lifecycle, US-102): read-only,
  │                                   cross-references usb_devices[] against live
  │                                   /Volumes state via bin/lib/usb-common.sh (ADR-004)
  └── require_config_file()        -- NEW (usb-device-lifecycle, Phase 3 aggregate refactor,
                                       not anticipated in DESIGN): replaces three near-identical
                                       config-existence checks across add/remove/list-devices

bin/lib/usb-common.sh  (new, usb-device-lifecycle, ADR-004)
  ├── find_usb_by_uuid()           -- MOVED from sync-usb.sh: pure query function,
  │                                   sourced by both install.sh and sync-usb.sh
  └── get_volume_uuid()            -- MOVED from sync-usb.sh (Phase 3 aggregate refactor;
                                       ADR-004's 02-02 extraction step missed this
                                       byte-identical duplicate, completed in cleanup)

sync-usb.sh  (new, replaces sync-to-usb-and-cloud.sh USB half)
  ├── load_config()                -- NEW: python3 parse-once, emits key=value pairs
  ├── find_usb_by_uuid()           -- MOVED to bin/lib/usb-common.sh (ADR-004); sourced,
  │                                   not redefined. Behavior unchanged.
  └── sync_to_usb()               -- ADAPT: wrapped in per-directory loop

sync-cloud.sh  (new, replaces sync-to-usb-and-cloud.sh cloud half)
  ├── load_config()                -- SHARED function (sourced or duplicated)
  └── sync_to_cloud()             -- ADAPT: parameterised remote per directory

config.yaml  (~/.config/securelocal/config.yaml)
  -- Data artifact. Written by install.sh. Read by sync-usb.sh and sync-cloud.sh.

com.securelocal.usb-sync.plist
  -- WatchPaths /Volumes → invokes sync-usb.sh

com.securelocal.cloud-sync.plist
  -- StartInterval (configurable, default 3600s) → invokes sync-cloud.sh

~/Library/Logs/securelocal-sync.log
  -- Append-only structured log. Written by both sync scripts.
```

---

## Data Flow

### USB Sync (mount event)

```
USB plugged in
  → launchd WatchPaths /Volumes fires
    → sync-usb.sh invoked
      → load_config() [python3 one-liner] parses config.yaml
        → bash variables populated (directories[], usb_devices[])
          → find_usb_by_uuid() iterates /Volumes, matches registered UUIDs
            → for each mounted registered UUID:
                for each directory with that UUID in usb_devices:
                  mkdir -p USB_TARGET
                  sync_to_usb(local_path, usb_target) [rsync with retry]
                    → log structured entry
```

### Cloud Sync (timer event)

```
launchd StartInterval fires (default 3600s)
  → sync-cloud.sh invoked
    → load_config() parses config.yaml
      → bash variables populated
        → for each directory:
            sync_to_cloud(local_path, cloud_remote) [rclone sync with retry]
              → log structured entry
```

### USB Registration (manual)

```
Dan runs: install.sh add-device
  → select_usb_volume() [reused] lists mounted volumes, prompts for label
    → UUID extracted via diskutil
      → duplicate UUID check against existing config.yaml usb_devices[]
        → if not duplicate:
            atomic write: config.yaml written to .config.yaml.tmp, then mv
              → log confirmation
```

---

## Technology Stack

| Component | Technology | License | Rationale |
|-----------|-----------|---------|-----------|
| Shell scripts | Bash 5 (system) | GPL-3 (system) | Existing codebase; macOS system shell; no new runtime |
| Config format | YAML | N/A (data format) | Human-readable, structured; replaces flat env file |
| YAML parser | python3 (system) | PSF-2 | Already present on macOS; zero new dependency; parse-once at startup |
| USB detection | diskutil (system) | N/A (system binary) | macOS native; only tool that reliably surfaces Volume UUID |
| File sync | rsync (system) | GPL-3 (system) | Existing; checksummed, incremental |
| Cloud sync | rclone (existing dep) | MIT | Existing; pre-configured remote |
| Process orchestration | launchd (system) | N/A (system) | macOS native; WatchPaths + StartInterval cover both trigger types |
| Dependency enforcement | shellcheck (CI lint) | GPL-3 | Already present; extend to cover new scripts |
| Architecture enforcement | dependency-cruiser | MIT | N/A for shell — enforcement is structural (function naming convention + shellcheck rules) |

No proprietary dependencies. No new runtime dependencies introduced.

---

## Reuse Analysis

| Existing function | Disposition | Rationale |
|------------------|-------------|-----------|
| `find_usb_by_uuid()` | ADAPT into sync-usb.sh | Generalise: iterate all registered UUIDs, not a single global |
| `sync_to_usb()` | ADAPT into sync-usb.sh | Wrap in per-directory loop; parameterise local_path and usb_target |
| `sync_to_cloud()` | ADAPT into sync-cloud.sh | Parameterise remote per directory; remove USB coupling |
| `log()` / `log_error()` | REPLACE | New structured format: `[ISO8601] [LEVEL] [SCRIPT] message` |
| `select_usb_volume()` | EXTEND | Core of `add-device` subcommand; add duplicate UUID detection |
| `check_dependencies()` | REUSE unchanged | No new system deps; list may grow to include python3 check |
| `check_rclone_remote()` | REUSE unchanged | Called during initial install; unchanged contract |
| `write_config_file()` | REPLACE | YAML v2 replaces config.env write |
| `create_launch_agent()` | REPLACE | Two plists replace one; old plist removed |
| Test harness framework | EXTEND | Config format + script targets change; mock factories need updating |
| Mock factories (diskutil) | EXTEND | diskutil mock needs multi-UUID response capability |

### usb-device-lifecycle (2026-08-24)

| Existing component | Disposition | Rationale |
|------------------|-------------|-----------|
| `find_usb_by_uuid()` (sync-usb.sh) | CREATE NEW location (`bin/lib/usb-common.sh`), MOVE not duplicate | `list-devices` needs the identical UUID-to-mount-path resolution `sync-usb.sh` already owns; shared-artifacts-registry flags independent re-implementation as HIGH integration risk. See ADR-004. |
| `cmd_add_device()`'s atomic-write pattern | EXTEND (mirrored, not shared code) | `cmd_remove_device()` follows the same temp-rename structure (ADR-003) applied to deletion; no shared write function extracted — each subcommand's config mutation is small enough that mirroring the pattern is lower-risk than introducing a shared read-modify-write helper this early |
| `load_config()` (sync-usb.sh / sync-cloud.sh) | REUSE unchanged, NOT extracted | Already intentionally duplicated per script (independence paradigm, ADR-002 precedent). `cmd_list_devices()` uses its own minimal read-only python3 block, following `cmd_add_device()`'s existing per-subcommand convention rather than reaching into the sync scripts' duplication pattern. |
| `tests/acceptance/multi-usb-sync/helpers.sh` mock factories (`create_mock_diskutil_multi`, `register_mock_volume`) | REUSE unchanged | Multi-UUID diskutil mocking already supports the fixtures both new commands need; no new mock factory required |
| Test harness location | CREATE NEW directory `tests/acceptance/usb-device-lifecycle/` | Per-feature test directory convention (established by `tests/acceptance/multi-usb-sync/`); sources the existing `helpers.sh` rather than duplicating it |

No component in this feature is a from-scratch build — every new piece either moves, mirrors, or directly reuses an existing, accepted pattern.

---

## Integration Patterns

### Config Loading Port Contract

`load_config(config_path)` — pure function (no side effects):
- Input: path to config.yaml
- Output: newline-separated `KEY=value` pairs on stdout (sourced by caller)
- Error: exits non-zero with structured message on stderr if file missing or unparseable
- Implementation: single python3 invocation — `python3 -c "import yaml, sys; ..."`
- Called once at script startup; result sourced into shell variables

### USB Detection Port Contract

`find_usb_by_uuid(uuid)` — query function:
- Input: single UUID string
- Output: mount path on stdout if found, empty if not
- Error: returns 1 if not found
- Wraps `diskutil info <volume>` for each entry in /Volumes

### Sync Port Contract (USB)

`sync_to_usb(local_path, usb_target)` — imperative function:
- Input: source directory path, destination directory path
- Output: exit 0 on success
- Error: exit 1 after MAX_RETRIES exhausted
- Wraps `rsync -avh --ignore-errors`

### Sync Port Contract (Cloud)

`sync_to_cloud(local_path, cloud_remote)` — imperative function:
- Input: source directory path, rclone remote string
- Output: exit 0 on success
- Error: exit 2 after MAX_RETRIES exhausted
- Wraps `rclone sync`

### Atomic Config Write Pattern

All writes to config.yaml use temp-rename:
1. Write to `config.yaml.tmp` in the same directory
2. `mv config.yaml.tmp config.yaml` (atomic on same filesystem)
3. Never leave a partial config.yaml visible to running scripts

### USB Matching Library Contract (usb-device-lifecycle, ADR-004)

`bin/lib/usb-common.sh : find_usb_by_uuid(uuid, volumes_base)` — pure query function, unchanged signature from its prior inline definition in `sync-usb.sh`:
- Input: UUID string, volumes base path (e.g. `/Volumes`)
- Output: mount path on stdout if found, empty otherwise
- No side effects on `source`; safe for any script to source without triggering execution
- Consumers: `sync-usb.sh` (existing), `install.sh:cmd_list_devices()` (new)

### remove-device Port Contract (usb-device-lifecycle, US-101)

`install.sh remove-device --label <name>|--uuid <uuid>`:
- Input: exactly one of `--label` or `--uuid` (mutually exclusive)
- On match: entry removed from `usb_devices[]`; UUID stripped from every `directories[*].usb_devices` list; atomic temp-rename write (ADR-003 pattern); all other entries byte-for-byte unchanged
- On no match: exit 2, `config.yaml` completely unmodified, error names `list-devices` as the recovery step
- On config read/schema error: exit 4 (consistent with `sync-usb.sh`/`sync-cloud.sh`/`add-device` convention)
- Structural constraint: the new-config computation must be a step separable from the write step, so a future tombstone/audit-log write (deferred US-103) can be inserted between them without restructuring the function (OQ-004)

### list-devices Port Contract (usb-device-lifecycle, US-102)

`install.sh list-devices`:
- Read-only: never writes to `config.yaml`
- Reads `usb_devices[]`; for each entry, resolves live mount state via `find_usb_by_uuid()` (ADR-004) — never an independent `/Volumes` scan
- Empty registry: exit 0, inviting message naming `add-device` as the next action
- Config read/schema error: exit 4

---

## Quality Attribute Strategies

### Reliability

- Retry logic (MAX_RETRIES=2, 30s sleep) on both rsync and rclone — inherited from existing script
- USB sync and cloud sync are independent processes; USB sync failure does not block cloud sync
- Atomic config writes prevent corrupt config from reaching running scripts
- Duplicate UUID detection in `add-device` prevents silent misconfiguration

### Observability

- Structured log format: `[ISO8601] [LEVEL] [SCRIPT] message` — both scripts write to same log file
- Exit codes preserved and documented: 0=success, 1=USB fail, 2=cloud fail, 3=both fail, 4=config error
- Log rotation: out of scope; flagged for future concern (logrotate or launchd StandardOutPath rotation)

### Maintainability

- Scripts are small and single-responsibility (USB sync / cloud sync / install)
- `load_config()` is the only YAML-aware function; format changes require editing one function
- Reuse of existing functions reduces surface area of change
- shellcheck enforced in CI (existing gate); extend to new scripts

### Security

- FileVault check preserved in install.sh (inherited)
- Config file at `~/.config/securelocal/config.yaml` — user-owned, not world-readable (install.sh sets chmod 600)
- No secrets in plist files; config path passed as environment variable
- rclone remote credentials managed by rclone config (existing security boundary)

### Portability

- No Homebrew-only dependencies introduced; all new functionality uses macOS system tools
- python3 assumed present (macOS 12.3+ ships python3); `check_dependencies()` extended to verify

---

## Deployment Architecture

Single macOS machine. No containers, no network services.

```
~/.config/securelocal/
  config.yaml              -- written by install.sh; read by sync scripts

~/secureLocal/bin/
  install.sh               -- interactive setup + add-device subcommand
  sync-usb.sh              -- launchd WatchPaths target
  sync-cloud.sh            -- launchd StartInterval target

~/Library/LaunchAgents/
  com.securelocal.usb-sync.plist    -- WatchPaths /Volumes
  com.securelocal.cloud-sync.plist  -- StartInterval (default 3600s)

~/Library/Logs/
  securelocal-sync.log     -- append-only; both scripts write here
```

---

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| ADR-001 | Config Schema v2 (YAML, directories-first) | Accepted |
| ADR-002 | YAML Parser: python3 parse-once strategy | Accepted |
| ADR-003 | USB Registration: install.sh add-device subcommand | Accepted |
| ADR-004 | Shared USB Matching Library: bin/lib/usb-common.sh | Accepted |

---

## Open Questions (flagged for DISTILL / BUILD)

| ID | Question | Disposition |
|----|----------|-------------|
| OQ-001 | Log rotation | Out of scope for this feature; flag in README as future concern |
| OQ-002 | `check_dependencies()` — add python3 to dependency list? | Yes, trivial; crafter adds during implementation |
| OQ-003 | `sync_interval_seconds` in config.yaml — plist must be regenerated on change | Crafter documents this in install.sh help output |
| OQ-004 | `cmd_remove_device()`'s config mutation must compute the new config dict as a step separable from the atomic-write step (not one undifferentiated block) | Deferred US-103 (orphaned-data cleanup on stale reinsert) would need to hook a tombstone/audit-log write between "compute new config" and "write" without restructuring `cmd_remove_device()`. Not building US-103 now — this is a structural constraint on the new function's shape, not new scope. Crafter honors during GREEN/REFACTOR. |
