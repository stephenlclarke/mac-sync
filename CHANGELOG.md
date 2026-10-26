# Changelog

## Current (after 1.1.0)

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
