# Support

<!-- markdownlint-disable MD013 -->

## Desktop UI memory growth

A user-triggered sync in desktop version 1.1.0 (build 63) produced a frozen UI, nearly one CPU core of activity and a sampled memory footprint of 27.1 GB on a 32 GB Mac. The captured main thread repeatedly updated the menu-bar image and AppKit layout. No CLI worker was active when the sample was taken.

An isolated desktop reproduction on macOS 27.0.1 confirms that the animated SwiftUI `MenuBarExtra` label is sufficient to cause the failure. The original label reached a 671 MiB physical footprint in five seconds and starved the main run loop. An independent watchdog stopped the fixture before it could exhaust RAM. No sync worker, repository or user files were involved.

The fix replaces the menu-bar animation with a static status image. Idle, syncing and warning states remain visible and accessible. The final two-minute check, with the fixed production label and a visible dashboard animation, peaked at 26 MiB and used 2.5% of one CPU core after warm-up, with no main-loop stall. A separate full-app test with a temporary repository and a 45-second fake worker peaked at 51 MB; Sync Health repainted during the run and the controls returned to idle afterwards. No real files were synced. Run `make menu-bar-memory-check` in a logged-in macOS desktop session to repeat the check. CI is configured to run it too. This is a regression check, not proof of multi-day leak freedom or the cause of earlier memory-exhaustion incidents.

The fix is in development, not yet released or installed. Keep desktop build 63 closed while running CLI or scheduled syncs. If an affected app becomes unresponsive and its memory grows, stop the desktop UI to contain the growth; check worker status separately rather than starting another sync. Preserve a process sample and the app version for diagnosis. Do not delete snapshots or reset the data repository as a workaround.

## Reporting issues

Use the right GitHub surface so questions and contributions stay easy to triage.

- Use issues for reproducible bugs and focused feature requests.
- Use pull requests for proposed fixes and improvements.
- Use [security reporting](SECURITY.md) for vulnerabilities or anything that might expose credentials, private data, or sensitive runtime details.

Before opening an issue, search existing issues and pull requests to avoid duplicate reports.

For a sync issue, include the installed channel/version, `mac-sync status`, the
last run's result, and whether the app-managed schedule or Homebrew service is
used. A background `deferred` result means that work is waiting for resources or
its saved retry time; it does not mean the snapshot was published. Use the
app's explicit GitHub test for access failures. Do not repeatedly delete status
files or change Keychain permissions to clear a temporary offline state.

For memory growth, record both MacSync and mac-sync child-process memory, time
since launch, history size and active command. See the reproducible synthetic
probe and limits in [Architecture](docs/architecture.md). Sanitizers passing
does not rule out retained memory in a long-running desktop session.

For command output and local history locations, see the [status reference](docs/cli-reference.md#status). For setup and schedule recovery, see the [workflow](WORKFLOW.md).
