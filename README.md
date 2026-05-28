# mac-sync

`mac-sync` keeps a curated snapshot of important Mac dotfiles in git, split by
machine name.

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
mac-sync list
mac-sync status
mac-sync uninstall
```

Commands:

- `install`: install or refresh the command and daily LaunchAgent
- `uninstall`: unload the LaunchAgent and remove the installed command
- `sync`: copy configured home paths into the machine snapshot, commit, and push
- `run`: LaunchAgent mode; same behavior as `sync`
- `list`: show every configured source path and repo destination
- `status`: show install, LaunchAgent, repo, and git state

## Configuration

The synced paths are listed in:

```text
config/sync-paths.txt
```

Paths are relative to `$HOME` unless they start with `/`.

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
- `MAC_SYNC_DRY_RUN=1`: preview rsync changes without committing or pushing
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
