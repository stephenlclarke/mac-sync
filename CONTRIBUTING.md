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
smoke tests, and an 80% minimum line-coverage check for the Swift core. Coverage
is written to `coverage.lcov` and `coverage.xml`; CI passes `coverage.xml` to
SonarCloud.
