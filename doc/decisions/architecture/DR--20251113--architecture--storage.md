---
id: DR--20251113--architecture--storage
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: architecture
slug: storage
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--storage--architecture

## Notes
This structure balances simplicity, autonomy, and resilience. Further DRs define the sync and encryption details.
## 🧭 Context

SecureLocal manages sensitive personal data. We need a simple, reliable backup and recovery model that doesn’t depend on constant connectivity or external services.

## ⚖️ Options Considered


| Option | Description | Outcome  | Rationale                      |
| ------ | ----------- | -------- | ------------------------------ |
| A      | Do nothing  | Rejected | Insufficient long-term clarity |
| B      |             |          |                                |

## 🧠 Decision

Adopt a **three-layer architecture**:

Adopt a three-layer backup model:

1. Local (~/secureLocal) — authoritative working copy, git-tracked.
1. USB (IronKey) — offline, nearline safety net.
1. Cloud (rclone crypt) — encrypted offsite mirror.

Each layer has distinct purpose and trust boundary:

- Local = editable, fast, full history.
- USB = air-gapped, physically controlled.
- Cloud = disaster-recovery tier.

## 🪶 Principles

- Data remains available offline and offsite.
- Local deletion errors recoverable from USB.
- Remote compromise exposes only encrypted data.
- Must manage sync timing manually (launchd triggers).

## 🔁 Lifecycle

new

## 🧩 Reasoning

_Explain the rationale, trade-offs, and considerations behind the decision._

## 🔄 Next Actions

Future automation may expand to multiple devices or versioned cloud archives.

## 🧠 Confidence

medium 

## 🧾 Changelog

Notes
