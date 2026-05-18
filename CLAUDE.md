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
- USB registration: `install.sh add-device` subcommand
- Two launchd triggers: WatchPaths `/Volumes` → `sync-usb.sh`; StartInterval → `sync-cloud.sh`

See `docs/product/architecture/brief.md` for full architecture.
See `docs/product/architecture/c4-diagrams.md` for C4 diagrams.

## Shipped Features

### multi-usb-sync (2026-05-17)
Wave progress: DISCUSS ✓ | DESIGN ✓ | DISTILL ✓ | DELIVER ✓
Evolution: `docs/evolution/2026-05-17-multi-usb-sync.md`
Tests: 38/38 GREEN — `tests/acceptance/multi-usb-sync/run-tests.sh`
