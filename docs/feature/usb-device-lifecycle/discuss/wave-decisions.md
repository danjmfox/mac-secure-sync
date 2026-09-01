<!-- markdownlint-disable MD024 -->
# Wave Decisions: usb-device-lifecycle

Feature ID: `usb-device-lifecycle`
Wave: DISCUSS
Analyst: Luna (nw-product-owner)
Date: 2026-08-24

---

## Routing Decisions (pre-answered by calling context)

| # | Decision | Answer | Rationale |
|---|----------|--------|-----------|
| 1 | Feature Type | Backend/CLI tooling | Same class of work as `add-device`; `install.sh` subcommand extension, not GUI |
| 2 | Walking Skeleton | No | Incremental extension of an already-shipped, isolated CLI surface (multi-usb-sync), not greenfield |
| 3 | UX Research Depth | Lightweight | CLI happy-path + error path; not a GUI experience needing full emotional-arc depth |
| 4 | JTBD | Yes (default), check for duplication first | See JTBD Grounding below |

## Missing DIVERGE — Noted, Not a Gap

No `docs/feature/usb-device-lifecycle/diverge/` artifacts exist, and none are expected: this is a small, well-bounded extension to an already-designed CLI surface (`install.sh` subcommands) with an established pattern (`add-device`, ADR-003) to mirror. Running a full DIVERGE (JTBD exploration + competitive research + option generation) for the inverse of an existing, accepted command would be ceremony without decision value — the shape of the solution (a sibling subcommand following the same flag/atomic-write conventions) is already constrained by ADR-001 and ADR-003. Flagged here as a deliberate skip, not an oversight.

---

## JTBD Grounding

Read `docs/product/jobs.yaml` (JOB-001 silent-guardian, JOB-002 multi-device-guardian) before minting anything new, per the routing instruction.

### remove-device and list-devices → new job (JOB-003, confident-decommissioner)

JOB-002's statement is explicitly additive: *"When I acquire a second USB device, I want to register it alongside the first... so I can maintain independent USB copies."* Its anxiety force is "adding device 2 could accidentally overwrite device 1" — a forward-only fear. Retiring a device inverts both the trigger (loss/retirement, not acquisition) and the anxiety (accidentally corrupting *other* devices while removing *one*, or removing the *wrong* device with no physical drive present to double-check). Forcing remove-device and list-devices under JOB-002's label would blur a job whose whole value is being about *adding safely* with a job about *removing safely* — different trigger, different fear, different done-state. Minted **JOB-003 — confident-decommissioner** (`docs/product/jobs.yaml`).

list-devices traces to JOB-003 as well: its job-map role is "Locate" (confirm what's registered before acting), directly serving JOB-003's outcome statement "minimize the time to confirm what devices are currently registered." It does not warrant its own job — it has no independent trigger; it exists to serve decommissioning (and, secondarily, general sanity-checking) rather than being sought for its own sake.

### status / "last synced" → no new job, existing JOB-001 outcome statement already covers it

JOB-001's outcome statements already include *"maximize confidence that the last sync completed successfully."* The candidate "status" story would not be pursuing a job that lacks a home — it would be a second way to satisfy an already-registered outcome statement that US-004 (`docs/feature/multi-usb-sync/discuss/user-stories.md:293`) already satisfies via structured, grep-friendly logging. No new job entry. See Scope Assessment below for the disposition of this candidate.

---

## Scope Assessment (Elephant Carpaccio Gate)

Candidates after JTBD grounding: **remove-device**, **list-devices**. Status is deferred (see below), so it does not count toward this gate.

| Oversized signal | This feature | Verdict |
|---|---|---|
| >10 user stories | 2 stories | No |
| >3 bounded contexts/modules | 1 (config.yaml lifecycle, inside `install.sh`) | No |
| Walking skeleton needs >5 integration points | 2 (diskutil UUID lookup, config.yaml atomic write — both already proven by `add-device`) | No |
| Estimated effort >2 weeks | ~2-3 days combined (mirrors an existing, accepted pattern) | No |
| Multiple independent user outcomes shippable separately | Arguably yes (see dependency question below) — evaluated, not blocking | See below |

**Scope Assessment: PASS — 2 stories, 1 bounded context, estimated 2-3 days.** No split required. (No `story-map.md` existed yet at gate time per skill instruction — re-affirmed after story mapping in Phase 4, no change.)

---

## Dependency Question: Does list-devices structurally precede remove-device?

The steer flagged this explicitly and asked it be resolved with reasoning, not assumed.

**The case for "yes, precursor":** `remove-device` takes an identifier (label or UUID) as an argument. It is often invoked when the device is *not* mounted — that's frequently *why* it's being removed (lost, retired, at another location). Without some way to see registered devices, Dan has to already know or guess the right identifier.

**The case for "no, not load-bearing":** Two facts from the shipped feature undercut the "hard precursor" reading:

1. **`config.yaml` is already a supported human-read surface.** ADR-001 states the format was chosen specifically because "Dan edits it directly" and "human-readable and human-editable; structure is self-documenting." `cat ~/.config/securelocal/config.yaml` (or `grep -A2 usb_devices`) already answers "what's registered" today, the same way `grep ERROR` on the log already answers "did the last sync work" for US-004 — the project's established pattern is that raw-file-reading is an acceptable interface for a solo-operator tool, not a gap that blocks a command.
2. **Labels are human-chosen at add-time** (`install.sh add-device --label "IronKey-B (office)"`), and for a registry of 2-3 devices, recall is realistic — this is not a fleet-management tool.

**What list-devices adds that raw file-reading cannot:** live mount state. `config.yaml` is static; whether a UUID is *currently* mounted, and at what path, is runtime information from `/Volumes` + `diskutil`, unavailable from the file alone. That's the genuine, non-redundant value of the command — not identifier discovery (which `cat` already covers), but confidence about current device state.

**Verdict: list-devices is a high-value companion, not a hard structural precursor.** remove-device does not depend on list-devices to function or to be usable — Dan can target a device today by label he chose himself, or by reading `config.yaml`. list-devices ships in the **same release** as remove-device (not gating it) because it directly reduces the friction and anxiety the user flagged ("list might be necessary to do that"), and because it is itself trivial to build (read-only, reuses `find_usb_by_uuid` matching logic already proven in `sync-usb.sh`). Priority order: **remove-device first (P1, user-named highest value), list-devices second (P2, ships same release).**

---

## Status / "Last Synced" Disposition

Per the steer: surface as an explicit option rather than force-fitting a command. Decision: **defer — stay log-based, no new story.**

- JOB-001's outcome statement "maximize confidence that the last sync completed successfully" is already served by US-004's structured log format (`docs/feature/multi-usb-sync/discuss/user-stories.md:293`) — `grep ERROR ~/Library/Logs/securelocal-sync.log` and `tail` already answer this in under 30 seconds per US-004's own outcome KPI.
- A dedicated `status` command would be new surface area (parsing the log for a per-directory/per-device "last successful sync" summary) with no user-named urgency in this steer — the user explicitly ranked it lowest priority and floated log-grep sufficiency as the working hypothesis.
- Building it now would duplicate US-004's job coverage without new evidence that log-grep is failing Dan in practice. Revisit if/when it demonstrably isn't (e.g., Dan reports checking the log is no longer fast enough as directory/device count grows).

No story created for status in this feature. Not silently dropped — recorded here as an evaluated, deferred option.

---

## Definition of Ready Validation

### Story: US-101 Remove USB Device

| DoR Item | Status | Evidence |
|----------|--------|----------|
| 1. Problem statement clear, domain language | PASS | "IronKey-C travel drive was lost... no supported way to deregister it" — concrete, no tech jargon |
| 2. User/persona with specific characteristics | PASS | Dan Fox, sole operator, macOS single machine — same established persona as `multi-usb-sync` |
| 3. 3+ domain examples with real data | PASS | 4 examples — IronKey-A/B/C, real UUIDs (1A2B-3C4D, 5E6F-7A8B, 9C0D-1E2F) |
| 4. UAT in Given/When/Then (3-7 scenarios) | PASS | 5 scenarios |
| 5. AC derived from UAT | PASS | 8 AC bullets, each traceable to a scenario |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS | 5 scenarios; mirrors `add-device`'s already-delivered effort (US-005 shipped in the walking skeleton of multi-usb-sync) |
| 7. Technical notes: constraints/dependencies | PASS | Reuse of ADR-003 pattern, test harness extension named explicitly |
| 8. Dependencies resolved or tracked | PASS | No blocking dependency (see wave-decisions.md dependency resolution); list-devices companion tracked, not blocking |
| 9. Outcome KPIs defined with measurable targets | PASS | KPI 1 (0 unintended mutations) in `outcome-kpis.md` |

**DoR Status: PASSED**

### Story: US-102 List Registered USB Devices

| DoR Item | Status | Evidence |
|----------|--------|----------|
| 1. Problem statement clear, domain language | PASS | "confirming which USB devices are registered... can't tell whether a device is currently mounted" |
| 2. User/persona with specific characteristics | PASS | Dan Fox, about to run remove-device or sanity-checking setup |
| 3. 3+ domain examples with real data | PASS | 3 examples — mixed mount state, empty registry, manually-edited label |
| 4. UAT in Given/When/Then (3-7 scenarios) | PASS | 4 scenarios |
| 5. AC derived from UAT | PASS | 7 AC bullets |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS | 4 scenarios, read-only command, smaller than US-101 |
| 7. Technical notes: constraints/dependencies | PASS | Reuse of `find_usb_by_uuid()` named explicitly as the integration constraint |
| 8. Dependencies resolved or tracked | PASS | None — read-only, no write-path dependency |
| 9. Outcome KPIs defined with measurable targets | PASS | KPI 2 (<10s identification) in `outcome-kpis.md` |

**DoR Status: PASSED**

---

## Anti-Pattern Check (Phase 6 gate, recorded here for traceability)

- Implement-X: avoided — both stories open from Dan's pain (stale config, no visibility), not "implement remove/list."
- Generic data: avoided — all examples use IronKey-A/B/C with concrete UUIDs, mirroring the established fixtures from `multi-usb-sync`.
- Technical AC: avoided — AC describe config-file outcomes and CLI-observable output, not `python3` implementation internals (those live in Technical Notes only).
- Oversized stories: both stories are 4-5 UAT scenarios, well within 3-7.

---

## Out of Scope / Deferred

### Candidate US-103 (unclaimed): Orphaned-data cleanup on stale USB insert

Surfaced during user review of this story set, explicitly flagged as "belt and braces, not a current priority" — captured here so it isn't lost, not story-mapped or DoR-validated.

**Scenario:** A USB device was previously registered and synced (via `add-device`), then later deregistered via `remove-device` (US-101). The USB itself still holds the files that were synced onto it before removal — `remove-device` only edits `config.yaml`, it does not touch the device's contents (by design — see US-101 AC, deregistration must not be destructive to data at rest). If that same USB is later reinserted, `sync-usb.sh`'s WatchPaths trigger fires but finds no matching entry in `usb_devices[]` and does nothing. The open question: should insertion of a now-unregistered-but-previously-synced device prompt/offer to clean up the stale files it's still carrying?

**Why deferred, not built now:**
- Explicitly named not-current-priority by the user.
- It is a *destructive* operation (deleting files from a device) gated behind a *detection* problem (distinguishing "this UUID was once registered and has our files on it" from "this is an unrelated USB with unrelated files") — meaningfully higher risk than US-101/US-102, which are pure `config.yaml` edits or read-only.
- Depends on US-101 shipping first (there must be a removal event to be stale relative to) and arguably on a removal *log* or *tombstone* existing (nothing today records that a UUID was ever registered, once `remove-device` has run) — a new mechanism, not a rewire of what US-101/US-102 already need.

**If revisited later:** this would need its own DISCUSS pass — job traceability (likely still JOB-003 confident-decommissioner, but with a much sharper anxiety force around unintended data loss), a prompt/offer UX (not silent deletion), and explicit boundary cases (device UUID reused by a different physical drive, partial sync state, offline/non-interactive invocation from `sync-usb.sh`'s launchd context where no one is present to answer a prompt).
