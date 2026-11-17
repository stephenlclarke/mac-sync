# Sync, transfer and recovery

<!-- markdownlint-disable MD013 -->

[Quick start](../README.md) · [Desktop guide](desktop-guide.md) · [CLI reference](cli-reference.md)

## Choose shared storage

Reopen the setup helper in Settings. For GitHub, GitLab, Bitbucket or another HTTPS/SSH host, create a **private** repository in your browser, paste its clone URL, and clone it to an empty local folder. Test access before the first sync. Mac Sync uses existing SSH keys or Git credential helpers. It does not create accounts, store provider passwords or configure OAuth. Fresh clones receive a local commit identity if Git has none.

For a cloud service, each Mac selects its local copy of the same private, provider-synced folder. The working Git cache stays outside that folder, in `~/Library/Application Support/mac-sync/workspaces/`. Immutable, self-contained bundles and manifests go under `MacSyncSnapshots/<machine>/<version>/`. SHA-256 checks reject incomplete or corrupt bundles. **Saved to selected folder is not proof of upload.** Check the provider's status. Do not sync a live Git working directory with a cloud client.

## Keep each Mac separate

Each Mac owns `machines/<identifier>/`. Choose a unique **This Mac identifier** in Settings. A separate local device identity detects name collisions and stops the sync. Changing the identifier preserves the previous storage area and carries forward the regular selection. Review encrypted-secret settings for the new identifier separately.

Regular selection is not end-to-end encrypted. Presets add only paths that exist. Credential-path and small-file warnings are advisory, not a complete secret scan. Removing a sensitive file does not erase old Git or cloud versions. Rotate exposed credentials and follow the host's history-removal procedure.

## Automatic changes and conflicts

A sync publishes local changes and applies non-conflicting incoming files only to paths selected on the receiving Mac. Per-file version vectors prevent a stale, offline Mac from winning by timestamp or connection order. Local state uses SQLite; portable metadata uses `sync-index.ndjson`. Hashing and metadata parsing have bounded buffers.

**Incoming Changes** in Settings and Overview offers **Keep This Mac**, **Use Incoming Version** and **Keep Both**. Concurrent edits and deletions require review. Applying a change keeps a local Undo copy. Keep Both creates a uniquely named adjacent file. Sync again to share the review decision. Choose **Review every incoming change** in Settings to disable automatic application.

Automatic incoming sync covers selected home-relative paths. Absolute paths, selected roots that are symbolic links, encrypted secrets and legacy snapshots without version metadata require explicit copying or recovery. File/folder replacements can also require manual recovery. Incoming changes cannot write through linked parents or into app storage.

## Pull files from another Mac

Select a Mac under **Other Macs**, browse stored files, then choose **Copy to This Mac**. Preview first. Existing local files are kept unless replacement is explicitly confirmed. Pre-restore copies are saved for Undo. **Versions & Recovery** offers older versions, comparison of one selected text file, and export to an empty folder without changing the original paths.

## Send or replace files

Drop regular files onto another Mac's view, or use **Send Files**. Confirm the destination folder under that Mac's home folder. To replace an exact file, select it and choose **Send Files → Replace selected file**, then choose its replacement. A batch accepts 1–100 regular files. Folders and symbolic links are not sent; archive a folder or select its files.

The sender owns only `machines/<target>/inbox/<sender>/<delivery-id>/`. It does not rewrite the target's canonical snapshot. Each delivery records the target path, payload checksum and expected stored-file checksum. Git publishes this namespace; cloud mode carries it in the sender's bundle.

On its next sync, the receiver applies a delivery if the path is selected, automatic incoming sync is enabled, and its local file still matches the expected copy. New files require the path not to exist. Conflicts preserve both copies and wait in **Inbox**. The receiver saves an Undo copy before replacement, then publishes a receipt. Receipts show the last published decision, not live online status.

In your Inbox, **Apply to This Mac** explicitly replaces the named file; **Keep This Mac** rejects the replacement. Applying an unselected path does not add it to Sync Selection. Add it there for future sync. Queued payloads remain after upload failure. Restore connectivity and retry sync; sending the file again is not required.

## Quiet background operation

**Settings → Automatic sync → When files change** reuses the existing `launchd` helper. One idle FSEvents observer starts the existing short-lived worker after 15 quiet seconds. Continuous edits have a two-minute maximum debounce. Only one worker runs. Startup always scans, so a crash cannot discard pending edits.

Hourly safety checks cover missed events, sleep/wake, changed selections, dynamic references, cloud downloads and remote Git updates. Local watchers cannot detect a remote Git push. Timed and calendar schedules remain available. Use either the app-managed job or the Homebrew service, not both. Watch mode is opt-in; it does not keep the desktop app open or add a process per folder.

Pause for one hour, 24 hours or until resumed. Preferences can wait for external power, avoid metered/constrained Git connections or allow Low Power Mode. Memory and thermal safeguards stay active. Manual Sync Now bypasses automatic pause. Cloud uploaders retain their own resource policies. Offline/authentication failures keep local commits and deliveries, with saved retry backoff. Successful manual sync clears the delay.

## Versions and recovery keys

Git versions are commits. Cloud-folder versions are independent full snapshots, not provider-native history. They use more storage than Git's shared history. Unchanged snapshots reuse the saved version. Mac Sync does not automatically prune versions or local Undo copies. Plan retention and monitor free space.

**Test Recovery** copies a selected version into a temporary folder and checks streamed hashes without replacing user files. It checks encrypted archive bytes, not decryption keys. Use **Test Encryption Access** separately. Export a private recovery key only to a new offline file outside sync/status storage and regular selections. It is owner-readable only, never printed or overwritten. Losing every trusted key means losing encrypted access.

Keep an independent verified backup. Read the [data-loss disclaimer](../NOTICE.md#data-loss-disclaimer). New public releases require the [signing and notarisation gates](../RELEASES.md); that is not App Store approval. This work does not establish live provider upload completion or a multi-day memory soak.
