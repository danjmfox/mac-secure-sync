# Shared Artifacts Registry: usb-device-lifecycle

Feature ID: `usb-device-lifecycle`

No new artifacts are introduced by this feature. Both new commands consume and mutate artifacts already established as the single source of truth by `multi-usb-sync` (ADR-001). This registry extends the existing consumer lists.

```yaml
shared_artifacts:
  usb_devices_registry:
    source_of_truth: "~/.config/securelocal/config.yaml : usb_devices[]"
    consumers:
      - "install.sh add-device (writes)"
      - "install.sh remove-device (writes) — NEW"
      - "install.sh list-devices (reads) — NEW"
      - "sync-usb.sh find_usb_by_uuid() (reads)"
    owner: "usb-device-lifecycle + multi-usb-sync (shared)"
    integration_risk: "HIGH — a mismatch between what remove-device deletes and what sync-usb.sh matches against would silently stop syncing a device Dan thinks is still registered, or vice versa"
    validation: "remove-device and list-devices UUID matching must reuse the same lookup convention as sync-usb.sh:find_usb_by_uuid() — no independent re-implementation"

  directory_usb_mapping:
    source_of_truth: "~/.config/securelocal/config.yaml : directories[*].usb_devices[]"
    consumers:
      - "install.sh add-device (appends UUID to every directory)"
      - "install.sh remove-device (strips UUID from every directory) — NEW"
      - "sync-usb.sh (reads, per-directory UUID match)"
    owner: "multi-usb-sync (unchanged ownership)"
    integration_risk: "HIGH — remove-device must strip the UUID from every directory that references it, or sync-usb.sh will keep attempting to sync to a mount point that will never appear (registered but removed device)"
    validation: "Acceptance test: after remove-device, grep the removed UUID across the full config.yaml (both usb_devices[] and every directories[*].usb_devices[]) — zero occurrences"

  mounted_state:
    source_of_truth: "live /Volumes scan via diskutil — NOT persisted in config.yaml"
    consumers:
      - "install.sh list-devices (reads, displays) — NEW"
      - "sync-usb.sh find_usb_by_uuid() (reads, matches)"
    owner: "usb-device-lifecycle (new consumer) + multi-usb-sync (original owner of the lookup logic)"
    integration_risk: "MEDIUM — mounted_state is inherently point-in-time; list-devices' output is a snapshot, not a guarantee, same caveat that already applies to sync-usb.sh's own mount detection"
    validation: "list-devices and sync-usb.sh must call the same UUID-to-mount-path resolution logic; test harness mocks diskutil identically for both"

  config_atomic_write_pattern:
    source_of_truth: "ADR-003 temp-rename pattern (config.yaml.tmp -> config.yaml)"
    consumers:
      - "install.sh add-device (established)"
      - "install.sh remove-device (reused) — NEW"
    owner: "multi-usb-sync (pattern), usb-device-lifecycle (new user of the pattern)"
    integration_risk: "HIGH — any write to config.yaml that skips the atomic pattern risks a sync script reading a partial file mid-write"
    validation: "Acceptance test: interrupt remove-device mid-write, assert config.yaml.tmp is cleaned up and original config.yaml is intact (mirrors the existing add-device test from ADR-003)"
```

## Validation Summary

- Every `${variable}` in the journey TUI mockups has a documented source above.
- No consumer hardcodes a value that should reference `config.yaml` — both new commands read/write through the same file.
- `list-devices` and `sync-usb.sh` sharing UUID-matching logic (not reimplementing it) is the single highest-risk integration point in this feature; flagged for DESIGN wave attention as a REUSE candidate (see ADR-003's own Reuse Analysis pattern).
