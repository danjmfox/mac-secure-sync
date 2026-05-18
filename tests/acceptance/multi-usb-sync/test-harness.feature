@US-007 @infrastructure
Feature: Test harness covers the new configuration format and multi-device scenarios

  As Dan Fox (as builder)
  I want the test harness to verify all sync behaviours against the new configuration format
  So that I can commit changes with confidence that no sync behaviour has been silently broken

  Background:
    Given the test harness creates an isolated temporary environment for each test
    And the isolated environment includes mock versions of all system tools

  # --- Happy path ---

  Scenario: Test harness verifies that USB-A sync does not touch the USB-B mount point
    Given a test configuration with both UUID-A and UUID-B registered
    And the mock drive environment contains only UUID-A
    When the USB sync runs under the test harness
    Then the sync tool is called only for paths under the UUID-A mount point
    And no sync call references a path under the UUID-B mount point

  Scenario: Test harness verifies cloud sync runs correctly without any drive present
    Given a test configuration with two directories and their cloud destinations
    And no mock drives are present
    When the cloud sync runs under the test harness
    Then the cloud tool is called once for each directory
    And the sync exits without errors

  Scenario: Test harness verifies schema version mismatch produces exit code 4
    Given a test configuration file with version 1
    When either sync script runs under the test harness
    Then it exits with code 4
    And the output contains "schema version mismatch"

  Scenario: Test harness verifies partial directory failure produces exit code 1 for USB sync
    Given a test configuration with two directories
    And one source directory does not exist
    When the USB sync runs under the test harness
    Then it exits with code 1
    And the successful directory is recorded in the log

  Scenario: Test harness verifies duplicate device registration is rejected
    Given a test configuration with UUID-A already registered
    When the registration tool attempts to register UUID-A again
    Then it exits with a non-zero code
    And the test configuration file is unchanged

  # --- Infrastructure / harness itself ---

  Scenario: Each test run uses its own isolated directory and does not affect other tests
    Given two test functions run in sequence
    When the first test modifies files in its environment
    Then the second test sees its own clean environment
    And no files from the first test are present in the second test's environment

  Scenario: Test harness cleans up all temporary files after each test completes
    Given a test run has completed (pass or fail)
    When the teardown runs
    Then no temporary directories remain from that test run

  Scenario: Mock system tools are confined to the test environment path
    Given the test harness sets up mock tools in the isolated environment
    When a sync script invokes a system tool
    Then the mock version is called rather than the real system tool
    And the real system tool is not invoked during the test run
