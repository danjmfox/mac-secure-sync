@US-003 @real-io
Feature: Directories are mirrored to the cloud on a timer independent of USB drives

  As Dan Fox
  I want my directories backed up to the cloud hourly without needing a USB drive connected
  So that my data is protected even when I haven't used a USB drive for days

  Background:
    Given a valid configuration file with two directories each mapped to their own cloud destination

  # --- Happy path ---

  Scenario: Cloud sync runs successfully when no USB drive is present
    Given no USB drive is connected
    When the cloud sync runs
    Then ~/secureLocal is mirrored to remote-crypt:secureLocal
    And ~/Projects is mirrored to remote-crypt:Projects
    And the log records a success entry for each directory
    And the sync completes without errors

  Scenario: Each directory is synced to its own separate cloud destination
    Given a valid configuration with two directories
    When the cloud sync runs
    Then the cloud tool is invoked separately for each directory
    And ~/secureLocal is not synced to the same destination as ~/Projects

  Scenario: Dan can trigger cloud sync manually to recover from a previous failure
    Given the previous cloud sync failed due to an unavailable network
    When Dan runs the cloud sync directly
    Then both directories are mirrored successfully
    And the log appends new success entries without removing previous failure entries
    And the sync exits without errors

  # --- Error paths ---

  Scenario: Network unavailable causes cloud sync to retry once then record failure
    Given the network is unavailable
    When the cloud sync runs for ~/secureLocal
    Then the first sync attempt fails
    And the sync waits 30 seconds before retrying
    And the retry also fails
    And the log records "cloud sync failed after 2 attempts" for that directory
    And the sync exits with code 2

  Scenario: Cloud sync failure does not affect USB sync running at the same time
    Given USB-A is connected and the network is unavailable
    When the USB sync and cloud sync run simultaneously
    Then the USB sync completes successfully
    And the cloud sync failure is recorded independently
    And neither process corrupts the shared log

  Scenario: Partial cloud sync failure logs which directories failed and which succeeded
    Given ~/secureLocal syncs successfully
    And the cloud destination for ~/Projects is unreachable
    When the cloud sync runs
    Then the log records success for ~/secureLocal
    And the log records failure for ~/Projects
    And the sync exits with code 2

  # --- Infrastructure failure ---

  @infrastructure-failure @in-memory
  Scenario: Cloud sync tool is missing from its configured location
    Given the cloud tool path in the configuration points to a non-existent location
    When the cloud sync runs
    Then the sync stops with a configuration error
    And it exits with code 4

  @infrastructure-failure @in-memory
  Scenario: Cloud sync is interrupted after the first directory completes
    Given ~/secureLocal syncs successfully
    And the connection drops during ~/Projects sync
    When the cloud sync runs
    Then ~/secureLocal is fully mirrored
    And the interrupted ~/Projects sync is recorded as a failure
    And the sync exits with code 2
