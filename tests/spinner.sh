#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-spinner}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-spinner-test.XXXXXX")"
readonly TMP_ROOT
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"
readonly CAPTURE_FILE="${TMP_ROOT}/capture"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'spinner test failed: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  grep -F "$pattern" "$file" >/dev/null || fail "missing pattern in $file: $pattern"
}

run_spinner() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    SCRIPT_COLOUR=off "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    SCRIPT_COLOUR=off "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

run_spinner --message "testing command" --output "$CAPTURE_FILE" -- \
  bash -c 'printf stdout; printf stderr >&2'
assert_file_contains "$STDOUT_FILE" $'\342\240\213 testing command'
assert_file_contains "$CAPTURE_FILE" "stdoutstderr"

if run_spinner --message "testing failure" --output "$CAPTURE_FILE" -- \
  bash -c 'printf failed; exit 7'; then
  fail "failing command returned success"
else
  exit_status=$?
fi
[[ "$exit_status" = "7" ]] || fail "expected exit status 7, got $exit_status"
assert_file_contains "$STDOUT_FILE" $'\342\240\213 testing failure'
assert_file_contains "$CAPTURE_FILE" "failed"

run_spinner --help
assert_file_contains "$STDOUT_FILE" "mac-spinner --message <text> --output <file> -- <command> [args...]"
assert_file_contains "$STDOUT_FILE" "mac-spinner --message <text> --pending"
assert_file_contains "$STDOUT_FILE" "mac-spinner --message <text> --done"

run_spinner --message "pending row" --pending
assert_file_contains "$STDOUT_FILE" $'\342\240\213 pending row'

run_spinner --message "done row" --done
assert_file_contains "$STDOUT_FILE" $'\342\234\224\357\270\216 done row'

if [[ -n "$SCRIPT_RUNNER" ]]; then
  SCRIPT_COLOUR=off "$SCRIPT_RUNNER" "$SCRIPT_PATH" --message "spin only" --spin-only >"$STDOUT_FILE" 2>"$STDERR_FILE" &
else
  SCRIPT_COLOUR=off "$SCRIPT_PATH" --message "spin only" --spin-only >"$STDOUT_FILE" 2>"$STDERR_FILE" &
fi
spinner_pid="$!"
sleep 0.2
kill "$spinner_pid" >/dev/null 2>&1 || true
wait "$spinner_pid" 2>/dev/null || true
assert_file_contains "$STDOUT_FILE" $'\342\240\213 spin only'
