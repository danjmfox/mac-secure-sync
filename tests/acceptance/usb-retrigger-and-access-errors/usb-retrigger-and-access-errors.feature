Feature: Quiet USB triggers and honest access-error reporting (ADR-008)

  Scenario: Unchanged drives within the interval are skipped
    Given a registered drive is mounted and a run finished less than 600 s ago with the same drive set
    When launchd triggers sync-usb.sh again
    Then it logs one INFO line, runs no rsync, exits 0, and does not refresh the stamp

  Scenario: A changed drive set, or an elapsed interval, runs
    Then the sync runs; SECURELOCAL_MIN_INTERVAL overrides the 600 s default

  Scenario: A failed run is stamped and retried after the interval
  Scenario: A live lock skips an overlapping run; a stale lock is taken over

  Scenario: rsync exit 23, 0 files transferred, access errors
    Then ERROR names Full Disk Access for /bin/bash, rsync is retried once after 30 s, and the job exits 1

  Scenario: rsync exit 23 with files transferred, or without access errors
    Then the job completes with skips (exit 3) without retrying
