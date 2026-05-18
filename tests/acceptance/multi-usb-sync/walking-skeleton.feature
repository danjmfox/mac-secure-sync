@walking_skeleton @real-io @US-001 @US-002 @US-003 @US-004
Feature: Dan can back up his files to a registered USB drive and the cloud

  As Dan Fox
  I want to plug in a registered USB drive and have my files backed up automatically
  So that I can work knowing my data is protected without any manual steps

  Background:
    Given Dan has a registered configuration with one directory, one USB device, and one cloud destination

  @walking_skeleton @real-io @US-001 @US-002
  Scenario: Files are copied to USB drive when a registered drive mounts
    Given a registered USB drive is connected
    When the USB sync runs
    Then the directory is copied to the USB drive
    And the sync log records a successful completion entry
    And the sync completes without errors

  @walking_skeleton @real-io @US-001 @US-003
  Scenario: Files are copied to the cloud on a timer when no USB is present
    Given no USB drive is connected
    When the cloud sync runs
    Then the directory is mirrored to its cloud destination
    And the sync log records a successful completion entry
    And the sync completes without errors

  @walking_skeleton @real-io @US-001 @US-004
  Scenario: Each sync operation produces a readable log entry
    Given a registered USB drive is connected
    When the USB sync runs
    Then the sync log contains a timestamped entry for the directory that was synced
    And the log entry identifies the outcome as a success
