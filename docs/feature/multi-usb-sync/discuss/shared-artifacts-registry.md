# Shared Artifacts Registry: multi-usb-sync

Feature ID: `multi-usb-sync`
Date: 2026-05-15

---

## Registry

```yaml
shared_artifacts:

  config_yaml:
    source_of_truth: ~/.config/securelocal/config.yaml
    consumers:
      - sync-usb.sh (reads usb_devices + directories mapping)
      - sync-cloud.sh (reads directories + cloud_remote mapping)
      - installer / registration tool (writes at setup + device registration time)
    owner: config context
    integration_risk: >
      HIGH — if the YAML schema changes without updating both sync scripts, one script
      silently reads stale or empty values. The previous flat config.env had this problem.
      Schema version field (schema_version: 2) is the guard.
    validation: >
      Both sync scripts assert schema_version == 2 at startup.
      If mismatch, exit 4 with: "Config schema version mismatch. Re-run install."

  log_file_path:
    source_of_truth: config.yaml:log_file
    consumers:
      - sync-usb.sh (writes timestamped entries)
      - sync-cloud.sh (writes timestamped entries)
      - Dan (reads via tail/grep for verification)
    owner: config context
    integration_risk: >
      MEDIUM — if two scripts resolve log_file differently, Dan gets split log history.
      Both scripts must read log_file from config.yaml at startup; no hardcoded path.
    validation: >
      Both scripts log their startup line to the same resolved path.
      "grep -c 'USB sync' log && grep -c 'cloud sync' log" both return non-zero.

  usb_uuid:
    source_of_truth: config.yaml:usb_devices[*].id
    consumers:
      - sync-usb.sh (UUID validation against /Volumes at runtime)
      - installer / registration tool (writes at registration time)
    owner: config context
    integration_risk: >
      HIGH — a typo in UUID means the device never matches and sync silently never fires.
      UUID must be written by the registration mechanism (not hand-typed by Dan).
      [DESIGN] The mechanism is deferred to the DESIGN wave.
    validation: >
      Post-registration: diskutil info /Volumes/<label> | grep "Volume UUID" matches
      the value written to config.yaml. Registration tool must verify before writing.

  cloud_remote:
    source_of_truth: config.yaml:directories[*].cloud_remote
    consumers:
      - sync-cloud.sh (rclone target per directory)
    owner: config context
    integration_risk: >
      MEDIUM — wrong remote maps a local directory to the wrong cloud destination.
      Dan sets this at install time; no runtime validation possible without rclone call.
    validation: >
      Installer confirms rclone remote exists (rclone lsd <remote>) before writing to config.

  rclone_bin:
    source_of_truth: config.yaml:rclone_bin
    consumers:
      - sync-cloud.sh (executable invocation)
    owner: config context
    integration_risk: >
      LOW — standard Homebrew path (/usr/local/bin/rclone). Risk if Dan uses a non-standard
      install location.
    validation: >
      Installer writes the resolved path from `which rclone`. sync-cloud.sh asserts
      the binary exists and is executable at startup.

  exit_codes:
    source_of_truth: docs/feature/multi-usb-sync/discuss/journey-multi-usb-sync.yaml (decision log)
    consumers:
      - sync-usb.sh (exit contract)
      - sync-cloud.sh (exit contract)
      - launchd (reads exit code for SuccessfulExit / error handling)
      - Dan (manual diagnosis)
    owner: sync orchestration context
    integration_risk: >
      MEDIUM — inconsistent exit codes across scripts make launchd error detection ambiguous.
      Contract: 0=success, 1=USB fail, 2=cloud fail, 3=both fail, 4=config error.
    validation: >
      Exit code contract tested by test harness (mocked rsync/rclone). Each script
      exits the documented code for each failure scenario.

  launchd_plist_usb:
    source_of_truth: ~/Library/LaunchAgents/com.securelocal.usb-sync.plist
    consumers:
      - launchd (loads on login, fires on /Volumes change)
      - sync-usb.sh (invoked by plist)
    owner: sync orchestration context
    integration_risk: >
      HIGH — if plist is not loaded, USB sync never fires and Dan has no signal.
      Install script must run: launchctl load <plist>.
    validation: >
      After install: launchctl list | grep com.securelocal.usb-sync returns a row.

  launchd_plist_cloud:
    source_of_truth: ~/Library/LaunchAgents/com.securelocal.cloud-sync.plist
    consumers:
      - launchd (loads on login, fires on StartInterval)
      - sync-cloud.sh (invoked by plist)
    owner: sync orchestration context
    integration_risk: >
      HIGH — plist not loaded means cloud sync never fires without USB dependency
      (the original problem this feature solves).
    validation: >
      After install: launchctl list | grep com.securelocal.cloud-sync returns a row.
```

---

## Integration Risk Summary

| Artifact | Risk Level | Primary Risk |
|----------|-----------|--------------|
| config_yaml | HIGH | Schema mismatch between scripts |
| usb_uuid | HIGH | Typo in UUID → sync silently never fires |
| launchd_plist_usb | HIGH | Not loaded → USB sync never fires |
| launchd_plist_cloud | HIGH | Not loaded → cloud sync never fires |
| log_file_path | MEDIUM | Split log → incomplete visibility |
| cloud_remote | MEDIUM | Wrong remote → data in wrong destination |
| exit_codes | MEDIUM | Inconsistency → ambiguous failure diagnosis |
| rclone_bin | LOW | Non-standard install path |
