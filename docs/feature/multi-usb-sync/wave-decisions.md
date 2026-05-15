# Wave Decisions: multi-usb-sync

## Meta

- Feature ID: `multi-usb-sync`
- Wave: DISCUSS
- Date: 2026-05-15
- Analyst: Luna (nw-product-owner)

---

## Scope Assessment: PASS

Estimated 6-8 stories, 2 bounded contexts (config + sync orchestration), estimated 6-8 days total.
Stories are separable by user outcome. No splitting required.

Contexts touched:
1. Config — device registry schema, installer
2. Sync orchestration — USB sync script, cloud sync script, launchd plists

---

## Risk: No DISCOVER or DIVERGE Wave

No validated opportunity framing, no job analysis document. Proceeding on:
- Project context from `docs/features.md`
- Spike learnings (separation of concerns, device-first config model)
- Dan as sole user and builder — JTBD grounded directly from builder intent

Mitigation: JTBD analysis run in-wave. Jobs bootstrapped to `docs/product/jobs.yaml`.

---

## Resolved Decisions (from Dan's answers, 2026-05-15)

| ID | Question | Decision | Implication |
|----|----------|----------|-------------|
| Q1 | Cloud sync trigger | **C — launchd timer (default, e.g. hourly) + manual invocation both work** | Two mechanisms: a `StartInterval`-based launchd plist for cloud sync, plus direct script invocation. Cloud sync never blocks on USB presence. |
| Q2 | USB sync scope | **A — sync all registered directories always** | No per-directory enabled flag. Every directory mapped to a device syncs whenever that device mounts. Simpler config; revisit if selective sync is needed later. |
| Q3 | rclone remote scoping | **Per-directory (not per-USB-device)** | Config model: each directory entry carries both `usb_devices: [UUID, ...]` and `cloud_remote: remote:path`. USB sync script reads device→dirs mapping. Cloud sync script reads dirs→remote mapping. Rationale: with cloud sync decoupled from USB, the USB device has no logical relationship to which cloud account a directory backs up to. The base unit for cloud sync is the local directory. |
| Q4 | Install flow for USB device registration | **[DESIGN] — open/TBD** | The outcome is clear (user can register a new USB device and have it sync correctly). The mechanism (auto-detect UUID, manual entry, or hybrid) is a DESIGN wave decision. User stories describe the outcome only. |

---

## Decisions Made (from spike learnings — not to re-litigate)

| Decision | Detail |
|----------|--------|
| Separation of concerns | USB sync and cloud sync are independent scripts with independent triggers |
| Device-first config model | Config is keyed by USB UUID, not by flat JOB_N_* scheme |
| Config location | `~/.config/securelocal/config.env` (from DR config-governance) |
| USB sync semantics | rsync without `--delete` (from DR sync-strategy) |
| Cloud sync semantics | rclone sync, mirrors current state (from DR sync-strategy) |
| UUID validation mandatory | Script must verify UUID before writing (from DR architecture) |
| launchd WatchPaths | `/Volumes` is the USB trigger mechanism (from DR automation) |
| Log file | `~/Library/Logs/securelocal-sync.log` (from DR observability) |
| Exit codes | 0=success, 1=USB fail, 2=cloud fail, 3=both fail, 4=config error (from DR observability) |
