# Support

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
