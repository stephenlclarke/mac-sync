#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-help.XXXXXX")"
readonly TMP_ROOT
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'help test failed: %s\n' "$*" >&2
  exit 1
}

assert_stdout_contains() {
  local pattern="$1"

  grep -F -- "$pattern" "$STDOUT_FILE" >/dev/null || fail "missing stdout pattern: $pattern"
}

assert_stderr_contains() {
  local pattern="$1"

  grep -F -- "$pattern" "$STDERR_FILE" >/dev/null || fail "missing stderr pattern: $pattern"
}

run_mac_sync() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINE=target \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINE=target \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

run_mac_sync_expect_failure() {
  if run_mac_sync "$@"; then
    fail "expected failure: $*"
  fi
}

mkdir -p "$TEST_HOME" "$TEST_REPO"

run_mac_sync help restore
assert_stdout_contains "USAGE:"
assert_stdout_contains "mac-sync restore [--from <machine>|--select|--list-machines] [--force]"
assert_stdout_contains "--from <machine>   Restore from another machine snapshot."
assert_stdout_contains "--select           Prompt for a machine snapshot"
assert_stdout_contains "--list-machines    List available machine snapshots and exit."
assert_stdout_contains "MAC_SYNC_DRY_RUN=1 mac-sync restore --from old-mbp"

run_mac_sync restore --help
assert_stdout_contains "USAGE:"
assert_stdout_contains "mac-sync restore [--from <machine>|--select|--list-machines] [--force]"

run_mac_sync help secrets
assert_stdout_contains "USAGE:"
assert_stdout_contains "mac-sync secrets <command>"
assert_stdout_contains "init       Create or reuse this Mac's Keychain age identity"
assert_stdout_contains "mac-sync secrets restore --from old-mbp --force"

run_mac_sync secrets help
assert_stdout_contains "USAGE:"
assert_stdout_contains "mac-sync secrets <command>"

run_mac_sync_expect_failure help nope
assert_stderr_contains "ERROR: unknown help topic: nope"
