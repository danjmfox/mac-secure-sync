@US-005 @real-io
Feature: Dan can register a second USB device without disrupting the first

  As Dan Fox
  I want to add USB-B to my backup configuration
  So that I can keep a separate offsite drive syncing the same directories without any risk to USB-A's setup

  Background:
    Given USB-A (device identifier UUID-A, label "IronKey-A") is registered and backing up correctly

  # --- Happy path ---

  Scenario: Registering USB-B adds it to the configuration without changing USB-A
    When Dan registers USB-B with label "IronKey-B"
    Then the configuration lists both USB-A and USB-B as registered devices
    And each directory entry now includes both UUID-A and UUID-B in its device list
    And the UUID-A entry in the configuration is unchanged from before registration

  Scenario: USB-B syncs all directories on first connection after registration
    Given USB-B has just been registered
    When USB-B connects
    Then the USB sync copies all registered directories to the USB-B mount point
    And the sync exits without errors

  @real-io
  Scenario: The registered device identifier matches the actual drive's identifier
    Given USB-B is connected at /Volumes/IronKey-B
    When Dan registers USB-B
    Then the identifier written to the configuration matches the drive's volume identifier exactly

  # --- Error paths ---

  Scenario: Registering a device that is already registered is rejected without modifying the configuration
    Given UUID-A is already in the configuration as "IronKey-A"
    When Dan attempts to register UUID-A again
    Then the tool outputs that the device is already registered as "IronKey-A"
    And the configuration file is not modified
    And the tool exits with a non-zero code

  Scenario: Registration with no USB drive connected exits with a clear message
    Given no USB drive is connected
    When Dan runs the device registration
    Then the tool exits with a message indicating no drive was found
    And the configuration is not modified

  Scenario: Interrupted registration does not leave a partial configuration file
    Given USB-B is connected and ready for registration
    When the registration process is interrupted after starting the configuration write
    Then no partial configuration file is present
    And the original configuration file is intact
    And the configuration is readable by both sync scripts

  # --- Edge / boundary ---

  Scenario: Configuration is written atomically during registration
    Given USB-B is connected
    When Dan registers USB-B
    Then no temporary configuration file remains after registration completes
    And the final configuration contains both devices
