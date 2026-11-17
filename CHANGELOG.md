# Changelog

## Unreleased

- Improve credential-risk warnings with normal-size, full-contrast descriptions, bold file paths and clearer spacing. Keep orange on the warning heading rather than the explanatory text.

## 1.2.0

- Support private GitHub, GitLab, Bitbucket and custom Git destinations, plus verified immutable snapshots in user-selected cloud-synced folders. Distinguish a folder save from confirmed provider upload.
- Keep per-Mac storage, apply non-conflicting selected-file changes using causal versions, and review conflicts/deletions. Add file drops, exact-path replacements, per-Mac Inboxes and published delivery receipts.
- Reuse the existing background helper for opt-in filesystem observation, debounced saves, single-flight workers and periodic safety/remote checks. Add pause, power/network controls and incoming policy.
- Add versioned preview/export/restore, local Undo copies, streamed recovery verification, recovery-key export, reviewed presets and credential warnings. Add an explicit data-loss disclaimer.
- Fix file/directory snapshot transitions, same-size rapid saves, preview checkpoint writes, restore/secret-operation locking, unsafe storage recursion, failed schedule replacement and personal-repository setup assumptions. Require a successful remote operation before reporting an upload.
- Keep cloud-folder health checks and repair actions separate from Git authentication checks.
- Sign release apps with Developer ID, require Apple notarisation, staple the acceptance ticket and verify the extracted download before publication.
- Update the publisher and copyright notices to quux.io. Keep existing app and background-service identifiers for upgrade compatibility.

- Stop animating the system menu-bar label during sync. The original SwiftUI status-image update loop reproduced rapid memory growth and a frozen main thread on macOS 27.0.1. Keep static idle/syncing/warning indicators and accessible labels; retain the separate dashboard animation. Add a real menu-bar memory/responsiveness check to CI.
- Keep Sync Health's panes full-height and top-aligned when there are no active conditions, including after resizing the window.
- Distinguish a failed Git branch lookup from a confirmed detached HEAD. Stop before changing snapshots when the initial branch check fails, check again before committing, and retain the command's exit status and output in diagnostics.
- Use neutral sync and restore history headings: an attempted run is not proof that a snapshot was published. Preserve existing historical records and local repository changes.
- Require a healthy named branch, not just an origin URL, before marking a recorded branch condition as recovered.

## 1.1.0

- Separate automatic sync from the optional desktop UI; remove UI-at-login and
  three-second recursive refreshes.
- Use low-priority, single-instance workers with resource deferral, daily
  inventories, saved retry backoff and bounded subprocess execution/output.
- Stream comparisons, fingerprints, rsync history and legacy ledger imports;
  drain Foundation autorelease buffers per chunk.
- Page local SQLite history and snapshot folders; coalesce activity updates.
- Encrypt unattended backups with public recipients, without private Keychain
  reads. Preserve existing archives when recipients change, source reads fail
  or encryption fails.
- Recover pending local commits after a push outage; verify GitHub SSH fallback
  on port 22 or 443 without changing the configured remote.
- Gate CI on ASan/TSan and scan Swift with CodeQL security-and-quality queries.
- Add resource regression probes, update setup/operator/security/release docs.
- Include the previously unreleased standalone mac-spinner integration, redraw
  fixes, generated DocC site and coverage-build corrections.

This release does not claim that the historical memory-exhaustion crash was
reproduced or that a multi-day desktop soak has completed.
