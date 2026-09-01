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

  Container(install, "install.sh", "Bash", "Interactive setup: checks deps, selects USB, writes config.yaml, installs launchd plists. add-device registers, remove-device deregisters, list-devices enumerates USB drives.")
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

## L3 — Component (install.sh subcommands + shared USB matching)

**Feature:** usb-device-lifecycle (2026-08-24)

Produced for this subsystem only: `install.sh` now dispatches to 3 subcommands plus its interactive install flow, and introduces the project's first cross-container shared library (ADR-004). This crosses the "5+ components" / cross-container-reuse threshold that the L2 view cannot show without mixing abstraction levels.

```mermaid
C4Component
  title Component Diagram — install.sh Subcommands and Shared USB Matching

  Container_Boundary(install, "install.sh") {
    Component(main_flow, "main() / install flow", "Bash", "Interactive install: dependency checks, FileVault check, volume select, config write, plist install")
    Component(cmd_add, "cmd_add_device()", "Bash", "Registers a USB device: diskutil UUID lookup, duplicate check, atomic config write")
    Component(cmd_remove, "cmd_remove_device()", "Bash", "Deregisters a device by --label or --uuid: removes from usb_devices[] and every directory mapping, atomic config write")
    Component(cmd_list, "cmd_list_devices()", "Bash", "Enumerates registered devices with live mount state")
  }

  Component(usb_common, "usb-common.sh", "Bash library", "find_usb_by_uuid(uuid, volumes_base) — pure query function. No side effects on source.")
  Container(syncusb, "sync-usb.sh", "Bash", "USB sync script (existing container, unchanged behavior)")
  System_Ext(diskutil, "diskutil (system)", "Volume UUID lookup")

  Rel(cmd_list, usb_common, "Sources and calls find_usb_by_uuid() from")
  Rel(syncusb, usb_common, "Sources and calls find_usb_by_uuid() from")
  Rel(usb_common, diskutil, "Queries Volume UUID via")
  Rel(cmd_remove, cmd_add, "Mirrors atomic temp-rename write pattern of (ADR-003)")
```

See ADR-004 for the reuse decision and rejected alternatives.

## Notes

- L1/L2 container topology is unchanged by usb-device-lifecycle: same containers, extended `install.sh` behavior. `bin/lib/usb-common.sh` is a source-time library, not a deployment unit, so it appears only at L3, not as a new L2 container.
- L3 (Component) was previously not produced (both sync scripts had fewer than 5 internal functions). It is now produced for the `install.sh` subsystem only, per the 5+ components / cross-container-reuse trigger.
- Every arrow is labeled with a verb phrase per the C4 convention.
- Abstraction levels are not mixed: launchd plists are Containers (deployment units), not Components of a script.
