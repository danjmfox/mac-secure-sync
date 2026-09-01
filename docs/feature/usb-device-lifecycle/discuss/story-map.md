# Story Map: usb-device-lifecycle

## User: Dan Fox (builder-user, sole operator)
## Goal: Keep config.yaml an accurate reflection of the USB devices Dan actually owns, across the full register → use → retire lifecycle

## Backbone

| Register Device (shipped) | List Devices | Remove Device | Check Sync Status (deferred) |
|---|---|---|---|
| `add-device --volume --label` | `list-devices` | `remove-device --label\|--uuid` | *(log-grep, US-004 — no new command; see wave-decisions.md)* |
| Duplicate UUID rejected | Empty state when none registered | Unknown identifier rejected, config untouched | |
| Atomic config write | Live mount state shown | Strips UUID from every directory mapping | |
| | | Atomic config write | |

---

### Walking Skeleton

Both new activities are already right-sized single stories (per LeanUX sizing, each bundles its own happy/edge/error scenarios rather than being split further — consistent with how `add-device`'s US-005 was structured). The walking skeleton **is** the two stories:

- **List Devices** — `install.sh list-devices` happy path (registered devices + live mount state)
- **Remove Device** — `install.sh remove-device --label <name>` happy path (removes from `usb_devices[]` and every directory mapping, atomic write, other entries untouched)

No further release slicing needed — each story's own UAT scenarios (4-5 each, see `user-stories.md`) cover the edge and error paths within the story rather than as separate release bands. "Register Device" is already delivered (`multi-usb-sync`). "Check Sync Status" is deferred — no tasks in this map (see `wave-decisions.md` for the explicit disposition).

### Release 1: Config Accuracy (both new stories, single release)

- **Tasks**: List Devices (all scenarios), Remove Device (all scenarios)
- **Outcome KPI targeted**: Zero stale/orphaned UUID references in `config.yaml` at any time; time-to-identify-and-remove a retired device < 1 minute (see `outcome-kpis.md`)
- **Rationale**: The two stories are small enough (1-3 days combined, per Scope Assessment PASS in `wave-decisions.md`) that splitting them across releases would fragment a single coherent outcome — "Dan's config tells the truth" — for no delivery-risk reduction. remove-device ships as functionally complete on its own (it does not require list-devices to work); both ship together because list-devices is trivial and materially de-risks remove-device's usability, per the resolved dependency question.

## Priority Rationale

| Priority | Story | Outcome Impact | Dependency | Rationale |
|---|---|---|---|---|
| P1 | Remove USB Device (US-101) | High — directly resolves the user-named pain (config only ever accretes); addresses JOB-003's core push force | None — functions standalone using a label Dan chose himself, or by reading config.yaml directly (established pattern per ADR-001) | User-named highest priority; walking skeleton |
| P2 | List Registered USB Devices (US-102) | Medium — reduces friction/anxiety around targeting remove-device correctly; adds live mount state unavailable from raw config reading | None — read-only, reuses `sync-usb.sh`'s existing UUID-matching logic | Companion to P1, not a precursor (see wave-decisions.md dependency resolution); ships same release because it is low-effort and high-confidence-value |
| — | Status / last-synced | Deferred | — | Existing JOB-001 outcome statement already served by US-004 (log-grep). No story created this feature — see wave-decisions.md |

Tie-breaking per `nw-user-story-mapping`: Walking Skeleton > Riskiest Assumption > Highest Value. Both stories together *are* the walking skeleton; within that pair, remove-device is ordered first because it is the user-named priority and does not require list-devices to be useful or demoable on its own.
