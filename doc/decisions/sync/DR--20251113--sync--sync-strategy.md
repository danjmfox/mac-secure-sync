---
id: DR--20251113--sync--sync-strategy
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: sync
slug: sync-strategy
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--sync--sync-strategy

🔁 DR: Sync strategy — preserve deletions on USB, mirror to cloud

Context
We need both historical safety and accurate remote mirroring.

Decision
Use two distinct sync semantics:
	•	USB: rsync -avh --ignore-errors — no --delete; keeps old files as a recovery buffer.
	•	Cloud: rclone sync — mirrors current state, deletions included, ensuring the cloud copy reflects live truth.

Consequences
	•	Local deletions are recoverable from USB.
	•	Cloud remains a clean, authoritative mirror.
	•	USB may require manual pruning.
	•	Divergent semantics are intentional and documented.

Notes
Optionally, rclone --backup-dir may later provide versioned history in cloud storage.


## 🧭 Context

_Describe the background and circumstances leading to this decision._

## ⚖️ Options Considered

_List the main options or alternatives that were evaluated before making the decision, including why each was accepted or rejected._

| Option | Description | Outcome  | Rationale                      |
| ------ | ----------- | -------- | ------------------------------ |
| A      | Do nothing  | Rejected | Insufficient long-term clarity |
| B      |             |          |                                |

## 🧠 Decision

_State the decision made clearly and succinctly._

## 🪶 Principles

_List the guiding principles or values that influenced this decision._

## 🔁 Lifecycle

_Outline the current lifecycle state and any relevant change types._

## 🧩 Reasoning

_Explain the rationale, trade-offs, and considerations behind the decision._

## 🔄 Next Actions

_Specify the immediate next steps or actions following this decision._

## 🧠 Confidence

_Indicate the confidence level in this decision and any planned reviews._

## 🧾 Changelog

_Summarise notable updates, revisions, or corrections. Each should have a date and note in YAML frontmatter for traceability._
