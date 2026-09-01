# Feature Delta: usb-device-lifecycle

Extends: `multi-usb-sync` (shipped 2026-05-17, `docs/evolution/2026-05-17-multi-usb-sync.md`)
Wave: DISCUSS complete

## What's Changing

`multi-usb-sync` shipped `install.sh add-device` (register a USB device into `config.yaml` v2's `usb_devices[]`) with no inverse or enumeration operation — devices only ever accreted. This feature adds the missing lifecycle operations, surfaced from real use after shipping.

| Dimension | Before (multi-usb-sync) | After (usb-device-lifecycle) |
|---|---|---|
| Register a device | `install.sh add-device --volume <path> --label <name>` | Unchanged |
| Remove a device | Not supported — manual YAML editing only | `install.sh remove-device --label <name>\|--uuid <uuid>` |
| Enumerate devices | Not supported — read `config.yaml` directly | `install.sh list-devices` (adds live mount state, unavailable from the static file) |
| Check last-sync status | Log-grep (US-004) | Unchanged — evaluated and explicitly deferred, see below |

## New Job

**JOB-003 — confident-decommissioner** minted in `docs/product/jobs.yaml`. Distinct from JOB-002 (multi-device-guardian, which is specifically about *adding* devices safely): JOB-003 covers the inverse trigger (loss/retirement) and inverse anxiety (accidentally corrupting *other* devices while removing *one*, or targeting the wrong device with no physical drive present to check).

## Resolved Open Question: list-devices as a precursor to remove-device?

**No** — `list-devices` is a high-value companion, not a hard structural precursor. `config.yaml` is already an established human-read surface (ADR-001: "Dan edits it directly"), and labels are Dan's own human-chosen strings — `remove-device` functions standalone. `list-devices` earns its place by providing live mount state, which the static config file cannot show regardless. Both ship in the same release; `remove-device` is prioritized first as the user-named highest-value story. Full reasoning: `docs/feature/usb-device-lifecycle/discuss/wave-decisions.md`.

## Deferred: Dedicated Status Command

Evaluated and explicitly deferred, not silently dropped. JOB-001's outcome statement "maximize confidence that the last sync completed successfully" is already served by US-004's structured log format. No new story created — revisit only if log-grep demonstrably stops being sufficient in practice.

## Architecture Continuity

No new ADRs required this feature — both new subcommands are siblings to `add-device` within `install.sh`, reusing:
- The atomic temp-rename config write pattern (ADR-003)
- The `find_usb_by_uuid()` UUID-matching convention from `sync-usb.sh` (reused, not reimplemented, for `list-devices`' mount-state lookup)
- The existing exit-code convention (0/2/4; 1/3 remain reserved for sync-usb.sh/sync-cloud.sh partial-failure semantics)

## DISCUSS Wave Outputs

| Artifact | Location |
|---|---|
| Wave decisions (JTBD grounding, scope gate, dependency resolution) | `docs/feature/usb-device-lifecycle/discuss/wave-decisions.md` |
| Journey (visual) | `docs/feature/usb-device-lifecycle/discuss/journey-usb-device-lifecycle-visual.md` |
| Journey (structured, Gherkin embedded) | `docs/feature/usb-device-lifecycle/discuss/journey-usb-device-lifecycle.yaml` |
| Shared artifacts registry | `docs/feature/usb-device-lifecycle/discuss/shared-artifacts-registry.md` |
| Story map | `docs/feature/usb-device-lifecycle/discuss/story-map.md` |
| User stories (US-101, US-102) | `docs/feature/usb-device-lifecycle/discuss/user-stories.md` |
| Outcome KPIs | `docs/feature/usb-device-lifecycle/discuss/outcome-kpis.md` |

## Next Wave

DESIGN (solution-architect): confirm `cmd_remove_device()` and `cmd_list_devices()` placement within `install.sh`, confirm UUID-matching reuse mechanism with `sync-usb.sh`, no new ADRs anticipated but architect should confirm.

---

## DESIGN Wave (2026-08-24, Morgan/nw-solution-architect)

Scope: Application/components (same-shape extension of an already-designed CLI surface). Mode: Propose.

### Decision Point Resolved: 1 new ADR (feature-delta.md's "no new ADRs anticipated" partially revised)

The DISCUSS wave anticipated no new ADRs. One was warranted: **how does `install.sh` (new `list-devices`) obtain live mount state without reimplementing `sync-usb.sh`'s `find_usb_by_uuid()`?** This is a genuine cross-container reuse decision with 3 real alternatives (extract to shared lib / shell out to sync-usb.sh in query mode / duplicate) — not a mechanical application of an existing ADR. See **ADR-004** (`docs/product/architecture/adr-004-shared-usb-matching-library.md`): extract `find_usb_by_uuid()` to `bin/lib/usb-common.sh`, sourced by both `install.sh` and `sync-usb.sh`. `load_config()` is explicitly NOT extracted — it stays duplicated per script per the existing ADR-002 precedent and the project's sync-script-independence paradigm.

`cmd_remove_device()`'s atomic write is not a new ADR — it is ADR-003's pattern applied to deletion, confirmed as sufficient. One structural constraint added (OQ-004 in `brief.md`): the config mutation must be computed as a step separable from the atomic-write step, so the deferred US-103 (orphaned-data cleanup) could later insert a tombstone/audit-log write without restructuring the function. This does not build US-103 — it keeps the door open per the steer's explicit instruction.

### Component Decomposition

- `install.sh:cmd_remove_device()` (NEW) — sibling to `cmd_add_device()`, same flag-parsing and atomic-write conventions (ADR-003)
- `install.sh:cmd_list_devices()` (NEW) — read-only, sources `bin/lib/usb-common.sh`
- `bin/lib/usb-common.sh` (NEW) — `find_usb_by_uuid()` moved from `sync-usb.sh` (ADR-004)
- `sync-usb.sh` — sources the library instead of defining `find_usb_by_uuid()` inline; no behavior change

### Reuse Analysis Verdicts

See `docs/product/architecture/brief.md` § Reuse Analysis → "usb-device-lifecycle (2026-08-24)" subsection for the full table. Summary: every new piece MOVES, MIRRORS, or REUSES an existing accepted pattern — no from-scratch component.

### Outcome Collision Check

Skipped: `docs/product/outcomes/` does not exist in this repo — no outcomes registry to check against.

### C4 Diagrams

L1/L2 unchanged in topology (confirmed feature-delta's prediction); `install.sh` container description updated to name all 3 subcommands. New L3 Component diagram added to `docs/product/architecture/c4-diagrams.md` for the `install.sh` subsystem, showing subcommand dispatch and the `usb-common.sh` shared-library relationship to both `install.sh` and `sync-usb.sh`.

### Gate Status

DoR: both stories PASSED (DISCUSS). Reuse Analysis: complete, hard gate passed. C4: L1+L2 confirmed unchanged, L3 added for the reuse-relevant subsystem. ADR: 1 new (ADR-004), 3 existing confirmed unchanged. External integrations: none (no third-party APIs in this feature — diskutil/python3/YAML are all existing system-tool integrations already covered by ADR-002/003, no new contract-testing surface). Peer review: pending `nw-solution-architect-reviewer` invocation.

---

## DISTILL Wave (2026-08-26, Quinn/nw-acceptance-designer)

### Prior Wave Consultation

Read: `docs/product/architecture/brief.md`, ADR-001..004, this file's DISCUSS+DESIGN sections, `discuss/user-stories.md` (US-101 full AC + 5 UAT scenarios, US-102 full AC + 4 UAT scenarios), `discuss/story-map.md`, `discuss/wave-decisions.md`, `discuss/outcome-kpis.md`, `discuss/shared-artifacts-registry.md`, `design/wave-decisions.md`, `bin/install.sh`, `bin/sync-usb.sh`, `tests/acceptance/multi-usb-sync/{helpers.sh,run-tests.sh,device-registration.feature}`. No contradictions found across waves.

- No `docs/feature/usb-device-lifecycle/devops/` — graceful degradation, default env matrix (clean install / with-existing-devices) applied.
- No `docs/product/journeys/` or `kpi-contracts.yaml` in this repo — graceful degradation, proceeded without.
- `outcome-kpis.md` explicitly states no `@kpi` scenarios are planned this wave (personal single-operator tool, KPI 3 is self-assessment) — honored, no `@kpi` tags used.

### Test Placement Decision

**New directory `tests/acceptance/usb-device-lifecycle/`**, sourcing `tests/acceptance/multi-usb-sync/helpers.sh` unchanged — not extending the `multi-usb-sync` suite directly. Rationale: DESIGN's Reuse Analysis explicitly verdicts the mock factories (`create_mock_diskutil_multi`, `register_mock_volume`) as "REUSE unchanged" and separately verdicts "Test harness location: CREATE NEW directory `tests/acceptance/usb-device-lifecycle/`" — this is a DESIGN decision, not a DISTILL judgment call. It also matches this project's own established precedent: `usb-device-lifecycle` already has its own `docs/feature/` directory distinct from `multi-usb-sync`'s, so the test tree mirrors the docs tree (directory-per-feature, both docs and tests).

Files added:
- `tests/acceptance/usb-device-lifecycle/remove-device.feature`
- `tests/acceptance/usb-device-lifecycle/list-devices.feature`
- `tests/acceptance/usb-device-lifecycle/run-tests.sh` (sources `../multi-usb-sync/helpers.sh`; adds only feature-local fixtures — a 3-device config factory, a lone-directory-device config factory, an empty-registry config factory, an erroring-diskutil mock, and a byte-for-byte device-entry comparison helper — none of which duplicate anything in the reused `helpers.sh`)

### Scenario List

**`remove-device.feature` (@US-101) — 11 scenarios:**

| Scenario | Tags |
|---|---|
| Removing a device by label leaves other devices unchanged | `@walking_skeleton @real-io @driving_port` |
| Removing a device strips its UUID from every directory mapping | `@driving_port` |
| Removing a device by UUID works identically to removing by label | `@driving_port` |
| Removing the only device mapped to a directory leaves an empty list, not an error | `@boundary @driving_port` |
| Attempting to remove an unregistered label leaves config.yaml untouched | `@error-path @driving_port` |
| Attempting to remove an unregistered UUID leaves config.yaml untouched | `@error-path @driving_port` |
| remove-device exits with a config error when config.yaml is missing | `@error-path @infrastructure-failure @driving_port` |
| remove-device exits with a config error on malformed config.yaml | `@error-path @infrastructure-failure @driving_port` |
| remove-device requires an identifier (neither flag given) | `@error-path @driving_port` |
| remove-device rejects both --label and --uuid together | `@error-path @driving_port` |
| remove-device writes the configuration atomically | `@real-io @driving_port` |

**`list-devices.feature` (@US-102) — 9 scenarios:**

| Scenario | Tags |
|---|---|
| Listing devices shows every registered device with UUID and label | `@walking_skeleton @real-io @driving_port` |
| A currently mounted device shows its live mount path | `@real-io @driving_port` |
| A registered but not-mounted device shows "not mounted" | `@driving_port` |
| Listing devices with none registered shows a helpful empty state | `@boundary @driving_port` |
| list-devices exits with a config error when config.yaml is missing | `@error-path @infrastructure-failure @driving_port` |
| list-devices exits with a config error on malformed config.yaml | `@error-path @infrastructure-failure @driving_port` |
| list-devices treats an unreadable mount query as "not mounted" rather than failing | `@error-path @infrastructure-failure @driving_port` |
| list-devices never modifies config.yaml regardless of registry contents | `@property @driving_port` |
| list-devices and sync-usb.sh agree on live mount state for the same device | `@real-io @adapter-integration @driving_port` |

**Totals: 20 scenarios, 2 walking skeletons, 9 error-path (45%), 1 property, 1 dedicated adapter-integration regression probe.** Both driving ports (`install.sh remove-device`, `install.sh list-devices`) are exercised exclusively via real subprocess invocation — no internal function is imported or called directly (Mandate 1).

### Adapter Coverage

| Driven adapter | Real-I/O scenario(s) |
|---|---|
| `config.yaml` (read) | All 20 scenarios (real temp files via `setup_test_env`) |
| `config.yaml` (atomic write) | remove-device scenarios 1–4, 11 |
| Live mount state (`diskutil`/`/Volumes` via the future `bin/lib/usb-common.sh`, ADR-004) | list-devices scenarios 2, 3, 7, 9 (mock-binary-in-PATH, Strategy C convention) |

Every driven adapter named in DESIGN's component boundaries has at least one real-I/O scenario. The `@adapter-integration` scenario directly implements ADR-004's own "Earned Trust" regression probe: `install.sh list-devices` and `sync-usb.sh` must agree on mount state for an identical mocked `diskutil`/`/Volumes` fixture.

### RED-Scaffold

`bin/install.sh`'s subcommand dispatch had no `remove-device`/`list-devices` branches — invoking either fell through to the interactive install flow (`read -rp`), which would hang tests indefinitely. Added two minimal stub branches (exit 2, "not yet implemented") immediately after the existing `add-device` dispatch — scaffolding only, no business logic. Full RED/BROKEN classification: `docs/feature/usb-device-lifecycle/distill/red-classification.md`. Result: all 20 scenarios (43 assertions) run once against the stub — 16 pass (trivial "config untouched" checks), 27 fail, **zero BROKEN**. Suite reverted to one-scenario-enabled (`test_ws_remove_device_by_label_leaves_others_unchanged`), all others present but commented out per the one-at-a-time mandate — same convention as the original `multi-usb-sync/run-tests.sh` scaffold.

### Wave-Decision Contradictions Found

None. All prior-wave decisions (ADR-004 extraction target, OQ-004 structural separation of compute-then-write, exit-code convention 0/2/4, no `@kpi` scenarios) were directly honored, not reopened.

### Gate Status

- [x] All stories covered (US-101, US-102 both have `@US-1xx`-tagged scenarios)
- [x] Error-path ratio 45% (9/20), exceeds 40% mandate
- [x] Business language verified (no HTTP/JSON/API/status-code terms in any `.feature` file — see review below)
- [x] `@driving_port` tagged on all walking-skeleton scenarios (and all others)
- [x] `@kpi` scenarios: none, per `outcome-kpis.md`'s explicit soft-gate disposition
- [x] Feature files created, steps (test functions) implemented, first scenario executable and genuinely RED
- [x] Peer review (Sentinel/`nw-acceptance-designer-reviewer`): approved, 0 blockers, 1 low (non-blocking tag-convention note) — part of the Final Wave Review Gate alongside Eclipse (DISCUSS, approved) and Architect (DESIGN, approved)

### Next Wave

DELIVER (software-crafter): implement `cmd_remove_device()` and `cmd_list_devices()` in `bin/install.sh`, extract `find_usb_by_uuid()` to `bin/lib/usb-common.sh` per ADR-004, replacing the RED-scaffold stubs one scenario at a time starting from the enabled walking skeleton.

## Wave: DELIVER (2026-08-26, nw-software-crafter, orchestrated by main instance)

### Implementation Summary

Both stories shipped on `feat/usb-device-lifecycle`, 16 roadmap steps, each an independent RED→GREEN→COMMIT cycle: `cmd_remove_device()` and `cmd_list_devices()` added to `bin/install.sh` as siblings to the existing `cmd_add_device()`; `find_usb_by_uuid()` extracted from `bin/sync-usb.sh` into new `bin/lib/usb-common.sh` per ADR-004, sourced by both `sync-usb.sh` and `install.sh`. A spec-drift correction was made mid-implementation: the "no match found" exit code was corrected from an ad-hoc `3` to the documented convention's `2` (`discuss/user-stories.md:119`) before it could propagate further.

### Files Modified

- `bin/install.sh` — `cmd_remove_device()`, `cmd_list_devices()` added; RED-scaffold stubs removed
- `bin/lib/usb-common.sh` — new; `find_usb_by_uuid()` extracted from `bin/sync-usb.sh`
- `bin/sync-usb.sh` — sources the shared library, inline copy removed, behavior unchanged (verified: 38/38 regression suite green throughout)
- `tests/acceptance/usb-device-lifecycle/run-tests.sh` — all 20 scenarios enabled incrementally

### Scenarios Green

20 of 20 (`tests/acceptance/usb-device-lifecycle/{remove-device,list-devices}.feature`, 43/43 assertions). Regression: `tests/acceptance/multi-usb-sync/run-tests.sh` 38/38 throughout every step.

### DoD Check

- [x] All acceptance scenarios green
- [x] No regression in the existing 38-scenario multi-usb-sync suite
- [x] Every step passed through DES RED/GREEN/COMMIT with `des-verify-integrity` confirming all 16 steps have complete traces (exit 0)
- [x] Atomic write pattern (ADR-003) preserved for `remove-device`; `list-devices` confirmed read-only (property scenario 02-07)
- [x] ADR-004 extraction confirmed behavior-neutral via dedicated cross-caller regression probe (02-08)

### Demo Evidence — 2026-08-26

**US-101 remove-device** — `install.sh remove-device --label "IronKey-C (travel)"` against a real temp config (2 registered devices, one mapped to a directory):
```
1 devices remain registered
```
Exit 0. Resulting `config.yaml`: `IronKey-C (travel)` removed from both `usb_devices[]` and the directory's `usb_devices` list; `IronKey-A`'s entry unchanged. (Cosmetic nit found during demo: "1 devices remain registered" — singular/plural grammar, not fixed, tracked as a follow-up, not a functional defect.)

**US-102 list-devices** — `install.sh list-devices` against the same config before removal:
```
  IronKey-A  (1A2B-3C4D)  not mounted
  IronKey-C (travel)  (5E6F-7A8B)  not mounted
2 devices registered
```
Exit 0.

Both commands run as real subprocess invocations (not function calls) against a config outside the test harness, per the Elevator Pitch hard gate.

### Environment Matrix

No `docs/feature/usb-device-lifecycle/devops/` exists (DEVOPS wave was not run for this feature — graceful degradation per DISTILL). This project has no distinct multi-environment CI matrix (no pre-commit-hook or stale-config-environment concept separate from the acceptance suite itself); the suite's own scenario set (missing config, malformed config, empty registry, various mount states) is the environment-variation coverage for this Bash CLI, run directly rather than against a fictional "with-pre-commit" environment that doesn't exist in this repo.

### Quality Gates

- Refactoring: per-step (each step's crafter confirmed no L1-L6 transformations warranted) **plus** a consolidated Phase 3 aggregate pass (commit `229a04c`) that found and fixed two cross-function duplications invisible from any single step: `get_volume_uuid()` extracted into `bin/lib/usb-common.sh` (completing ADR-004's intent — `sync-usb.sh`'s own scan loop had carried a byte-identical copy the extraction step missed), and `require_config_file()` extracted in `bin/install.sh` to replace three near-identical config-existence checks. Both suites confirmed green before, during, and after.
- Adversarial review (`nw-software-crafter-reviewer`): **iteration 1 REJECTED** — 2 BLOCKERs found and confirmed genuine by independent orchestrator verification (not just trusted from the report):
  - **D1**: `bin/install.sh`'s three `python3 - <<PYEOF` heredocs (unquoted delimiter) interpolated `--label`/`--uuid` values directly into Python string literals; a label containing `"` broke out of the string and executed arbitrary Python. Affected `cmd_add_device()` (pre-existing, shipped in `multi-usb-sync`) and the new `cmd_remove_device()`, which had mirrored the same pattern by design.
  - **D2** (found by the fix-D1 crafter while working, not by the original reviewer): `cmd_list_devices()` rendered each device as `USB_DEVICE_i_LABEL='...'` bash source text and ran `eval` on it — a label containing `'` broke out and executed arbitrary bash. Worse than D1 in one respect: exploitable via a hand-edited or otherwise arbitrary `config.yaml`, no CLI argument required.
  - Both fixed: D1 via environment-variable passing + quoted `<<'PYEOF'` delimiters (commit `7df9615`); D2 via eliminating `eval` entirely in favor of NUL-delimited records read with `while IFS= read -r -d ''` (commit `c882b03`). Both fixes independently re-verified by the orchestrator with fresh manual exploit attempts against real temp configs (double-quote payload against `remove-device`, single-quote payload against `list-devices`) — neither executed, both handled the malicious label as inert literal text. Regression tests added for both (`test_remove_device_malicious_label_no_code_execution`, `test_list_devices_single_quote_label_no_code_execution`).
  - **Iteration 2 APPROVED**, 0 defects. (D3 from iteration 1, a test-parametrization suggestion, was withdrawn on re-review — it held the suite to a Python/pytest convention this Bash project's already-shipped `multi-usb-sync` suite doesn't follow either.)
- Mutation testing: **skipped** — this is a Bash project with no mutation-testing tool in its toolchain (mutmut/similar are Python-specific); project `CLAUDE.md` has no `## Mutation Testing Strategy` section. Logged here rather than claiming a nonexistent CI pipeline handles it.
- Integrity verification: `des-verify-integrity docs/feature/usb-device-lifecycle/deliver/` → "All 16 steps have complete DES traces", exit 0 (re-confirmed after Phase 3 and Phase 4 remediation commits)

### Scenarios Green (updated)

49 of 49 assertions across `tests/acceptance/usb-device-lifecycle/` (22 scenarios — the original 20 plus 2 security regression scenarios added during Phase 4 remediation). Regression: `tests/acceptance/multi-usb-sync/run-tests.sh` 38/38 throughout, including after the `cmd_add_device()` security fix (pre-existing shipped code this feature had to touch).

### Known Follow-Ups (not blocking)

- ADR-004's own structural CI enforcement item (a grep check asserting `find_usb_by_uuid()` is defined exactly once, scoped to exclude the deprecated `bin/sync-to-usb-and-cloud.sh`) was manually verified once during step 02-02 but not wired up as a persistent check.
- "1 devices remain registered" grammar (singular/plural) in `cmd_remove_device()`'s output.
- Symmetric regression-test coverage for `cmd_add_device()`'s injection fix in the `multi-usb-sync` test suite (that suite's own test file wasn't touched by this feature; only the vulnerable code it exercises was fixed).

### Pre-requisites

DISTILL's 20 scenarios and DESIGN's component manifest (ADR-004, Reuse Analysis) — both fully consumed, no deviation from either.
