# Configuration and snapshot layout

<!-- markdownlint-disable MD013 -->

[Quick start](../README.md) · [Setup and workflow](../WORKFLOW.md) · [CLI reference](cli-reference.md)

The installed app and default CLI use one private data checkout, normally `~/github/mac-sync-data`. They do not use the legacy `dot-files` repository unless a CLI compatibility override is explicitly selected.

Each Mac is the source for its own selected files: sync replaces that Mac's snapshot with its local copies, regardless of timestamps. Restoring a peer snapshot is a separate action; missing local files are added and existing files are kept unless replacement is explicitly requested.

```text
~/github/mac-sync-data/machines/<machine-name>/
```

## Paths and inventories

The configured backup paths for the current Mac are listed in:

```text
machines/<machine-name>/config/sync-paths.txt
```

Paths are relative to `$HOME` unless they start with `/`. Inspect the active manifest with:

```sh
mac-sync manifest list
mac-sync manifest configured
mac-sync manifest dynamic
mac-sync manifest source
```

At runtime, `mac-sync` also scans safe top-level dotfiles in `$HOME` and follows safe `$HOME`, `${HOME}`, and `~` references it finds. This keeps sourced files such as `~/.shellenv`, `~/.aliases`, `~/.functions`, and referenced plugin directories in the sync set without hand-editing the manifest every time a startup file changes. The generated per-machine dynamic list is persisted to:

```text
~/github/mac-sync-data/machines/<machine-name>/dynamic-sync-paths.txt
```

On later runs, paths that were previously dynamic but are no longer discovered are pruned from that machine snapshot, unless they overlap a curated path in the configured manifest.

Homebrew package state is captured during sync when `brew` is available. The generated per-machine lists are persisted to:

```text
~/github/mac-sync-data/machines/<machine-name>/homebrew/
```

That directory contains sorted `taps.txt`, `formulae.txt`, and `casks.txt` lists, plus a generated `Brewfile` for browsing or reuse.

VS Code extension state is captured during sync when `code` is available. The generated per-machine manifest is persisted to:

```text
~/github/mac-sync-data/machines/<machine-name>/editor/vscode-extensions.txt
```

If a Homebrew or VS Code inventory command fails, sync stops without replacing the previous package or extension snapshot with an empty result.

Git repositories under `~/github`, including nested paths such as `xyzzy.tools/fixdecoder_rs`, are captured during sync when they have at least one GitHub remote. The generated per-machine clone list is persisted to:

```text
~/github/mac-sync-data/machines/<machine-name>/github-repositories/repositories.txt
```

Each row stores the path relative to `~/github` and a credential-free GitHub clone URL. Non-GitHub remotes, submodules, and non-repo directories are ignored.

Before pushing a machine snapshot, `mac-sync` checks whether the data repository is behind its upstream branch and rebases only when needed. A configured remote pull is attempted up to three times. Mac Sync stops before changing managed snapshot files if it cannot verify that refresh. Unrelated local edits are preserved with Git autostash; changes inside the current machine snapshot remain visible as a health condition for manual review.

Rsync excludes are listed in:

```text
machines/<machine-name>/config/excludes.txt
```

Environment overrides:

- `MAC_SYNC_MACHINES_REPO`: mac-sync data repository path, defaulting to `~/github/mac-sync-data`
- `MAC_SYNC_REPO`: legacy-only separate command/config repository override. The installed app removes this override and uses `MAC_SYNC_MACHINES_REPO`.
- `MAC_SYNC_APP_CONFIG`: local app/service repository-location file, defaulting to `~/Library/Application Support/mac-sync/config.env`. Explicit environment variables take precedence over values in this file.
- `MAC_SYNC_MACHINE`: machine directory name, defaulting to the macOS host name
- `MAC_SYNC_STATUS_DIR`: local status directory, defaulting to `~/Library/Application Support/mac-sync/status`
- `MAC_SYNC_DRY_RUN=1`: preview sync or restore changes without writing files, committing, or pushing
- `MAC_SYNC_DYNAMIC_REFS=0`: disable dynamic dotfile reference discovery
- `MAC_SYNC_HOMEBREW=0`: disable Homebrew package snapshotting and restore command suggestions
- `MAC_SYNC_VSCODE_EXTENSIONS=0`: disable VS Code extension snapshotting and restore command suggestions
- `MAC_SYNC_GITHUB_ROOT`: local GitHub clone root, defaulting to `~/github`
- `MAC_SYNC_GITHUB_REPOS=0`: disable GitHub repository snapshotting and restore cloning
- `MAC_SYNC_SECRETS=0`: disable encrypted secret snapshotting and restore hints
- `MAC_SYNC_MANIFEST_SOURCE`: choose `config`, `auto`, or `dot-files`. The default `config` uses the current machine's `machines/<machine>/config/sync-paths.txt`. The `dot-files` option is a legacy compatibility mode only.
- `MAC_SYNC_KEYCHAIN_SERVICE`: Keychain service for the `age` identity, defaulting to `mac-sync age identity`
- `MAC_SYNC_KEYCHAIN_ACCOUNT`: Keychain account for the `age` identity, defaulting to `$USER` or `id -un`
- `SCRIPT_COLOUR=off`: disable colour output

## Security Notes

The regular dotfile sync list is explicit by design. Do not add raw secret material such as SSH private keys, cloud credentials, token files, shell history, or decrypted secret directories to `machines/<machine-name>/config/sync-paths.txt`. The private data repository should also ignore common credential-bearing paths under `machines/`, but the path manifest is still the real safety boundary.

Machine names and configured or persisted paths are validated before use. Machine names cannot be `.` or `..`, start with `-`, or contain characters outside letters, digits, `.`, `_`, and `-`; path traversal components are rejected.

Use encrypted secrets for `~/.ssh`, `~/.secrets`, or similar sensitive paths. Only encrypted `*.age` snapshots and public recipients belong in git. The private `age` identity must stay in Apple Keychain or another secret manager.

For encryption setup and recovery, see [Encrypted secrets](cli-reference.md#encrypted-secrets). Worker resource limits, bounded history and GitHub recovery are documented in [Architecture](architecture.md).
