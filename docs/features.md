# Technical approach

## 1. USB detection via UUID

- Install script captures UUID with `diskutil info /Volumes/YourDrive | grep "Volume UUID"`
- launchd watches `/Volumes` with WatchPaths
- Sync script validates correct USB is mounted by checking UUID matches before proceeding
- Falls back gracefully if wrong/no USB present

## 2. USB rsync - preserve deletions

```bash
rsync -avh --ignore-errors ~/secureLocal/ /Volumes/YourDrive/secureLocal/
```

No `--delete` flag, so deleted local files stay on USB as hi storical safety net.

## ## 3. Cloud rclone - mirror

```bash
rclone sync ~/secureLocal remote-crypt:secureLocal --log-file ~/Library/Logs/securelocal-sync.log
```

Cloud is authoritative mirror of current state.

## 4. Retry logic

Simple approach - if rsync or rclone fails, wait 30s and try once more. Log attempt numbers. Exit with meaningful codes (0=success, 1=USB fail, 2=cloud fail, 3=both fail).

## 5. Encryption documentation

README section covering:

- Local: relies on FileVault (user responsibility)
  - USB: unencrypted by default - recommend Kingston IronKeyD300 or similar hardware-encrypted drives
- Cloud: encrypted via rclone crypt - strong password needed,document where config lives (`~/.config/rclone/rclone.conf`) and importance of backing that up separately
- Make clear: if someone gets your USB, they get plaintext unless you use encrypted USB

## Additional thought

- Should the install script offer to create a backup of the rclone config somewhere safe? Or just warn them heavily to back it up? Losing that password = losing cloud access entirely.

## Sync Script: Key features

### Robustness

- UUID-based USB detection (iterates through /Volumes)
- Retry logic with 30s delay between attempts
- Clear exit codes (0=all good, 1=USB fail, 2=cloud fail, 3=both fail, 4=config error)

### Logging

- Timestamps on everything
- Separate error logging to stderr
- rclone writes to same log file

### Safety

- `set -euo pipefail` for strict error handling
- Validates config before attempting syncs
- Creates USB target directory if missing
- Full path to rclone (launchd PATH issue workaround)

### What it needs from installer

- Environment vars or a config file to set LOCAL_DIR, USB_UUID, USB_BACKUP_PATH, RCLONE_REMOTE
- rclone installed at /usr/local/bin/rclone (standard homebrew location)

### Potential improvements for later

- Config file support (source from ~/.config/securelocal-sync/config)

## Test Script

### Configuration validation

- Missing USB_UUID
- Missing LOCAL_DIR
- Missing rclone binary

### USB detection

- USB not found
- UUID matching (ignores wrong UUIDs)

### Sync scenarios

- Successful sync (exit 0)
- USB failure only (exit 1)
- Cloud failure only (exit 2)
- Both fail (exit 3)

### Functionality

- Log file creation
- Files actually copied
- Backup path auto-created

### How it works

- Creates isolated test environment in temp directory
- Mocks `diskutil`, `rsync`, and `rclone` for controlled testing
- No actual USB or cloud access needed
- Cleans up after each test

### To run

```bash
chmod +x test-sync-script.sh
./test-sync-script.sh
```

### Limitations

- Doesn't test retry logic timing (would need to mock sleep or be very slow)
- Doesn't test actual rclone encryption (needs real rclone config)
- Mock `diskutil` is simplified (real one has more complex output)
