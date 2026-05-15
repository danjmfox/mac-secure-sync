# ADR-001: Config Schema v2 — YAML, Directories-First Model

**Status:** Accepted
**Date:** 2026-05-15
**Deciders:** Dan Fox (principal), Morgan (solution-architect)

---

## Context

The existing system uses a flat `config.env` file (shell key=value format) with a single USB UUID, a single local directory, and a single rclone remote. This format cannot represent N USB devices or M directories with per-directory cloud remotes without a naming scheme that becomes unmaintainable (e.g., `JOB_1_USB_UUID`, `JOB_2_USB_UUID`).

The multi-usb-sync feature introduces:
- Multiple USB devices, each identified by Volume UUID
- Multiple local directories, each with its own cloud remote and its own list of USB devices that should receive it
- A sync_interval_seconds setting for the cloud sync timer

The config model must be human-readable (Dan edits it directly), machine-parseable by a Bash script, and safe to write atomically (concurrent script invocations must not read a partial write).

---

## Decision

Adopt YAML as the config format (v2), replacing `config.env`. The data model uses a **directories-first** structure for cloud sync mapping and a **device-first** structure for the USB device registry. Both live in a single file at `~/.config/securelocal/config.yaml`.

```yaml
schema_version: 2
log_file: ~/Library/Logs/securelocal-sync.log
rclone_bin: /usr/local/bin/rclone
sync_interval_seconds: 3600

directories:
  - local_path: ~/secureLocal
    cloud_remote: remote-crypt:secureLocal
    usb_devices: [UUID-A, UUID-B]

  - local_path: ~/Projects
    cloud_remote: remote-crypt:Projects
    usb_devices: [UUID-A, UUID-B]

usb_devices:
  - id: UUID-A
    label: IronKey-A (home)
  - id: UUID-B
    label: IronKey-B (office)
```

The `schema_version` field enables future format migration detection without parsing the rest of the file.

---

## Alternatives Considered

### Option A (Rejected): Extended flat env file with JOB_N_* namespace

```
JOB_1_LOCAL_DIR=~/secureLocal
JOB_1_CLOUD_REMOTE=remote-crypt:secureLocal
JOB_1_USB_UUIDS=UUID-A,UUID-B
JOB_2_LOCAL_DIR=~/Projects
...
USB_DEVICE_UUID_A_LABEL=IronKey-A (home)
```

Rejected because: human-unreadable at more than 2 jobs; requires custom parser for array values (CSV splitting); no standard tooling; adding a new directory requires knowing the next available JOB_N index; no structural validation possible.

### Option B (Rejected): TOML

```toml
[[directories]]
local_path = "~/secureLocal"
cloud_remote = "remote-crypt:secureLocal"
usb_devices = ["UUID-A", "UUID-B"]
```

Rejected because: no TOML parser present on macOS system by default; would require Homebrew dependency (python3-toml or go binary); YAML is strictly more widely known to the target user; `python3` with `PyYAML` is available via system python3 on macOS 12+.

### Option C (Rejected): JSON

Rejected because: JSON does not support comments (Dan will want to annotate entries); no trailing comma tolerance; visual noise for nested structures; human-editability is worse than YAML for this use case.

---

## Consequences

**Positive:**
- Human-readable and human-editable; structure is self-documenting
- Supports N devices and M directories with a clean data model
- `schema_version` field enables future migration detection
- `sync_interval_seconds` is configurable without editing plist XML
- Single file: one place to inspect the full system state

**Negative:**
- YAML requires a parser (python3); Bash cannot parse it natively
- Indentation-sensitive; malformed YAML produces cryptic python3 errors (mitigated by `load_config()` error handling)
- Config file must be written atomically (temp-rename pattern) to prevent partial reads during script execution

**Mitigations:**
- `load_config()` wraps the python3 call and surfaces a structured error message on parse failure
- Atomic write pattern is mandated in `install.sh` and `add-device` subcommand (see ADR-003)
- `schema_version` check in `load_config()` will reject v1 files with a clear upgrade message
