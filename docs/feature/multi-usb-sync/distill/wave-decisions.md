# Wave Decisions: DISTILL — multi-usb-sync

Feature ID: `multi-usb-sync`
Wave: DISTILL
Date: 2026-05-15
Designer: Quinn (nw-acceptance-designer)

---

## WD-DISTILL-001: Walking Skeleton Strategy — Strategy C (Real local)

**Decision:** Strategy C — all test resources are local to the shell process. No containers, no network services, no external hardware.

**Rationale:**
- The entire system is local to one macOS machine. There are no network boundaries to cross during testing.
- The existing test harness (`bin/test-sync-script.sh`) already uses this pattern: mock binaries in a temp PATH, real filesystem operations, isolated `mktemp -d` directories.
- The only "external" systems are the USB drive (replaced by a temp directory) and the cloud remote (rclone mocked to record calls without real network access).
- Real rsync is delegated to by the mock wrapper — file copy operations are real, confirming the sync tool integration is wired correctly.
- Strategy A (full integration with real USB hardware) would require physical hardware in CI. Rejected.
- Strategy B (containers) adds no value for a single-machine Bash tool. Rejected.

**Walking skeleton test:** `test_ws_usb_sync_copies_directory_to_drive` in `run-tests.sh`. Uses a real `config.yaml` file, a mock diskutil binary returning the registered UUID, a mock rsync wrapper delegating to real `/usr/bin/rsync`, and a real log file — all inside a `mktemp -d` temp directory.

---

## WD-DISTILL-002: Test placement rationale

**Decision:** Feature files under `tests/acceptance/multi-usb-sync/*.feature`. Bash implementations as `run-tests.sh` + `helpers.sh` collocated in the same directory.

**Rationale:**
- Feature files serve as living specification — they belong in `tests/acceptance/` not `bin/`, `docs/`, or scattered across the repo.
- Collocating `run-tests.sh` and `helpers.sh` with the feature files keeps the specification and its executable counterpart co-located without polluting `bin/` (which is for production scripts only).
- The existing `bin/test-sync-script.sh` covers the old combined script. New acceptance tests for the split scripts live in the structured `tests/` directory. `bin/test-sync-script.sh` remains as-is — it tests `sync-to-usb-and-cloud.sh` which is being deprecated but not yet deleted.

---

## WD-DISTILL-003: Adapter coverage decisions

**Decision:** Every driven adapter from DESIGN gets at least one `@real-io` scenario. Mock factories for all adapters are provided in `helpers.sh`.

| Adapter | Coverage approach |
|---|---|
| `load_config()` (python3) | All tests write a real `config.yaml` and invoke scripts that must parse it |
| `find_usb_by_uuid()` (diskutil) | Mock diskutil binary per volume path; delegating real UUID lookup logic |
| `sync_to_usb()` (rsync) | Mock wrapper delegates to real `/usr/bin/rsync`; real file copy verified by `assert_file_exists` |
| `sync_to_cloud()` (rclone) | Mock records calls; no real cloud access (rclone remote not available in CI) |
| Log writer (echo append) | Real log file in temp dir; assertions on log content |
| Atomic config write | Real temp file + rename; `assert_file_not_exists` on `.tmp` |
| `launchctl` | Mock records load/unload calls; assertions on call log |

**Rationale for not using real rclone:** rclone requires a pre-configured remote credential file. This is not available in a clean CI environment. The adapter boundary is the mock binary's call signature — the call arguments are verified. The real rclone integration is the subject of a separate manual verification step documented in the journey map.

---

## WD-DISTILL-004: One-at-a-time sequencing

**Decision:** Only the walking skeleton test (`test_ws_usb_sync_copies_directory_to_drive`) is enabled in `run-tests.sh` at the start of DELIVER. All other test function calls are commented out.

**Rationale:** The global standing orders require one test at a time (TDD rhythm). The walking skeleton is the outermost loop that validates the full path: config read → UUID match → rsync → log write → exit 0. All other tests are enabled one at a time as the crafter implements each behaviour.

**Recommended implementation sequence:**
1. Walking skeleton (USB sync) — requires `load_config()`, `find_usb_by_uuid()`, `sync_to_usb()`, log writer
2. Walking skeleton (cloud sync) — requires `sync_to_cloud()`
3. Schema version mismatch (USB + cloud) — guard in `load_config()`
4. Missing / malformed config — `load_config()` error handling
5. USB-B independence — multi-UUID iteration in `find_usb_by_uuid()`
6. Unregistered USB — silent exit path
7. Partial directory failure — per-directory error handling loop
8. Cloud per-directory remotes — `sync_to_cloud()` loop
9. Cloud retry + failure — retry logic
10. Log format and grep tests — structured log formatting
11. Device registration (duplicate rejection, atomic write) — `install.sh add-device`
12. launchd plist installation — `create_launch_agent()` replacement
13. Test harness isolation tests — self-verification of mock boundaries

---

## WD-DISTILL-005: Back-propagation findings

**Finding 1 — load_config() is the critical first dependency.**
The walking skeleton requires a working `load_config()` implementation before any other behaviour can be tested. The crafter must implement `load_config()` first. This is expected (it is the config read port) but should be flagged explicitly so the crafter does not attempt to test sync behaviour before config parsing works.

**Finding 2 — SECURELOCAL_VOLUMES_BASE environment variable needed.**
The existing `sync-to-usb-and-cloud.sh` uses `USB_MOUNT_BASE` from `config.env`. The new `sync-usb.sh` will scan `/Volumes` directly. For test isolation, the test harness overrides the volumes scan root via `SECURELOCAL_VOLUMES_BASE`. The crafter must honour this environment variable (defaulting to `/Volumes` when unset) so that tests can redirect volume scanning to the temp directory.
This is a back-propagation to DESIGN: `SECURELOCAL_VOLUMES_BASE` should be documented as a test-seam environment variable in the architecture brief, with the contract: "default `/Volumes`; override in tests".

**Finding 3 — install.sh add-device needs --non-interactive mode for launchd tests.**
The `test_both_plists_recorded_by_launchctl` test invokes `install.sh --non-interactive`. The crafter must add a non-interactive mode that skips prompts and uses `CONFIG_FILE` from the environment. This is consistent with the existing test harness pattern but needs to be explicit in the implementation.

**Finding 4 — No KPI contracts file found.**
`docs/product/kpi-contracts.yaml` was not found during prior wave reading. Soft gate applied: no `@kpi` scenarios written. If KPI instrumentation is added in a future wave, `@kpi` scenarios can be appended to the appropriate feature files.
