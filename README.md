# mac-secure-sync

mac-secure-sync automates one-way sync of designated local directories to one or more UUID-locked USB drives and an encrypted cloud remote (via `rclone`). It is tailored for macOS and driven by the scripts in `bin/`.

## Requirements

- macOS with `launchd`
- `rsync`, `diskutil`, `python3`, `rclone`, and `fdesetup` on your `PATH`
- One or more dedicated USB drives (hardware-encrypted drives like Kingston IronKey D300 are recommended)
- An `rclone` remote that already exists and is reachable (see `docs/rclone-advice.md`)
- Optionally: FileVault enabled to protect local source directories

## How it works

Two independent scripts handle two independent concerns:

| Script | Trigger | What it does |
|--------|---------|--------------|
| `bin/sync-usb.sh` | USB drive mounts (`/Volumes` change) | rsyncs registered directories to the matched drive |
| `bin/sync-cloud.sh` | Hourly timer (launchd `StartInterval`) | rclones each directory to its configured cloud remote |

Both scripts read from a single config file (`~/.config/securelocal/config.yaml`) but operate independently — cloud sync runs on schedule whether or not a USB drive is connected.

## Installation

Run `bin/install.sh`. The installer:

1. Verifies required binaries and warns if FileVault is disabled
2. Prompts for the mounted USB volume name and captures its UUID
3. Asks for the rclone remote per directory (default `remote-crypt:secureLocal`)
4. Writes `~/.config/securelocal/config.yaml` (schema v2)
5. Installs two LaunchAgents:
   - `com.securelocal.usb-sync.plist` — watches `/Volumes`, runs `sync-usb.sh`
   - `com.securelocal.cloud-sync.plist` — fires hourly, runs `sync-cloud.sh`

### Registering additional USB drives

After initial install, add a second drive without re-running the full installer:

```bash
bin/install.sh add-device --volume /Volumes/IronKey-B --label "IronKey-B"
```

This appends the new device to your existing config atomically. Duplicate UUIDs are detected and rejected.

## Configuration

Config lives at `~/.config/securelocal/config.yaml` (written by the installer):

```yaml
schema_version: 2
log_file: ~/Library/Logs/securelocal-sync.log
rclone_bin: /usr/local/bin/rclone
sync_interval_seconds: 3600

directories:
  - local_path: ~/secureLocal
    cloud_remote: remote-crypt:secureLocal
    usb_devices:
      - UUID-OF-IRONKEY-A
      - UUID-OF-IRONKEY-B

usb_devices:
  - id: UUID-OF-IRONKEY-A
    label: IronKey-A (home)
  - id: UUID-OF-IRONKEY-B
    label: IronKey-B (office)
```

Each directory entry carries its own `cloud_remote` and a list of USB device UUIDs it should sync to. USB sync and cloud sync are independent concerns — adding a new USB device does not affect cloud config, and vice versa.

Override `CONFIG_FILE` to point at a different config (useful for testing).

## Exit codes

Both sync scripts use the same exit code contract:

| Code | Meaning |
|------|---------|
| 0 | All syncs succeeded |
| 1 | USB sync failed (one or more directories) |
| 2 | Cloud sync failed (one or more directories) |
| 4 | Configuration error (missing file, wrong schema version, invalid YAML) |

## Logging

Both scripts write structured entries to the log file configured in `config.yaml`:

```
2026-05-17T07:32:01 INFO  sync-usb  ~/secureLocal  rsync started
2026-05-17T07:32:04 INFO  sync-usb  ~/secureLocal  rsync complete (3.1s)
2026-05-17T07:32:04 ERROR sync-cloud ~/Projects    cloud sync failed after 2 attempts
```

To check for failures: `grep ERROR ~/Library/Logs/securelocal-sync.log`

## Manual usage

Run either script directly to sync on demand:

```bash
bin/sync-usb.sh    # syncs any currently-mounted registered USB drives
bin/sync-cloud.sh  # syncs all directories to their cloud remotes
```

To run the acceptance test suite:

```bash
bash tests/acceptance/multi-usb-sync/run-tests.sh
```

The test harness mocks `diskutil`, `rsync`, `rclone`, and `launchctl` — no real hardware required.

To remove the automation:

```bash
bin/uninstall.sh
```

This unloads both LaunchAgents, removes the config, and optionally purges logs.

## Additional docs

- `docs/product/architecture/brief.md` — component map, data flow, port contracts
- `docs/product/architecture/c4-diagrams.md` — C4 System Context and Container diagrams
- `docs/rclone-advice.md` — rclone remote setup and encryption guidance
- `docs/troubleshooting.md` — issue triage notes
- `docs/features.md` — original sync approach and retry strategy notes

## Security reminders

- Keep source directories inside FileVault (install script warns if disabled)
- USB backups are plaintext unless you use a hardware-encrypted drive — treat the device as sensitive
- Cloud data is encrypted only if the rclone remote uses `crypt`; back up `~/.config/rclone/rclone.conf` separately — losing it means losing cloud access
