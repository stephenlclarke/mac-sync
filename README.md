# mac-sync

`mac-sync` keeps a curated snapshot of important Mac dotfiles and Homebrew
packages in git, split by machine name.

Snapshots are written to:

```text
machines/<machine-name>/
```

The reusable sync command lives in:

```text
bin/mac-sync
```

## Install

From this repo:

```sh
./bin/mac-sync install
```

That command:

- installs `mac-sync` to `~/bin/mac-sync`
- writes `~/Library/LaunchAgents/tools.xyzzy.mac-sync.plist`
- loads the LaunchAgent into the current GUI session
- schedules a daily run at 09:00 local time

Override install-time settings when needed:

```sh
MAC_SYNC_MACHINE=work-mbp MAC_SYNC_DAILY_HOUR=8 ./bin/mac-sync install
```

## Usage

```sh
mac-sync sync
mac-sync restore
mac-sync restore --from old-mbp
mac-sync list
mac-sync status
mac-sync uninstall
```

Commands:

- `install`: install or refresh the command and daily LaunchAgent
- `uninstall`: unload the LaunchAgent and remove the installed command
- `sync`: copy configured home paths into the machine snapshot, commit, and push
- `run`: LaunchAgent mode; same behavior as `sync`
- `restore`: copy a machine snapshot from the repo back into `$HOME`
- `list`: show every configured source path and repo destination
- `status`: show install, LaunchAgent, repo, and git state

## Restore

Restore the current machine snapshot:

```sh
mac-sync restore
```

Restore from another machine:

```sh
mac-sync restore --from old-mbp
```

Restore pulls the repo first when the worktree is clean, then copies the curated
paths from `config/sync-paths.txt` plus the selected machine's persisted dynamic
paths from `machines/<machine-name>/dynamic-sync-paths.txt`. It also compares
the selected machine's Homebrew snapshot with the local Homebrew state.

By default, restore copies missing files and files that are newer in the repo
snapshot while keeping newer local files in `$HOME`. Use `--force` to overwrite
newer local files and resolve file/directory conflicts in favor of the snapshot:

```sh
mac-sync restore --from old-mbp --force
```

Preview a restore without changing local files:

```sh
MAC_SYNC_DRY_RUN=1 mac-sync restore --from old-mbp
```

When Homebrew packages differ, restore prints the manual commands needed to
install missing taps, formulae, and casks or upgrade outdated packages from the
synced list. It does not run those commands for you and it does not uninstall
extra local packages.

## Configuration

The synced paths are listed in:

```text
config/sync-paths.txt
```

Paths are relative to `$HOME` unless they start with `/`.

At runtime, `mac-sync` also scans safe top-level dotfiles in `$HOME` and follows
safe `$HOME`, `${HOME}`, and `~` references it finds. This keeps sourced files
such as `~/.shellenv`, `~/.aliases`, `~/.functions`, and referenced plugin
directories in the sync set without hand-editing the manifest every time a
startup file changes. The generated per-machine dynamic list is persisted to:

```text
machines/<machine-name>/dynamic-sync-paths.txt
```

On later runs, paths that were previously dynamic but are no longer discovered
are pruned from that machine snapshot, unless they overlap a curated path in
`config/sync-paths.txt`.

Homebrew package state is captured during sync when `brew` is available. The
generated per-machine lists are persisted to:

```text
machines/<machine-name>/homebrew/
```

That directory contains sorted `taps.txt`, `formulae.txt`, and `casks.txt`
lists, plus a generated `Brewfile` for browsing or reuse.

Rsync excludes are listed in:

```text
config/excludes.txt
```

Environment overrides:

- `MAC_SYNC_REPO`: repo path, defaulting to `~/github/mac-sync`
- `MAC_SYNC_MACHINE`: machine directory name, defaulting to the macOS host name
- `MAC_SYNC_INSTALL_PATH`: installed command path, defaulting to `~/bin/mac-sync`
- `MAC_SYNC_DAILY_HOUR`: LaunchAgent hour, defaulting to `9`
- `MAC_SYNC_DAILY_MINUTE`: LaunchAgent minute, defaulting to `0`
- `MAC_SYNC_DRY_RUN=1`: preview sync or restore changes without writing files,
  committing, or pushing
- `MAC_SYNC_DYNAMIC_REFS=0`: disable dynamic dotfile reference discovery
- `MAC_SYNC_HOMEBREW=0`: disable Homebrew package snapshotting and restore
  command suggestions
- `SCRIPT_COLOUR=off`: disable colour output

## Self Update

The repo copy at `bin/mac-sync` is canonical. Each sync pulls the repo first
when the worktree is clean. If that updates `bin/mac-sync` while the installed
`~/bin/mac-sync` command is running, the command updates itself, exits, and asks
you to re-run the sync with the new script.

## Security Notes

The sync list is explicit by design. Do not add raw secret material such as SSH
private keys, cloud credentials, token files, shell history, or decrypted secret
directories. `.gitignore` blocks several common credential paths under
`machines/`, but the path manifest is still the real safety boundary.

## License

This repository is licensed under the GNU Affero General Public License v3.0
(AGPL-3.0). See `LICENSE`, `LICENSE.md`, and `NOTICE.md`.
