# Mac Sync memory review

Reviewed on 26 October 2026 against commit `bb7d5cd`, with local workflow changes. The existing checkout at `/Users/sclarke/github/mac-sync` was clean and matched the fetched `origin/main` before work began.

This is the historical baseline review, not a description of the 1.1 runtime.
The implementation and compatibility policy are in [Architecture](../architecture.md).

## 1.1 implementation follow-up

Whole-file comparisons, full-history reloads and unbounded output capture have
been replaced with streamed I/O, a paged SQLite index, on-demand folder pages and
coalesced local observation. The UI no longer runs at login or scans every three
seconds. The worker uses resource deferral and persisted network backoff.

The production-core probe exposed an additional Foundation detail: chunked
FileHandle reads without an inner autorelease pool reached about 1,054 MiB RSS
for two 512 MiB files. Per-chunk pools reduced the same comparison to 26 MiB.
The combined probe, including 64 MiB command output and 100,000 history entries,
peaked at 29 MiB. Warm history RSS was 28 MiB and final RSS 29 MiB over 1,000
page/detail reads. Reproduce it with
`bash Tools/diagnostics/run-memory-probe.sh`. This measures the core APIs, not
the full SwiftUI app or a multi-day soak. The historical crash is not proven.

The complete local CI contract passed with more than 87% instrumented core coverage,
above the unchanged 85% floor. ASan and TSan passed the 42 core and 77 app tests.
Hosted gates and release provenance must still pass for the exact published
commit; local tests do not establish that result.

The packaged app was launched with an isolated synthetic home and repository.
One idle observation after two minutes showed about 105 MiB RSS and 0.0% CPU.
The native UI-inspection service timed out and then closed its connection, so
the new folder layout was not visually verified. Filesystem observer tests
cover write-burst coalescing and attachment before the status directory exists.

## Assessment

There are credible paths to memory exhaustion, but this review does not establish that an ARC retain-cycle leak caused the reported MBP crash. The strongest findings are unbounded input sizes and history retention. A short loader probe reached a plateau across repeated reloads. ASan and TSan reported no errors in the existing test suite. Those results do not establish that the complete app remains stable over days of use.

## Findings

### P1: Complete archives and ordinary files are loaded to compare them

[`MacSyncCore.swift:1975`](../../Sources/MacSyncCore/MacSyncCore.swift#L1975) reads both the new compressed secrets archive and its decrypted predecessor into `Data` before comparing them. [`filesEqual`, line 2717](../../Sources/MacSyncCore/MacSyncCore.swift#L2717) does the same for an existing ordinary file during restore. There is no size limit. A large archive or selected file can therefore cause a large transient allocation in the CLI child process. System memory pressure can come from that child even when the desktop process itself looks small.

Use a bounded streaming comparison, with an early size check, in both paths. Verify equal, different, empty, unreadable and multi-gigabyte synthetic files, and measure peak resident memory. This is a size-dependent allocation risk; the historic crash has not been reproduced.

### P1: Every dashboard refresh decodes the complete accumulated history

[`readHistory`, line 359](../../Sources/MacSyncApp/Services/SyncRepository.swift#L359) decodes every history JSON file, including every transfer entry. [`ContentView.swift:52`](../../Sources/MacSyncApp/Views/ContentView.swift#L52) calls `store.reload()` every three seconds on the main thread. The replacement overview is constructed while the previous overview is still held, so refreshes can temporarily hold two generations. Snapshot files and folder statistics are also rescanned on each refresh.

This grows with the number and size of completed runs, even without leaked objects. The synthetic probe retained about 27 MiB for 100 records with 20,000 total entries and 95 MiB for 500 records with 100,000 entries after warm-up. Ten reloads of the fixed 500-record fixture then remained near 95 MiB, rather than growing on every iteration. Each reload took about 0.24 seconds before SwiftUI rendering or issue reconciliation.

Load a bounded page of history summaries, read transfer details only for the selected run, and cache unchanged records. Keep the full ledger on disk. Refresh expensive snapshot data when its inputs change, and move disk work off the main thread. Test a fixed history for stable repeated-refresh memory, then test increasing history sizes against a memory budget.

### P1: ProcessRunner captures all stdout and stderr in memory

[`Support.swift:457`](../../Sources/MacSyncCore/Support.swift#L457) drains each pipe with `readDataToEndOfFile()`, then converts the captured data to strings. Git and rsync output and encrypted archive listings can be arbitrarily large. The lock protects concurrent access to the capture object, but does not bound its size.

A probe of the actual `ProcessRunner` captured 64 MiB of synthetic stdout. Resident memory rose from about 6 MiB to 138 MiB. The output was retained for the measurement; this demonstrates allocation amplification, not a permanent leak.

Stream structured command output into its consumer. Use a bounded tail for diagnostics, or a temporary file where complete output is required. Do not silently truncate manifests or archive listings. Add a sustained-output test with explicit memory and output-correctness limits.

### P2: The live output queue is unbounded before the display limit applies

[`SyncStore.swift:483`](../../Sources/MacSyncApp/Stores/SyncStore.swift#L483) schedules a separate main-queue closure for each pipe read. Each closure holds its output text until it runs. The 50,000-character limit at line 516 applies only after that closure reaches the main thread. A busy main thread, including the full reload above, can let pending output accumulate beyond the display limit. This path was identified in source; its backlog was not measured in the full running UI.

Buffer output in a bounded synchronised accumulator and schedule at most one UI delivery at a time. Batch updates at a fixed interval. Test a noisy process while the main thread is delayed, and confirm both the queue and retained output stay bounded.

## Validation and limits

| Check | Result |
| --- | --- |
| ASan | 31 core tests and 74 app tests passed, no reported sanitizer finding |
| TSan | 31 core tests and 74 app tests passed, no reported sanitizer finding |
| Workflow syntax | `actionlint` passed for CI, CodeQL and Quality |
| Documentation | Markdown lint and `git diff --check` passed |
| Loader probe | Synthetic fixtures, 0/100/500 records, 200 entries per record, ten reloads each; plain Swift build with an autorelease pool per refresh |
| Output probe | Plain Swift build of the actual ProcessRunner; 64 MiB synthetic stdout; no user file content read |

Tests and probes ran locally with Apple Swift 6.4 and Xcode 27.1 on Apple Silicon. Sanitizer logs are under `.build/sanitizers/address/test.log` and `.build/sanitizers/thread/test.log`. The temporary probe source and executable are under `.build/memory-review/`; they are ignored build artefacts. The probe uses the actual core sources and repository loader, not the full SwiftUI app. No full desktop soak test or Instruments allocation trace was captured, and no matching Mac Sync crash or memory report was found in the inspected local diagnostic-report directories. The historical installed version and crash-time process breakdown remain unknown.

The first ASan attempt failed one test because its deliberately minimal subprocess environment omitted PATH, preventing the sanitizer from finding Apple's symbolizer. The test now supplies system tool directories and still requires empty stderr. The complete rerun passed.

## Workflow changes

Both sanitizer jobs now run on pushes to main, pull requests and manual CI dispatches. They use separate build directories, two build workers, serial tests, direct failure propagation and retained logs. They are part of CI success, which the existing release workflow already requires. The old duplicate ASan job was removed from Quality; nightly TSan remains and uses the same Makefile target.

CodeQL already existed. It now explicitly selects Xcode 26.6 on macOS 26 and adds the security-and-quality query suite. GitHub [does not support Swift traced extraction with Xcode 27 or Swift 6.4](https://github.blog/changelog/2026-10-19-codeql-changes-for-macos-27-xcode-27-and-swift-6-4/). The local machine has only Xcode 27.1, so a hosted CodeQL run remains unverified. [Apple notes that ASan does not detect memory leaks](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early); the new checks complement a sustained allocation review.

## Proposed fix order

1. Replace whole-file comparisons with streaming comparisons and bound command-output capture.
2. Page history and load details on demand; avoid rebuilding unchanged snapshots every three seconds.
3. Bound and batch the live-output delivery queue.
4. Run a full desktop soak test with representative large snapshots, accumulated history, scheduled syncs and noisy output. Measure parent and child resident memory, allocations and retained objects across idle and active periods.

At the time of the baseline review, runtime fixes, installation, commits,
pushes and releases had not been performed. See the 1.1 follow-up above and the
release's exact-commit workflow records for subsequent delivery evidence.
