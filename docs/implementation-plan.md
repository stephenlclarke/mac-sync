# Quiet background sync implementation

## Guarded operational repairs — 24 November 2026

- [x] Preserve the read-only diagnosis option and add a separate on-demand Local Repair Assistant.
- [x] Limit automatic effects to app-memory status refresh, read-only observer reconnection and finished-process busy-state cleanup. Use cached triage decisions, not another disk read or migration.
- [x] Give the local model only verified repair IDs. Reject the whole invalid batch, recheck scope/worker state, verify effects and stop on cancellation, unavailable model or failure. Never use cloud AI or generated commands.
- [x] Require native, single-use, scope-bound approval for sync. Keep manual file/conflict and credential/security review separate. Do not enable background sync or choose file versions.
- [x] Add deterministic policy, production-adapter, bounded-read, observer and layout tests. Validate native diagnosis and synthetic repair plans on this Mac without applying real file changes.

The upgrade uses the existing signed/notarised Current delivery lane, exact-commit hosted gates and protected Homebrew tap. App Store sandbox model access and earlier-macOS AI behaviour remain unqualified. This assistant is not an unrestricted repair agent; only its explicit operational allowlist can run automatically. See [the user guide](desktop-guide.md#local-repair-assistant).

## Read-only on-device diagnosis — 23 November 2026

- [x] Add a user-requested Sync Health diagnosis sheet and native on-device-only model service, without a cloud or command-line fallback.
- [x] Stream complete review counts through a read-only ledger connection; keep missing or malformed evidence distinct from zero.
- [x] Exclude file contents, names, paths, raw logs and credentials. Validate generated counts/result and finding identifiers; render only trusted explanations.
- [x] Add cancellation, bounded generation, a deadline, unavailable-model handling and deterministic regression tests for false deletion claims.
- [x] Complete final tests, native offline integration, running-window inspection and review. No installed app, sync destination or conflict is changed by development.

Local validation on 24 November: `make ci` passed with 96 core and 115 app test cases, including one opt-in model test skipped in ordinary CI, and 88.17% instrumented core coverage. The focused AddressSanitizer and ThreadSanitizer runs passed. Strict lint and formatting checks passed for the new Swift files, as did documentation lint. The isolated production-view fixture showed the verified counts and a visible Close action without using real sync data.

The native `make diagnosis-model-test` target passed separately on macOS 27.2.1 with external connectivity disabled throughout three fresh model sessions: zero deletions, a synthetic two-deletion case, then zero again. Ethernet was restored and checked afterwards. A first native validation correctly rejected an omitted zero-deletion finding; an explicit required-ID list corrected the model input without weakening validation. These results do not qualify earlier macOS runtimes, Store-sandbox model access or hosted release gates. No installed app was replaced, no conflict was resolved and nothing was published.

## Dual distribution — started 17 November 2026

Approved: keep Git and cloud-folder file sync in the App Store and GitHub/Homebrew editions. Optional developer-tool features may remain direct-distribution only. Keep one shared sync engine. quux.io has authorised an MIT option alongside AGPL for its own Mac Sync code; third-party licences are unchanged.

- [x] Implement a bounded scrolling warning panel, scan cancellation and a visible Settings Close action, with regression tests. Final running-window inspection remains pending.
- [x] Define explicit distribution capabilities and prevent App Store builds from using Homebrew paths or developer-tool installation.
- [x] Build and audit an unsigned self-contained runtime, with dependency provenance, notices, corresponding-source materials and executable/library validation.
- [ ] Persist user-granted folder access and restore it in UI and background processes. Fail closed when access needs renewal.
- [x] Implement the bundled `SMAppService` entry point and registration/approval/rollback tests; retain the direct-edition schedule path and explicit consent. Real registration/disable/relaunch qualification remains pending.
- [x] Provide separate direct and Store archive/export paths, without replacing the existing installer channel. Store export needs Apple Distribution certificates/profiles, not the available Developer ID identity.
- [ ] Validate both editions, including a sandboxed generated-data round trip, background registration/permission states and an archive audit. Confirm signing/profile requirements before claiming submission readiness.
- [x] Update user, security, architecture, privacy, release and submission documentation.
- [ ] Finish the final source/package review and unresolved external-folder, service-lifecycle, signing and third-party distribution checks before publication.

Local evidence on 17 November: full local CI passed at an intermediate revision with 88.11% Swift coverage; the final permission/transfer changes passed focused tests and ThreadSanitizer. The native sandbox fixture completed repeated sync, age encryption/decryption, GNU tar and denied-grant snapshot preservation using container-local generated files. The runtime audit passed for all ten executables. Resource probes held at 28 MiB over 1,000 iterations and 21–22 MiB during a 30-second menu-bar check. These results do not prove external-folder access, multi-day stability, minimum-OS operation or App Store acceptance.

The user approved the empty `/private/tmp/mac-sync-store-access.DRiz3c` fixture. The exact-path external-folder test passed, then the same signed test app exited and restarted without a dialogue. The saved bookmark restored successfully; sync/update, age encryption, GNU tar and missing-grant snapshot preservation passed again on macOS 27.2.1. The test-only saved bookmark was removed. A harness cleanup-order defect left one generated subfolder after the first relaunch test; only that known fixture was removed, and cleanup was corrected to run before releasing access. Both stages passed again with the corrected cleanup, and the approved parent folder was verified empty. Final local CI passed with 88.12% Swift coverage. No installed Mac Sync app, destination, selection or schedule was changed. This does not qualify other macOS versions or the real registered background-service lifecycle. Apple distinguishes static inheritance from user-granted dynamic access; see [sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html). Do not infer those untested cases from metadata or container-only tests.

The App Store archive is not complete merely because it compiles. It must contain its runtime tools, have appropriate signatures/profiles and folder permissions, and pass the sandbox tests. Actual App Store submission, acceptance of Apple agreements and approval are not inferred from a local archive. No real user files or installed schedules will be used as test fixtures.

## Multi-Mac sync delivery — 16–17 November 2026

Approved scope: fix all confirmed review defects; provide guided GitHub, GitLab and Bitbucket setup; support a Finder-selected cloud-synced folder; add versioned restore with undo, reviewed presets and credential warnings, honest protection status, pause/resource controls, and test recovery/key-recovery guidance. Do not change the maintainer's installed destination or sync real files during development. Folder mode must never claim that a provider has uploaded a locally saved backup. Direct cloud APIs and App Store submission are not part of this delivery.

The primary purpose is syncing important files between Macs. Each Mac owns its canonical storage. Automatically apply only non-conflicting selected home-relative files; review conflicts and deletions. Reuse the existing helper for opt-in filesystem observation. Provide peer browsing/pull, drag-and-drop sending, exact-path replacement deliveries and receiving receipts. Final delivery must be Developer ID signed, accepted by Apple, stapled, released through GitHub/Homebrew and verified on this Mac. Notarisation reuses the authorised Apple credentials used by AWS Auto Approve.

- [x] Fix file/directory replacement, preview side effects, restore locking and personal-repository assumptions, with regressions.
- [x] Add host-neutral Git setup and a Settings setup helper, with browser-based private-repository creation and user-supplied clone URLs.
- [x] Add immutable, verified folder backups while keeping live working repositories out of cloud-synced folders.
- [x] Add version selection, recovery preview, undo copies, and a non-destructive test-recovery workflow.
- [x] Add reviewed settings presets, credential-path warnings and encryption recovery guidance.
- [x] Add truthful destination/protection status and pause/resource preferences.
- [x] Add causal incoming sync, review decisions, per-Mac Inboxes and expected-hash replacements, including real Git and shared-folder round trips.
- [x] Add a single idle observer with debounce, periodic checks, pause/backoff and graceful cancellation; verify that it does not schedule itself from its own status writes.
- [x] Update user, CLI, architecture, contributor, licence and release documentation.
- [x] Run full local tests, sanitizers, desktop/resource checks and a fresh review; resolve the new safety findings. See [review evidence](reviews/reliability-review-2026-11-17.md).

Public completion is established by the exact-commit CI/CodeQL and release workflow records, Apple's accepted submission and stapled ticket, and the installed Homebrew asset. A source checklist is not proof of a published or installed release.

Implementation uses Conventional Commits. Validate provider adapters with local remotes and generated folders; live account creation, cloud upload completion and a multi-day soak require separate evidence and must not be claimed from mocks.

## Original 1.1 delivery

Started 26 October 2026. Delivery target: stable 1.1.0 and the existing `stephenlclarke/tap` Homebrew formulae.

## Scope and acceptance

- [x] Stream file comparisons, transfer output and history writes with bounded memory.
- [x] Run one short-lived background worker independently of the desktop UI; defer expensive work under resource pressure.
- [x] Store local history in SQLite, worker policy in a small JSON checkpoint, and page history/detail queries.
- [x] Replace full UI polling with coalesced state observation and demand-driven snapshot loading.
- [x] Bound process output, execution time and live UI delivery queues.
- [x] Handle offline/DNS/authentication failures without prompts, tight retries or loss of local commits.
- [x] Preserve snapshot format, selections, existing history and safe restore behaviour.
- [x] Update architecture, user, operator, contributor and release documentation.
- [x] Pass focused tests, full local CI, sanitizers and synthetic memory checks; record limits of local soak testing.

Publication is controlled by [RELEASES.md](../RELEASES.md): Conventional
Commits, exact-commit hosted gates, immutable 1.1.0 assets and both Homebrew
channels. The publication workflow records, not this source checklist, establish
whether a release has been published successfully.

## Delivery order

1. Bounded I/O and persistent local state.
2. Worker policy, network recovery and schedule migration.
3. Read-only UI observation, paging and output coalescing.
4. Documentation, integration and resource validation.
5. Conventional Commits and publication of the final verified source only.

The previously prepared sanitizer/CodeQL changes are included. No snapshot checkout or user file will be reset. A 48–72-hour soak is a separate elapsed-time acceptance check; short tests will not be represented as that result.
