# ADR-003: USB Registration — install.sh add-device Subcommand

**Status:** Accepted
**Date:** 2026-05-15
**Deciders:** Dan Fox (principal), Morgan (solution-architect)

---

## Context

US-005 requires Dan to register a second USB device. The Volume UUID of the new device must be written to `config.yaml` under `usb_devices[]` without corrupting the existing config or creating duplicate entries.

The design must answer:
- Where does the registration command live? (separate binary vs subcommand vs prompts within main install flow)
- How is the USB volume identified? (auto-detect vs manual UUID entry)
- How is the config file updated safely? (append vs full rewrite with atomic write)
- What prevents duplicate UUID registration?

---

## Decision

Extend `install.sh` with an `add-device` subcommand. Invoked as `install.sh add-device`.

Mechanism:
1. `select_usb_volume()` (existing function) is reused as-is: lists mounted external volumes, prompts Dan for the volume name, extracts UUID via `diskutil info`
2. Duplicate UUID check: before any write, `load_config()` is called to read the current `usb_devices[]`; if the extracted UUID already exists, the subcommand exits with a clear message and code 0 (idempotent)
3. Prompt for device label (e.g., "IronKey-B (office)")
4. Atomic write: the full updated config.yaml is written to `~/.config/securelocal/config.yaml.tmp`, then renamed to `config.yaml` — both sync scripts will see either the old or new file, never a partial write

---

## Alternatives Considered

### Option A — Chosen: install.sh add-device subcommand

Reuses `select_usb_volume()` directly. Single entry point for all installation concerns. Dan already knows `install.sh`. No new file, no new command in PATH.

### Option B (Rejected): Separate `register-device.sh` script

A standalone script at `bin/register-device.sh`. Cleaner separation at the file level. Rejected because: it duplicates the volume selection and config-writing logic (or requires sourcing install.sh as a library, which is fragile); Dan must remember a second command name; no meaningful complexity reduction for a single-operator tool.

### Option C (Rejected): Prompted registration during initial install only

The initial `install.sh` flow prompts for multiple USB devices at install time. Rejected because: Dan may not have the second device available at install time; the journey map shows the second device being purchased and registered later; US-005 explicitly describes a post-install registration path.

### Option D (Rejected): Manual UUID entry (no diskutil assistance)

Dan runs `diskutil info /Volumes/IronKey-B` himself, copies the UUID, and passes it as an argument. Rejected because: error-prone (UUID is a 36-character string); `select_usb_volume()` already solves this correctly; removing the assistance increases the chance of a silently misconfigured entry.

---

## Consequences

**Positive:**
- `select_usb_volume()` is reused unchanged — no regression risk in volume detection
- Duplicate UUID detection prevents silent double-registration
- Atomic write prevents corrupt config reaching running sync scripts
- Idempotent: running `add-device` for an already-registered UUID is safe
- Single command entry point: `install.sh [add-device]`

**Negative:**
- `install.sh add-device` must parse `config.yaml` before writing (requires `load_config()` to be available in install.sh context); this introduces a python3 dependency into install.sh as well as the sync scripts
- Full config rewrite on each registration (not an append): for 2-10 devices this is negligible; at larger scale a targeted YAML merge would be preferable

**Earned Trust (probe):**
- Test: `add-device` with a new UUID → UUID appears in config.yaml usb_devices[]
- Test: `add-device` with an already-registered UUID → config.yaml unchanged, exit 0
- Test: `add-device` with no USB mounted → exits with clear error, config.yaml unchanged
- Test: `add-device` interrupted mid-write → config.yaml.tmp cleaned up, original config.yaml intact
- The atomic write must be verified by the test harness: assert that config.yaml.tmp does not exist after a successful or failed invocation
