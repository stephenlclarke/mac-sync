# Security Disclosure Process

The GitHub/Homebrew edition uses the current user's normal permissions. The separate App Store target uses explicit folder grants, private container state, a bundled runtime and an opt-in `SMAppService` agent. Missing grant metadata fails closed before selected sources can become deletion records. Each worker uses the permission snapshot from its own launch; changing grants does not expand an existing child's rights. Resetting access disables the Store background agent.

Store Git ignores external credential helpers, hooks, custom SSH commands and shell startup files. HTTPS credentials travel over standard input to the bundled Keychain helper and are never placed in process arguments, URLs or settings. SSH retains strict known-host checking. Store developer package/editor/Makefile operations are disabled. See [privacy](PRIVACY.md), [edition boundaries](docs/distribution.md) and the [submission gates](docs/app-store-submission.md).

Ordinary synced files, Inbox deliveries and Undo copies are not end-to-end encrypted. Do not send credentials as ordinary file replacements. Causal metadata and expected hashes prevent accidental stale overwrites; they are not authentication against another writer with access to the same shared repository or provider folder. Use private, trusted destinations and separate encrypted-secret recovery. Cloud manifests verify integrity, not the provider's upload completion. See [sync and transfer safety](docs/sync-and-transfer.md) and the [data-loss disclaimer](NOTICE.md#data-loss-disclaimer).

If you believe that you have discovered a security or privacy vulnerability in this open source project, please report it using the [GitHub private vulnerability reporting feature](https://github.com/stephenlclarke/mac-sync/security/advisories/new).

Reports should include the product and software versions that you believe are affected, a technical description of the behaviour that you observed and expected, the steps required to reproduce the issue, and a proof of concept or exploit when available.

The project maintainer will do their best to acknowledge receiving security reports within 7 days. This initial acknowledgement is neither acceptance nor rejection of your report. The maintainer may ask follow-up questions while working through the details.

Do not include credentials, tokens, certificates, SSH keys, API keys, personal data, private hostnames, or proprietary files in public issues, tests, examples, logs, or screenshots.

Known, publicly disclosed CVEs can usually be submitted as normal issues. Output from automated scanners should include enough context to show why the finding is exploitable in this project.

Scheduled sync uses public encryption recipients and never reads a private
Keychain identity. Recipient changes require a reviewed interactive sync before
replacing an existing archive. Git operations disable credential prompts and
retain SSH host-key verification, including verified port-443 fallback.

Local status/history contains paths and redacted diagnostics, not decrypted
secret contents. Treat paths as potentially sensitive when sharing logs. See
[Architecture](docs/architecture.md) for temporary-file permissions, bounded
capture, failure handling and the limits of unattended encryption.
