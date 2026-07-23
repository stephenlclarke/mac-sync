#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-status.XXXXXX")"
readonly TMP_ROOT
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly FAKE_BIN="${TMP_ROOT}/fake-bin"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'status test failed: %s\n' "$*" >&2
  if [[ -s "$STDOUT_FILE" ]]; then
    printf 'captured command stdout:\n' >&2
    sed 's/^/  /' "$STDOUT_FILE" >&2
  fi
  exit 1
}

assert_stdout_contains() {
  local pattern="$1"

  grep -F "$pattern" "$STDOUT_FILE" >/dev/null || fail "missing stdout pattern: $pattern"
}

assert_stdout_lacks() {
  local pattern="$1"

  if grep -F "$pattern" "$STDOUT_FILE" >/dev/null; then
    fail "unexpected stdout pattern: $pattern"
  fi
}

assert_file_contents() {
  local file="$1"
  local expected="$2"
  local actual

  [[ -f "$file" ]] || fail "missing file: $file"
  actual="$(cat "$file")"
  [[ "$actual" == "$expected" ]] || fail "unexpected contents in $file: $actual"
}

assert_stdout_before() {
  local first="$1"
  local second="$2"
  local first_line
  local second_line

  first_line="$(grep -n -F "$first" "$STDOUT_FILE" | sed -n '1s/:.*//p')"
  second_line="$(grep -n -F "$second" "$STDOUT_FILE" | sed -n '1s/:.*//p')"
  [[ -n "$first_line" ]] || fail "missing stdout pattern: $first"
  [[ -n "$second_line" ]] || fail "missing stdout pattern: $second"
  (( first_line < second_line )) || fail "expected '$first' before '$second'"
}

run_mac_sync() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p \
  "$FAKE_BIN" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO" \
  "$TEST_HOME"

git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "mac-sync test"
git -C "$TEST_REPO" config user.email "mac-sync@example.invalid"
git -C "$TEST_MACHINES_REPO" init -b main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"

cat >"$TEST_REPO/config/sync-paths.txt" <<'EOF'
.bashrc
.config/tool
EOF

: >"$TEST_REPO/config/excludes.txt"
git -C "$TEST_REPO" add config/sync-paths.txt config/excludes.txt
git -C "$TEST_REPO" commit -m "test local repo" >/dev/null

mkdir -p "$TEST_MACHINES_REPO/machines/target/home"
printf 'stale repo bash\n' >"$TEST_MACHINES_REPO/machines/target/home/.bashrc"
touch -t 202701010000 "$TEST_MACHINES_REPO/machines/target/home/.bashrc"
printf 'home bash\n' >"$TEST_HOME/.bashrc"
mkdir -p "$TEST_HOME/.config/tool"
printf 'tool setting\n' >"$TEST_HOME/.config/tool/settings"

run_mac_sync sync
assert_file_contents "$TEST_MACHINES_REPO/machines/target/home/.bashrc" "home bash"
assert_file_contents "$TEST_MACHINES_REPO/machines/target/home/.config/tool/settings" "tool setting"
assert_stdout_contains "new snapshot file:"
assert_stdout_contains "updated snapshot file:"
assert_stdout_lacks "sync directory:"
[[ -f "$TEST_HOME/Library/Application Support/mac-sync/status/target.env" ]] \
  || fail "missing local status file"
HISTORY_DIR="$TEST_HOME/Library/Application Support/mac-sync/status/history/target"
[[ -d "$HISTORY_DIR" ]] || fail "missing sync history directory"

run_mac_sync sync
assert_stdout_lacks "sync file:"
assert_stdout_lacks "sync directory:"
grep -R -F '"outcome" : "skipped"' "$HISTORY_DIR" >/dev/null \
  || fail "missing skipped file history"

printf 'home bash updated\n' >"$TEST_HOME/.bashrc"
run_mac_sync sync
assert_file_contents "$TEST_MACHINES_REPO/machines/target/home/.bashrc" "home bash updated"
assert_stdout_contains "updated snapshot file:"
assert_stdout_lacks "sync directory:"
[[ "$(find "$HISTORY_DIR" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 3 ]] \
  || fail "expected one history record for each completed sync"
grep -R -F '"direction" : "upload"' "$HISTORY_DIR" >/dev/null \
  || fail "missing upload history"
grep -R -F '"outcome" : "new"' "$HISTORY_DIR" >/dev/null \
  || fail "missing new file history"
grep -R -F '"outcome" : "updated"' "$HISTORY_DIR" >/dev/null \
  || fail "missing updated file history"

printf 'local machines repo note\n' >"$TEST_MACHINES_REPO/README.md"

run_mac_sync status
expected_version="$(git -C "$TEST_REPO" rev-parse --short HEAD)"
assert_stdout_contains "mac-sync version: $expected_version"
assert_stdout_contains "local repo: $TEST_REPO"
assert_stdout_contains "machines repo: $TEST_MACHINES_REPO"
assert_stdout_lacks "machine dir:"
assert_stdout_contains "status file: $TEST_HOME/Library/Application Support/mac-sync/status/target.env"
assert_stdout_contains "Homebrew service: use \`brew services info mac-sync\`"
assert_stdout_contains "last sync: success"
assert_stdout_contains "last sync finished:"
assert_stdout_contains "last sync duration:"
assert_stdout_contains "last sync updated:"
assert_stdout_contains "last sync net storage change:"
assert_stdout_lacks "last sync started storage:"
assert_stdout_contains "last sync warnings: 3"
assert_stdout_contains "last sync errors: 0"
assert_stdout_contains "last sync remote repo: none"
assert_stdout_contains "last sync commit:"
assert_stdout_contains "machine snapshot stored:"
assert_stdout_before "machine snapshot stored:" "last sync: success"
assert_stdout_before "last sync warnings: 3" "last sync warning messages:"
assert_stdout_before "last sync warning messages:" "last sync errors: 0"
assert_stdout_before "last sync errors: 0" "last sync error messages:"
assert_stdout_before "last sync error messages:" "last sync remote repo: none"
assert_stdout_before "last sync remote repo: none" "last sync commit:"
assert_stdout_contains "last sync warning messages:"
assert_stdout_contains "WARN: no origin remote configured for local repo; skipping git pull"
assert_stdout_contains "WARN: no origin remote configured for machines repo; skipping git pull"
assert_stdout_contains "WARN: no origin remote configured for machines repo; skipping git push"
assert_stdout_contains "last sync error messages: none"
assert_stdout_contains "machines repo local changes:"
assert_stdout_contains "?? README.md"

MACHINES_ORIGIN="${TMP_ROOT}/machines-origin.git"
git init --bare "$MACHINES_ORIGIN" >/dev/null
git -C "$TEST_MACHINES_REPO" remote add origin "$MACHINES_ORIGIN"
printf 'manual local change\n' >"$TEST_MACHINES_REPO/machines/target/local-change.txt"

run_mac_sync sync
assert_file_contents \
  "$TEST_HOME/Library/Application Support/mac-sync/status/target.local-changes.log" \
  "?? machines/target/local-change.txt"
