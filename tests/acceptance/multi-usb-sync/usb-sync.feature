@US-002 @real-io
Feature: Plugging in a registered USB drive backs up all mapped directories

  As Dan Fox
  I want every mapped directory backed up automatically when I plug in a registered USB drive
  So that I can protect my data without remembering which directories to sync manually

  Background:
    Given a valid configuration file with USB-A and USB-B registered
    And directories ~/secureLocal and ~/Projects are mapped to both USB devices

  # --- Happy path ---

  Scenario: All mapped directories are copied when USB-A connects
    Given USB-A is connected at its expected location
    When the USB sync runs
    Then ~/secureLocal is copied to the USB-A mount point
    And ~/Projects is copied to the USB-A mount point
    And the log records a success entry for each directory
    And the sync completes without errors

  Scenario: Target directory is created on the USB drive if it does not already exist
    Given USB-A is connected at its expected location
    And the target directory does not yet exist on the drive
    When the USB sync runs
    Then the target directory is created on the drive
    And the files are copied successfully

  Scenario: Sync does not remove files already on the USB drive
    Given USB-A is connected with existing files in the target directory
    When the USB sync runs
    Then previously existing files on the drive are not deleted
    And new files from the source are added

  # --- Independence scenarios ---

  @real-io
  Scenario: USB-B syncs independently without any knowledge of USB-A
    Given USB-B is connected at its expected location
    And USB-A is not connected
    When the USB sync runs
    Then ~/secureLocal is copied to the USB-B mount point
    And ~/Projects is copied to the USB-B mount point
    And no sync operation references the USB-A mount point
    And the sync completes without errors

  # --- Error paths ---

  Scenario: Unregistered drive connecting does not trigger any backup
    Given an unregistered USB drive is connected with identifier "FFFF-0000"
    When the USB sync runs
    Then no files are copied
    And the log records that no registered drive was found
    And the sync exits without errors

  Scenario: One directory failing to sync does not stop the remaining directories
    Given USB-A is connected at its expected location
    And ~/Projects does not exist on the source machine
    When the USB sync runs
    Then ~/secureLocal is still copied to the USB-A mount point
    And the log records a failure entry for ~/Projects with the reason
    And the sync exits with code 1

  Scenario: No drives connected results in a silent, successful exit
    Given no USB drives are connected
    When the USB sync runs
    Then no files are copied
    And the sync exits without errors

  # --- Infrastructure failure ---

  @infrastructure-failure @in-memory
  Scenario: Sync tool becomes unavailable mid-operation
    Given USB-A is connected at its expected location
    And the sync tool is unavailable
    When the USB sync runs
    Then the failure is recorded in the log
    And the sync exits with a non-zero code

  @infrastructure-failure @in-memory
  Scenario: USB drive disappears during sync
    Given USB-A is connected but disconnects during the copy operation
    When the USB sync runs for the first directory
    Then the log records the interrupted sync
    And the sync exits with code 1
    And any remaining directories are attempted
