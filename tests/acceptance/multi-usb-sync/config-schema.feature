@US-001 @real-io
Feature: Configuration file describes all sync targets in a readable, structured format

  As Dan Fox
  I want a single configuration file that clearly maps each directory to its USB devices and cloud destination
  So that I can understand and verify my backup setup at a glance without consulting documentation

  Background:
    Given the installer has completed successfully

  # --- Happy path ---

  Scenario: Installer produces a configuration file with the correct structure
    Given Dan provided USB volume "IronKey-A" and cloud destination "remote-crypt:secureLocal" during setup
    When the installer completes
    Then the configuration file exists at the expected location
    And it contains a directories entry for the local directory with its cloud destination
    And it contains a registered devices entry with the detected device identifier and label "IronKey-A"
    And the configuration version is marked as 2

  Scenario: Configuration file with two directories maps each to its own cloud destination
    Given the configuration contains two directory entries:
      | directory      | cloud destination             |
      | ~/secureLocal  | remote-crypt:secureLocal      |
      | ~/Projects     | remote-crypt:Projects         |
    When the cloud sync reads the configuration
    Then it identifies two separate cloud destinations
    And each directory maps to its own distinct destination

  # --- Error paths (target >= 40%) ---

  Scenario: Schema version mismatch prevents sync and surfaces a clear message
    Given a configuration file with version 1 exists
    When the USB sync starts
    Then it stops immediately with a configuration error
    And the log records "Config schema version mismatch" with the versions found and expected
    And it exits with code 4

  Scenario: Schema version mismatch also prevents cloud sync
    Given a configuration file with version 1 exists
    When the cloud sync starts
    Then it stops immediately with a configuration error
    And it exits with code 4

  Scenario: Missing configuration file prevents sync from starting
    Given no configuration file exists
    When the USB sync starts
    Then it stops immediately with a configuration error
    And the error message identifies the missing configuration
    And it exits with code 4

  Scenario: Malformed configuration file prevents sync from starting
    Given a configuration file exists but contains invalid content
    When the USB sync starts
    Then it stops immediately with a configuration error
    And it exits with code 4

  # --- Edge / boundary ---

  Scenario: Configuration file with two USB devices and two directories is fully valid
    Given a configuration file with two USB devices (UUID-A, UUID-B) and two directories
    When the USB sync reads the configuration
    Then it identifies both registered devices
    And it identifies both directories and their assigned devices

  @property
  Scenario: Configuration loading is repeatable and produces identical output on every call
    Given a valid configuration file
    When the configuration is loaded twice in succession
    Then both loads produce identical variables
