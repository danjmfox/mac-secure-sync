# ADR-004: Shared USB Matching Library — bin/lib/usb-common.sh

**Status:** Accepted
**Date:** 2026-08-24
**Deciders:** Dan Fox (principal), Morgan (solution-architect)
**Feature:** usb-device-lifecycle

---

## Context

US-102 (`list-devices`) must report live mount state for each registered device — whether a UUID is currently mounted, and at what path. `sync-usb.sh` already solves exactly this problem via `find_usb_by_uuid(uuid, volumes_base)`. The DISCUSS shared-artifacts-registry (`docs/feature/usb-device-lifecycle/discuss/shared-artifacts-registry.md`) flags this as the single highest integration risk in the feature: *"a mismatch between what remove-device deletes and what sync-usb.sh matches against would silently stop syncing a device Dan thinks is still registered, or vice versa... no independent re-implementation."*

`find_usb_by_uuid()` currently lives inline in `sync-usb.sh`, a container owned by `install.sh`'s sibling script, not by `install.sh` itself (where `list-devices` must run). This is a genuine cross-container reuse problem, distinct from the `load_config()` precedent: `load_config()` **is** already duplicated between `sync-usb.sh` and `sync-cloud.sh`, by design — the project's paradigm (`CLAUDE.md`) states those two scripts are "fully independent" with "no shared mutable globals." That duplication is intentional isolation between two launchd-triggered containers that must never depend on each other. `find_usb_by_uuid()` has no such precedent: `sync-cloud.sh` never needed USB matching, so there is no established "duplicate on purpose" pattern to extend — this is a new consumer (`install.sh`) needing the *exact* existing logic, not a reason to fork it.

---

## Decision

Extract `find_usb_by_uuid(uuid, volumes_base)` out of `sync-usb.sh` into a new file, `bin/lib/usb-common.sh`. The file contains only pure query functions (no `main()`, no top-level side effects), making it safe for any script to `source` without triggering unrelated execution.

- `sync-usb.sh` sources the library and removes its inline copy. Behavior is unchanged.
- `install.sh` sources the library at startup and calls `find_usb_by_uuid()` from `cmd_list_devices()`.
- `sync-cloud.sh` is untouched — it has no USB-matching need, so it does not source the library. The `sync-usb.sh`/`sync-cloud.sh` independence boundary (CLAUDE.md paradigm) is preserved: this decision only affects the `install.sh` ↔ `sync-usb.sh` relationship, not the two sync scripts' relationship to each other.
- `load_config()` is **not** extracted. It remains duplicated per-script by existing design (ADR-002 precedent). `cmd_list_devices()` uses its own minimal read-only `python3` block, matching the existing convention already established by `cmd_add_device()` inside `install.sh` (ADR-003) — each `install.sh` subcommand owns its own config-parsing needs, consistent with how the two sync scripts each own theirs.

---

## Alternatives Considered

### Option A — Chosen: Extract to `bin/lib/usb-common.sh`, sourced by both consumers

Single source of truth for UUID-to-mount-path resolution. Low blast radius: one function moves, callers unchanged in behavior. Establishes the project's first shared-library file, but the file is intentionally minimal (pure functions only) so it does not become a dumping ground or reintroduce the shared-mutable-state problem the sync-script independence rule exists to prevent.

### Option B (Rejected): `install.sh` shells out to `sync-usb.sh` in a query mode

E.g. `sync-usb.sh --resolve-uuid <uuid>`, with `install.sh` capturing stdout per device. Rejected because: turns `sync-usb.sh` into a dual-purpose script (launchd sync trigger + CLI query API), muddying its single responsibility (`brief.md` describes it as "USB sync script"); `list-devices` would spawn one subprocess (a full bash + python3 script invocation) per registered device instead of one in-process function call; harder to unit-test in isolation from the full sync flow.

### Option C (Rejected): Duplicate `find_usb_by_uuid()` into `install.sh`

Copy-paste the function. Rejected on the DISCUSS wave's own explicit finding: the shared-artifacts-registry names this exact duplication as HIGH integration risk and mandates "no independent re-implementation." Included here only to record why it is not a live option.

---

## Consequences

**Positive:**
- Single implementation of UUID-to-mount-path matching; `remove-device`'s deletions and `list-devices`'/`sync-usb.sh`'s matching can never silently drift apart.
- `sync-usb.sh` behavior is unchanged (pure refactor: function moved, not rewritten).
- Library is trivially testable in isolation (pure function, explicit `volumes_base` argument — no ambient global).

**Negative:**
- Introduces the project's first shared-library file and a `bin/lib/` directory — new structural element to document and enforce.
- `install.sh` and `sync-usb.sh` now both have a source-time file-path dependency on `bin/lib/usb-common.sh` (mitigated: both scripts already compute their own install-root-relative paths, e.g. `INSTALL_DIR` in `install.sh`).

**Earned Trust (probe):**
- Regression probe: given an identical mocked `diskutil`/`/Volumes` fixture (reusing `tests/acceptance/multi-usb-sync/helpers.sh`'s `create_mock_diskutil_multi` / `register_mock_volume`), `install.sh list-devices` and `sync-usb.sh` must agree on mount state for the same UUID. This is the extraction's own correctness check — it must prove the move didn't silently change behavior for either caller.
- Structural enforcement: a CI/pre-commit grep check asserting `find_usb_by_uuid()` is defined exactly once in the repository (in `bin/lib/usb-common.sh`) — the language-appropriate equivalent of an import-linter rule for a Bash codebase with no AST tooling available. Extend `shellcheck` (existing CI gate) to cover `bin/lib/usb-common.sh`.
