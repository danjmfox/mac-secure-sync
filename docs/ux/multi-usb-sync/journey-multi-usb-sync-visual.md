# Journey: Multi-USB Sync — Visual Map

Feature ID: `multi-usb-sync`
Persona: Dan Fox (builder-user)
Date: 2026-05-15

---

## Emotional Arc

```
SETUP                    REGULAR USE              FAILURE/RECOVERY
Confident but cautious   Low-awareness (silent)   Alert → Methodical
"Does this actually      "I haven't thought        "Something went wrong.
 work for both drives?"   about this in weeks."    What? Can I trust it?"
        |                        |                         |
   [verify each step]    [trust the automation]    [clear signal + fix path]
```

---

## Happy Path: USB Sync (Dan's USB-A mounts at home)

```
[USB-A mounts]      [launchd fires]     [UUID matched]      [rsync runs]        [log written]
/Volumes changes    WatchPaths trigger   USB-A UUID found    ~/secureLocal →     timestamps +
detected            sync-usb.sh called  in config; dirs     /Volumes/USB-A/     exit 0 logged
                                        resolved             secureLocal/
  Feels:              Feels:              Feels:              Feels:              Feels:
  Unaware             Unaware             [invisible]         [invisible]         [invisible unless
  (daily work)        (automation)                                                 checking log]
```

```
[USB-B mounts]      [launchd fires]     [UUID matched]      [rsync runs]        [log written]
(office drive)      sync-usb.sh called  USB-B UUID found    same ~/secureLocal   separate entry,
/Volumes changes    (same script)       in config; same     → /Volumes/USB-B/    same log file
                                        dir list resolved   secureLocal/
```

**Key insight**: Dan's directories don't change based on which USB is plugged in — both drives get the same content. The device determines the *target mount point*, not the *source directories*.

---

## Happy Path: Cloud Sync (launchd hourly timer)

```
[launchd timer]     [sync-cloud.sh]     [dirs resolved]     [rclone runs]       [log written]
StartInterval       fires hourly        reads config:        each dir →          timestamps +
fires               regardless of       dir → cloud_remote   its cloud_remote    exit 0 logged
                    USB presence        mapping                                   (or exit 2)

  Feels:              Feels:              Feels:              Feels:              Feels:
  Unaware             Unaware             [invisible]         [invisible]         [invisible unless
  (could be sleeping) (background)                                                 checking log]
```

**Key insight**: Cloud sync never waits for USB. Dan's data is in the cloud even when both USB drives are at the office.

---

## TUI Mockup: USB Sync Script Output (stdout when run manually)

```
$ sync-usb.sh --verbose

securelocal-usb-sync v2.0
Config: ~/.config/securelocal/config.yaml
USB device: USB-A (UUID: 1A2B-3C4D) [MOUNTED at /Volumes/IronKey-A]

[1/2] Syncing ~/secureLocal → /Volumes/IronKey-A/secureLocal ... done (2.3s)
[2/2] Syncing ~/Projects → /Volumes/IronKey-A/Projects ...     done (0.8s)

Result: 2/2 directories synced successfully
Log:    ~/Library/Logs/securelocal-sync.log
Exit:   0
```

---

## TUI Mockup: Cloud Sync Script Output (stdout when run manually)

```
$ sync-cloud.sh --verbose

securelocal-cloud-sync v2.0
Config: ~/.config/securelocal/config.yaml

[1/2] Syncing ~/secureLocal → remote-crypt:secureLocal ... done (8.1s)
[2/2] Syncing ~/Projects    → remote-crypt:Projects    ... done (12.4s)

Result: 2/2 directories synced successfully
Log:    ~/Library/Logs/securelocal-sync.log
Exit:   0
```

---

## TUI Mockup: New Config Schema (YAML, not env vars)

```yaml
# ~/.config/securelocal/config.yaml
schema_version: 2

log_file: ~/Library/Logs/securelocal-sync.log
rclone_bin: /usr/local/bin/rclone

directories:
  - local_path: ~/secureLocal
    cloud_remote: remote-crypt:secureLocal
    usb_devices:
      - UUID-A
      - UUID-B

  - local_path: ~/Projects
    cloud_remote: remote-crypt:Projects
    usb_devices:
      - UUID-A
      - UUID-B

usb_devices:
  - id: UUID-A
    label: IronKey-A (home)
  - id: UUID-B
    label: IronKey-B (office)
```

---

## Error Path: USB Not Present

```
[launchd fires]     [UUID scan]         [no match]          [log + exit]
WatchPaths trigger  iterates /Volumes   neither UUID found  "USB not mounted"
(other volume)      for registered      (expected — other   logged, exit 0
                    UUIDs               volume change)       (not an error)
```

**Design note**: A non-matching USB mount is NOT an error — it is the normal case when Dan mounts an external hard drive or USB key for other purposes. Script exits 0 silently.

---

## Error Path: Cloud Sync Failure (network down)

```
[launchd timer]     [sync-cloud.sh]     [rclone fails]      [retry]             [log + exit 2]
fires hourly        runs               network refused      wait 30s, retry     "Cloud sync failed"
                                                            once more; fails     logged, exit 2
                                                            again
  Feels:              Feels:              Feels:              Feels:              Feels:
  Unaware             Unaware             [invisible]         [invisible]         Alert if checking
                                                                                  log; silent otherwise
```

---

## Error Path: Config Missing or Malformed

```
[script fires]      [config load]       [validation fails]  [exit 4]
either trigger      reads config.yaml   required field       "Config error: ..."
                                        missing or invalid   logged stderr + exit 4
```

---

## Error Path: Partial Directory Failure

```
[USB sync]          [dir 1 succeeds]    [dir 2 fails]       [log + exit 1]
rsync runs          ~/secureLocal ok    ~/Projects rsync    "2/3 dirs succeeded.
all dirs for                            error               Dir 2 failed: ..."
device                                                       logged, exit 1
```

---

## Integration Checkpoints

| Checkpoint | What must hold |
|------------|----------------|
| Config schema v2 | All scripts read the same config.yaml; no script reads old config.env |
| UUID→dirs mapping | USB sync script correctly resolves which dirs to sync for the mounted UUID |
| dirs→remote mapping | Cloud sync script correctly resolves which remote each dir targets |
| Log file | Both scripts write to the same log file with consistent timestamp format |
| Exit codes | Both scripts use the agreed exit code contract (0/1/2/3/4) |
| launchd plists | USB plist uses WatchPaths `/Volumes`; cloud plist uses `StartInterval` |

---

## Shared Artifacts

| Artifact | Source | Consumers |
|----------|--------|-----------|
| `config.yaml` | `~/.config/securelocal/config.yaml` | USB sync script, cloud sync script, installer |
| `log_file` path | `config.yaml:log_file` | Both sync scripts, operator (tail/grep) |
| `rclone_bin` path | `config.yaml:rclone_bin` | Cloud sync script |
| USB UUID | `config.yaml:usb_devices[*].id` | USB sync script (UUID validation) |
| `cloud_remote` | `config.yaml:directories[*].cloud_remote` | Cloud sync script |
| `usb_devices` list on dir | `config.yaml:directories[*].usb_devices` | USB sync script (dir filtering) |
