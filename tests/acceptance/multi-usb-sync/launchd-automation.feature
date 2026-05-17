@US-006 @real-io
Feature: Both USB and cloud sync run automatically without any manual steps after install

  As Dan Fox
  I want two independent automation agents installed that run USB sync on drive mount and cloud sync hourly
  So that my data is protected automatically for both paths without me thinking about it

  Background:
    Given the installer is available and dependencies are satisfied

  # --- Happy path ---

  Scenario: Both automation agents are present and active after a clean install
    Given Dan runs the installer on a machine with no prior installation
    When the installer completes
    Then the USB sync automation agent is present in the user agents directory
    And the cloud sync automation agent is present in the user agents directory
    And both agents are registered with the system process manager
    And the system process manager shows two securelocal agents

  Scenario: USB sync automation agent is configured to watch for drive connections
    Given the USB sync automation agent has been installed
    When Dan inspects the agent configuration
    Then it is configured to trigger on changes to the drives mount location
    And it references the USB sync script at its correct absolute path

  Scenario: Cloud sync automation agent is configured to run on a timer
    Given the cloud sync automation agent has been installed
    When Dan inspects the agent configuration
    Then it is configured to run at the interval specified in the configuration file
    And it references the cloud sync script at its correct absolute path

  # --- Upgrade path ---

  Scenario: Old combined automation agent is removed when upgrading from version 1
    Given the previous combined automation agent (com.securelocal.sync) is installed and active
    When Dan runs the version 2 installer
    Then the old combined automation agent is deregistered
    And the old agent file is removed from the user agents directory
    And both new independent agents are installed and active
    And the old agent name no longer appears in the process manager list

  # --- Error paths ---

  Scenario: Installer reports failure clearly when an agent cannot be registered
    Given the cloud sync automation agent file cannot be loaded by the system process manager
    When the installer attempts to register it
    Then the installer outputs a clear message identifying which agent failed to load
    And the installer exits with a non-zero code

  Scenario: Running installer twice does not create duplicate automation agents
    Given the installer has already been run successfully
    When Dan runs the installer a second time
    Then the system process manager still shows exactly two securelocal agents
    And no duplicate agents are registered

  # --- Edge / boundary ---

  Scenario: Automation agents reference absolute script paths so they work from any directory
    Given both automation agents are installed
    When Dan inspects the agent configurations
    Then the script paths are absolute and do not rely on the current working directory
