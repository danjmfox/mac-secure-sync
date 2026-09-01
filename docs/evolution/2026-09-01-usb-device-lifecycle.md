# Evolution Record: usb-device-lifecycle

Date: 2026-09-01
Feature ID: `usb-device-lifecycle`
Branch: `feat/usb-device-lifecycle`
Waves: DISCUSS ✓ | DESIGN ✓ | DISTILL ✓ | DELIVER ✓ (DEVOPS not run — graceful degradation, see below)
Delivery: 49/49 acceptance tests GREEN (`tests/acceptance/usb-device-lifecycle/`), 38/38 regression GREEN (`tests/acceptance/multi-usb-sync/`)
Final Wave Review Gate: passed — 3 reviewers approved (Eclipse/DISCUSS, Architect/DESIGN, Sentinel/DISTILL)

---

## Feature Summary and Business Context

### Extends

`multi-usb-sync` (shipped 2026-05-17, `docs/evolution/2026-05-17-multi-usb-sync.md`). That feature shipped `install.sh add-device` with no inverse or enumeration operation — devices only ever accreted into `config.yaml`. This feature adds the missing lifecycle operations, surfaced from real use after shipping (an IronKey travel drive was lost with no supported way to deregister it).

### Jobs to Be Done

**JOB-003 — confident-decommissioner** (new, minted this feature): When Dan retires, loses, or replaces a USB device that was previously registered, he wants to cleanly remove it from his sync configuration and confirm what is currently registered, so he can trust that `config.yaml` reflects only the devices he actually uses. Distinct from JOB-002 (multi-device-guardian, which is about *adding* devices safely) — inverse trigger (loss/retirement, not acquisition), inverse anxiety (corrupting *other* devices while removing *one*, or targeting the wrong device with no physical drive present to check).

### What Changed

| Dimension | Before (multi-usb-sync) | After (usb-device-lifecycle) |
|---|---|---|
| Register a device | `install.sh add-device --volume <path> --label <name>` | Unchanged |
| Remove a device | Not supported — manual YAML editing only | `install.sh remove-device --label <name>\|--uuid <uuid>` |
| Enumerate devices | Not supported — read `config.yaml` directly | `install.sh list-devices` (adds live mount state, unavailable from the static file) |
| UUID matching | Inline in `sync-usb.sh` only | Extracted to `bin/lib/usb-common.sh` (project's first shared-library file), sourced by both `install.sh` and `sync-usb.sh` |

### Resolved: is `list-devices` a hard precursor to `remove-device`?

No. `config.yaml` is already an established human-read surface (ADR-001: "Dan edits it directly"), and labels are Dan's own human-chosen strings — `remove-device` functions standalone. `list-devices` earns its place by providing live mount state, which the static config file cannot show regardless. Both shipped in the same release; `remove-device` prioritized first as the user-named highest-value story (US-101 P1, US-102 P2).

### Deferred, not dropped

- **US-103 (unclaimed): orphaned-data cleanup on stale USB reinsert** — flagged by the user as "belt and braces, not a current priority." A *destructive* operation gated behind a *detection* problem, meaningfully higher risk than US-101/US-102. Depends on US-101 shipping first and likely a removal log/tombstone that doesn't yet exist. Needs its own DISCUSS pass if revisited.
- **Dedicated `status` command** — evaluated and deferred. JOB-001's "maximize confidence that the last sync completed successfully" is already served by US-004's structured log format (`grep ERROR` / `tail`). Revisit only if log-grep demonstrably stops being sufficient in practice.

---

## Key Decisions

### ADR-004 — Shared USB Matching Library (`bin/lib/usb-common.sh`)

The one genuine architectural choice point in this feature: how does `list-devices` (in `install.sh`) obtain live mount state without reimplementing `sync-usb.sh`'s `find_usb_by_uuid()`? The DISCUSS shared-artifacts-registry flagged this as the single highest integration risk: *"a mismatch between what remove-device deletes and what sync-usb.sh matches against would silently stop syncing a device Dan thinks is still registered, or vice versa."*

| Option | Verdict | Why |
|---|---|---|
| A — Extract to `bin/lib/usb-common.sh`, sourced by both `install.sh` and `sync-usb.sh` | **Chosen** | Single source of truth; pure function, no `main()`, safe to source; preserves the `sync-usb.sh`/`sync-cloud.sh` independence boundary (`sync-cloud.sh` does not source it) |
| B — `install.sh` shells out to `sync-usb.sh` in a query mode | Rejected | Turns `sync-usb.sh` dual-purpose (trigger + query API); one subprocess spawn per device; harder to test |
| C — Duplicate `find_usb_by_uuid()` into `install.sh` | Rejected | Directly contradicts DISCUSS's explicit "no independent re-implementation" finding |

`load_config()` was explicitly **not** extracted alongside it — it stays duplicated per script, per the ADR-002 precedent and the project's sync-script-independence paradigm (`CLAUDE.md`). This is a different kind of duplication than `find_usb_by_uuid()`'s: `load_config()`'s duplication is *intentional isolation* between two launchd-triggered containers; `find_usb_by_uuid()` had no such precedent, since `sync-cloud.sh` never needed USB matching.

ADR-004's own Earned Trust regression probe (step 02-08): `install.sh list-devices` and `sync-usb.sh` must agree on mount state for an identical mocked `diskutil`/`/Volumes` fixture. Passed — the extraction changed neither caller's behavior.

Full record: `docs/product/architecture/adr-004-shared-usb-matching-library.md`.

### OQ-004 — Structural separation of compute and write

`cmd_remove_device()`'s config mutation must be computed as a step separable from the atomic-write step, so a future (out-of-scope) US-103 tombstone/audit-log write could later be inserted without restructuring the function. This does not build US-103 — it keeps the door open per explicit steer instruction. Honored during GREEN/REFACTOR.

### Spec-drift correction

Mid-implementation, the "no match found" exit code for `remove-device` was corrected from an ad-hoc `3` to the documented convention's `2` (`discuss/user-stories.md:119`) before it could propagate further into the codebase or tests.

---

## Steps Completed

16 roadmap steps, each an independent Outside-In TDD cycle (RED → GREEN → COMMIT), plus one consolidated refactor pass and two security-fix cycles — 19 commits total on `feat/usb-device-lifecycle`.

| Phase | Steps | Focus |
|---|---|---|
| 01 — remove-device (US-101) | 01-01 .. 01-08 | Walking skeleton by label; UUID-stripping from directory mappings; removal by UUID; empty-directory-list boundary; unknown-identifier rejection; config-error exit code; flag-combination validation; atomic-write regression |
| 02 — list-devices (US-102) + ADR-004 | 02-01 .. 02-08 | Enumeration walking skeleton; `find_usb_by_uuid()` extraction to `bin/lib/usb-common.sh`; not-mounted state; empty-registry message; config-error exit code; unresolvable-mount fault tolerance; never-mutates-config property check; cross-caller mount-state agreement probe |
| Refactor | `229a04c` | Consolidated Phase 3 aggregate pass — cross-function duplication invisible from any single step |
| Security fixes | `security-fix-01`, `security-fix-02` | Phase 4 adversarial review remediation (see below) |

Every step verified via `des-verify-integrity docs/feature/usb-device-lifecycle/deliver/`: "All 16 steps have complete DES traces", exit 0 — re-confirmed after both the refactor and the security remediation commits.

**Scenarios green:** 49/49 assertions across 22 scenarios (the original 20 from DISTILL plus 2 security regression scenarios added during Phase 4). Regression: `tests/acceptance/multi-usb-sync/run-tests.sh` 38/38 throughout, including after `cmd_add_device()`'s security fix (pre-existing shipped code this feature had to touch).

---

## Security: Adversarial Review Findings

Phase 4 adversarial review (`nw-software-crafter-reviewer`) **rejected iteration 1** with 2 BLOCKERs, both independently confirmed genuine by the orchestrator via manual exploit attempts against real temp configs (not merely trusted from the review report):

### D1 — Python-heredoc string injection via unescaped label/UUID

`bin/install.sh`'s three `python3 - <<PYEOF` heredocs (unquoted delimiter) interpolated `--label`/`--uuid` values directly into Python string literals. A label containing `"` broke out of the string and executed arbitrary Python. Affected `cmd_add_device()` — **pre-existing, shipped in `multi-usb-sync`** — and the new `cmd_remove_device()`, which had mirrored the same pattern by design.

**Fix** (commit `7df9615`): environment-variable passing instead of string interpolation, plus quoted `<<'PYEOF'` delimiters.

### D2 — eval-based injection in list-devices label rendering

Found by the crafter fixing D1, not by the original reviewer, while working on the fix. `cmd_list_devices()` rendered each device as `USB_DEVICE_i_LABEL='...'` Bash source text and ran `eval` on it — a label containing `'` broke out and executed arbitrary Bash. Worse than D1 in one respect: exploitable via a hand-edited or otherwise arbitrary `config.yaml`, no CLI argument required.

**Fix** (commit `c882b03`): eliminated `eval` entirely in favor of NUL-delimited records read with `while IFS= read -r -d ''`.

### Verification

Both fixes independently re-verified by the orchestrator with fresh manual exploit attempts against real temp configs — a double-quote payload against `remove-device`, a single-quote payload against `list-devices` — neither executed; both were handled as inert literal text. Regression tests added for both: `test_remove_device_malicious_label_no_code_execution`, `test_list_devices_single_quote_label_no_code_execution`.

**Iteration 2: APPROVED, 0 defects.** (A third finding from iteration 1, a test-parametrization suggestion, was withdrawn on re-review — it held the suite to a Python/pytest convention this Bash project's already-shipped `multi-usb-sync` suite doesn't follow either.)

This is a genuinely notable part of this feature's delivery, not a footnote: two real, exploitable code-injection vulnerabilities — one in code shipped four months earlier — were caught by adversarial review before reaching `main`, with independent verification rather than trust-the-report.

---

## Lessons Learned

### The Phase 3 aggregate refactor caught what per-step refactoring couldn't

Each individual step's crafter confirmed no L1-L6 transformations were warranted in isolation. A consolidated pass after both phases completed found two cross-function duplications invisible from any single step: `get_volume_uuid()` — `sync-usb.sh`'s own scan loop had carried a byte-identical copy that the ADR-004 extraction step (02-02) missed, now completed and moved into `bin/lib/usb-common.sh` — and `require_config_file()`, extracted in `install.sh` to replace three near-identical config-existence checks. Both suites confirmed green before, during, and after. Aggregate-level duplication is a distinct failure mode from per-step duplication; both passes are needed.

### Injection risk hides in "internal" string interpolation, not just user-facing input

Neither heredoc (D1) nor eval (D2) looked like an obvious injection surface during implementation — the values being interpolated were Dan's own labels, chosen by Dan, in a single-operator tool. The adversarial review's value was treating "attacker-controlled input" as "any value that reaches a string-interpolation boundary," regardless of who normally supplies it. D2 in particular shows the risk compounds silently: a hand-edited `config.yaml` (an explicitly supported interface per ADR-001) is itself an injection vector once `eval` is in the path.

### Mutation testing: skipped, explicitly

This is a Bash project with no mutation-testing tool in its toolchain (mutmut and equivalents are Python-specific); project `CLAUDE.md` has no `## Mutation Testing Strategy` section. Logged as a deliberate skip rather than a silently absent gate.

### Graceful degradation, not silent gaps

Several DEVOPS/DISTILL inputs don't exist in this repo and were treated as expected absence, not failure: no `docs/feature/usb-device-lifecycle/devops/` (DEVOPS wave not run — the suite's own scenario variation, missing/malformed config, empty registry, various mount states, stands in for a CI environment matrix this Bash CLI doesn't have); no `docs/product/journeys/` or `kpi-contracts.yaml`; no `docs/product/outcomes/` registry (Outcome Collision Check skipped per instruction).

---

## Permanent Artifacts

### Architecture (already permanent — no migration needed)

| Artifact | Location |
|----------|----------|
| ADR-004: Shared USB Matching Library | `docs/product/architecture/adr-004-shared-usb-matching-library.md` |
| Architecture brief (Component Map, Reuse Analysis, Port Contracts updated in place) | `docs/product/architecture/brief.md` |
| C4 diagrams (L3 added for `install.sh` subsystem) | `docs/product/architecture/c4-diagrams.md` |
| ADR-001/002/003 (confirmed unchanged, referenced not revised) | `docs/product/architecture/` |

### UX Journeys (migrated this close)

| Artifact | Location |
|----------|----------|
| Journey map (structured YAML) | `docs/ux/usb-device-lifecycle/journey-usb-device-lifecycle.yaml` |
| Journey map (visual) | `docs/ux/usb-device-lifecycle/journey-usb-device-lifecycle-visual.md` |

### Acceptance Tests (already permanent)

| Artifact | Location |
|----------|----------|
| Feature files (2) + shared test runner | `tests/acceptance/usb-device-lifecycle/` |

### Feature Workspace (preserved as delivery history)

| Artifact | Location |
|----------|----------|
| All wave artifacts (DISCUSS/DESIGN/DISTILL/DELIVER) | `docs/feature/usb-device-lifecycle/` |

---

## Outcome KPI Baseline

`docs/feature/usb-device-lifecycle/discuss/outcome-kpis.md` defines the outcome KPIs. No automated KPI instrumentation was implemented this wave (no `@kpi` scenarios), consistent with the `multi-usb-sync` precedent — this is a personal single-operator tool, and KPI 3 in particular is inherently a self-assessment the system cannot measure about itself.

North Star: zero stale/orphaned UUID references in `config.yaml` at any time.

- **KPI 1 — Removal isolation** (0 unintended mutations to other `usb_devices[]` entries): automated, every CI run, via the acceptance suite's byte-for-byte diff assertions (11 `remove-device.feature` scenarios). Baseline before this feature: 0% of removals verifiable as safe (manual YAML editing only).
- **KPI 2 — Identification time** (<10s via `list-devices`, no text editor): self-reported by Dan during the DELIVER demo (2026-08-26) — demonstrated as a single command, well under 10s. Baseline before: open `config.yaml` in an editor, parse YAML by eye; mount state unavailable at all regardless of time spent.
- **KPI 3 — Config accuracy (North Star)**: manual audit, ad hoc, whenever Dan runs `list-devices`. No automated instrumentation — self-assessment against devices Dan knows he owns.

---

## Known Follow-Ups (not blocking, tracked)

- ADR-004's structural CI enforcement item — a grep check asserting `find_usb_by_uuid()` is defined exactly once in the repo — was manually verified once during step 02-02 but not wired up as a persistent check.
- "1 devices remain registered" grammar (singular/plural) in `cmd_remove_device()`'s output. Cosmetic, found during demo, not fixed.
- `cmd_add_device()`'s injection fix (D1) has no symmetric regression-test coverage in the `multi-usb-sync` suite itself — that suite's test file wasn't touched by this feature; only the vulnerable code it exercises was fixed. `remove-device`'s own regression test (`test_remove_device_malicious_label_no_code_execution`) covers the same code path via the new command.
