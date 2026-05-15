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
