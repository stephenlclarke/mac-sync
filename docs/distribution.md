# Installation editions

Mac Sync keeps one sync engine and snapshot format. The distribution channel changes installation, permissions and background-service registration, not ownership of your files.

| Capability | GitHub / Homebrew | App Store build |
| --- | --- | --- |
| GitHub, GitLab, Bitbucket and other Git hosts | Yes | Yes, bundled Git |
| Selected cloud-synced folder | Yes | Yes, explicit folder grant |
| Peer browsing, pull, Inbox delivery, replacement and recovery | Yes | Yes, explicit target/source folder grants |
| Automatic change detection and timed sync | App-managed LaunchAgent or Homebrew service | Bundled `SMAppService` agent, with macOS approval |
| Runtime installation | Homebrew dependencies | Self-contained; no Homebrew required |
| Developer package/editor/repository Makefile actions | Available | Disabled |
| Updates | Homebrew or a signed GitHub release | App Store only |
| Signing | Developer ID, notarised and stapled | Apple Distribution and App Store provisioning |

The App Store edition is under validation. It is not yet listed or available for installation from the store. Build and submission checks are in the [submission guide](app-store-submission.md). Do not describe a local archive as an approved App Store release.

## App Store permissions and background work

Choose the containing folders when prompted. Access to a containing folder supports atomic saves, new files, deletion detection and background observation. Permission alone does not add that folder to Sync Selection. Files outside your saved selection are not uploaded merely because you granted access.

The app saves bookmarks in its private container. The UI and background agent use the same signed app identity; each process resolves its own bookmarks. Each worker receives an immutable record of the grants held at launch. Missing access stops sync instead of turning inaccessible files into deletions. Renew access in Settings. Changing grants restarts the idle observer so the next worker receives the new access.

Saving Automatic sync permits the bundled agent to run after login and while the UI is closed. Check Login Items & Extensions if macOS asks for approval. A saved schedule is not reported as enabled when approval is pending or macOS has disabled it. No administrator access is required. Reset Folder Access disables this edition's background service and forgets its grants; it does not delete source files or snapshots.

HTTPS access can be entered in the setup helper or Settings and saved through the bundled Git Keychain helper. Use a least-privilege repository token. SSH uses `/usr/bin/ssh`, batch mode and strict known-host checking, without shell startup files, custom SSH commands or ProxyCommand. Grant the required `.ssh` folder, or use HTTPS. Private keys, credentials and trust records are never downloaded automatically.

## Move between editions on the same Mac

Only one installation must sync automatically on a physical Mac. The editions have different private containers and do not share their temporary worker locks. Stop the old schedule or Homebrew service and quit the old app first. Keep a verified independent backup.

1. Record the old destination, This Mac identifier and Status records location from Settings. Disable Automatic sync. If using a Homebrew service, stop it too.
2. Install the other edition. Choose the same destination and This Mac identifier. For a cloud folder, let the setup helper create this edition's private working repository outside that folder.
3. Before the first sync, expand **Moving from another Mac Sync edition on this Mac?** in setup or Settings. Confirm the old edition is stopped and choose its `device-id` file from Status records. Do not import another Mac's identity. An existing different identity is never overwritten.
4. Grant source and destination folders, configure Git access and encrypted-secrets access again, then preview and test a sync. No automatic schedule is imported or enabled.
5. Enable one schedule in the new edition only. Keep the old local history and Undo records until you no longer need them. Git/cloud version history remains at the shared destination.

If the new edition has already synced under a different identity, keep a different This Mac identifier. Do not delete its identity/database or copy a peer's identity to bypass the ownership check.

## Build boundaries

`make store-archive` builds a self-contained unsigned Xcode archive for inspection; `make store-audit` checks executables, deployment targets and resources. `make store-smoke` runs generated-data tests in an actual restricted application. None of these installs or upgrades the normal Homebrew app.

The Store runtime pins source hashes, includes notices and corresponding-source materials, and links only Apple system libraries. See [runtime provenance](../Tools/runtime/README.md). The MIT option covers Mac Sync's own code only; third-party distribution terms remain a submission gate.
