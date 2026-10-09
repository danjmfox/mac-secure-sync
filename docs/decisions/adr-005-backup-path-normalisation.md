---
status: accepted
date: 2026-10-08
feature: backup-path-handling
---

# ADR-005: Normalise the rclone backup path and create it private

## Context

`bin/install.sh` offers to copy `~/.config/rclone/rclone.conf` to a location the user types. That file holds a Google OAuth token and the obscured passwords of the rclone crypt remote, so loss or exposure matters. The prompt used `read -rp`, which delivers the typed text literally. Typing `~/crypt-backup` therefore reached `mkdir -p` as a relative path, and the installer created a directory named `~` under the current working directory and put the config in it. The copy was also created with the user's default umask, so the directories were 755 and the file followed the source mode.

## Options Considered

### Option A (chosen): pure `normalise_backup_path <raw> <home>` in `install.sh`, with a re-prompt loop

A leading `~` or `~/` is replaced by `$HOME` using parameter expansion. Any result not starting with `/` returns non-zero, and the caller prints a message and asks again. Empty input (or end of input) skips the backup as before. `~user` forms are not expanded and, being relative, are rejected. The function sits in `install.sh` because it has one consumer. `install.sh` now runs `main` only when executed directly (`BASH_SOURCE[0] == $0`), so tests source it and drive the real `backup_rclone_config`.

### Option B (rejected): `eval echo "${raw}"`

Expands `~` and `~user`, but also executes command substitutions in whatever is typed. The repo removed `eval` from the sync scripts for that reason (injection fix, PR 5).

### Option C (rejected): put the function in `bin/lib/usb-common.sh`

ADR-004 reserves that file for USB matching. A backup-path helper there mixes concerns for no second consumer.

### Option D (rejected): resolve relative paths against `$HOME` or the cwd

Silently picks a location the user did not state, for a file holding credentials. Rejecting is safer than guessing.

## Decision

Adopt Option A. Directory and file creation run in a subshell with `umask 077`, so every directory the installer creates, including intermediate parents, is mode 700, and the copied file is mode 600. A directory that already exists keeps its mode, because the user may have chosen a mount point or shared folder and the installer should not change permissions it did not create.

## Exceptions

- Trailing-component quirks such as `~/` alone resolve to `$HOME` itself, which is accepted as typed.
- A path containing `..` is not canonicalised; it is absolute and therefore allowed.
- Backups already written to a stray `~` directory by earlier installer versions are not migrated. Move or delete them by hand and tighten their permissions.
