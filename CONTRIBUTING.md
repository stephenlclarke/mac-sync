# Contributing to This Project

<!-- markdownlint-disable MD013 -->

## Local development

For the separate self-contained Store target, see [distribution boundaries](docs/distribution.md), [build and submission gates](docs/app-store-submission.md) and [runtime source provenance](Tools/runtime/README.md). `make store-archive`, `make store-audit` and `make store-smoke` do not replace the direct build or its CI gates. Own-code contributions must be available under **AGPL-3.0-or-later OR MIT**; third-party licences must stay intact.

Use generated temporary HOME/repository/cloud directories for sync and recovery tests. Do not point development fixtures at a real selection or installed schedule. New core files must be included in the coverage export. The [sync and transfer guide](docs/sync-and-transfer.md) describes causal versions, Inbox ownership and storage-provider boundaries. Preserve the static menu-bar label; use the real desktop memory check before releasing UI status changes.

Clone with `--recurse-submodules`, or initialise the pinned standalone `mac-spinner` submodule in an existing checkout:

```sh
git submodule update --init --recursive
make ci
make package-release
./script/build_and_run.sh --verify
```

To build and launch the app for development without the verification-only flag, run `./script/build_and_run.sh`. Its bundled CLI is available at `dist/mac-sync/MacSync.app/Contents/Resources/mac-sync`. Source builds are for development and release packaging; users install with Homebrew.

The [DocC developer documentation](https://stephenlclarke.github.io/projects/mac-sync/) covers synchronisation, configuration, history, diagnostics and scheduling APIs. Build the same static site locally with `make docs`.

## Commit Message Guidelines (Conventional Commits)

All commit messages **must follow the
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)**
format:

```text
<type>(optional-scope): <short summary>

[optional body]

[optional footer(s)]
```

### Types

- `feat` – a new feature
- `fix` – a bug fix
- `chore` – non-functional changes (builds, tools)
- `docs` – documentation only
- `style` – formatting, whitespace, etc.
- `refactor` – code change not fixing a bug or adding a feature
- `test` – adding or correcting tests
- `ci` – changes to CI/CD config or scripts

### Examples

```text
feat(secrets): add archive integrity checks
fix(ci): upload Swift coverage to SonarCloud
docs: clarify Homebrew service setup
```

## Validation

Live project checks: [CI](https://github.com/stephenlclarke/mac-sync/actions/workflows/ci.yml), [CodeQL](https://github.com/stephenlclarke/mac-sync/actions/workflows/codeql.yml), [Documentation](https://github.com/stephenlclarke/mac-sync/actions/workflows/docs.yml), [Homebrew](https://github.com/stephenlclarke/mac-sync/actions/workflows/homebrew.yml), [Releases](https://github.com/stephenlclarke/mac-sync/actions/workflows/prebuilt-binaries.yml), and the [SonarCloud quality and coverage dashboard](https://sonarcloud.io/summary/new_code?id=stephenlclarke_mac-sync).

Before opening a pull request, run:

```sh
make ci
make package-release
```

`make ci` runs lint checks, Swift unit tests, the shell regression suite, CLI
smoke tests, and an 85% minimum line-coverage check for `MacSyncCore.swift` and
the other instrumented `MacSyncCore` sources. The shell regression suite uses
four isolated workers by default; set `SHELL_TEST_JOBS=1` when debugging a test
serially. Coverage is written to `coverage.lcov` and `coverage.xml`; CI passes
`coverage.xml` to SonarCloud. SonarCloud scans all maintained source for
static-analysis findings and applies coverage only to the instrumented core
files.

### On-device diagnosis tests

Normal CI uses fake AI generators and generated review records. It checks exact deletion counts, explicit nulls for unknown counts, invalid or omitted findings, cancellation, deadlines, privacy filtering and read-only database access. Advice tests cover unknown and corrupt ledgers, healthy queues with historical warnings, recorded failures, cloud folders, fixed preservation/approval order and zero generator calls for unknown or empty review queues. Do not point these fixtures at an installed Mac Sync configuration or real synced files.

`LocalRepairTests` checks the separate active assistant: complete allowlist validation before effects, protected/invented IDs, duplicate/omitted IDs, no inference when healthy, active/unknown workers, scope changes, cancellation, deadlines, verification failure, already-recovered faults, conservative worker markers, bounded no-follow reads, replaced observer inodes and stale sync approval. The automatic runtime must not gain file-write, sync, credential or security APIs. Preserve the native confirmation boundary. Never test protected approval against a user's real files. The opt-in model target also tests synthetic repair plans without applying any repair to the installed app.

`LocalWorkerInspectionTests` checks the normal retained empty PID file and real kernel lock ownership. A small generated C child holds the same POSIX record lock as the worker, including while its PID file is empty. Tests query it repeatedly, preserve all file bytes, release the child and verify idle state. A separate process is required because `F_GETLK` excludes the caller's own locks. The probe must never acquire a lock, create or remove a marker, or infer ownership from stale PID text.

For an explicit native-model check on an eligible Mac with macOS 26 or later and a prepared Apple Intelligence model, run `make diagnosis-model-test`. It uses only `SystemLanguageModel.default`, generated zero- and two-deletion cases, and a fresh session for each request. It never resolves conflicts or uses a cloud fallback. To verify offline operation, disconnect external networking before this opt-in check and confirm that it stays disconnected throughout; the target itself never changes network settings. Run with normal permission to contact macOS's local model service: a restricted command runner can report model error 1008 when it blocks that local service.

### Runtime instrumentation

Run these checks when changing process handling, concurrency or memory ownership:

```sh
make sanitize-address
make sanitize-thread
make memory-check
make menu-bar-memory-check
```

CI runs ASan and TSan as separate jobs; both must succeed for the workflow to pass. They use isolated build directories, two build workers, serial tests, and retained logs. Sanitizer failures fail the job directly, without the normal test runner's toolchain-failure exception. ASan checks invalid memory access; TSan checks data races. Neither proves that a long-running app has bounded memory use or no retained objects. Use Instruments Allocations/Leaks and a representative sustained workload for that assessment. The existing CodeQL workflow scans Swift with the security-and-quality suite on macOS 26 and Xcode 26.6, since Swift traced extraction does not support Xcode 27 / Swift 6.4.

The menu-bar memory check runs a real SwiftUI status item using the production label and dashboard animation. It needs a logged-in desktop session, but no screen-recording or Accessibility access. It uses only synthetic state, never real files or a sync worker. A separate watchdog enforces memory, CPU and main-loop responsiveness budgets; a hosting-view unit test alone does not cover this boundary. CI runs this check as well as the core memory probe. See [Architecture](docs/architecture.md#validation-and-remaining-limits) for limits and longer runs.

CodeQL resolves SwiftPM dependencies before enabling tracing and explicitly
targets ARM64 on the ARM64 runner. LLVM coverage-tool discovery is lazy, so it
does not run Swift toolchain probes during the traced build. Maintained app and
core sources are still compiled under tracing.

Only maintainers publish releases. The exact stable/current contract, validation
gates, Homebrew update sequence, retention policy, and rollback commands are in
[RELEASES.md](RELEASES.md).

Read [Architecture](docs/architecture.md) before changing worker lifetimes,
history, refresh triggers or process capture. Do not replace streamed reads with
whole-file Data loads, unbounded arrays or per-chunk main-queue callbacks.
Retain explicit overflow failures for structured output. The memory probe is a
short synthetic regression check, not a substitute for a multi-day app soak.
