<!-- markdownlint-disable MD024 -->
# Outcome KPIs: usb-device-lifecycle

## Feature: usb-device-lifecycle

### Objective
Dan's `config.yaml` always tells the truth about which USB devices he actually owns and uses — no stale entries lingering from lost or retired drives, and no guesswork about what's currently registered.

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Dan Fox | Removes a retired/lost USB device without disturbing any other device or directory entry | 0 unintended mutations to other `usb_devices[]` entries across all removals (100% isolation) | Today: manual YAML editing, 0% of removals verifiable as safe | Acceptance test byte-for-byte diff of untouched entries | Leading |
| 2 | Dan Fox | Identifies which UUID/label to target for removal, or confirms current setup | Under 10 seconds via `list-devices`, without opening a text editor | Today: open `config.yaml` in an editor, parse YAML by eye; mount state unavailable at all | Manual timing / qualitative check | Leading (secondary) |
| 3 | Dan Fox | Config accuracy — registered devices reflect devices actually owned | 0 stale/orphaned UUID references at any point in time | Today: config only accretes, no way to detect staleness | Manual audit: `list-devices` mounted=no entries cross-checked against devices Dan still owns | Leading |

### Metric Hierarchy
- **North Star**: Zero stale/orphaned UUID references in `config.yaml` at any time (config accuracy)
- **Leading Indicators**: Removal isolation rate (KPI 1), time-to-identify-target (KPI 2)
- **Guardrail Metrics**: `directories[]` count must never change as a side effect of device lifecycle commands (add/remove/list touch `usb_devices[]` membership only, never the directory list itself); other `usb_devices[]` entries must remain byte-for-byte unchanged after any single removal (inherits JOB-002's original non-corruption guarantee, applied in reverse)

### Measurement Plan

| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| 1 — Removal isolation | Acceptance test suite | Automated diff assertion (DISTILL wave) | Every CI run | acceptance-designer |
| 2 — Identification time | Manual/qualitative | Dan self-reports during DELIVER demo | Once, at feature demo | Dan Fox |
| 3 — Config accuracy (North Star) | `config.yaml` + Dan's own knowledge of owned devices | Manual audit — no automated instrumentation planned (personal tool, no telemetry) | Ad hoc, whenever Dan runs `list-devices` | Dan Fox |

No automated KPI instrumentation (`@kpi` scenarios) is planned this wave — consistent with the precedent set in `multi-usb-sync` (soft gate applied, WD-DISTILL-005 Finding 4). This is a personal single-operator tool; KPI 3 in particular is inherently a self-assessment, not something the system can measure about itself (the system cannot know which devices Dan still physically owns).

### Hypothesis
We believe that adding `remove-device` and `list-devices` to `install.sh` for Dan Fox will achieve a `config.yaml` that always reflects reality.
We will know this is true when Dan removes a retired device without any other entry changing, and can identify any device to target in under 10 seconds without opening a text editor.
