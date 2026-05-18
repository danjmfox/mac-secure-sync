---
id: DR--20251113--observability--logging-strategy
dateCreated: '2025-11-13'
version: 1.0.0
status: new
changeType: creation
domain: observability
slug: logging-strategy
changelog:
  - date: '2025-11-13'
    note: Initial creation
---
# DR--20251113--observability--logging-strategy

📊 DR: Observability — standardised logs, exit codes, retries

Context
We need consistent feedback and diagnosability for automated sync jobs.

Decision
Implement unified observability conventions:
	•	Log to ~/Library/Logs/securelocal-sync.log.
	•	Include timestamped structured lines.
	•	Use standard exit codes:
	•	0 success
	•	1 USB fail
	•	2 cloud fail
	•	3 both fail
	•	4 config/runtime issue
	•	Retry failed operations once after 30 s delay.
	•	Capture attempt numbers in logs.

Consequences
	•	Simplifies troubleshooting and future monitoring.
	•	Predictable behaviour for launchd or CI pipelines.
	•	Adds small latency on transient failures.

Notes
Future version could add log rotation or notification hooks (e.g., email or desktop alerts).

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
