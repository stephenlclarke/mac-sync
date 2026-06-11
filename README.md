# mac-sync

`mac-sync` keeps a curated snapshot of important Mac dotfiles and Homebrew
packages in git, split by machine name. This repo owns the command and config;
machine snapshots live in the separate `stephenlclarke/dot-files` repo.

Snapshots are written to:

```text
~/github/dot-files/machines/<machine-name>/
```

The reusable sync command lives in:

```text
bin/mac-sync
```

See [WORKFLOW.md](WORKFLOW.md) for the full download, setup, install, sync, and
restore runbook.

## Install

From this repo:

```sh
./bin/mac-sync install
```

The machine snapshot repo must also exist locally:

```sh
git clone https://github.com/stephenlclarke/dot-files ~/github/dot-files
```

That command:

- installs `mac-sync` to `~/bin/mac-sync`
- installs the spinner helper to `~/bin/mac-spinner`
- writes `~/Library/LaunchAgents/tools.xyzzy.mac-sync.plist`
- loads the LaunchAgent into the current GUI session
- schedules an hourly run at minute `0`

Override install-time settings when needed:

```sh
MAC_SYNC_MACHINE=work-mbp MAC_SYNC_HOURLY_MINUTE=17 ./bin/mac-sync install
```

## Usage

```sh
mac-sync sync
mac-sync restore
mac-sync restore --from old-mbp
mac-sync secrets init
mac-sync secrets list --from old-mbp
mac-sync secrets restore --from old-mbp
mac-sync help restore
mac-sync help secrets
mac-sync list
mac-sync status
mac-sync uninstall
```

Commands:

- `install`: install or refresh the command and hourly LaunchAgent
- `uninstall`: unload the LaunchAgent and remove the installed command
- `sync`: copy configured home paths into the machine snapshot, commit, and push
- `run`: LaunchAgent mode; same behavior as `sync`
- `restore`: copy a machine snapshot from `dot-files` back into `$HOME`
- `secrets`: manage encrypted secret snapshots with `age` and Apple Keychain
- `list`: show every configured source path and repo destination
- `status`: show install, LaunchAgent, repo, git, and last-sync state
- `help [topic]`: show general help or command-specific help

During `sync`, in-progress work is shown with a compact rotating Braille-dot
marker from `mac-spinner`, and completed work is printed with a tick marker.
Paths that are already unchanged stay quiet.

## Status

Show current install state, the LaunchAgent state, the next scheduled run, the
last completed sync, the amount of data changed by that sync, total machine
snapshot storage, and warning or error messages captured during the last sync:

```sh
mac-sync status
```

Sync status is local machine state and is intentionally not committed to the
repo. By default it is written under:

```text
~/Library/Application Support/mac-sync/status/
```

The status output also shows the LaunchAgent stdout and stderr log paths.

## Restore

Restore the current machine snapshot:

```sh
mac-sync restore
```

Show restore help:

```sh
mac-sync help restore
```

Restore from another machine:

```sh
mac-sync restore --from old-mbp
```

Restore pulls both repos first when their worktrees are clean, then copies the
curated paths from `config/sync-paths.txt` plus the selected machine's persisted
dynamic paths from `~/github/dot-files/machines/<machine-name>/dynamic-sync-paths.txt`.
It also compares the selected machine's Homebrew snapshot with the local
Homebrew state.

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

If an encrypted secrets snapshot exists for the selected machine, restore prints
the `mac-sync secrets list` and `mac-sync secrets restore` commands to inspect
or restore it. Normal restore never decrypts secrets automatically.

## Encrypted Secrets

Install the required tools:

```sh
brew install age gnu-tar
```

Initialize this Mac's encryption identity:

```sh
mac-sync secrets init
```

Show encrypted secrets help:

```sh
mac-sync help secrets
```

That command creates an `age` identity if needed, stores the private identity in
Apple Keychain under `mac-sync age identity`, and adds only the public recipient
to:

```text
config/age-recipients.txt
```

The encrypted secret paths are listed in:

```text
config/secret-paths.txt
```

By default, that file includes:

```text
.ssh
.secrets
```

Once at least one recipient is configured, hourly sync writes:

```text
~/github/dot-files/machines/<machine-name>/secrets/secrets.tar.gz.age
~/github/dot-files/machines/<machine-name>/secrets/included-paths.txt
```

You can also update only the encrypted secret snapshot:

```sh
mac-sync secrets sync
```

Inspect an encrypted snapshot:

```sh
mac-sync secrets list --from old-mbp
```

Restore encrypted secrets:

```sh
mac-sync secrets restore --from old-mbp
```

Without `--force`, restore refuses to overwrite existing local secret files.
Use `--force` to overwrite files from the encrypted snapshot:

```sh
mac-sync secrets restore --from old-mbp --force
```

Test Keychain and current-machine archive access:

```sh
mac-sync secrets test
```

Each trusted Mac should run `mac-sync secrets init`, which adds that Mac's public
recipient to the repo. Future encrypted snapshots are encrypted to every
recipient in `config/age-recipients.txt`, so any matching Keychain identity can
decrypt them.

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
~/github/dot-files/machines/<machine-name>/dynamic-sync-paths.txt
```

On later runs, paths that were previously dynamic but are no longer discovered
are pruned from that machine snapshot, unless they overlap a curated path in
the configured manifest.

Homebrew package state is captured during sync when `brew` is available. The
generated per-machine lists are persisted to:

```text
~/github/dot-files/machines/<machine-name>/homebrew/
```

That directory contains sorted `taps.txt`, `formulae.txt`, and `casks.txt`
lists, plus a generated `Brewfile` for browsing or reuse.

Rsync excludes are listed in:

```text
config/excludes.txt
```

Environment overrides:

- `MAC_SYNC_REPO`: mac-sync command/config repo path, defaulting to
  `~/github/mac-sync`
- `MAC_SYNC_MACHINES_REPO`: machine snapshot repo path, defaulting to
  `~/github/dot-files`
- `MAC_SYNC_MACHINE`: machine directory name, defaulting to the macOS host name
- `MAC_SYNC_INSTALL_PATH`: installed command path, defaulting to `~/bin/mac-sync`
- `MAC_SYNC_HOURLY_MINUTE`: LaunchAgent minute, defaulting to `0`
- `MAC_SYNC_DAILY_MINUTE`: legacy alias for `MAC_SYNC_HOURLY_MINUTE`
- `MAC_SYNC_LAUNCH_AGENT_PATH`: `PATH` used by the LaunchAgent, defaulting to
  `~/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`
- `MAC_SYNC_STATUS_DIR`: local status directory, defaulting to
  `~/Library/Application Support/mac-sync/status`
- `MAC_SYNC_DRY_RUN=1`: preview sync or restore changes without writing files,
  committing, or pushing
- `MAC_SYNC_DYNAMIC_REFS=0`: disable dynamic dotfile reference discovery
- `MAC_SYNC_HOMEBREW=0`: disable Homebrew package snapshotting and restore
  command suggestions
- `MAC_SYNC_SECRETS=0`: disable encrypted secret snapshotting and restore hints
- `MAC_SYNC_MANIFEST_SOURCE`: choose `auto`, `dot-files`, or `config`.
  The default `auto` uses `make print-mac-sync-paths` from the `dot-files`
  repo when available, then falls back to `config/sync-paths.txt`.
- `MAC_SYNC_SELF_UPDATE=0`: disable the remote self-update check during
  `sync` and `secrets sync`
- `MAC_SYNC_SELF_UPDATE_MODE=exit`: install an updated command and exit instead
  of restarting automatically. The default is `restart`.
- `MAC_SYNC_SELF_UPDATE_REMOTE`: override the Git remote used for self-updates.
  By default this is the local mac-sync origin, falling back to
  `https://github.com/stephenlclarke/mac-sync.git`.
- `MAC_SYNC_SELF_UPDATE_REF`: branch or ref used for self-updates, defaulting
  to `main`
- `MAC_SYNC_KEYCHAIN_SERVICE`: Keychain service for the `age` identity,
  defaulting to `mac-sync age identity`
- `MAC_SYNC_KEYCHAIN_ACCOUNT`: Keychain account for the `age` identity,
  defaulting to `$USER` or `id -un`
- `SCRIPT_COLOUR=off`: disable colour output

## Self Update

The GitHub remote is the canonical source for `bin/mac-sync` and
`bin/mac-spinner`. At the start of `sync` and `secrets sync`, the installed
`~/bin/mac-sync` command checks the configured remote ref directly with
`git ls-remote`.

When the local mac-sync checkout is clean and exactly matches that remote commit,
the installed command updates from the local checkout. If the checkout is stale
or dirty, `mac-sync` clones the remote ref to a temporary directory and updates
from that clone instead.

By default, an updated installed command restarts itself and continues the sync
with the new script. Set `MAC_SYNC_SELF_UPDATE_MODE=exit` to keep the older
behavior of installing the update and asking you to re-run, or
`MAC_SYNC_SELF_UPDATE=0` to disable the check.

## Security Notes

The regular dotfile sync list is explicit by design. Do not add raw secret
material such as SSH private keys, cloud credentials, token files, shell
history, or decrypted secret directories to `config/sync-paths.txt`.
The machine snapshot repo should also ignore common credential-bearing paths
under `machines/`, but the path manifest is still the real safety boundary.

Use encrypted secrets for `~/.ssh`, `~/.secrets`, or similar sensitive paths.
Only encrypted `*.age` snapshots and public recipients belong in git. The
private `age` identity must stay in Apple Keychain or another secret manager.

## License

This repository is licensed under the GNU Affero General Public License v3.0
(AGPL-3.0). See `LICENSE`, `LICENSE.md`, and `NOTICE.md`.
