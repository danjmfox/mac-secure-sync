@US-101
Feature: Dan retires a lost or replaced USB device without disturbing any other device

  As Dan Fox
  I want to remove a registered USB device by label or UUID
  So that config.yaml only ever lists devices I actually own, without risking damage to any other device's setup

  Background:
    Given config.yaml has 3 registered devices: IronKey-A (1A2B-3C4D), IronKey-B (5E6F-7A8B), IronKey-C (9C0D-1E2F)

  # --- Happy path ---

  @walking_skeleton @real-io @driving_port
  Scenario: Removing a device by label leaves other devices unchanged
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then usb_devices[] contains only IronKey-A and IronKey-B
    And IronKey-A's and IronKey-B's entries are byte-for-byte identical to before removal
    And the command output confirms "2 devices remain registered"

  @driving_port
  Scenario: Removing a device strips its UUID from every directory mapping
    Given both registered directories list IronKey-C's UUID in their usb_devices
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then neither directory's usb_devices list contains IronKey-C's UUID
    And both directory entries themselves still exist, only the UUID reference is removed

  @driving_port
  Scenario: Removing a device by UUID works identically to removing by label
    When Dan runs install.sh remove-device --uuid "9C0D-1E2F"
    Then IronKey-C is removed from usb_devices[] and every directory mapping
    And the outcome is identical to removal by label "IronKey-C"

  # --- Boundary ---

  @boundary @driving_port
  Scenario: Removing the only device mapped to a directory leaves an empty list, not an error
    Given a directory whose usb_devices list contains only IronKey-C's UUID
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then that directory's usb_devices list is an empty array
    And the command exits 0

  # --- Error paths ---

  @error-path @driving_port
  Scenario: Attempting to remove an unregistered label leaves config.yaml untouched
    When Dan runs install.sh remove-device --label "IronKey-Z"
    Then the command exits with a non-zero code
    And config.yaml is byte-for-byte unchanged
    And the error message names install.sh list-devices as the recovery step

  @error-path @driving_port
  Scenario: Attempting to remove an unregistered UUID leaves config.yaml untouched
    When Dan runs install.sh remove-device --uuid "FFFF-0000"
    Then the command exits with a non-zero code
    And config.yaml is byte-for-byte unchanged
    And the error message names install.sh list-devices as the recovery step

  @error-path @infrastructure-failure @driving_port
  Scenario: remove-device exits with a config error when config.yaml is missing
    Given config.yaml does not exist
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then the command exits with the config-error code

  @error-path @infrastructure-failure @driving_port
  Scenario: remove-device exits with a config error on malformed config.yaml
    Given config.yaml contains malformed YAML
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then the command exits with the config-error code

  @error-path @driving_port
  Scenario: remove-device requires an identifier
    When Dan runs install.sh remove-device with neither --label nor --uuid
    Then the command exits with a non-zero code
    And config.yaml is byte-for-byte unchanged

  @error-path @driving_port
  Scenario: remove-device rejects both --label and --uuid together
    When Dan runs install.sh remove-device --label "IronKey-C" --uuid "9C0D-1E2F"
    Then the command exits with a non-zero code
    And config.yaml is byte-for-byte unchanged

  # --- Infrastructure / write-safety ---

  @real-io @driving_port
  Scenario: remove-device writes the configuration atomically
    When Dan runs install.sh remove-device --label "IronKey-C"
    Then no temporary configuration file remains after removal completes
    And the final configuration is readable by both sync scripts

  # --- Security ---

  @security @driving_port
  Scenario: A label containing a double quote cannot break out of the config-mutation logic
    Given a registered device whose label contains an embedded double quote and a code-injection payload
    When Dan runs install.sh remove-device --label with that exact literal label
    Then the injected code is never executed
    And the device is matched and removed by its literal label
    And the command exits 0
