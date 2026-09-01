<!-- markdownlint-disable MD024 -->
# User Stories: usb-device-lifecycle

Feature ID: `usb-device-lifecycle`
Date: 2026-08-24
Analyst: Luna (nw-product-owner)
Jobs traced: JOB-003 (confident-decommissioner, `docs/product/jobs.yaml`)
Extends: `multi-usb-sync` (shipped, `docs/evolution/2026-05-17-multi-usb-sync.md`)

---

## System Constraints

- macOS only; extends `install.sh` (same file as `add-device`, ADR-003)
- Config location: `~/.config/securelocal/config.yaml` (schema v2)
- All config writes use the atomic temp-rename pattern (ADR-003): write `config.yaml.tmp`, then `mv` to `config.yaml`
- UUID matching for both new commands must reuse `sync-usb.sh`'s `find_usb_by_uuid()` convention — no independent re-implementation (see `shared-artifacts-registry.md`)
- Exit codes: extend the existing convention (0=success, 2=usage/not-found error, 4=config error) — never repurpose 1/3 (reserved for sync-usb.sh/sync-cloud.sh partial-failure semantics)
- `directories[]` themselves are never removed or reordered by device lifecycle commands — only `usb_devices[]` entries and directory-level `usb_devices` list membership change

---

## US-101: Remove USB Device

### Elevator Pitch
- **Before**: Dan's IronKey-C travel drive was lost. `config.yaml` still lists it in `usb_devices[]` and in both directories' `usb_devices` arrays. `add-device` only appends — there is no supported way to remove a stale entry short of hand-editing YAML and risking a syntax error or, worse, deleting the wrong device's block.
- **After**: Running `install.sh remove-device --label "IronKey-C (travel)"` removes the device from `usb_devices[]`, strips its UUID from every directory's `usb_devices` list, and confirms exactly what changed — with an atomic write, mirroring `add-device`'s own safety guarantees in reverse.
- **Decision enabled**: Dan can retire a lost, broken, or replaced USB drive and trust that his config accurately reflects only the devices he actually owns, without fear of breaking his working sync setup.

### Problem
Dan Fox is the sole operator of mac-secure-sync. His IronKey-C travel drive was lost on a trip. `config.yaml` still references it in `usb_devices[]` and in both `~/secureLocal` and `~/Projects`'s `usb_devices` lists. There is no supported way to deregister it — `add-device` (ADR-003) only ever appends. Hand-editing the YAML risks breaking indentation or, worse, deleting the wrong device's entry by mistake.

### Who
- Dan Fox | macOS, single machine, personal use | Needs to deregister a USB device he may no longer have physical access to, without touching any other device's config or the `directories[]` list itself

### Solution
A `remove-device` subcommand on `install.sh` (sibling to `add-device`, same flag-style conventions) that accepts `--label <name>` or `--uuid <uuid>`, locates the matching `usb_devices[]` entry, removes it, strips the UUID from every `directories[*].usb_devices` list, and writes the result atomically using the same temp-then-rename pattern as `add-device`.

### Domain Examples

#### 1: Happy Path — Remove IronKey-C by Label
Dan runs `install.sh remove-device --label "IronKey-C (travel)"`. Config had 3 devices (IronKey-A, IronKey-B, IronKey-C) across 2 directories, each mapped to all three UUIDs. After removal: `usb_devices[]` has exactly 2 entries (IronKey-A, IronKey-B). Both directories' `usb_devices` lists no longer include UUID `9C0D-1E2F`. IronKey-A and IronKey-B's entries are byte-for-byte unchanged. Output confirms "2 devices remain registered."

#### 2: Edge Case — Remove by UUID Instead of Label
IronKey-C isn't mounted (it's lost), but Dan has the UUID noted from an old `list-devices` run. He runs `install.sh remove-device --uuid 9C0D-1E2F`. Removal succeeds identically to removal by label — same config mutation, same confirmation output.

#### 3: Boundary — Removing the Last Device Mapped to a Directory
Dan had `~/Projects` mapped only to IronKey-C (not to IronKey-A or IronKey-B). After `remove-device --label "IronKey-C (travel)"`, `~/Projects`'s `usb_devices` list becomes `[]` — empty, not an error. `sync-usb.sh` already treats "no matched UUID for this directory" as a silent no-op (established behavior from US-002 in `multi-usb-sync`); cloud sync (US-003) is entirely unaffected since it doesn't consult `usb_devices` at all.

#### 4: Error/Boundary — Unknown Label
Dan mistypes `--label "IronKey-Z"`. The tool exits non-zero: `"No registered device matches label 'IronKey-Z'. Run install.sh list-devices to see registered devices."` `config.yaml` is completely unmodified.

### UAT Scenarios (BDD)

#### Scenario: Removing a device by label leaves other devices unchanged
```gherkin
Given config.yaml has 3 registered devices: IronKey-A (1A2B-3C4D), IronKey-B (5E6F-7A8B), IronKey-C (9C0D-1E2F)
When Dan runs install.sh remove-device --label "IronKey-C (travel)"
Then usb_devices[] contains only IronKey-A and IronKey-B
And IronKey-A's and IronKey-B's entries are byte-for-byte identical to before removal
And the command output confirms "2 devices remain registered"
```

#### Scenario: Removing a device strips its UUID from every directory mapping
```gherkin
Given config.yaml has ~/secureLocal and ~/Projects, both listing IronKey-C's UUID (9C0D-1E2F) in usb_devices
When Dan runs install.sh remove-device --label "IronKey-C (travel)"
Then neither ~/secureLocal's nor ~/Projects's usb_devices list contains 9C0D-1E2F
And directories[] itself still contains both directory entries (only the UUID reference is removed)
```

#### Scenario: Removing a device by UUID works identically to removing by label
```gherkin
Given IronKey-C (UUID 9C0D-1E2F) is registered and not currently mounted
When Dan runs install.sh remove-device --uuid 9C0D-1E2F
Then IronKey-C is removed from usb_devices[] and every directory mapping
And the outcome is identical to removal by --label "IronKey-C (travel)"
```

#### Scenario: Removing the only USB device mapped to a directory leaves an empty list, not an error
```gherkin
Given ~/Projects's usb_devices list contains only IronKey-C's UUID
When Dan runs install.sh remove-device --label "IronKey-C (travel)"
Then ~/Projects's usb_devices list is an empty array
And the command exits 0 (not an error)
And a subsequent sync-usb.sh run treats ~/Projects as having no matched device (silent no-op, per existing US-002 behavior)
```

#### Scenario: Attempting to remove an unregistered label leaves config.yaml untouched
```gherkin
Given config.yaml does not contain any device labeled "IronKey-Z"
When Dan runs install.sh remove-device --label "IronKey-Z"
Then the command exits non-zero
And config.yaml is byte-for-byte unchanged
And the error message names install.sh list-devices as the recovery step
```

### Acceptance Criteria
- [ ] `remove-device` accepts `--label <name>` or `--uuid <uuid>` (at least one required, mutually exclusive)
- [ ] On match, the device's entry is removed from `usb_devices[]`
- [ ] On match, the device's UUID is stripped from every `directories[*].usb_devices` list
- [ ] Every other `usb_devices[]` entry remains byte-for-byte unchanged after removal
- [ ] A directory left with an empty `usb_devices: []` list is valid — command exits 0, not an error
- [ ] On no match, the command exits non-zero, `config.yaml` is completely unmodified, and the error names `list-devices` as the recovery step
- [ ] Config write uses the atomic temp-rename pattern (ADR-003) — an interrupted write never leaves `config.yaml` partial
- [ ] Command output confirms the device removed and the count of devices remaining registered

### Outcome KPIs
- **Who**: Dan Fox (sole operator)
- **Does what**: Removes a retired/lost USB device from config.yaml without disturbing any other device or directory entry
- **By how much**: 0 unintended mutations to other `usb_devices[]` entries across all removals (100% isolation) — directly mirrors JOB-002's original anxiety ("adding device 2 could accidentally overwrite device 1"), now verified in reverse
- **Measured by**: Acceptance test assertion (byte-for-byte diff of untouched entries) + config.yaml.tmp cleanup verification on interrupted writes
- **Baseline**: Today, removal requires manual YAML editing with no safety net — 0% of removals are currently verifiable as safe

### Technical Notes
- Reuse the atomic write pattern and python3 YAML manipulation approach established in `install.sh:cmd_add_device()` (ADR-003) — mirror its structure for `cmd_remove_device()`
- UUID/label matching must be consistent with how `add-device`'s duplicate-check reads `usb_devices[]` (same `id`/`label` field names)
- Extend `bin/test-sync-script.sh` (or its successor test harness) with remove-device mocks: known-UUID removal, unknown-label rejection, last-device-in-directory boundary — same mock-binary-in-temp-PATH pattern used for `add-device` tests
- Exit code 2 for "no match found" / usage errors, exit 4 reserved for config schema/read errors (consistent with existing convention)

### job_id: JOB-003

---

## US-102: List Registered USB Devices

### Elevator Pitch
- **Before**: The only way to see what's registered is opening `config.yaml` in a text editor and parsing YAML by eye — and even then, the static file can't show whether a device is currently plugged in.
- **After**: Running `install.sh list-devices` prints every registered device (label, UUID, live mounted state and path) without opening any file.
- **Decision enabled**: Dan can confidently pick the right label or UUID to pass to `remove-device` — or just sanity-check his setup — in under 10 seconds, without touching raw YAML.

### Problem
Dan Fox wants to confirm which USB devices are registered before removing one, or just periodically check his setup is what he thinks it is. `config.yaml` is human-readable by design (ADR-001), but confirming registration state still means opening a text editor and mentally parsing YAML — and even then it can't tell him whether a device is *currently* mounted, since mount state is live system state, not config data.

### Who
- Dan Fox | about to run `remove-device`, or periodically checking his setup | wants a fast, no-file-editing way to see registered devices and their live mount state

### Solution
A `list-devices` subcommand on `install.sh` that reads `config.yaml:usb_devices[]`, cross-references each UUID against currently mounted `/Volumes` entries (reusing the UUID-matching approach from `sync-usb.sh`'s `find_usb_by_uuid()`), and prints a table: label, UUID, mounted (yes/no + path).

### Domain Examples

#### 1: Happy Path — Three Devices, One Mounted
Dan runs `install.sh list-devices` while IronKey-A is plugged in at home. Output shows IronKey-A as mounted at `/Volumes/IronKey-A`; IronKey-B and IronKey-C both show "not mounted."

#### 2: Edge Case — No Devices Registered Yet
A fresh install where `add-device` has never been run. Output: `"No USB devices registered. Run install.sh add-device to register one."` — an inviting empty state with a clear next action, not a blank output or an error.

#### 3: Boundary — Label Edited Manually in config.yaml
Dan once hand-edited a label in `config.yaml` (unusual but valid, since the file is meant to be human-editable per ADR-001). `list-devices` reflects the label exactly as currently stored — no caching, no staleness.

### UAT Scenarios (BDD)

#### Scenario: Listing devices shows every registered device with UUID and label
```gherkin
Given config.yaml has 3 registered USB devices: IronKey-A, IronKey-B, IronKey-C
When Dan runs install.sh list-devices
Then the output lists all 3 devices, each with its label and UUID
And the output states "3 devices registered"
```

#### Scenario: A currently mounted device shows its live mount path
```gherkin
Given IronKey-A (UUID 1A2B-3C4D) is registered and mounted at /Volumes/IronKey-A
When Dan runs install.sh list-devices
Then IronKey-A's row shows "mounted" and the path /Volumes/IronKey-A
```

#### Scenario: A registered but not-mounted device shows "not mounted"
```gherkin
Given IronKey-C (UUID 9C0D-1E2F) is registered but not currently in /Volumes
When Dan runs install.sh list-devices
Then IronKey-C's row shows "not mounted" with no path
```

#### Scenario: Listing devices with none registered shows a helpful empty state
```gherkin
Given config.yaml has an empty usb_devices[] list (fresh install, no add-device run yet)
When Dan runs install.sh list-devices
Then the output reads "No USB devices registered. Run install.sh add-device to register one."
And the command exits 0 (empty registry is not an error)
```

### Acceptance Criteria
- [ ] `list-devices` reads `config.yaml:usb_devices[]` and prints label + UUID for every entry
- [ ] Each device's mounted state is determined via the same UUID-matching logic as `sync-usb.sh:find_usb_by_uuid()` (no independent re-implementation)
- [ ] A mounted device's row shows its live mount path
- [ ] A registered-but-unmounted device's row shows "not mounted", no path
- [ ] An empty registry shows an inviting message with a concrete next action (`add-device`), not a blank output
- [ ] Command is read-only — never writes to `config.yaml`
- [ ] `config.yaml` schema mismatch or unreadable config exits 4, consistent with `sync-usb.sh`/`sync-cloud.sh`/`add-device` convention

### Outcome KPIs
- **Who**: Dan Fox
- **Does what**: Identifies which UUID/label to target for removal, or confirms his current setup, without opening a text editor
- **By how much**: Identification time under 10 seconds (single command, no file navigation)
- **Measured by**: Manual timing / qualitative check — can Dan name the exact device to remove within 10 seconds of running the command?
- **Baseline**: Today requires opening `config.yaml` in an editor and manually parsing YAML structure; mount state isn't available from the file at all

### Technical Notes
- Reuse `sync-usb.sh`'s `find_usb_by_uuid()` matching convention rather than reimplementing `/Volumes` scanning — see `shared-artifacts-registry.md` (HIGH integration risk if these drift)
- Read-only command: no atomic-write concern, no python3 write path needed (read-only YAML parse via the same `load_config()`-style approach)
- Extend `bin/test-sync-script.sh` with list-devices mocks: multi-device mixed mount state, empty registry — same mock-diskutil pattern as existing tests

### job_id: JOB-003
