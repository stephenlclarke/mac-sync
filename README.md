# Mac Sync

Mac Sync backs up selected Mac files and settings to a private GitHub repository, with a separate snapshot for each Mac. It also records Homebrew packages, VS Code extensions and GitHub clone locations, and can encrypt sensitive files. Restoring files is a separate, explicit action.

## Install

Requires an Apple silicon Mac, macOS 13 or later, Homebrew, and GitHub access to your private snapshot repository.

```sh
brew tap stephenlclarke/tap
brew trust --formula stephenlclarke/tap/mac-spinner
brew install mac-sync
```

For the opt-in Current build, use `mac-sync-current` instead. Uninstall one channel before installing the other. See [release channels](WORKFLOW.md#download).

## Use

> Desktop build 63 has a [memory-growth defect](SUPPORT.md#desktop-ui-memory-growth). The fix is in development, not yet released. Keep that installed build closed while syncing; use the CLI or background worker.

1. Open `mac-sync ui` and choose or clone your private data repository. The default location is `~/github/mac-sync-data`.
2. In **Sync Selection**, choose the files and folders to back up, then save the selection.
3. Close the app and run a sync in Terminal:

   ```sh
   mac-sync sync
   mac-sync status
   ```

Each Mac is the source for its own snapshot. Do not add private keys, tokens or credentials to the regular selection; use [encrypted secrets](docs/cli-reference.md#encrypted-secrets) instead.

To restore from another Mac, preview the changes first:

```sh
MAC_SYNC_DRY_RUN=1 mac-sync restore --select
mac-sync restore --select
```

Restore keeps existing local files unless you explicitly choose to replace them. See the [restore guide](WORKFLOW.md#restore) before applying a snapshot.

## Automatic sync

Use **Settings → Automatic sync** to choose a schedule, then close the app. The background worker runs without the desktop UI and exits between runs.

Alternatively, use the hourly Homebrew service:

```sh
brew services start mac-sync
```

Choose one scheduling method, not both. For Current, substitute `mac-sync-current`. See [automatic sync](WORKFLOW.md#automatic-sync) for migration, retry and service instructions.

## Upgrade

```sh
brew upgrade mac-sync
```

For Current, use `brew upgrade mac-sync-current`. Restart an existing Homebrew service after upgrading; older app-managed schedules may need to be saved once in Settings. See the [upgrade and schedule guidance](WORKFLOW.md#automatic-sync).

## More help

- [Setup, sync and restore walkthrough](WORKFLOW.md)
- [Desktop app guide](docs/desktop-guide.md)
- [CLI reference](docs/cli-reference.md)
- [Configuration and snapshot layout](docs/configuration.md)
- [Troubleshooting and known issues](SUPPORT.md)
- [Development and API documentation](CONTRIBUTING.md) · [Releases and rollback](RELEASES.md)

Licensed under [AGPL-3.0-or-later](LICENSE.md). See [notices](NOTICE.md).
