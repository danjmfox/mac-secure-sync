---
status: accepted
date: 2026-10-15
feature: test-harness-portable-path
route: direct execution, no waves (test-harness bug fix)
---

# ADR-009: The acceptance harness resolves interpreters by capability probe, not by fixed path

## Context

The acceptance suites run the scripts under test with a restricted `PATH` built in `tests/acceptance/multi-usb-sync/helpers.sh`. That `PATH` hard-coded `/usr/local/bin` ahead of the system directories, and `launchd-environment/run-tests.sh` chose a PyYAML-capable `python3` from three fixed locations tested only with `-x`.

On an Apple-silicon Mac without Rosetta, `/usr/local/bin` can hold Intel-only binaries (bash, python3, timeout). They are executable but fail with "Bad CPU type in executable". Every suite then failed: multi-usb-sync 12/42, usb-device-lifecycle 17/49, backup-path-handling 2/8, launchd-environment aborted with exit 2.

A second cause sat behind the first. Apple's `/usr/bin/python3` finds PyYAML only through the user site (`~/Library/Python/3.9`). The suites run the scripts under a temporary `HOME`, which hides it, so `install.sh` refused to continue (ADR-007) and the sync scripts exited 4 (config error). Previously `/usr/local/bin/python3` masked this.

## Options Considered

- **(a) Drop `/usr/local/bin` from `PATH` and probe for python3 (chosen).** The harness no longer depends on a directory that may be dead, and finds a working interpreter by running it.
- **(b) Install PyYAML for Apple's python3 into the real system.** Modifies the machine under test and is exactly what the temporary `HOME` is meant to avoid.
- **(c) Skip tests when the toolchain is broken.** Hides the gap. Rejected: a missing capability must fail loudly.
- **(d) Keep `/usr/local/bin` unconditionally.** Fails on the machine that motivated this change.

## Decision

- `harness_system_path` returns `/usr/bin:/bin:/usr/sbin:/sbin` and appends `/usr/local/bin` only when `/usr/local/bin/bash -c :` actually runs.
- `provide_yaml_python3` (now in `helpers.sh`, called by `setup_test_env`) runs `python3 -c 'import yaml'` under `env -i` with an empty temporary `HOME`. If that fails, it tries `/usr/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and every `python3` on the invoking `PATH`, each by execution, and exposes the first working one as `python3` on the mock bin. If none works it exits 2 naming the missing capability.
- `teardown_test_env` restores the `PATH` the suite started with, not a literal.
- `backup-path-handling` runs `"${BASH}" -c` instead of a bare `bash -c`.

What the tests still prove is unchanged: the scripts under test run under the same `env -i ... /bin/bash` and the same restricted `PATH`. The only difference is that PyYAML capability is supplied by the harness through the mock bin, as `launchd-environment` already did. The real-machine PyYAML requirement remains covered by the ADR-007 tests, which replace `python3` with one lacking yaml.

## Exceptions

- A python3 on the invoking `PATH` is trusted if it imports yaml; a stale one is not detected beyond that.
- `usb-retrigger-and-access-errors` (unmerged branch) defines its own `provide_yaml_python3` after sourcing `helpers.sh`, which overrides this one. It must drop that local copy when merged, or it will still fail here.
