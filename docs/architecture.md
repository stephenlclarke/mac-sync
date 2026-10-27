# Quiet background sync

Version 1.1 keeps the existing snapshot format and separates the worker's
lifetime from the desktop UI. The goal is low disturbance and bounded resource
use, not the shortest possible sync time.

## Process and data boundaries

```text
launchd schedule → short-lived mac-sync run → rsync / Git / inventory / age
                            ↓
               local status + SQLite + JSON history
                            ↓
                optional, read-mostly SwiftUI app
```

Use either the app-managed schedule or Homebrew service, not both. A global
service lock rejects duplicate workers. An operation lock prevents scheduled,
manual and app-started syncs from overlapping. The worker sets Darwin
background scheduling priority. New app-owned jobs also set Background,
Nice=10 and LowPriorityIO. The Homebrew service sets background priority and
Nice=10. There is no permanent synchronisation daemon or polling UI process.

Opening the app reads local state without a remote health probe, Keychain
identity read, automatic repair or sync. A filesystem watcher coalesces status
changes over 500 ms; window activation also refreshes saved state. Only one
overview read and one pending replacement are allowed. Disk reads run off the
main thread. A user-requested sync or health action can use the network and
interactive credentials.
Overview and health queues drain an autorelease pool after each work item;
folder reads also drain one per page. They do not rely on a global queue to
release Foundation's temporary objects.

The system menu-bar label is a static image, updated only on status changes. Do not put `TimelineView`, repeating animation or a frame timer in a `MenuBarExtra` label: its SwiftUI-to-AppKit image/layout path reproduced runaway allocation and main-loop starvation on macOS 27.0.1. Dashboard animation is separate and respects Reduce Motion.

Activity uses the shared status PID marker, not just a temporary-directory
path which may differ between Finder and launchd. A PID must identify a real
`mac-sync` worker. Stop rechecks that identity; invalid, reused or process-group
PIDs are not signalled.

## Bounded work

| Path | Bound or policy |
| --- | --- |
| Ordinary file/archive comparisons | Two 64 KiB chunks; early mismatch exit |
| SHA-256 archive fingerprint | One 64 KiB chunk |
| Foundation read loops | Per-chunk autorelease pool; buffers do not accumulate until process exit |
| Structured rsync output | Complete lines streamed directly to the ledger; maximum pending line 256 KiB |
| Other subprocess output | 8 MiB per stream; overflow is an explicit non-success, never silent successful truncation |
| Command execution | Five-minute default; Git network commands two minutes, SSH verification 30 seconds |
| Pipe closure | Two seconds after child exit, then readers are cancelled |
| Run diagnostics | 100 warning/error messages, 2,000 characters each; 32 command diagnostics |
| Local SQLite | WAL, 1 MiB page-cache target; batched writes of 256 entries |
| History UI | 50 summaries; 200 details for the selected run |
| Legacy history migration | Stream entries; maximum entry 64 KiB, header/suffix 1 MiB; no whole-ledger read |
| Folder browser | 100 direct children per page; no recursive descendant scan |
| Activity view | Latest 50,000 bytes, coalesced updates; five recent app-started activity log files |
| Expensive inventory/encryption | At most daily for background runs; always checked by manual sync |
| Resource pressure | Defer for Low Power Mode, serious/critical thermal state or a memory-pressure warning |
| Background work budget | Check 15-minute budget and resource pressure between configured paths and inventory stages |

The worker does not stop a file copy halfway through on resource pressure.
Individual commands have deadlines. Filesystem copies are incremental, not a
transaction across all selected paths. A deferred run can leave unpublished
snapshot changes; rsync and Git make the next attempt incremental. Local source
files remain authoritative. Neither restore nor conflict resolution is started
automatically.

The Git object ID already identifies a stored blob. It cannot establish that a
source file outside the repository is unchanged. rsync uses size/mtime checks
first; Git uses its index/stat cache for snapshot changes. Exact content checks
stream bytes. The encrypted backup caches a streaming SHA-256 fingerprint of
the deterministic compressed plaintext so unchanged data need not be encrypted
again. No plain secret data or private identity is stored in the checkpoint.

## Offline and GitHub recovery

Scheduled work makes one attempt, then saves retry state in
`status/<machine>.background.json`. Transient failures back off from 15 minutes
to six hours. Authentication failures wait 12 hours and remain actionable.
The schedule determines the next opportunity to retry. A manual sync bypasses
this background checkpoint and makes up to three attempts. A successful manual
sync clears saved backoff and refreshes inventory/encryption timestamps, so
automatic work does not stay paused after explicit recovery.
Checkpoints are scoped to the machine and canonical data-repository path;
selecting another checkout cannot carry its backoff or inventory timestamps over.

Git disables terminal/Git Credential Manager prompts, uses low-speed limits and
bounded connection attempts. An HTTPS failure can use verified SSH on port 22,
then verified SSH through `ssh.github.com:443`. The fallback is per process:
`origin` and SSH host-key checks are not changed. A failed remote refresh stops
before snapshot copies. A failed push preserves local commits. The next run
can rebase pending commits over a peer update; conflicts from a rebase started
by Mac Sync are aborted back to the preserved state and reported. A pre-existing
user rebase is not aborted. There is no force push or reset.

The first two transient unavailable conditions remain in history without an
attention badge. Repeated failures become actionable. Authentication, changed
recipients, conflicts and invalid configuration are not hidden as normal offline
states.

## Encryption without unattended identity reads

The worker encrypts using the configured public recipient list. It does not
read a private Keychain identity or decrypt an existing archive. Before it can
replace an existing archive, its saved public-recipient manifest must match the
configuration. A changed or missing recipient manifest requires a reviewed
interactive sync. The new encrypted archive is staged on the destination
filesystem and renamed only after encryption succeeds. Pipelines fail if any
stage fails. Archive creation does not ignore unreadable inputs: a source-read
failure preserves the previous archive and is recorded as a local error, not a
GitHub outage. Temporary secret directories are mode 0700; temporary files are
mode 0600. Normal completion/error cleanup removes them. Abrupt process or
machine termination can leave private temporary directories for OS cleanup.

Interactive sync retains the previous decryption and recipient verification.
Changing recipients still needs that explicit verification. Existing schedules
which deliberately set `MAC_SYNC_SECRETS=0` remain disabled; saving a new
schedule uses public-recipient encryption.

## Compatibility and migration

`machines/<machine>/` and regular restore behaviour are unchanged. Each completed
run still exports compatible JSON. The local SQLite index stores summaries and
transfer entries separately; it is not tracked or synced. Legacy JSON is imported
once, streamed in bounded chunks. Invalid records stay on disk for diagnosis;
one malformed file does not hide valid runs. New exports are marked indexed
without reading them back. An interrupted index write can leave incomplete
entry rows, but these have no completed summary and are not shown as successful
runs. Portable JSON remains available to rebuild the index.

Snapshots now include file/byte totals in MACHINE.md. Older peer snapshots show
that totals are unavailable until their next sync, rather than triggering a
recursive UI scan. Browsing remains available.

The worker migrates only app-owned launch agents, keeps explicit environment
choices, uses stable Homebrew opt paths and removes the old UI-at-login job.
It does not change another service or start the UI. Resave a schedule for
immediate migration; otherwise the worker updates its plist on its next run.
Restart an existing Homebrew service after upgrading to reload its definition.
An old job pinned to an older Cellar binary cannot migrate itself to new code:
save Automatic sync once after upgrading such a schedule. This one-off
migration is explicit; opening the UI does not repair jobs or start work.

## Validation and remaining limits

Run `make ci`, `make sanitize-address`, `make sanitize-thread`, and:

```sh
bash Tools/diagnostics/run-memory-probe.sh
make menu-bar-memory-check
```

The probe uses production core APIs with synthetic 512 MiB file pairs, 64 MiB
command output, 500 history summaries/100,000 entries and 1,000 repeated page
reads. Its budgets are below 128 MiB peak RSS and less than 32 MiB growth after
warm-up. It does not read user files or exercise the entire SwiftUI process.

The menu-bar check requires a logged-in macOS desktop session. It compiles the production status label and dashboard animation into an isolated SwiftUI app, holds synthetic syncing state, and exercises idle, syncing and warning transitions for two minutes. A watchdog outside the main run loop fails on a three-second UI stall, a footprint above 512 MiB, growth above 32 MiB after ten seconds, or steady CPU above 25% of one core. It measures physical footprint, including compressed memory, rather than RSS alone. It opens no repository and starts no sync worker. To run a longer synthetic check, use `bash Tools/diagnostics/run-menu-bar-memory-probe.sh 600` (30–3,600 seconds).

The review found allocation amplification, not a proven ARC retain cycle or a
reproduction of the historical MBP crash. ASan/TSan do not prove long-term leak
freedom. A representative 48–72-hour desktop/worker soak, with parent and child
RSS and Instruments allocations, remains an elapsed-time acceptance check.
History and external service logs remain on disk; paging bounds memory, not
total disk use. Inventory and rsync/Git can still use CPU/I/O, at low priority.
