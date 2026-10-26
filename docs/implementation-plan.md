# Quiet background sync implementation

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
