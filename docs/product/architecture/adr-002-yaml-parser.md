# ADR-002: YAML Parser — python3 Parse-Once Strategy

**Status:** Accepted
**Date:** 2026-05-15
**Deciders:** Dan Fox (principal), Morgan (solution-architect)

---

## Context

Bash has no native YAML parser. The config.yaml file (ADR-001) must be parsed at startup of `sync-usb.sh` and `sync-cloud.sh`. The parser choice must satisfy:

1. Zero new runtime dependencies (macOS system tools only)
2. Parse-once at startup (not on every config access)
3. Output bash-compatible variables that the rest of the script can use directly
4. Fail loudly and clearly on malformed YAML — no silent partial reads
5. Portable across macOS 12+ (the minimum expected environment)

---

## Decision

Use a single `python3 -c "..."` one-liner invoked by a `load_config()` function. The function calls python3 once, collects its stdout (newline-separated `KEY=value` pairs), and the caller sources the result into the shell environment. After this call, the rest of the script uses plain bash variables — no further python3 invocations.

```
load_config() receives: path to config.yaml
load_config() emits:    KEY=value lines on stdout
load_config() exits:    non-zero with structured stderr message on any failure

Caller pattern:
  eval "$(load_config "${CONFIG_PATH}")"
  -- or --
  source <(load_config "${CONFIG_PATH}")
```

The python3 script:
- Uses `import yaml, sys` (PyYAML is bundled with macOS system python3)
- Emits flat bash-compatible variable names (e.g., `DIR_0_LOCAL_PATH`, `DIR_0_CLOUD_REMOTE`, `USB_0_ID`, `USB_0_LABEL`, `DIR_COUNT`, `USB_COUNT`)
- Emits `SCHEMA_VERSION` for the shell to validate before using any other variable
- Fails with exit code 4 and a structured message if the file is missing, unparseable, or has an unexpected schema_version

---

## Alternatives Considered

### Option A — Chosen: python3 parse-once one-liner

Invokes python3 once at startup. Entire config is in bash variables thereafter. No subprocess overhead during iteration loops.

### Option B (Rejected): yq (standalone binary)

`yq` is a purpose-built YAML CLI tool. It is not present on macOS by default; requires Homebrew installation. This introduces a dependency that is not part of the macOS system baseline. The explicit constraint is zero new dependencies.

### Option C (Rejected): sed/awk YAML "parser"

Simple key: value extraction via awk/sed is feasible for flat YAML but fails on nested structures (lists, maps). The config.yaml has a nested structure (directories[], usb_devices[]). Implementing a correct YAML parser in awk is a significant engineering risk — YAML has edge cases (multiline strings, anchors, quoted values) that awk cannot handle reliably. Rejected on correctness grounds.

### Option D (Rejected): Shell heredoc with python3 script file

Identical to Option A but externalises the python3 logic to a separate `.py` file. Adds a file to manage, deploy, and keep in sync with the script. No benefit over the inline one-liner for code of this size.

---

## Consequences

**Positive:**
- Zero new dependencies — python3 is present on macOS 12+ (system baseline)
- Parse-once: one subprocess per script invocation regardless of directory count
- Plain bash variables after load: no performance overhead in loops
- Fails loudly: malformed YAML exits with code 4 before any sync begins
- Testable in isolation: `load_config()` has a clear input (file path) and output (stdout) contract

**Negative:**
- python3 must be available; `check_dependencies()` must be extended to verify it
- Output is flat bash variables (e.g., `DIR_0_LOCAL_PATH`); array emulation is required for multi-directory iteration (use `DIR_COUNT` to drive a `for i in $(seq 0 $((DIR_COUNT-1)))` loop)
- If the config format changes, both the python3 script and the bash iteration logic must be updated together

**Earned Trust (probe):**
- `load_config()` must be tested with: missing file, empty file, malformed YAML, wrong schema_version, minimum valid file, file with 2 directories and 2 USB devices
- The test harness (US-007) must include a `write_config_yaml()` helper that replaces `write_config()` (the existing env-file helper)
- The mock factory for diskutil in the test harness must support multi-UUID responses (one mock per volume path)
