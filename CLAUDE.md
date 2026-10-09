# mac-secure-sync — Claude Instructions

## Development Paradigm

This project follows a **Bash / FP-leaning** paradigm.

- Pure functions for config loading and validation (no side effects, explicit arguments)
- Separation of concerns: `sync-usb.sh` and `sync-cloud.sh` are fully independent
- Imperative shell at the edges (launchd invocations, rsync, rclone, diskutil, log writes)
- No shared mutable globals between sync scripts

Use `@nw-software-crafter` for implementation tasks.

## Architecture

- Config: `~/.config/securelocal/config.yaml` (schema v2, directories-first)
- YAML parsing: `python3` parse-once at startup via `load_config()`
- USB lifecycle: `install.sh add-device` / `remove-device` / `list-devices` subcommands
- Shared USB-matching: `bin/lib/usb-common.sh` (`find_usb_by_uuid()`), sourced by `install.sh` and `sync-usb.sh` (ADR-004)
- Two launchd triggers: WatchPaths `/Volumes` → `sync-usb.sh`; StartInterval → `sync-cloud.sh`

See `docs/product/architecture/brief.md` for full architecture.
See `docs/product/architecture/c4-diagrams.md` for C4 diagrams.

## Shipped Features

### multi-usb-sync (2026-05-17)
Wave progress: DISCUSS ✓ | DESIGN ✓ | DISTILL ✓ | DELIVER ✓
Evolution: `docs/evolution/2026-05-17-multi-usb-sync.md`
Tests: 38/38 GREEN — `tests/acceptance/multi-usb-sync/run-tests.sh`

### usb-device-lifecycle (2026-09-01)
Wave progress: DISCUSS ✓ | DESIGN ✓ | DISTILL ✓ | DELIVER ✓ (DEVOPS not run — graceful degradation)
Evolution: `docs/evolution/2026-09-01-usb-device-lifecycle.md`
Tests: 49/49 GREEN — `tests/acceptance/usb-device-lifecycle/run-tests.sh` (regression: multi-usb-sync 38/38 GREEN)
Adds `install.sh remove-device`/`list-devices`; extracts `find_usb_by_uuid()` to `bin/lib/usb-common.sh` (ADR-004). Phase 4 adversarial review found and fixed two code-injection vulnerabilities before ship (see evolution doc).

### launchd-environment (2026-10-09)
Fix, direct execution (no waves): `sync-usb.sh` used `declare -A`, which fails under launchd's `/bin/bash` 3.2, so USB sync never ran; one dataless (cloud-evicted) file aborted a whole rsync; launchd's `/usr/bin/python3` lacks PyYAML.
Decisions: `docs/decisions/adr-006-launchd-bash32-and-dataless-files.md`, `docs/decisions/adr-007-pyyaml-check-at-install.md`
Tests: `tests/acceptance/launchd-environment/run-tests.sh` (runs scripts as `env -i ... /bin/bash`)
Adds `bin/lib/dataless.sh`; `sync-usb.sh` skips dataless files and exits 3 "completed with skips"; `install.sh` refuses to continue without PyYAML for launchd's python3.
