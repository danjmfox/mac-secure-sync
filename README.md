# mac-secure-sync

mac-secure-sync automates a one-way sync of your trusted `~/secureLocal` folder to both a UUID-locked USB drive and an encrypted cloud remote (via `rclone`). It is tailored for macOS and is driven by the scripts in `bin/`.

## Requirements

- macOS with `launchd` (the installer registers a LaunchAgent to trigger on `/Volumes` changes).
- `rsync`, `diskutil`, `rclone`, and `fdesetup` on your `PATH`.
- A dedicated USB drive (hardware encrypted drives like Kingston IronKey D300 are recommended) whose UUID you control.
- An `rclone` remote that already exists and is reachable (see `docs/rclone-advice.md`).
- Optionally: FileVault enabled on your Mac to protect the local `~/secureLocal` directory.

## Installation

1. Run `bin/install.sh`. The installer:
   - verifies the required binaries and warns if FileVault is disabled;
   - prompts for the mounted USB volume name and captures its UUID;
   - asks for or defaults the `rclone` remote (default `remote-crypt:secureLocal`);
   - offers to back up `~/.config/rclone/rclone.conf` securely;
   - writes the runtime config to `~/.config/securelocal/config.env`;
   - installs `~/Library/LaunchAgents/com.securelocal.sync.plist` which watches `/Volumes`.
2. The LaunchAgent runs `sync-to-usb-and-cloud.sh` every time `/Volumes` changes, ensuring the latest files flow to the USB and the encrypted remote, with retry logic, logging, and strict exit codes.

## Configuration

`bin/sync-to-usb-and-cloud.sh` loads `CONFIG_FILE` (defaults to `~/.config/securelocal/config.env`). The installer seeds the following variables:

- `LOCAL_DIR`: `~/secureLocal`
- `USB_UUID`: the locked UUID of your USB (install-time detected)
- `USB_MOUNT_BASE`: usually `/Volumes`
- `USB_BACKUP_PATH`: path under the USB mount (`secureLocal`)
- `RCLONE_REMOTE`: e.g. `remote-crypt:secureLocal`
- `LOG_FILE`: `~/Library/Logs/securelocal-sync.log`

You can override `CONFIG_FILE` by exporting it before invoking the script manually.

## How it works

`sync-to-usb-and-cloud.sh`:

- verifies the config, the local folder, and that `rclone` is executable;
- scans `/Volumes` for the configured USB UUID before attempting an `rsync` (USB) or `rclone sync` (cloud);
- retries each operation twice with 30s backoff and logs to `LOG_FILE`;
- exits with 0 for success, 1 for USB failure, 2 for cloud failure, 3 if both fail, or 4 for configuration issues.

Logs live under `~/Library/Logs/securelocal-sync.log`, and every major step timestamps itself there.

## Manual usage

- To dry-run or debug: execute `bin/sync-to-usb-and-cloud.sh` manually after exporting `CONFIG_FILE`.
- To test the sync logic without touching real hardware: run `chmod +x bin/test-sync-script.sh && bin/test-sync-script.sh`. The test harness mocks `diskutil`, `rsync`, and `rclone`, covering config validation, USB detection, and exit-code expectations.
- To remove the automation: run `bin/uninstall.sh` and follow the prompts (it unloads the LaunchAgent, deletes the config, and optionally purges logs).
- To confirm everything is gone: `bin/verify-uninstall.sh [--clean-logs]`.

## Additional docs

- `docs/features.md`: high-level sync approach, retry strategy, logging, and encryption guidance.
- `docs/rclone-advice.md`: step-by-step rclone remote setup and encryption guidance.
- `docs/troubleshooting.md`: placeholder for future issue triage notes (add problems/solutions here as they arise).

## Continuous analysis

- GitHub Actions runs a SonarCloud scan on pushes to `main` and pull requests via `.github/workflows/sonarcloud.yml`.
- Set repository secrets `SONAR_TOKEN`, `SONAR_ORGANIZATION`, and `SONAR_PROJECT_KEY` so the workflow can authenticate and associate reports with your SonarCloud project (the scan currently targets `bin` and `docs`).

## Security reminders

- Keep `~/secureLocal` inside FileVault (install script already reminds you).
- USB backups are plaintext unless you use an encrypted drive—treat the hardware as sensitive.
- `rclone` data is encrypted only if the remote uses `crypt`; back up `~/.config/rclone/rclone.conf` and its passwords separately.

## Next steps

1. Review `docs/` if you need more detail on the encryption workflow or remote setup.
2. Run the installer on the target Mac and confirm the LaunchAgent is watching `/Volumes`.
3. Monitor `~/Library/Logs/securelocal-sync.log` during the first few syncs to ensure both USB and cloud jobs complete.
