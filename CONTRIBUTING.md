# Contributing to This Project

## Commit Message Guidelines (Conventional Commits)

All commit messages **must follow the
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)**
format:

```text
<type>(JIRA-KEY:scope): <short summary>

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
feat(DO-1431:decoder): add support for obfuscated fix tags
fix(DO-1431:autogen): fix malformed xml
BREAKING CHANGE(DO-1431): changed cmdline flag prefix to --
```

## 🛠️ Local Git Config (Optional)

To enable a default commit message structure:

```bash
git config commit.template .gitmessage.txt
```
