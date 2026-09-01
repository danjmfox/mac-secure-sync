@US-102
Feature: Dan confirms which USB devices are registered and currently mounted

  As Dan Fox
  I want to list every registered USB device along with its live mount state
  So that I can pick the right device to target for removal, or sanity-check my setup, in under 10 seconds

  # --- Happy path ---

  @walking_skeleton @real-io @driving_port
  Scenario: Listing devices shows every registered device with UUID and label
    Given config.yaml has 3 registered USB devices: IronKey-A, IronKey-B, IronKey-C
    When Dan runs install.sh list-devices
    Then the output lists all 3 devices, each with its label and UUID
    And the output states "3 devices registered"

  @real-io @driving_port
  Scenario: A currently mounted device shows its live mount path
    Given IronKey-A is registered and mounted at /Volumes/IronKey-A
    When Dan runs install.sh list-devices
    Then IronKey-A's row shows "mounted" and the path /Volumes/IronKey-A

  @driving_port
  Scenario: A registered but not-mounted device shows "not mounted"
    Given IronKey-C is registered but not currently mounted
    When Dan runs install.sh list-devices
    Then IronKey-C's row shows "not mounted" with no path

  # --- Boundary ---

  @boundary @driving_port
  Scenario: Listing devices with none registered shows a helpful empty state
    Given config.yaml has an empty usb_devices[] list
    When Dan runs install.sh list-devices
    Then the output reads "No USB devices registered. Run install.sh add-device to register one."
    And the command exits 0

  # --- Error paths ---

  @error-path @infrastructure-failure @driving_port
  Scenario: list-devices exits with a config error when config.yaml is missing
    Given config.yaml does not exist
    When Dan runs install.sh list-devices
    Then the command exits with the config-error code

  @error-path @infrastructure-failure @driving_port
  Scenario: list-devices exits with a config error on malformed config.yaml
    Given config.yaml contains malformed YAML
    When Dan runs install.sh list-devices
    Then the command exits with the config-error code

  @error-path @infrastructure-failure @driving_port
  Scenario: list-devices treats an unreadable mount query as "not mounted" rather than failing
    Given a registered device whose live mount lookup cannot be resolved
    When Dan runs install.sh list-devices
    Then that device's row shows "not mounted"
    And the command still exits 0

  # --- Property / invariant ---

  @property @driving_port
  Scenario: list-devices never modifies config.yaml regardless of registry contents
    Given config.yaml has any combination of registered devices, mounted or not
    When Dan runs install.sh list-devices
    Then config.yaml is byte-for-byte unchanged before and after the command runs

  # --- Adapter integration (ADR-004 regression probe) ---

  @real-io @adapter-integration @driving_port
  Scenario: list-devices and sync-usb.sh agree on live mount state for the same device
    Given IronKey-A is registered and mounted at /Volumes/IronKey-A
    When Dan runs install.sh list-devices
    And sync-usb.sh independently evaluates the same mounted state
    Then both report IronKey-A as mounted at the same path

  # --- Security ---

  @security @driving_port
  Scenario: A label containing a single quote cannot break out of the label-rendering logic
    Given a registered device whose label contains an embedded single quote and a code-injection payload
    When Dan runs install.sh list-devices
    Then the injected code is never executed
    And the device's literal label is rendered in the output
    And the command exits 0
