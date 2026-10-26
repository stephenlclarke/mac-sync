# ``MacSyncCore``

Snapshot, restore, and diagnose curated macOS configuration through a testable Swift API.

## Overview

MacSyncCore contains the configuration model, repository boundaries, synchronisation engine, scheduler, history, status, and diagnostic types shared by the command-line and native menu-bar applications. Use the module to build Mac Sync integrations without depending on either user interface.

The short-lived background worker uses resource deferral and persistent retry
backoff. ``LocalHistoryStore`` provides bounded summary/detail pages while the
portable JSON ledger stays on disk. ``StreamingFileComparison`` and
``StreamingFileFingerprint`` avoid whole-file allocations. ``ProcessRunner``
streams structured output and enforces capture limits and command deadlines.

Unattended encryption uses public recipients rather than reading a private
Keychain identity. The desktop UI observes saved state and loads folders and
history on demand; it is not needed to run an automatic schedule.
