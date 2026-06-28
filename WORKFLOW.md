# mac-sync Workflow

This workflow describes how to download, configure, install, sync, restore, and update `mac-sync` on a Mac.

`mac-sync` is implemented as a SwiftPM package and installed as a Homebrew-managed binary. The CLI does not install or remove itself; Homebrew owns the installed executables and the launchd service.

`mac-sync` uses two repositories:

- `~/github/mac-sync`: command, backup/restore configuration, tests, and documentation
- `~/github/dot-files`: per-machine snapshots under `machines/<machine-name>/`
  including dotfiles, Homebrew state, VS Code extension state, encrypted secrets,
  and GitHub clone inventory

## End-to-End Flow

<!-- markdownlint-disable MD013 -->

```mermaid
flowchart TD
  A["Start on a Mac"] --> B["Install with Homebrew<br/>brew tap stephenlclarke/tap<br/>brew install mac-sync"]
  B --> C["Clone config repo<br/>git clone https://github.com/stephenlclarke/mac-sync ~/github/mac-sync"]
  B --> D["Clone snapshot repo<br/>git clone https://github.com/stephenlclarke/dot-files ~/github/dot-files"]
  C --> E["Review sync paths<br/>mac-sync manifest configured"]
  D --> E
  E --> F["Start Homebrew service<br/>brew services start mac-sync"]
  F --> G{"Existing machine snapshot?<br/>find ~/github/dot-files/machines -maxdepth 1 -type d"}
  G -- "No" --> H["Run initial sync<br/>mac-sync sync"]
  G -- "Yes" --> I["Preview restore<br/>MAC_SYNC_DRY_RUN=1 mac-sync restore --select"]
  I --> J["Restore selected machine snapshot<br/>mac-sync restore --select"]
  J --> K["Apply packages/editor state if needed<br/>mac-sync packages install ...<br/>mac-sync editor install ..."]
  J --> L["Restore encrypted secrets if needed<br/>mac-sync secrets restore --from old-mbp"]
  H --> M["Check hourly automation<br/>mac-sync status"]
  K --> M
  L --> M
```

<!-- markdownlint-enable MD013 -->

## Download

Install Homebrew first if this Mac does not already have it. Then install the
released Swift binary and runtime dependencies from Homebrew:

```sh
brew tap stephenlclarke/tap
brew install mac-sync
```

Clone both repositories for configuration and snapshot storage:

```sh
mkdir -p ~/github
git clone https://github.com/stephenlclarke/mac-sync ~/github/mac-sync
git clone https://github.com/stephenlclarke/dot-files ~/github/dot-files
```

Use a different location only when you also set the matching environment
variables:

```sh
MAC_SYNC_REPO=/path/to/mac-sync
MAC_SYNC_MACHINES_REPO=/path/to/dot-files
```

## Configure

Review the tracked configuration before the first sync. The regular path list
lives in the `mac-sync` repo:

```sh
mac-sync manifest configured
```

- `config/sync-paths.txt`: regular dotfiles and directories to copy
- `config/excludes.txt`: `rsync` exclude patterns used during dotfile sync
- `config/secret-paths.txt`: sensitive paths encrypted into the secrets archive
- `config/age-recipients.txt`: public `age` recipients trusted to decrypt secrets

The default machine name is derived from the macOS host name. Set
`MAC_SYNC_MACHINE` when running manual commands if you want a stable or
friendlier directory name:

```sh
MAC_SYNC_MACHINE=work-mbp mac-sync status
```

The machine snapshot will be written under:

```text
~/github/dot-files/machines/<machine-name>/
```

## Install

Homebrew owns installation and service management:

```sh
brew tap stephenlclarke/tap
brew install mac-sync
brew services start mac-sync
```

Use Homebrew for updates, restarts, and removal:

```sh
brew upgrade mac-sync
brew services restart mac-sync
brew services stop mac-sync
brew uninstall mac-sync
```

For local development only, build and run the Swift package directly from the checkout:

```sh
cd ~/github/mac-sync
make build-release
.build/release/mac-sync --help
```

## Initial Sync

Run a manual sync once after installation:

```sh
mac-sync sync
```

During sync, `mac-sync`:

1. Pulls the local `mac-sync` repo when it is clean.
2. Pulls the `dot-files` snapshot repo when the current machine archive is
   clean, preserving unrelated local edits in that checkout.
3. Copies configured paths from `$HOME` into the machine snapshot.
4. Discovers safe referenced dotfiles and persists dynamic paths.
5. Captures Homebrew taps, formulae, casks, and a generated `Brewfile`.
6. Captures VS Code extensions when the `code` CLI is available.
7. Captures GitHub repos below `~/github` that have GitHub remotes.
8. Updates an encrypted secrets snapshot when recipients and tools exist.
9. Commits and pushes `machines/<machine-name>` in the `dot-files` repo.

<!-- markdownlint-disable MD013 -->

```mermaid
sequenceDiagram
  participant User
  participant CLI as mac-sync
  participant Home as "$HOME"
  participant Code as "mac-sync repo"
  participant Snap as "dot-files repo"

  User->>CLI: mac-sync sync
  CLI->>Code: git -C ~/github/mac-sync pull --ff-only
  CLI->>Snap: git -C ~/github/dot-files pull --ff-only
  CLI->>Code: read config/sync-paths.txt
  CLI->>Home: discover dynamic referenced paths
  CLI->>Snap: rsync into machines/machine-name/home
  CLI->>Snap: brew list and write homebrew snapshot
  CLI->>Snap: code --list-extensions and write editor snapshot
  CLI->>Home: inspect git repos under ~/github
  CLI->>Snap: write github-repositories/repositories.txt
  CLI->>Snap: age -R config/age-recipients.txt when enabled
  CLI->>Snap: git add machines/machine-name
  CLI->>Snap: git commit -m chore(machine): sync machine state
  Snap->>GitHub: git push -u origin main
```

<!-- markdownlint-enable MD013 -->

Check status after the first run:

```sh
mac-sync status
```

The status output shows the `mac-sync` version SHA, local repo, machines repo,
last sync result, storage totals, warnings, errors, remote repo, and commit.

## Hourly Sync

Homebrew services owns the launchd job:

```sh
brew services start mac-sync
brew services restart mac-sync
brew services stop mac-sync
brew services info mac-sync
```

The service runs `mac-sync run`, which is the automation entrypoint for `sync`.
Local sync status is written outside git:

```text
~/Library/Application Support/mac-sync/status/<machine-name>.env
```

## Restore

Use restore when setting up a new Mac or copying a snapshot from another Mac.

Install the Homebrew package and clone both repos first:

```sh
brew tap stephenlclarke/tap
brew install mac-sync
mkdir -p ~/github
git clone https://github.com/stephenlclarke/mac-sync ~/github/mac-sync
git clone https://github.com/stephenlclarke/dot-files ~/github/dot-files
```

List available machine snapshots:

```sh
mac-sync restore --list-machines
```

If this Mac's hostname has no matching snapshot, `mac-sync restore` offers the
available machines from the `dot-files` repo. If the hostname does match a
snapshot, `mac-sync restore` defaults to that snapshot; use `--select` to choose
another source interactively.

Preview a restore before writing files:

```sh
MAC_SYNC_DRY_RUN=1 mac-sync restore --select
```

Restore the selected snapshot:

```sh
mac-sync restore --select
```

Use `--force` only when the snapshot should win over newer local files:

```sh
mac-sync restore --from old-mbp --force
```

Restore copies regular dotfiles and prints Homebrew and VS Code commands when
the selected machine snapshot differs from the current Mac. It does not run
those package/editor commands for you. It also clones missing GitHub repos from
the selected machine's `github-repositories/repositories.txt` into `~/github`,
skipping targets that already exist.

<!-- markdownlint-disable MD013 -->

```mermaid
flowchart TD
  A["Choose source machine<br/>mac-sync restore --list-machines"] --> B["Dry-run restore<br/>MAC_SYNC_DRY_RUN=1 mac-sync restore --select"]
  B --> C{"Looks correct?"}
  C -- "No" --> D["Adjust config or source machine<br/>vim ~/github/mac-sync/config/sync-paths.txt"]
  D --> B
  C -- "Yes" --> E["Run restore<br/>mac-sync restore --select"]
  E --> F{"Package/editor differences?"}
  F -- "Yes" --> G["Review printed commands<br/>mac-sync restore --from old-mbp"]
  F -- "No" --> H["Skip package/editor changes"]
  G --> I["Run desired commands<br/>mac-sync packages install ...<br/>mac-sync editor install ..."]
  E --> R{"Missing GitHub repos?"}
  R -- "Yes" --> S["Clone into ~/github"]
  R -- "No" --> T["Skip existing repos"]
  E --> J{"Encrypted secrets snapshot?"}
  J -- "Yes" --> K["Inspect secrets archive<br/>mac-sync secrets list --from old-mbp"]
  K --> L["Restore secrets if needed<br/>mac-sync secrets restore --from old-mbp"]
  J -- "No" --> M["No secrets restore"]
  I --> N["Check status<br/>mac-sync status"]
  H --> N
  S --> N
  T --> N
  L --> N
  M --> N
```

<!-- markdownlint-enable MD013 -->

## Encrypted Secrets

Initialize this Mac's Keychain-backed `age` identity:

```sh
mac-sync secrets init
```

That command stores the private identity in Apple Keychain and writes only the
public recipient to `config/age-recipients.txt` in the `mac-sync` repo.

Update the encrypted snapshot manually:

```sh
mac-sync secrets sync
```

Inspect a source machine's encrypted archive:

```sh
mac-sync secrets list --from old-mbp
```

Restore encrypted secrets:

```sh
mac-sync secrets restore --from old-mbp
```

Secrets restore refuses to overwrite existing local files unless `--force` is
used:

```sh
mac-sync secrets restore --from old-mbp --force
```

## Moving to Another Mac

For a replacement Mac, the usual order is:

1. Clone `mac-sync` and `dot-files`.
2. Install the Homebrew package.
3. Start or restart the Homebrew service when this Mac is ready for scheduled syncs.
4. Run `mac-sync restore --list-machines` and pick the old Mac snapshot.
5. Run `MAC_SYNC_DRY_RUN=1 mac-sync restore --from <old-machine>`.
6. Run `mac-sync restore --from <old-machine>`.
7. Run `mac-sync packages install --from <old-machine>` if you want the old
   Homebrew state.
8. Run `mac-sync editor install --from <old-machine>` if you want the old VS
   Code extension state.
9. Run `mac-sync secrets init` to add this Mac as a trusted recipient.
10. Run `mac-sync secrets restore --from <old-machine>` if needed.
11. Re-run `mac-sync restore --from <old-machine>` if private repo cloning
    needed secrets that were restored in the previous step.
12. Run `mac-sync sync` to create this Mac's own snapshot.
13. Confirm with `mac-sync status`.

<!-- markdownlint-disable MD013 -->

```mermaid
flowchart LR
  Old["Old Mac snapshot<br/>mac-sync sync"] --> Dot["dot-files repo<br/>git clone ... ~/github/dot-files"]
  Dot --> New["New Mac restore<br/>mac-sync restore --from old-mbp"]
  New --> Repos["Missing GitHub repos<br/>git clone into ~/github"]
  New --> Brew["Optional package restore<br/>mac-sync packages install ..."]
  New --> Editor["Optional editor restore<br/>mac-sync editor install ..."]
  New --> Secrets["Optional secrets restore<br/>mac-sync secrets restore --from old-mbp"]
  Repos --> Sync["New Mac sync<br/>mac-sync sync"]
  Brew --> Sync["New Mac sync<br/>mac-sync sync"]
  Editor --> Sync["New Mac sync<br/>mac-sync sync"]
  Secrets --> Sync
  Sync --> Dot
```

<!-- markdownlint-enable MD013 -->

## Useful Commands

```sh
mac-sync help
mac-sync help restore
mac-sync help secrets
mac-sync list
mac-sync status
mac-sync sync
mac-sync restore --from <machine>
mac-sync packages diff --from <machine>
mac-sync packages install --from <machine>
mac-sync editor diff --from <machine>
mac-sync editor install --from <machine>
mac-sync manifest list
mac-sync secrets list --from <machine>
mac-sync secrets restore --from <machine>
brew services restart mac-sync
brew upgrade mac-sync
```
