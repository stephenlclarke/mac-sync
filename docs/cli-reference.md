# Command-line reference

<!-- markdownlint-disable MD013 -->

[Quick start](../README.md) · [Setup and workflow](../WORKFLOW.md) · [Configuration](configuration.md)

The CLI and desktop app use the same data repository and local configuration. Keep desktop build 63 closed while syncing; the [UI memory-growth fix](../SUPPORT.md#desktop-ui-memory-growth) is in development, not yet released.

## Commands

```sh
mac-sync sync
mac-sync restore
mac-sync restore --select
mac-sync restore --list-machines
mac-sync restore --from old-mbp
mac-sync secrets init
mac-sync packages diff --from old-mbp
mac-sync packages install --from old-mbp
mac-sync editor diff --from old-mbp
mac-sync editor install --from old-mbp
mac-sync secrets list --from old-mbp
mac-sync secrets restore --from old-mbp
mac-sync manifest list
mac-sync ui
mac-sync version
mac-sync help restore
mac-sync help secrets
mac-sync list
mac-sync status
```

Commands:

- `sync`: copy configured home paths into the machine snapshot, commit, and push
- `run`: service mode; exits successfully if the service is already running
- `restore`: copy a machine snapshot from `mac-sync-data` back into `$HOME` and re-clone missing GitHub repos
- `secrets`: manage encrypted secret snapshots with `age` and Apple Keychain
- `packages`: manage Homebrew snapshots, diffs, and installs
- `editor`: manage VS Code extension snapshots, diffs, and installs
- `manifest`: show configured and dynamically discovered backup paths
- `list`: show every configured source path and repo destination
- `status`: show repo, git, local status, and last-sync state
- `ui`: open the installed Mac Sync desktop app, reusing the existing app instance when it is already running
- `version` or `--version`: show the installed Mac Sync app version and build number
- `help [topic]`: show general help or command-specific help

During `sync`, in-progress work is shown with a compact three-dot figure-eight Braille marker from `mac-spinner`, and completed work is printed with a tick marker. Paths that are already unchanged stay quiet.

## Status

Show the current `mac-sync` version SHA, local repo paths, local status files, the last completed sync, the amount of data changed by that sync, total machine snapshot storage, warning or error messages, and the captured local Git changes that caused a pre-operation pull to be skipped:

```sh
mac-sync status
```

Sync status is local machine state and is intentionally not committed to the repo. By default it is written under:

```text
~/Library/Application Support/mac-sync/status/
```

Completed real syncs and restores also write one JSON record per run under `history/<machine-name>/` in that same directory. These records contain transfer metadata, typed health conditions, and credential-redacted command diagnostics; they never contain decrypted secret contents. A result is `success` only when all enabled work completed, `partial` when the usable snapshot completed but an optional subsystem was skipped, `deferred` when background work waits for resources or connectivity, and `failed` when the run stopped.

Use `brew services info mac-sync` for the optional Homebrew service status. The app shows its own automatic-sync schedule in **Settings → Automatic sync**.

## Restore

Restore the current machine snapshot:

```sh
mac-sync restore
```

When the current hostname has no snapshot, restore lists available snapshots from `~/github/mac-sync-data/machines/` and prompts for the source machine. Use `--select` to force that prompt even when the current hostname exists:

```sh
mac-sync restore --select
```

List available restore sources:

```sh
mac-sync restore --list-machines
```

Show restore help:

```sh
mac-sync help restore
```

Restore from another machine:

```sh
mac-sync restore --from old-mbp
```

Restore pulls the data repository when its worktree is clean, then copies the curated paths from the selected machine's `machines/<machine-name>/config/sync-paths.txt` plus its persisted dynamic paths from `~/github/mac-sync-data/machines/<machine-name>/dynamic-sync-paths.txt`. It also compares the selected machine's Homebrew snapshot with the local Homebrew and VS Code extension state and re-clones missing GitHub repositories from the selected machine's saved clone list into `~/github`.

By default, restore copies only missing files. Existing local files in `$HOME` remain the golden source regardless of their timestamp. Use `--force` only when you have explicitly decided to replace existing local files and resolve file/directory conflicts in favour of the snapshot:

```sh
mac-sync restore --from old-mbp --force
```

Preview a restore without changing local files:

```sh
MAC_SYNC_DRY_RUN=1 mac-sync restore --from old-mbp
```

In the Mac app on the destination Mac, browse the source under **Other Macs**, select the files or folders, and choose **Copy to This Mac**. This uses the shared `mac-sync-data` snapshot as the transfer medium and never changes the source Mac or its archive. Before the app writes any existing local files, it asks you to keep this Mac's copy or replace it with the selected peer snapshot. Select **Copy specific paths only** to review the exact paths. The CLI equivalent accepts one or more `--path` options:

```sh
mac-sync restore --from old-mbp --path .zshrc --path .config/tool
```

A selected-path restore intentionally skips Homebrew, VS Code, repository, and encrypted-secret restore steps; use the normal restore flow when those machine state hints are required.

When Homebrew packages differ, restore prints the manual commands needed to install missing taps, formulae, and casks or upgrade outdated packages from the synced list. It does not run those commands for you and it does not uninstall extra local packages.

When VS Code extensions differ, restore prints the manual `code` commands needed to reconcile the local extension set. It does not run those commands for you.

If an encrypted secrets snapshot exists for the selected machine, restore prints the `mac-sync secrets list` and `mac-sync secrets restore` commands to inspect or restore it. Normal restore never decrypts secrets automatically.

GitHub clone restore is conservative: it only uses real GitHub remotes captured from git worktrees under the configured GitHub root, strips credentials from stored remote URLs, and skips any target path that already exists.

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

`mac-sync secrets init` creates an `age` identity if needed, stores the private identity in Apple Keychain under `mac-sync age identity`, and adds only the public recipient to the shared registry:

```text
machines/_shared/config/age-recipients.txt
```

The encrypted secret paths are listed in:

```text
machines/<machine-name>/config/secret-paths.txt
```

By default, that file includes:

```text
.ssh
.secrets
```

Once at least one recipient is configured, a normal sync writes:

```text
~/github/mac-sync-data/machines/<machine-name>/secrets/secrets.tar.gz.age
~/github/mac-sync-data/machines/<machine-name>/secrets/included-paths.txt
~/github/mac-sync-data/machines/<machine-name>/secrets/recipients.txt
```

`recipients.txt` records the public recipients used for that archive. When the shared recipient registry changes, the next sync from a Mac that can decrypt the archive re-encrypts it for the new recipient set even when the secret files have not changed. This is how a newly trusted Mac gains access without exposing any secret values.

You can also update only the encrypted secret snapshot:

```sh
mac-sync secrets sync
```

Inspect an encrypted snapshot:

```sh
mac-sync secrets list --from old-mbp
```

In the Mac app, choose a machine and select **View Encrypted Secrets** to list the same encrypted archive's file and folder names with this Mac's Keychain identity. That view deliberately never displays secret values or writes files.

Restore encrypted secrets:

```sh
mac-sync secrets restore --from old-mbp
```

Without `--force`, restore refuses to overwrite existing local secret files. Use `--force` to overwrite files from the encrypted snapshot:

```sh
mac-sync secrets restore --from old-mbp --force
```

Test Keychain and current-machine archive access:

```sh
mac-sync secrets test
```

Each trusted Mac should run `mac-sync secrets init`, which adds that Mac's public recipient to the shared registry. The Mac app offers the same action as **Set Up This Mac's Access** when it cannot inspect an archive. It publishes only the public recipient and never replaces an archive that this Mac cannot decrypt. After adding a new Mac, run `mac-sync sync` once on each source Mac to re-encrypt its current archive for the new recipient.

Before replacing an existing encrypted archive, `mac-sync` decrypts and compares it with the new snapshot. If that verification fails, sync stops and preserves the existing archive. A normal sync performs the Keychain recipient and archive decryption checks before changing any managed snapshot files, so an access failure cannot leave a partially updated data repository.

## Packages

Homebrew package state is captured during normal `mac-sync sync` when `brew` is available. Manage it directly with:

```sh
mac-sync packages sync
mac-sync packages diff --from old-mbp
mac-sync packages install --from old-mbp
mac-sync packages install --from old-mbp --formulae-only
mac-sync packages install --from old-mbp --admin-user adm-sclarke
```

`packages diff` prints the same manual commands that `restore` prints. `packages install` runs `brew bundle install` from the selected machine snapshot. Use `--formulae-only` to skip casks, or `--admin-user` when cask installs need a different admin-capable account.

## Editor State

VS Code extension state is captured during normal `mac-sync sync` when the `code` CLI is available. Manage it directly with:

```sh
mac-sync editor sync
mac-sync editor diff --from old-mbp
mac-sync editor install --from old-mbp
```

`editor diff` prints the manual `code --install-extension` and `code --uninstall-extension` commands. `editor install` reconciles the local VS Code extensions to the selected machine snapshot.
