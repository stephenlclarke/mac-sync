# Mac Sync

Mac Sync helps keep important files and settings in sync between Macs. Each Mac has its own storage area. Browse another Mac to pull files, drop files onto it to send them, or queue a replacement for its next sync. Version history and Undo provide recovery safeguards.

> **Data-loss warning:** Use at your own risk. Mac Sync can lose, corrupt, overwrite or delete files. Stephen Clarke and contributors disclaim liability to the extent permitted by law. Keep an independent, verified backup. Read the [data-loss disclaimer](NOTICE.md#data-loss-disclaimer).

## Install

Requires an Apple silicon Mac, macOS 13 or later, and Homebrew. Use a private Git repository (GitHub, GitLab, Bitbucket or another host), or a folder already synced by iCloud Drive, OneDrive or another provider.

```sh
brew tap stephenlclarke/tap
brew trust --formula stephenlclarke/tap/mac-spinner
brew install mac-sync
```

For the opt-in Current build, use `mac-sync-current` instead. Uninstall one channel before installing the other. See [release channels](WORKFLOW.md#download).

## Use

> Desktop build 63 has a [memory-growth defect](SUPPORT.md#desktop-ui-memory-growth). Upgrade to version 1.2.0 or later before syncing with the desktop app. Until then, keep the app closed and use the CLI or background worker.

1. Open `mac-sync ui`. The setup helper lets you create a private repository in your browser and clone it, or choose a cloud-synced folder. Use the same destination on each Mac and a unique **This Mac identifier**.
2. In **Sync Selection**, choose the files and folders to sync, then save the selection. Presets can help you start.
3. Click **Sync Now** in Overview, or run a sync in Terminal:

   ```sh
   mac-sync sync
   mac-sync status
   ```

Non-conflicting changes to selected home-folder files are applied automatically. Conflicts and deletions wait for review. You can choose review-only mode in Settings. Do not add private keys, tokens or credentials to the regular selection; use [encrypted secrets](docs/cli-reference.md#encrypted-secrets) instead.

Under **Other Macs**, select files and use **Copy to This Mac** to pull them. Drop regular files onto another Mac's view to send them. Select one stored file and use **Send Files → Replace selected file** to queue a replacement. The receiving Mac applies it on its next sync if selected and unchanged locally; otherwise it waits in **Inbox**. See [sync, transfer and recovery](docs/sync-and-transfer.md).

To restore from another Mac, preview the changes first:

```sh
MAC_SYNC_DRY_RUN=1 mac-sync restore --select
mac-sync restore --select
```

Restore keeps existing local files unless you explicitly choose to replace them. See the [restore guide](WORKFLOW.md#restore) before applying a snapshot.

## Automatic sync

Use **Settings → Automatic sync → When files change** to watch selected folders, combine repeated saves, and keep hourly safety and remote checks. Or choose a timed schedule. The same background worker runs without the desktop UI and exits between runs; watch mode keeps one idle observer.

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

Copyright © 2026 quux.io. Licensed under [AGPL-3.0-or-later](LICENSE.md). See [notices](NOTICE.md).
