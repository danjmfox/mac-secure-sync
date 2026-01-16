---
id: DR--20251113--config--multi-usb-syncs
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: config
slug: multi-usb-syncs
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--config--multi-usb-syncs

## 🧭 Context

The current CLI was built around a single `~/secureLocal` → USB + rclone sync. As guardians of multiple devices (e.g., a daily-use IronKey plus an offline backup USB) and additional local folders we now want to keep in sync, the single-job `config.env` model is becoming too rigid. We need a way to describe several sync targets (each with its own USB UUID, mount point, backup subpath, and optionally its own local folder or rclone remote) so future enhancements like multi-USB and multi-local syncing are anchored in the config.

## ⚖️ Options Considered

| Option | Description | Outcome  | Rationale                      |
| ------ | ----------- | -------- | ------------------------------ |
| A      | Do nothing, keep single-target config | Rejected | Becomes onerous to maintain as more drives/paths pile up and launchd jobs multiply. |
| B      | Duplicate the script per target | Rejected | Hard to keep in sync; installers and tests would need to be duplicated. |
| C      | Extend the canonical config to enumerate sync jobs | Accepted | Keeps a single source of truth while allowing structured support for multiple USB+local combinations. |

## 🧠 Decision

We will evolve `~/.config/securelocal/config.env` (and the installer that writes it) to support an ordered list of sync jobs. Each job entry specifies the local source directory, UUID-identified USB target (with its mount base/backup path), and the rclone remote to mirror to. The sync runner iterates the list and executes the current `sync-to-usb-and-cloud.sh` flow for every configured target in sequence.

## 🪶 Principles

- Keep one canonical config file for the automation so installs and inspections stay simple.
- Preserve the USB UUID guardrails and logging/retry behaviour for each job.
- Allow incremental adoption (existing single-job installs remain valid; new schema is backwards-compatible via defaults).

## 🔁 Lifecycle

Status is `new` (configuration expansion defined but not yet implemented). The changeType is `creation`; once the schema is stabilized and the scripts consume it we will update the lifecycle to `active` and capture any revisions in the changelog.

## 🧩 Reasoning

- Enumerating jobs lets the installer prompt for multiple volumes in one session rather than requiring separate installs per drive.
- Keeping the UUID + rclone remote paired per job avoids accidental writes to the wrong USB or remote during retries.
- This approach scales naturally to future ideas like `secureLocal-photos` + `secureLocal-work` while reusing the same sync script logic (just iterate over `job.local_dir` etc.).

## 🔄 Next Actions

1. Design the new config schema (structured list) and update `bin/install.sh` so it can collect multiple USBs/remotes interactively.
2. Modify the sync script to parse the job list, validate each entry, and continue with the existing rsync/rclone pipeline for every target, accumulating failures but still reporting per-job status.
3. Extend the tests (`bin/test-sync-script.sh`) to cover multi-job scenarios and ensure log files clearly identify which job emitted which lines.

## 🧠 Confidence

Moderate; the existing automation already validates config and retries per job, so enumerating jobs mostly affects configuration parsing. We will revisit this record after implementing schema parsing and multi-job execution to confirm the trade-offs remain acceptable.

## 🧾 Changelog

See frontmatter for the initial creation entry; future updates should append new date/notes in the YAML list.
