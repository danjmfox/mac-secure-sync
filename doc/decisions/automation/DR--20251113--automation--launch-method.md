---
id: DR--20251113--automation--launch-method
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: automation
slug: launch-method
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--automation--launch-method

DR: Automation method — launchd event trigger

Context
We need to run sync jobs automatically without heavy background daemons or continuous watchers.

Decision
Use macOS launchd to watch the /Volumes directory and trigger the sync script on volume mount.
The sync script validates UUID before proceeding, preventing false triggers.

Consequences
	•	Lightweight, native, no polling.
	•	Works offline and doesn’t depend on third-party tools.
	•	Sync runs reliably when the correct USB mounts.
	•	Requires one-time setup of .plist and UUID capture.

Notes
Alternative triggers (Hazel, fswatch, Syncthing) were rejected due to complexity or background overhead.


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
