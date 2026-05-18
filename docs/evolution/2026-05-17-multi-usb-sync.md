# Evolution Record: multi-usb-sync

Date: 2026-05-17
Feature ID: `multi-usb-sync`
Branch: `feat/muliple-usb-config`
Waves: DISCUSS ✓ | DESIGN ✓ | DISTILL ✓ | DELIVER ✓
Delivery: 38/38 acceptance tests GREEN

---

## Feature Summary and Business Context

### Jobs to Be Done

**JOB-001 — silent-guardian**: As Dan, I want my files to back up silently and automatically whenever I plug in a USB drive and on a schedule to the cloud, so I never have to remember to back up.

**JOB-002 — multi-device-guardian**: As Dan, I want to register multiple USB drives and have all of them sync the same directories when plugged in, so that I can have separate drives for home and office.

### What Changed

The existing `sync-to-usb-and-cloud.sh` was a single coupled script: one UUID, one local directory, one rclone remote, USB mount triggering both USB and cloud sync. This feature replaces it with a separated, configurable system.

| Dimension | Before | After |
|-----------|--------|-------|
| Scripts | 1 combined | 2 independent: `sync-usb.sh`, `sync-cloud.sh` |
| Config | Flat `config.env` (JOB_N_* scheme) | Structured `config.yaml` v2 (directories-first) |
| USB devices | 1 UUID hardcoded | N registered devices (UUID + label) |
| Directories | 1 local directory | M directories, each with `cloud_remote` and `usb_devices` list |
| Cloud trigger | Coupled to USB mount | Independent: launchd `StartInterval` (default hourly) |
| launchd plists | 1 plist (combined) | 2 plists: `usb-sync` (WatchPaths) + `cloud-sync` (StartInterval) |

---

## Key Decisions

### Design Decisions (DDD series)

| ID | Decision | Outcome |
|----|----------|---------|
| DDD-001 | Config schema format | YAML v2, directories-first. Human-readable; structured; replaces flat `config.env`. |
| DDD-002 | YAML parser in Bash | `python3` parse-once at startup. Zero new runtime dependency; macOS system `python3` has PyYAML; robust vs grep/sed. |
| DDD-003 | USB registration mechanism | `install.sh add-device` subcommand. Reuses `select_usb_volume()` logic; minimal new code; single entrypoint. |
| DDD-004 | USB target directory | Auto-create (`mkdir -p`). Consistent with existing behaviour; first sync to fresh USB should not fail. |
| DDD-005 | StartInterval | Configurable via `sync_interval_seconds` in `config.yaml` (default 3600). Config as single source of truth. |
| DDD-006 | Atomic config writes | Temp-file-then-rename pattern. Prevents partial `config.yaml` being read by running sync scripts. |
| DDD-007 | Script separation | Two fully independent scripts. Neither script imports the other. Independent triggers; independent failure domains. |

### Architecture Decision Records

| ADR | Title | Permanent Location |
|-----|-------|--------------------|
| ADR-001 | Config Schema v2 | `docs/product/architecture/adr-001-config-schema-v2.md` |
| ADR-002 | YAML Parser (python3 parse-once) | `docs/product/architecture/adr-002-yaml-parser.md` |
| ADR-003 | USB Registration Mechanism (`add-device`) | `docs/product/architecture/adr-003-usb-registration-mechanism.md` |

ADRs were created in `docs/product/architecture/` during DESIGN wave — this is the permanent SSOT for architecture decisions in this project. No migration needed.

### DISCUSS Wave Resolutions (Q1–Q4)

| Q | Question | Decision |
|---|----------|----------|
| Q1 | Cloud sync trigger | launchd `StartInterval` (default hourly) + manual invocation both work |
| Q2 | USB sync scope | Sync all registered directories always; no per-directory enabled flag |
| Q3 | rclone remote scoping | Per-directory (`directories[*].cloud_remote`), not per-USB-device |
| Q4 | USB registration mechanism | `install.sh add-device` subcommand (resolved in DESIGN) |

---

## Steps Completed

Three delivery steps executed via Outside-In TDD (PREPARE → RED_ACCEPTANCE → RED_UNIT → GREEN → COMMIT).

| Step | Name | Tests | Completed |
|------|------|-------|-----------|
| 01-01 | Implement `sync-usb.sh` | 19 GREEN | 2026-05-17T19:57:36Z |
| 01-02 | Implement `sync-cloud.sh` | +13 = 32 GREEN | 2026-05-17T20:04:46Z |
| 02-01 | Extend `install.sh` | +6 = 38 GREEN | 2026-05-17T20:25:07Z |

**Total: 38/38 acceptance tests GREEN.**

### Files Modified (Production)

- `bin/sync-usb.sh` — replaced RED scaffold; full implementation (`load_config`, `find_usb_by_uuid`, `sync_to_usb`, structured logging, exit codes 0/1/4)
- `bin/sync-cloud.sh` — replaced RED scaffold; full implementation (`load_config` duplicated per DDD-007, `sync_to_cloud`, structured logging, exit codes 0/2/4)
- `bin/install.sh` — extended; `write_config_file` (YAML v2 atomic write), `create_launch_agent` (2 plists + old plist removal), `add-device` subcommand, `--non-interactive` flag

### Files Modified (Tests)

- `tests/acceptance/multi-usb-sync/run-tests.sh` — all 38 test functions enabled

### Definition of Done — All Passed

| Item | Status |
|------|--------|
| All AC testable and verified | PASS — 38 tests GREEN |
| Walking skeleton end-to-end | PASS — config.yaml v2 + sync-usb.sh + sync-cloud.sh |
| No `__SCAFFOLD__` markers in production | PASS |
| Structured log grep-friendly | PASS — `ISO8601 LEVEL SCRIPT DIR MSG` format |
| Exit codes consistent | PASS — 0/1/2/4 per AC |
| Config atomic writes | PASS — temp-rename in `add-device` |
| Scripts independent (no cross-import) | PASS — `sync-cloud.sh` has no USB logic |

---

## Lessons Learned

### Spike Learnings Validated

The feature proceeded without a DISCOVER or DIVERGE wave, relying on prior spike learnings. These were confirmed as correct by DELIVER:

1. **Separation of concerns was the right call.** Making USB sync and cloud sync independent scripts with independent launchd triggers eliminated coupling bugs entirely. The two scripts failed independently in tests, making error diagnosis straightforward. DDD-007 was never revisited.

2. **Device-first config model scaled cleanly.** The `directories[*].usb_devices` array mapping allowed multi-UUID iteration without duplicating directory config. The same config serves both scripts from different perspectives (device→dirs for USB, dirs→remote for cloud) with no ambiguity.

3. **`python3` parse-once for YAML (ADR-002) avoided a class of Bash parsing bugs.** The spike identified that `grep`/`sed` YAML parsing in Bash is fragile. The `python3` one-liner at startup emitting `KEY=value` pairs eliminated an entire failure mode. Zero new runtime dependency (macOS system `python3` since 12.3).

### Separation of Concerns Discovery

The walking skeleton design (WD-DISTILL-001, Strategy C — Real local) revealed that the `load_config()` function is the critical first dependency for all other behaviour. The sequence: implement `load_config()` → walking skeleton GREEN → all other tests unblocked. This informed the step ordering in the roadmap and should inform any future Bash tool that reads structured config.

### YAML Parsing Approach

The `python3` one-liner approach (`python3 -c "import yaml, sys; ..."`) emitting flat `KEY=value` pairs that Bash `source`s at startup is the pattern. It is:
- Testable: tests write real `config.yaml` files; the parser either passes or fails on them
- Debuggable: the emitted variables are inspectable with `set -x`
- Extensible: adding a config field requires one change (the python3 one-liner) and the consuming Bash variables

The schema version guard (`schema_version == 2`, exit 4 on mismatch) is the critical safety net — it prevents old `config.env` files from silently producing wrong behaviour.

### Test Harness Pattern

The mock-binary-in-temp-PATH pattern (inherited from `bin/test-sync-script.sh`) proved highly effective for Bash script testing. Mock `diskutil`, `rsync`, `rclone`, and `launchctl` binaries in a `mktemp -d` temp directory capture call arguments and control exit codes without touching real hardware or cloud services. Key insight: **mock the binary, not the function** — this tests the actual shell `command` invocations that production code makes.

The `SECURELOCAL_VOLUMES_BASE` environment variable as a test seam (WD-DISTILL-005, Finding 2) is the pattern for isolating filesystem scan paths in tests. Any future script that scans `/Volumes` or other system paths should honour an override env var.

### Deferred Items (Not Technical Debt)

- `sync-to-usb-and-cloud.sh` — superseded but not deleted. No active consumers. Removal deferred (low risk, no urgency).
- Log rotation — documented as future concern (macOS `newsyslog`). Out of scope.
- Mutation testing — on-demand per project rigor profile. Not run as merge gate.

---

## Permanent Artifacts

### Architecture (already permanent)

| Artifact | Location |
|----------|----------|
| ADR-001: Config Schema v2 | `docs/product/architecture/adr-001-config-schema-v2.md` |
| ADR-002: YAML Parser | `docs/product/architecture/adr-002-yaml-parser.md` |
| ADR-003: USB Registration | `docs/product/architecture/adr-003-usb-registration-mechanism.md` |
| Architecture brief | `docs/product/architecture/brief.md` |
| C4 diagrams | `docs/product/architecture/c4-diagrams.md` |

### UX Journeys (migrated this close)

| Artifact | Location |
|----------|----------|
| Journey map (structured YAML) | `docs/ux/multi-usb-sync/journey-multi-usb-sync.yaml` |
| Journey map (visual / ASCII) | `docs/ux/multi-usb-sync/journey-multi-usb-sync-visual.md` |

### Acceptance Tests (already permanent)

| Artifact | Location |
|----------|----------|
| Feature files (8) + test runner | `tests/acceptance/multi-usb-sync/` |

### Feature Workspace (preserved as history)

| Artifact | Location |
|----------|----------|
| All wave artifacts | `docs/feature/multi-usb-sync/` |

---

## Outcome KPI Baseline

`docs/feature/multi-usb-sync/discuss/outcome-kpis.md` defines the outcome KPIs. No automated KPI instrumentation was implemented this wave (no `@kpi` scenarios — soft gate applied per WD-DISTILL-005 Finding 4). Baseline measurement is manual:

- USB sync success rate: verified by log file (`~/Library/Logs/securelocal-sync.log`) — grep `INFO sync-usb`
- Cloud sync success rate: grep `INFO sync-cloud`
- Config error rate: grep `ERROR` + exit code 4 occurrences
- Multi-device coverage: both `IronKey-A` and `IronKey-B` UUIDs register and sync successfully
