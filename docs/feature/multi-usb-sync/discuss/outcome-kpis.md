# Outcome KPIs: multi-usb-sync

Feature ID: `multi-usb-sync`
Date: 2026-05-15
Jobs: JOB-001 (silent-guardian), JOB-002 (multi-device-guardian)

---

## Feature Objective

Mac-secure-sync becomes a true silent guardian: data is backed up to any registered USB automatically on mount AND to cloud on an hourly timer — with no missed syncs going undetected and no friction when adding a second USB device.

---

## North Star KPI

**Who**: Dan Fox (sole operator)
**Does what**: Goes 30+ days without manually intervening in backup — because the automation handles both USB and cloud without gaps
**By how much**: Zero missed sync windows > 2 hours for cloud; zero missed USB syncs when device is mounted
**Baseline**: Current state — cloud sync only runs on USB mount; cloud could go days without backup when USB is unused

---

## Outcome KPI Table

| # | Story | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-------|-----|-----------|-------------|----------|-------------|------|
| 1 | US-002 | Dan | Plugs in either USB and finds all directories backed up with no manual command | 100% of registered dirs synced per USB mount event | Single USB, single dir, manual verification | Log file entries per sync session vs dir count | Leading |
| 2 | US-003 | Dan | Has cloud backup updated within the last 2 hours at any time, regardless of USB state | ≥24 cloud sync attempts per day (hourly timer) | Cloud syncs only on USB mount — could be 0/day | Timestamped log entries; no gap >2h between cloud entries | Leading |
| 3 | US-004 | Dan | Identifies whether last sync succeeded or failed within 30 seconds of opening the log | 100% of failures visible via `grep ERROR <log>` — zero silent failures | Unstructured log requires reading all entries | Presence of `[ERROR]` lines for all failure scenarios in test harness | Leading |
| 4 | US-005 | Dan | Registers USB-B and has it syncing automatically the first time it mounts | Setup time < 5 minutes; zero disruption to USB-A | Manual config restructure: ~30min, high error risk | Time from registration to first successful USB-B sync log entry | Leading |
| 5 | US-006 | Dan | Confirms both sync automations are active immediately after install | Both plists visible in `launchctl list` — zero manual post-install steps | One combined plist, cloud dependent on USB | `launchctl list | grep com.securelocal | wc -l` == 2 | Leading |

---

## Metric Hierarchy

### North Star
Number of sync windows > 2 hours with no cloud backup entry (target: 0 per week).

### Leading Indicators
- USB sync sessions: log entries per device mount (target: directories_registered per session)
- Cloud sync sessions: log entries per hour (target: ≥1 per hour during uptime)
- Error detection speed: minutes from failure to Dan noticing (target: < 30 min next morning check)

### Guardrail Metrics (must NOT degrade)
- Exit code correctness: mocked test suite exit codes match contract — 100% pass
- Config atomicity: no partial config writes on registration failure — 0 corrupted configs
- USB-A independence: registering USB-B does not change USB-A sync outcomes — verified by test harness

---

## Measurement Plan

| KPI | Data Source | Collection Method | Frequency | Owner |
|-----|------------|-------------------|-----------|-------|
| Cloud sync gap | Log file | `grep "cloud sync complete" | awk '{print $1}' | sort` — check max gap | Weekly manual check | Dan |
| USB sync completeness | Log file | Compare dir entries per session vs config dir count | Per sync event | Automated (log parsing) |
| Error visibility | Log file | `grep ERROR` — verify all known failure scenarios produce ERROR lines | On each release | Test harness |
| Registration time | Observation | Dan times the process on first USB-B registration | Once (real use) | Dan |
| launchd load state | Terminal | `launchctl list \| grep com.securelocal \| wc -l` | Post-install | install.sh (assertion) |

---

## Hypothesis

We believe that decoupling USB sync from cloud sync (two independent scripts, two independent triggers) for Dan Fox will achieve zero cloud backup gaps > 2 hours.

We will know this is true when Dan goes 30 days without running cloud sync manually to fill a gap, and the log shows ≥24 cloud sync entries per day.

---

## KPI Smell-Test Pass/Fail

| Check | KPI 1 | KPI 2 | KPI 3 | KPI 4 | KPI 5 |
|-------|-------|-------|-------|-------|-------|
| Rate not total? | PASS (ratio: dirs synced / dirs registered) | PASS (rate: syncs/hour) | PASS (rate: failures visible / failures occurred) | PASS (time metric) | PASS (count with ceiling) |
| Outcome not output? | PASS | PASS | PASS | PASS | PASS |
| Has baseline? | PASS (described) | PASS (described) | PASS (described) | PASS (estimated) | PASS (described) |
| Team can influence? | PASS | PASS | PASS | PASS | PASS |
| Has guardrails? | PASS (exit code, atomicity, USB-A independence) | | | | |
