# Journey (Visual): Retiring a USB Device

Feature ID: `usb-device-lifecycle`
Persona: Dan Fox — solo builder-user, operator of mac-secure-sync
Depth: Lightweight (CLI happy-path + error path per routing Decision 3)

## Flow

```
[Trigger: IronKey-C lost/retired] → [list-devices] → [remove-device] → [Goal: config reflects reality]
  Feels: mildly anxious,             Feels: focused,     Feels: careful,     Feels: relieved, confident
  "did I break anything              confirming what's   targeting the      config.yaml has no
  registered somewhere?"             actually registered  right device       stale entries; other
                                                                              devices untouched
```

## Step 1 — `install.sh list-devices` (optional but common precursor)

```
+-- Step 1: List Registered Devices ---------------------------------+
| $ install.sh list-devices                                          |
|                                                                     |
| Registered USB Devices                                             |
| ------------------------------------------------------------------ |
| LABEL                UUID          MOUNTED                         |
| IronKey-A (home)     1A2B-3C4D     yes  /Volumes/IronKey-A         |
| IronKey-B (office)   5E6F-7A8B     no                              |
| IronKey-C (travel)   9C0D-1E2F     no                              |
|                                                                     |
| 3 devices registered.                                              |
+----------------------------------------------------------------------+
```

Entry feeling: uncertain what's registered. Exit feeling: informed — Dan now knows exactly which label/UUID to target, and that IronKey-C is not currently mounted (consistent with it being lost).

## Step 2 — `install.sh remove-device --label "IronKey-C (travel)"` (happy path)

```
+-- Step 2: Remove Device ---------------------------------------------+
| $ install.sh remove-device --label "IronKey-C (travel)"              |
|                                                                       |
| ℹ️  Found device: IronKey-C (travel) (9C0D-1E2F)                     |
| ℹ️  Removing from usb_devices[] and 2 directory mappings...          |
| ✅  Removed IronKey-C (travel) (9C0D-1E2F)                            |
| ✅  config.yaml updated — 2 devices remain registered                 |
+------------------------------------------------------------------------+
```

Entry feeling: careful, deliberate. Exit feeling: relieved — explicit confirmation of what changed and what didn't ("2 devices remain registered" reassures the other entries survived).

## Step 2 (error path) — unknown label

```
$ install.sh remove-device --label "IronKey-Z"
❌  No registered device matches label "IronKey-Z"
ℹ️  Run: install.sh list-devices to see registered devices
```

Guides recovery directly to Step 1 rather than leaving Dan guessing — no jarring transition, the error message itself completes the emotional loop back to "informed."

## Emotional Arc

| Phase | Target Emotion | Design Lever |
|---|---|---|
| Trigger (device lost/retired) | Mild anxiety, "will removing this break anything else?" | — |
| list-devices | Focused, confirming | Live mount state, not just static config |
| remove-device (happy) | Careful → relieved | Explicit "N devices remain registered" confirmation echoes ADR-003's "existing entries provably unchanged" pattern from add-device |
| remove-device (error) | Supported, not blamed | Error names the exact problem and the exact recovery command |

## Shared Artifacts Touched

See `shared-artifacts-registry.md` for full registry. Summary: `config.yaml` (`usb_devices[]`, `directories[*].usb_devices[]`), UUID, label — all already tracked artifacts from `multi-usb-sync`; this feature adds two new consumers (`remove-device`, `list-devices`) to the existing registry, no new artifacts.

## Integration Checkpoints

- `remove-device` must leave every *other* `usb_devices[]` entry byte-for-byte identical (mirrors the add-device test pattern from ADR-003).
- `remove-device` must strip the removed UUID from every `directories[*].usb_devices` list — a directory left with an empty `usb_devices: []` is valid, not an error (sync-usb.sh already treats "no matched UUID" as a silent no-op per US-002).
- `list-devices` mount-state check must reuse the same UUID-matching logic as `sync-usb.sh:find_usb_by_uuid()` — two independently-written UUID matchers would be a horizontal-integration risk (vocabulary/behavior drift).
