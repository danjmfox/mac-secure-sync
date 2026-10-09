@US-201
Feature: Dan backs up rclone.conf to a location he typed, and it lands where he meant

  As Dan Fox
  I want the installer's backup prompt to expand "~" and refuse relative paths
  So that rclone.conf (OAuth token and crypt passwords) is never written to a stray folder under the current directory

  @walking_skeleton @real-io @driving_port
  Scenario: A path typed with a leading tilde is backed up under the home directory
    Given a home directory containing ~/.config/rclone/rclone.conf
    When Dan answers "y" and enters "~/crypt-backup" at the backup prompt
    Then rclone.conf.backup-<date> exists in $HOME/crypt-backup
    And no directory named "~" exists in the current directory

  @real-io @driving_port
  Scenario: A relative path is rejected and nothing is created
    When Dan answers "y", enters "x/y", then enters nothing at the backup prompt
    Then the installer says the path must be absolute
    And no directory "x" exists in the current directory
    And the backup is skipped

  @real-io @driving_port
  Scenario: An absolute path still works
    When Dan answers "y" and enters an absolute path
    Then rclone.conf.backup-<date> exists in that directory

  @real-io @driving_port
  Scenario: Backup directories are private
    When Dan answers "y" and enters "~/a/b/c"
    Then every directory the installer created is mode 700
    And the backup file is mode 600
