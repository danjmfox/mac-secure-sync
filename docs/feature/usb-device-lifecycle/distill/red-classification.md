<!-- markdownlint-disable MD024 -->
# RED Classification: usb-device-lifecycle

Feature ID: `usb-device-lifecycle`
Wave: DISTILL
Date: 2026-08-26

## Bash-adapted RED/BROKEN gate

No import system exists in Bash to fail with `ImportError`. The equivalent
distinction: a new acceptance test is **RED** (correct) if it fails because
the real `install.sh` invocation produced the wrong observable behaviour
(wrong exit code, wrong config-file state, wrong stdout) — the assertion
genuinely fired against a real subprocess result. It is **BROKEN** (wrong)
if the test never gets that far: a typo in the test, a missing helper
function, a mock that doesn't exist, or the runner aborting before any
assertion executes.

## RED-scaffold stub added

`bin/install.sh`'s subcommand dispatch had no `remove-device`/`list-devices`
branches. Invoking either today fell through to the interactive install flow
(`read -rp` prompts), which would have hung every test indefinitely — a
harness failure, not a business-logic RED. Added two minimal stub branches
immediately after the existing `add-device` dispatch:

```bash
if [[ "${1:-}" == "remove-device" ]]; then
    log_err "remove-device: not yet implemented"
    exit 2
fi
if [[ "${1:-}" == "list-devices" ]]; then
    log_err "list-devices: not yet implemented"
    exit 2
fi
```

This is scaffolding only — DELIVER replaces both branches with
`cmd_remove_device()`/`cmd_list_devices()`. No business logic was added.

## Empirical run

All 20 scenarios (43 total assertions across `remove-device.feature` +
`list-devices.feature`) were run once against the stubbed `install.sh`
(temporarily uncommented in `run-tests.sh`, then reverted to the
one-scenario-enabled scaffold). Result: **16 passed, 27 failed, 0 BROKEN.**

| Failure signature | Classification | Reason |
|---|---|---|
| `expected exit code 0, got 2` | RED | Stub returns exit 2 for every invocation; real exit-code assertion fired against the real (wrong) result |
| `expected exit code 4, got 2` | RED | Same — config-error-path scenarios also hit the generic stub exit code, not the schema/missing-file-specific exit 4 they require |
| `output was: ❌ remove-device: not yet implemented` / `❌ list-devices: not yet implemented` | RED | stdout/stderr assertions (device list, confirmation message, recovery-step hint) compared real captured output against the stub's real message |
| `pattern 'IronKey-C' should not appear in log but does` | RED | Config-mutation assertions fired against the real, unmodified `config.yaml` on disk (stub never writes) |

The 16 passes are exclusively the "config.yaml is byte-for-byte unchanged /
still contains X" assertions on error-path and no-op scenarios — these
trivially hold because the stub exits before touching the file, which is
itself the correct current behaviour (no destructive action from an
unimplemented command).

**Zero BROKEN failures**: no `command not found`, no unbound-variable error,
no missing helper function, no runner abort before an assertion executed.
Every one of the 43 assertions reached its comparison against a real
subprocess result.

## Conclusion

The suite is genuinely RED, not BROKEN. Safe to hand off to DELIVER for
Outside-In implementation of `cmd_remove_device()` and `cmd_list_devices()`,
one scenario at a time starting from the enabled walking skeleton
(`test_ws_remove_device_by_label_leaves_others_unchanged`).
