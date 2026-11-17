# Reliability review — 17 November 2026

<!-- markdownlint-disable MD013 -->

## Outcome

The source candidate is Mac Sync 1.2.0. The review covered storage ownership, two-way file changes, targeted replacements, background lifetime, memory, preview/recovery safety, setup, documentation and distribution. The installed user's data and schedule were not used as test fixtures. This record covers local validation; GitHub release records and installed-asset checks establish deployment separately.

## Safety findings corrected

- File/folder transitions could nest a file inside an old directory or fail to commit a new directory. Stage replacements first and commit app-owned paths through an isolated Git index. Keep unrelated staged work.
- Preview could reset a failure checkpoint or mark inventories as current. It now avoids those writes and remote pulls.
- Restore and several secret operations could overlap the worker. They now share its operation lock. Real file replacement saves local Undo copies first.
- Fresh setup assumed the maintainer's repository. The helper now uses the user's own private Git URL or selected provider folder. Invalid destinations do not replace a working configuration. Failed schedule updates restore prior configuration; preparation happens before the old job stops.
- Same-size edits with the same modification time could be missed. Snapshot copying now requests checksum comparison. Tests cover rapid saves.
- A stale/offline Mac could overwrite newer content if connection order or timestamps chose a winner. Per-file causal versions now separate safe changes from conflicts. Deletions require a decision. An invalid peer ledger does not erase existing review items.
- Exclusions could become false deletion requests or be bypassed by incoming changes. Excluded files stop being advertised and cannot be written automatically. Advanced include/merge rules require manual copying.
- A watcher could trigger itself from its own checkpoint or generated manifest. Those writes do not schedule another worker. The real-process test verifies an initial run, a quiet idle period, a new source edit and graceful stop. Idle mode arms the next event deadline rather than polling every few seconds.
- macOS could shorten an existing `/private/tmp` path to `/tmp`, but leave a missing child unchanged. Shared boundary checks now resolve the existing ancestor before appending missing components. Tests cover aliases, missing descendants and a link escaping storage.
- A cached Git ref could be mistaken for a verified upload. Upload status now requires a successful remote operation. Folder saves explicitly do not confirm provider upload.
- Cloud-folder errors offered irrelevant Git authentication repairs. Health reconciliation and recovery actions now use the configured storage kind; provider errors remain active until a successful folder operation.
- Signed distribution had no notarisation gate. New release packaging requires Apple's `Accepted` result, a stapled ticket and Gatekeeper acceptance. Extracted release assets are checked again. Credentials stay outside the source and app bundle.

## Validation

- `make ci`: passed, including 165 Swift tests, 13 shell integration suites, seven release-tool tests, CLI smoke checks and the 85% coverage floor. Measured core line coverage: **88.16%**.
- AddressSanitizer: all 165 Swift tests passed; no reported invalid memory access.
- ThreadSanitizer: all 165 Swift tests passed; no reported data race.
- Core memory probe: 512 MiB file comparison, bounded 64 MiB command output and 100,000 history entries. Warm, final and peak resident memory were **28 MiB** over 1,000 read iterations.
- Native menu-bar probe: **21 MiB** warm/final/peak physical footprint over 120 seconds; steady CPU **2.2% of one core**. No watchdog failure or growing footprint.
- Generated two-Mac tests covered stale versions, concurrent edits, deletion review, Keep Both, expected-hash replacement and delivery receipts. A real local bare Git remote and independent shared-folder caches exercised both transport routes.
- The isolated native preview showed peer storage, version recovery and the watch-mode option. Its Test Recovery action completed for generated files without replacing source files. Native coordinate-based double-click automation was unavailable; folder navigation was not claimed from that failed automation path.
- Workflow syntax, Markdown, Python release-tool tests and whitespace checks passed.

## Limits

This is not a 48–72-hour sync soak or proof of a real OneDrive/iCloud upload. GitLab/Bitbucket support uses the common Git protocol and endpoint tests; it does not include new live account creation or provider OAuth. Advanced exclude filters, absolute selections, selected symlink roots, legacy snapshots and encrypted-secret recovery can require explicit copying. Folder drops require an archive or individual regular files. Versions and Undo copies are not automatically pruned. Shared-storage writers are trusted; checksums and causal versions are not a defence against another authorised writer deliberately changing scripts or metadata. App Store submission and sandbox migration remain separate work.
