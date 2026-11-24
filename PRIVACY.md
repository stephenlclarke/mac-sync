# Privacy

Mac Sync is a file-sync tool, not a hosted storage service. quux.io does not run a Mac Sync account service, receive your synced files, or collect analytics, advertising identifiers or tracking data through this app.

## Files and destinations

You choose the files and folders to sync and the destination. Git mode sends snapshots, paths, machine names, file metadata and version records to your chosen Git host. Folder mode writes versioned snapshots into the folder you choose. Your cloud provider may upload them using its own software, account and privacy terms. A local save is not proof of cloud upload.

Ordinary snapshots are not end-to-end encrypted by Mac Sync. A private repository is not a substitute for encryption. Only files configured for Encrypted Secrets are encrypted by Mac Sync before storage. Keep private keys, passwords and tokens out of ordinary selections. Deleting a file from the current selection does not remove historical copies.

The App Store edition requires you to grant access to containing folders. It saves security-scoped bookmarks in its private app container so the UI and approved background service can use those folders after relaunch. You can reset saved grants in Settings; this also disables that edition's automatic sync. The direct edition uses the normal file permissions of your macOS account.

## Credentials and local records

HTTPS tokens entered in the App Store edition are passed to its bundled Git Keychain helper, not saved in a URL or settings file. Tokens are matched by host; use a token limited to the required private repository. SSH uses the keys and known-hosts files to which you grant access. Encryption identities are kept in Keychain. Keychain items are not copied when moving between editions; configure access again. You can revoke provider tokens at the provider and remove app credentials in Keychain Access.

Selections, destination settings, file hashes, device UUIDs, history, recovery copies and error logs stay locally or at your chosen destination as needed for sync and recovery. A random device UUID distinguishes concurrent edits; it is not sent to quux.io. Logs can contain paths, hostnames and command diagnostics. Review them before sharing a support report. Support reports are not uploaded automatically.

Mac Sync reads file metadata for comparison and history, uses timers to combine changes and enforce deadlines, and checks storage availability where needed to protect writes. It uses its own preferences for app settings. It does not use these signals for fingerprinting or tracking.

## On-device diagnosis

On-device diagnosis is optional and starts only when you choose it in Sync Health. It uses Apple's native on-device system model, with no cloud provider, cloud fallback, external command, or model tools. macOS manages model availability and initial downloads; the prepared model can run offline. Mac Sync does not change network or Apple Intelligence settings for diagnosis.

The input is an in-memory, app-generated summary of the last displayed run result, warning/error counts, recorded publish exit status, destination kind, complete incoming-review category counts and recognised health-condition codes. It does not include file contents or names, paths, peer names, repository URLs, raw warnings, command output, credentials or Keychain data. It opens the ledger read-only, does not construct a sync engine, and never saves an AI transcript or diagnosis to the sync destination. Closing the sheet cancels the request; this feature does not save its results. The model can organise only supplied findings; the app discards an inconsistent answer and keeps verified records visible. Diagnosis never applies files, resolves conflicts, acknowledges conditions or changes configuration.

Unknown and empty incoming-review queues do not call the model. Missing or unreadable counts remain unknown, not zero. The app derives a fixed-order safety checklist from typed records; no model-generated repair prose is displayed. This advice has no executable actions and remains available if the model is absent, fails or returns an inconsistent answer. A healthy empty queue produces no repair tasks. The advice cannot initiate a sync, inspect file contents or select a winning version.

## Background activity and removal

Automatic sync is optional. The App Store edition registers its bundled background agent with macOS after you save a schedule. You can disable it in Mac Sync or in macOS Login Items & Extensions. The direct edition also supports Homebrew services. Stop automatic sync before switching editions or uninstalling.

Removing the app does not erase the Git repository, cloud snapshots, recovery records or Keychain items. These are retained to avoid unexpected data loss. Remove them explicitly only after verifying an independent backup. The storage provider's retention and deletion rules apply to remote copies.

For privacy questions, use the [support page](SUPPORT.md). Do not send private files, tokens or encryption keys in public issues.
