# Feature Delta: multi-usb-sync

Feature ID: `multi-usb-sync`
Wave: DISCUSS (complete)
Date: 2026-05-15
Analyst: Luna (nw-product-owner)
Jobs: JOB-001 (silent-guardian), JOB-002 (multi-device-guardian)

---

## What Changed From the Existing System

The existing `sync-to-usb-and-cloud.sh` is a single script triggered by one launchd WatchPaths plist. It reads a flat `config.env` with a single USB UUID, a single local directory, and a single rclone remote. USB sync and cloud sync are coupled — cloud only runs when USB mounts.

This feature replaces that with:

| Dimension | Before | After |
|-----------|--------|-------|
| Scripts | 1 combined script | 2 independent scripts: `sync-usb.sh`, `sync-cloud.sh` |
| Config | Flat `config.env` (JOB_N_* scheme) | Structured `config.yaml` v2 (directories as first-class entries) |
| USB devices | 1 UUID hardcoded | N registered devices (UUID + label per device) |
| Directories | 1 local dir | M directories, each with its own cloud_remote and usb_devices list |
| USB trigger | WatchPaths on /Volumes | WatchPaths on /Volumes (unchanged — same mechanism) |
| Cloud trigger | Coupled to USB mount | Independent: launchd StartInterval (hourly) |
| launchd plists | 1 plist (combined) | 2 plists: usb-sync (WatchPaths) + cloud-sync (StartInterval) |

---

## Resolved Open Questions

| Q | Decision |
|---|----------|
| Q1 — Cloud sync trigger | launchd StartInterval (hourly) + manual invocation both work |
| Q2 — USB scope | Sync all registered directories always (no per-directory flag) |
| Q3 — rclone remote scoping | Per-directory (not per-USB-device). Config model: `directories[*].cloud_remote` |
| Q4 — Install flow for USB registration | [DESIGN] — outcome defined in US-005; mechanism deferred to DESIGN wave |

---

## Config Model Delta (key decision)

The config model introduces a **directory-first data structure** for cloud sync and a **device-first data structure** for USB sync. These share the same config.yaml file.

```yaml
# ~/.config/securelocal/config.yaml (v2)
schema_version: 2
log_file: ~/Library/Logs/securelocal-sync.log
rclone_bin: /usr/local/bin/rclone

directories:
  - local_path: ~/secureLocal
    cloud_remote: remote-crypt:secureLocal
    usb_devices: [UUID-A, UUID-B]

  - local_path: ~/Projects
    cloud_remote: remote-crypt:Projects
    usb_devices: [UUID-A, UUID-B]

usb_devices:
  - id: UUID-A
    label: IronKey-A (home)
  - id: UUID-B
    label: IronKey-B (office)
```

`sync-usb.sh` reads the device→dirs mapping (iterate directories, filter by `usb_devices`).
`sync-cloud.sh` reads the dirs→remote mapping (iterate directories, use `cloud_remote`).

---

## User Stories Summary

| Story | Title | Job | Walking Skeleton? | Release |
|-------|-------|-----|-------------------|---------|
| US-001 | Config YAML v2 Schema | JOB-002 | Yes | Walking Skeleton |
| US-002 | USB Sync Script — Multi-Directory | JOB-001 | Yes | Walking Skeleton |
| US-003 | Cloud Sync Script — Timer-Driven | JOB-001 | Yes | Walking Skeleton |
| US-004 | Structured Log Output | JOB-001 | Yes | Walking Skeleton |
| US-005 | Register Second USB Device | JOB-002 | No | Release 1 |
| US-006 | launchd Automation — Two Independent Plists | JOB-001 | No | Release 1 |
| US-007 | @infrastructure — Test Harness Update | infrastructure-only | No | Release 1 |

---

## Artifacts Produced (DISCUSS wave)

All in `docs/feature/multi-usb-sync/discuss/`:

| File | Purpose |
|------|---------|
| `journey-multi-usb-sync-visual.md` | ASCII journey map + emotional arc + TUI mockups + error paths |
| `journey-multi-usb-sync.yaml` | Structured journey schema with embedded Gherkin per step |
| `story-map.md` | Backbone + walking skeleton + release slices with priority rationale |
| `shared-artifacts-registry.md` | All shared artifacts with source, consumers, integration risk |
| `user-stories.md` | 7 stories (LeanUX template, elevator pitches, BDD scenarios, DoR-validated) |
| `outcome-kpis.md` | Outcome KPI table, north star, guardrails, measurement plan, hypothesis |

Supporting files:
- `docs/feature/multi-usb-sync/wave-decisions.md` (updated with Q1-Q4 resolutions)
- `docs/product/jobs.yaml` (JOB-001, JOB-002 — bootstrapped this wave)
- `docs/product/personas/builder-user.yaml` (Dan Fox — bootstrapped this wave)

---

## DoR Validation Summary

| Story | Problem clear | Persona specific | 3+ examples | UAT (3-7) | AC from UAT | Right-sized | Tech notes | Dependencies | Status |
|-------|---|---|---|---|---|---|---|---|---|
| US-001 | PASS | PASS | PASS | PASS (3) | PASS | PASS | PASS | PASS | READY |
| US-002 | PASS | PASS | PASS | PASS (4) | PASS | PASS | PASS | US-001 tracked | READY |
| US-003 | PASS | PASS | PASS | PASS (4) | PASS | PASS | PASS | US-001 tracked | READY |
| US-004 | PASS | PASS | PASS | PASS (3) | PASS | PASS | PASS | US-002, US-003 tracked | READY |
| US-005 | PASS | PASS | PASS | PASS (4) | PASS | PASS | PASS | US-001 tracked | READY |
| US-006 | PASS | PASS | PASS | PASS (4) | PASS | PASS | PASS | US-002, US-003 tracked | READY |
| US-007 | PASS | PASS | PASS | PASS (2) | PASS | PASS | PASS | US-001 through US-006 | READY |

All 7 stories pass DoR. Handoff to DESIGN wave is unblocked.

---

## JTBD Traceability

| Story | job_id | Note |
|-------|--------|------|
| US-001 | JOB-002 | Config model is the foundation for multi-device (JOB-002) |
| US-002 | JOB-001 | Silent USB backup is the primary silent-guardian outcome |
| US-003 | JOB-001 | Decoupled cloud sync closes the cloud gap — core JOB-001 outcome |
| US-004 | JOB-001 | Observability is what makes the guardian trustworthy |
| US-005 | JOB-002 | Multi-device registration is JOB-002 directly |
| US-006 | JOB-001 | launchd automation enables the "set and forget" dimension of JOB-001 |
| US-007 | infrastructure-only | Enables verification of all above; no direct user-facing behavior |

---

## Open Design Questions (for DESIGN wave)

| ID | Question | Context |
|----|----------|---------|
| DESIGN-001 | Q4: How does Dan obtain and register a USB UUID? | Auto-detect from /Volumes, manual entry, or hybrid. Outcome: UUID written correctly. Mechanism: DESIGN wave. |
| DESIGN-002 | Is config.yaml written by install.sh alone, or is there a separate `register` command? | Affects installer UX and whether registration is a subcommand or prompts within install. |
| DESIGN-003 | Should USB target directory be auto-created if missing? | `rsync` can create it; question is whether this is desired behavior or a hard error. |
| DESIGN-004 | Is StartInterval configurable (e.g. hourly vs every 30min)? | Default 3600s; Dan may want to adjust. Config field vs hardcoded. |

---

## Wave: DESIGN / [REF] DDD List

| ID | Decision | Verdict | Rationale |
|----|----------|---------|-----------|
| DDD-001 | Config schema format | YAML v2, directories-first | Human-readable; structured; replaces flat config.env. See ADR-001. |
| DDD-002 | YAML parser in bash | python3 parse-once at startup | Zero new runtime dependency; macOS system python3 has PyYAML; robust vs grep/sed. See ADR-002. |
| DDD-003 | USB registration mechanism | `install.sh add-device` subcommand | Reuses existing `select_usb_volume()` logic; minimal new code; one entrypoint. See ADR-003. |
| DDD-004 | USB target directory | Auto-create (`mkdir -p`) | Consistent with existing behaviour; first sync to fresh USB should not fail. |
| DDD-005 | StartInterval | Configurable via `sync_interval_seconds` in config.yaml (default 3600) | Config is single source of truth per DR--config-governance. |
| DDD-006 | Atomic config writes | Temp-file-then-rename pattern | Prevents partial config.yaml being read by running sync scripts. |
| DDD-007 | Script separation | Two independent scripts (`sync-usb.sh`, `sync-cloud.sh`) | Separation of concerns; independent triggers; neither script imports the other. |

---

## Wave: DESIGN / [REF] Component Decomposition

| Component | Path | Change Type | Notes |
|-----------|------|-------------|-------|
| install.sh | `bin/install.sh` | MODIFY | Add YAML config writer, 2-plist installer, `add-device` subcommand |
| sync-usb.sh | `bin/sync-usb.sh` | CREATE | Replaces USB half of sync-to-usb-and-cloud.sh |
| sync-cloud.sh | `bin/sync-cloud.sh` | CREATE | Replaces cloud half of sync-to-usb-and-cloud.sh |
| sync-to-usb-and-cloud.sh | `bin/sync-to-usb-and-cloud.sh` | DELETE | Superseded by the two new scripts |
| test-sync-script.sh | `bin/test-sync-script.sh` | MODIFY | New config format, two script targets, multi-UUID mock |
| config.yaml | `~/.config/securelocal/config.yaml` | CREATE | Schema v2; replaces config.env |
| usb-sync.plist | `~/Library/LaunchAgents/com.securelocal.usb-sync.plist` | CREATE | WatchPaths /Volumes |
| cloud-sync.plist | `~/Library/LaunchAgents/com.securelocal.cloud-sync.plist` | CREATE | StartInterval (configurable) |
| sync.plist (old) | `~/Library/LaunchAgents/com.securelocal.sync.plist` | DELETE | Removed by install.sh upgrade path |

---

## Wave: DESIGN / [REF] Driving Ports

| Port | Surface | Trigger | Handler |
|------|---------|---------|---------|
| USB mount event | launchd WatchPaths `/Volumes` | USB device plugged in | `sync-usb.sh` |
| Timer event | launchd StartInterval | Every N seconds (default 3600) | `sync-cloud.sh` |
| Manual invocation | Shell (Dan's terminal) | Direct execution | `sync-usb.sh` or `sync-cloud.sh` |
| Install / add-device | Shell (Dan's terminal) | Direct execution | `install.sh` or `install.sh add-device` |

---

## Wave: DESIGN / [REF] Driven Ports and Adapters

| Port | Adapter | External System |
|------|---------|----------------|
| Config read | `load_config()` — python3 one-liner | config.yaml on disk |
| USB UUID detection | `find_usb_by_uuid()` — wraps `diskutil info` | macOS diskutil |
| File sync (USB) | `sync_to_usb()` — wraps `rsync -avh --ignore-errors` | USB drive at /Volumes |
| File sync (cloud) | `sync_to_cloud()` — wraps `rclone sync` | rclone remote (encrypted) |
| Structured logging | Append-mode `echo` to log file | securelocal-sync.log |
| Config write | Temp-rename pattern | config.yaml on disk |
| Plist management | `launchctl load/unload` | launchd |

---

## Wave: DESIGN / [REF] Technology Choices

| Technology | Version | Rationale |
|------------|---------|-----------|
| Bash | 5 (system) | Existing codebase; macOS system shell; no new runtime |
| YAML | — (data format) | Human-readable structured config; replaces flat env file |
| python3 | System (macOS 12.3+) | YAML parsing; zero new dependency; PyYAML in stdlib |
| rsync | System | Existing; checksummed incremental sync |
| rclone | Existing dep | Existing; pre-configured encrypted remote |
| diskutil | System | Only tool that reliably surfaces Volume UUID on macOS |
| launchd | System | WatchPaths + StartInterval cover both trigger types natively |

No new runtime dependencies introduced.

---

## Wave: DESIGN / [REF] Reuse Analysis

| Existing Function | File | Overlap | Decision | Justification |
|-------------------|------|---------|----------|---------------|
| `find_usb_by_uuid()` | sync-to-usb-and-cloud.sh:43 | UUID scan logic | ADAPT | Generalise: iterate all registered UUIDs, not one global |
| `sync_to_usb()` | sync-to-usb-and-cloud.sh:58 | rsync + retry | ADAPT | Wrap in per-directory loop; parameterise paths |
| `sync_to_cloud()` | sync-to-usb-and-cloud.sh:87 | rclone + retry | ADAPT | Parameterise remote per directory; remove USB coupling |
| `log()` / `log_error()` | sync-to-usb-and-cloud.sh:27 | Logging | REPLACE | New structured format required (US-004) |
| `select_usb_volume()` | install.sh:58 | Volume detection + UUID extract | EXTEND | Core of `add-device` subcommand; add duplicate UUID check |
| `check_dependencies()` | install.sh:26 | Dependency validation | REUSE | No new system deps; add python3 check |
| `check_rclone_remote()` | install.sh:91 | Remote validation | REUSE | Unchanged contract |
| `write_config_file()` | install.sh:133 | Config write | REPLACE | Must write YAML v2 instead of config.env |
| `create_launch_agent()` | install.sh:148 | Plist installation | REPLACE | Two plists + old plist removal |
| Test harness framework | test-sync-script.sh:1 | Test scaffold | EXTEND | Config format + script targets change |
| Mock factories (diskutil) | test-sync-script.sh:137 | diskutil mock | EXTEND | Add multi-UUID response capability |

---

## Wave: DESIGN / [REF] Open Questions

| ID | Question | Disposition |
|----|----------|-------------|
| OQ-001 | Log rotation | Out of scope; document in README as future concern (macOS newsyslog) |
| OQ-002 | python3 dependency check | Trivial; crafter adds to `check_dependencies()` during implementation |
| OQ-003 | `sync_interval_seconds` plist regeneration | Crafter documents in `install.sh` help output — plist must be reloaded after config change |
