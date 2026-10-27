#!/usr/bin/env bash
# USAGE: run-menu-bar-memory-probe.sh [seconds]
# Run a real SwiftUI menu-bar item in a logged-in macOS desktop session.
# Uses synthetic state only; no repositories, sync workers or credentials.
set -euo pipefail

# Compile production views into an isolated desktop fixture and run its watchdog.
main() {
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: %s [seconds: 30-3600, default 120]\nRequires a logged-in macOS desktop session. Does not sync files.\n' "$(basename "$0")"
    return
  fi
  local duration="${1:-120}"
  if [[ $# -gt 1 || ! "$duration" =~ ^[0-9]+$ ]] || ((10#$duration < 30 || 10#$duration > 3600)); then
    printf 'Duration must be an integer from 30 to 3600 seconds.\n' >&2
    return 2
  fi
  cd "$(dirname "$0")/../.."
  local probe_dir
  probe_dir="$(pwd)/.build/menu-bar-memory-probe"
  mkdir -p "$probe_dir"
  swiftc -O -swift-version 6 -parse-as-library \
    Sources/MacSyncApp/Views/SyncMenuBarIcon.swift \
    Sources/MacSyncApp/Views/SyncActivityIcon.swift \
    Tools/diagnostics/menu-bar-memory-probe.swift \
    -o "$probe_dir/probe"
  "$probe_dir/probe" "$duration"
}

main "$@"
