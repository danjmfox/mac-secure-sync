@US-004 @real-io
Feature: Sync log lets Dan confirm success or locate failures in under 30 seconds

  As Dan Fox
  I want the sync log to use a consistent, grep-friendly format
  So that I can immediately distinguish successful syncs from failures without reading every line

  Background:
    Given a valid configuration file
    And the log destination is set to a temporary file

  # --- Happy path ---

  Scenario: USB sync produces a timestamped success entry per directory
    Given USB-A is connected with two mapped directories
    When the USB sync runs and succeeds
    Then the log contains a timestamped INFO entry for each directory synced
    And the final log line records "USB sync complete" with exit code 0
    And no ERROR or WARN entries appear in the log

  Scenario: Cloud sync produces a timestamped success entry per directory
    Given a valid configuration with two cloud destinations
    When the cloud sync runs and succeeds
    Then the log contains a timestamped INFO entry for each directory synced
    And the final log line records "cloud sync complete" with exit code 0

  Scenario: Dan can identify the last failure by searching for errors
    Given the cloud sync failed at 03:00 due to an unavailable network
    When Dan searches the log for error entries
    Then he sees exactly one ERROR entry identifying the failed directory and reason
    And no INFO entries are returned by the error search

  Scenario: Log entries follow the expected format for every line
    Given the USB sync has run once
    When Dan reads the log file
    Then every line begins with a timestamp in the format YYYY-MM-DDTHH:MM:SS
    And every line has a level field of INFO, WARN, or ERROR
    And every line identifies the script that produced it

  # --- Error paths ---

  Scenario: Failed USB sync produces an ERROR entry with the directory and reason
    Given USB-A is connected
    And the sync tool fails for ~/Projects
    When the USB sync runs
    Then the log contains an ERROR entry identifying ~/Projects as the failed directory
    And the ERROR entry includes the failure reason

  Scenario: Failed cloud sync produces an ERROR entry after both attempts
    Given the network is unavailable
    When the cloud sync runs and exhausts both attempts
    Then the log contains an ERROR entry stating "cloud sync failed after 2 attempts"
    And the ERROR entry names the affected cloud destination

  # --- Edge / boundary ---

  @infrastructure-failure @in-memory
  Scenario: Concurrent log writes from USB sync and cloud sync produce no partial lines
    Given USB sync and cloud sync start within 1 second of each other
    When both scripts write to the shared log simultaneously
    Then every line in the log is complete and begins with a timestamp
    And no lines are merged or truncated
    And the log remains readable after concurrent writes
