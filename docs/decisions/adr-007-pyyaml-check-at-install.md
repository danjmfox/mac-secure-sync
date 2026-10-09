---
status: accepted
date: 2026-10-09
feature: launchd-environment
---

# ADR-007: Keep PyYAML; make the installer refuse to continue when launchd's python3 lacks it

## Context

`sync-usb.sh` and `sync-cloud.sh` parse `config.yaml` once at startup with `python3` and `import yaml` (ADR-002). launchd runs them with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, so `python3` is Apple's `/usr/bin/python3`. That interpreter does not ship PyYAML, although ADR-001 and ADR-002 assumed it did. Without the module, every launchd run exits 4 (config error). The failure is silent unless someone reads the log, and it appears only after the agents are installed.

## Options Considered

- **(a) A constrained parser or simpler format.** Removes the dependency, but means writing and maintaining a parser and migrating the schema-v2 config format.
- **(b) Keep PyYAML and check at install time (chosen).** Smallest change, lowest maintenance. The weakness is a manual per-machine step, `pip install --user`, which may need repeating after a macOS update replaces the interpreter. The installer check detects exactly that situation whenever it is re-run.
- **(c) Document the requirement only.** The failure stays silent at the moment it matters.
- **(d) Switch to `/usr/bin/ruby`.** Its standard library parses YAML, but Apple has deprecated Ruby and may remove it.
- **(e) JSON config read with `/usr/bin/jq`.** Needs a config migration, and `jq` ships with recent macOS only.

## Decision

Adopt (b). `install.sh` gains `check_launchd_yaml`, run in the interactive path straight after `check_dependencies`, in the `--non-interactive` path before any plist is created, and in `add-device`. It runs `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin python3`, imports `yaml`, and parses the config file when one exists. On failure it logs an error naming the fix, `/usr/bin/python3 -m pip install --user pyyaml`, and exits 1 before any config write, plist write or `launchctl` call. The installer installs nothing and does not prompt to install. A pure helper, `launchd_yaml_failure_message`, builds the text.

`SECURELOCAL_LAUNCHD_PATH` overrides the probe's PATH. It exists so tests can substitute a python3; the default is launchd's PATH.

`remove-device` and `list-devices` keep their own "yaml module not available" message (now with the same fix command) but do not run the probe: they use the user's interpreter, and `list-devices` is a diagnostic that should still run.

## Exceptions

- The probe uses the real `HOME`. Apple's python3 finds a `--user` install through `HOME`, so a machine where the install exists only under a different HOME will fail the check, correctly.
- Tests substitute a mock python3 through `SECURELOCAL_LAUNCHD_PATH`. They do not prove behaviour of Apple's real `/usr/bin/python3` on a machine without PyYAML.
- The check proves the interpreter and config at install time only. A later macOS update can remove the module again; re-running the installer reveals it.
- The existing `[@US-006]` test in `tests/acceptance/multi-usb-sync/run-tests.sh` now sets `SECURELOCAL_LAUNCHD_PATH="${PATH}"`, because it runs the installer with a temporary HOME, where Apple's python3 has no user-site PyYAML. Its assertions are unchanged.
