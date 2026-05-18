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
