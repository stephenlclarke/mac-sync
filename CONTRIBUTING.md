# Contributing to This Project

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

Run the Swift tests with runtime instrumentation when changing process handling, concurrency, or memory ownership:

```sh
make sanitize-address
make sanitize-thread
make memory-check
```

CI runs ASan and TSan as separate jobs; both must succeed for the workflow to pass. They use isolated build directories, two build workers, serial tests, and retained logs. Sanitizer failures fail the job directly, without the normal test runner's toolchain-failure exception. ASan checks invalid memory access; TSan checks data races. Neither proves that a long-running app has bounded memory use or no retained objects. Use Instruments Allocations/Leaks and a representative sustained workload for that assessment. The existing CodeQL workflow scans Swift with the security-and-quality suite on macOS 26 and Xcode 26.6, since Swift traced extraction does not support Xcode 27 / Swift 6.4.

Only maintainers publish releases. The exact stable/current contract, validation
gates, Homebrew update sequence, retention policy, and rollback commands are in
[RELEASES.md](RELEASES.md).

Read [Architecture](docs/architecture.md) before changing worker lifetimes,
history, refresh triggers or process capture. Do not replace streamed reads with
whole-file Data loads, unbounded arrays or per-chunk main-queue callbacks.
Retain explicit overflow failures for structured output. The memory probe is a
short synthetic regression check, not a substitute for a multi-day app soak.
