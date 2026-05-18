---
id: DR--20251113--security--encryption-boundary
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: security
slug: encryption-boundary
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--security--encryption-boundary

## 🧭 Context

_Describe the background and circumstances leading to this decision._

## ⚖️ Options Considered

_List the main options or alternatives that were evaluated before making the decision, including why each was accepted or rejected._

| Option | Description | Outcome  | Rationale                      |
| ------ | ----------- | -------- | ------------------------------ |
| A      | Do nothing  | Rejected | Insufficient long-term clarity |
| B      |             |          |                                |

## 🧠 Decision
🔒 DR: Encryption boundary — hardware USB + rclone crypt cloud

Context
We must protect sensitive data at rest and in transit without unnecessary complexity.

Decision
	•	Rely on FileVault for local encryption.
	•	Require hardware-encrypted USB (e.g., IronKey D300).
	•	Use rclone crypt for cloud backup encryption.

This defines clear trust boundaries:
	•	Local encryption handled by OS.
	•	USB encryption handled by hardware.
	•	Cloud encryption handled by software key.

Consequences
	•	Simple to operate; minimal performance cost.
	•	No plaintext data in the cloud.
	•	Users responsible for securing rclone.conf and remembering encryption password.
	•	Non-encrypted USBs are explicitly unsupported.

Notes
Installer warns about backup of rclone.conf but does not automate it.

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
