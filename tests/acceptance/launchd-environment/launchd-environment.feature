Feature: Scripts run in launchd's environment
  launchd starts agents with PATH=/usr/bin:/bin:/usr/sbin:/sbin and /bin/bash (3.2).

  Scenario: USB sync runs under bash 3.2
    Given a registered drive is mounted
    When sync-usb.sh runs under /bin/bash with launchd's environment
    Then the directory is copied and no bash error is printed

  Scenario: Cloud sync and installer run under bash 3.2
    When sync-cloud.sh and install.sh list-devices run under /bin/bash
    Then both succeed and every script under bin/ parses with /bin/bash -n

  Scenario: A dataless file is skipped, the rest of the directory syncs
    Given a directory with a dataless file and resident files
    When USB sync runs
    Then the resident files are copied and the dataless file is not
    And a WARN line names the skipped file
    And the final status says "completed with skips" with the count
    And the exit code is 3, not 0

  Scenario: Names with spaces and glob characters
    Given a dataless file named "we ird [1] *.bin" and resident files whose names the unescaped pattern would match
    When USB sync runs
    Then only the dataless file is skipped

  Scenario Outline: rsync partial-transfer exits
    Given rsync exits <code>
    Then the job completes with skips (exit 3) without retrying
    Examples:
      | code |
      | 23   |
      | 24   |

  Scenario: Other rsync failures still fail after one retry
    Given rsync exits 20
    Then rsync is retried once after 30 seconds and the job exits 1

  Scenario: A clean run reports clean success
    Given no dataless files
    Then the final status is "completed successfully" and the exit code is 0

  Scenario: Installer refuses when launchd's python3 lacks PyYAML
    Given python3 under launchd's PATH cannot import yaml
    When install.sh runs (interactive, --non-interactive, or add-device)
    Then it exits non-zero naming "/usr/bin/python3 -m pip install --user pyyaml"
    And writes no config, no plist, and never calls launchctl
