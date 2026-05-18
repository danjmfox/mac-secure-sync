# C4 Diagrams — mac-secure-sync

**Feature:** multi-usb-sync
**Wave:** DESIGN
**Date:** 2026-05-15

---

## L1 — System Context

```mermaid
C4Context
  title System Context — mac-secure-sync

  Person(dan, "Dan (builder-user)", "Runs install.sh, registers USB devices, monitors log")

  System(mss, "mac-secure-sync", "Backs up local directories to USB drives and encrypted cloud on macOS. Triggered by USB mount events and a periodic timer.")

  System_Ext(usb, "USB Drives", "IronKey or equivalent. Identified by Volume UUID. Mounted at /Volumes.")
  System_Ext(rclone, "rclone Remote (encrypted)", "Encrypted cloud storage. Accessed via pre-configured rclone remote.")
  System_Ext(launchd, "launchd", "macOS process orchestrator. Watches /Volumes for mount events; fires StartInterval timer.")

  Rel(dan, mss, "Installs and configures via")
  Rel(mss, usb, "Syncs files to via rsync")
  Rel(mss, rclone, "Syncs files to via rclone")
  Rel(launchd, mss, "Triggers on USB mount and timer via")
```

---

## L2 — Container

```mermaid
C4Container
  title Container Diagram — mac-secure-sync

  Person(dan, "Dan (builder-user)")

  Container(install, "install.sh", "Bash", "Interactive setup: checks deps, selects USB, writes config.yaml, installs launchd plists. add-device subcommand registers additional USB drives.")
  Container(syncusb, "sync-usb.sh", "Bash", "USB sync script. Loads config, finds mounted registered USB drives by UUID, rsync each directory to each matched drive.")
  Container(synccloud, "sync-cloud.sh", "Bash", "Cloud sync script. Loads config, rclone sync each directory to its configured remote.")
  ContainerDb(config, "config.yaml", "YAML", "Single source of truth for directories, USB device registry, and runtime settings. Located at ~/.config/securelocal/config.yaml.")
  ContainerDb(log, "securelocal-sync.log", "Append-only text", "Structured log. Written by both sync scripts. Located at ~/Library/Logs/securelocal-sync.log.")
  Container(usbplist, "com.securelocal.usb-sync.plist", "launchd plist", "WatchPaths /Volumes. Fires sync-usb.sh on USB mount/unmount events.")
  Container(cloudplist, "com.securelocal.cloud-sync.plist", "launchd plist", "StartInterval (configurable, default 3600s). Fires sync-cloud.sh on timer.")

  System_Ext(usb, "USB Drives", "Registered by UUID. Mounted at /Volumes.")
  System_Ext(rclone_remote, "rclone Remote", "Encrypted cloud storage.")
  System_Ext(launchd, "launchd", "macOS process orchestrator.")
  System_Ext(python3, "python3 (system)", "YAML parsing. Invoked once at sync script startup.")
  System_Ext(diskutil, "diskutil (system)", "USB Volume UUID lookup.")

  Rel(dan, install, "Runs interactively")
  Rel(install, config, "Writes atomically to")
  Rel(install, usbplist, "Installs and loads")
  Rel(install, cloudplist, "Installs and loads")
  Rel(launchd, usbplist, "Manages")
  Rel(launchd, cloudplist, "Manages")
  Rel(usbplist, syncusb, "Invokes on /Volumes change")
  Rel(cloudplist, synccloud, "Invokes on timer")
  Rel(syncusb, config, "Reads at startup via")
  Rel(synccloud, config, "Reads at startup via")
  Rel(syncusb, python3, "Parses YAML once via")
  Rel(synccloud, python3, "Parses YAML once via")
  Rel(syncusb, diskutil, "Queries Volume UUID via")
  Rel(syncusb, usb, "Syncs directories to via rsync")
  Rel(synccloud, rclone_remote, "Syncs directories to via rclone")
  Rel(syncusb, log, "Appends structured entries to")
  Rel(synccloud, log, "Appends structured entries to")
  Rel(install, log, "Appends install entries to")
```

---

## Notes

- L3 (Component) is not produced. Both sync scripts have fewer than 5 internal functions each; a Component diagram would add no information beyond the Container view and the Component Map in `brief.md`.
- Every arrow is labeled with a verb phrase per the C4 convention.
- Abstraction levels are not mixed: launchd plists are Containers (deployment units), not Components of a script.
