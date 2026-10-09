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

### backup-path-handling (2026-10-08)
Fix, direct execution (no waves): the installer's rclone.conf backup prompt expanded no `~`, so "~/crypt-backup" created a literal `~` directory under the cwd holding OAuth token and crypt passwords.
Decision: `docs/decisions/adr-005-backup-path-normalisation.md`
Tests: 8/8 GREEN — `tests/acceptance/backup-path-handling/run-tests.sh` (regression: multi-usb-sync 42/42, usb-device-lifecycle 49/49)
Adds `normalise_backup_path()` to `install.sh`; `install.sh` runs `main` only when executed, not when sourced.
