<!-- markdownlint-disable MD024 -->
# Wave Decisions: usb-device-lifecycle (DESIGN)

Feature ID: `usb-device-lifecycle`
Wave: DESIGN
Architect: Morgan (nw-solution-architect)
Date: 2026-08-24
Scope: Application/components. Mode: Propose.

---

## Prior Wave Consultation Checklist

| # | Artifact | Status |
|---|----------|--------|
| 1 | `docs/product/architecture/brief.md` | ✓ read |
| 2 | `docs/product/architecture/adr-001-config-schema-v2.md` | ✓ read |
| 3 | `docs/product/architecture/adr-002-yaml-parser.md` | ✓ read |
| 4 | `docs/product/architecture/adr-003-usb-registration-mechanism.md` | ✓ read |
| 5 | `docs/product/architecture/c4-diagrams.md` | ✓ read |
| 6 | `docs/feature/usb-device-lifecycle/discuss/wave-decisions.md` | ✓ read — dependency resolution and US-103 deferral honored, not reopened |
| 7 | `docs/feature/usb-device-lifecycle/discuss/user-stories.md` | ✓ read — US-101/US-102 full AC + UAT |
| 8 | `docs/feature/usb-device-lifecycle/discuss/story-map.md` | ✓ read |
| 9 | `docs/feature/usb-device-lifecycle/discuss/outcome-kpis.md` | ✓ read |
| 10 | `docs/feature/usb-device-lifecycle/feature-delta.md` | ✓ read, ✓ updated with DESIGN section |
| 11 | `docs/feature/usb-device-lifecycle/discuss/shared-artifacts-registry.md` | ✓ read — HIGH-risk reuse flag for `find_usb_by_uuid()` is the primary driver of ADR-004 |
| 12 | `bin/install.sh` (existing `add-device`, `select_usb_volume()`) | ✓ read |
| 13 | `bin/sync-usb.sh` (`find_usb_by_uuid()`, `load_config()`) | ✓ read |
| 14 | `bin/sync-cloud.sh` (checked for `load_config()` duplication precedent) | ✓ read — confirms `load_config()` is intentionally duplicated, informing the decision NOT to extract it |
| 15 | `tests/acceptance/multi-usb-sync/helpers.sh` | ✓ read — confirms existing mock factories (`create_mock_diskutil_multi`, `register_mock_volume`) already cover both new commands' fixture needs |
| 16 | `docs/product/outcomes/` | ⊘ does not exist — Outcome Collision Check skipped per instructions |

---

## Decision: How does `list-devices` obtain live mount state without reimplementing UUID matching?

This was the one real choice point in this feature — everything else is direct pattern-mirroring of ADR-003.

### Option A — Chosen: Extract `find_usb_by_uuid()` to `bin/lib/usb-common.sh`, sourced by `install.sh` and `sync-usb.sh`

- Single source of truth; `remove-device`'s deletions and `list-devices`'/`sync-usb.sh`'s matching can never silently drift.
- Pure function, no `main()` in the lib file — safe to source.
- Does not touch the `sync-usb.sh`/`sync-cloud.sh` independence boundary (`sync-cloud.sh` has no USB-matching need and does not source the library).
- Cost: introduces the project's first shared-library file (`bin/lib/`) — a genuinely new structural element, justified by the DISCUSS wave's own HIGH-risk flag on this exact duplication.

### Option B — Rejected: `install.sh` shells out to `sync-usb.sh` in a query mode

`sync-usb.sh --resolve-uuid <uuid>`, captured by `install.sh` per device. Turns `sync-usb.sh` into a dual-purpose script (launchd trigger + CLI query API); one subprocess spawn per device for `list-devices`; harder to test in isolation.

### Option C — Rejected: Duplicate `find_usb_by_uuid()` into `install.sh`

Directly contradicts the DISCUSS wave's explicit finding (shared-artifacts-registry.md): "no independent re-implementation." Recorded only to document why it's off the table.

**Recommendation: Option A.** Full alternatives analysis, consequences, and Earned Trust probe requirements in `docs/product/architecture/adr-004-shared-usb-matching-library.md`.

---

## Reuse Analysis (hard gate)

| Component | Disposition | Justification |
|---|---|---|
| `find_usb_by_uuid()` | MOVE to `bin/lib/usb-common.sh` | Cross-container reuse required by DISCUSS HIGH-risk flag; see ADR-004 |
| `cmd_add_device()` atomic-write structure | MIRROR in `cmd_remove_device()` | ADR-003 pattern is sufficient for deletion; no shared write helper needed at this scale |
| `load_config()` | REUSE unchanged, not extracted | Already intentionally duplicated per script (ADR-002 precedent); extracting it would go against the project's stated sync-script independence paradigm |
| `tests/acceptance/multi-usb-sync/helpers.sh` mocks | REUSE unchanged | `create_mock_diskutil_multi()` / `register_mock_volume()` already support every fixture both new commands need |

No CREATE NEW verdict without an existing-alternative check: every row above starts from an existing component.

---

## Outcome Collision Check

`docs/product/outcomes/` does not exist in this repository — no outcomes registry is in use. Check skipped per the instruction to skip when the registry isn't present.

---

## Quality Gate Status

- [x] Requirements traced to components (US-101 → `cmd_remove_device()`; US-102 → `cmd_list_devices()`)
- [x] Component boundaries with clear responsibilities
- [x] Technology choices: no new technology introduced (Bash, python3, diskutil — all existing, ADR-002 precedent holds)
- [x] Quality attributes addressed: reliability (atomic write, byte-for-byte isolation AC), observability (existing structured log format extended), maintainability (single UUID-matching source of truth)
- [x] Dependency-inversion compliance: `find_usb_by_uuid()` remains a pure query function; no new coupling to a concrete YAML representation beyond the existing `load_config()`/inline-python3 contracts
- [x] C4 diagrams: L1+L2 confirmed unchanged in topology, descriptions updated; L3 added for the `install.sh` subsystem
- [x] Integration patterns specified (port contracts for `remove-device`, `list-devices`, and the shared library, in `brief.md`)
- [x] OSS preference validated: no new dependency of any kind
- [x] AC behavioral, not implementation-coupled (inherited from DISCUSS; DESIGN did not alter AC)
- [x] External integrations: none present in this feature — no contract-testing annotation needed
- [x] Architectural enforcement: `shellcheck` extended to `bin/lib/usb-common.sh`; new CI grep check asserting `find_usb_by_uuid()` is defined exactly once in the repo
- [ ] Peer review: pending `nw-solution-architect-reviewer` invocation (next step)
