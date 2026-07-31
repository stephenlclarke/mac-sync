#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-reliability.XXXXXX")"
readonly TMP_ROOT
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_REMOTE="${TMP_ROOT}/remote.git"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/mac-sync-data"
readonly TEST_STATUS="${TMP_ROOT}/status"
readonly TEST_BIN="${TMP_ROOT}/bin"
readonly TEST_TEMP="${TMP_ROOT}/tmp"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'reliability test failed: %s\n' "$*" >&2
  if [[ -s "$STDOUT_FILE" ]]; then
    printf 'captured command stdout:\n' >&2
    sed 's/^/  /' "$STDOUT_FILE" >&2
  fi
  if [[ -s "$STDERR_FILE" ]]; then
    printf 'captured command stderr:\n' >&2
    sed 's/^/  /' "$STDERR_FILE" >&2
  fi
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  grep -F -- "$pattern" "$file" >/dev/null || fail "missing pattern in $file: $pattern"
}

run_mac_sync() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    TMPDIR="${TEST_TEMP}/" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_STATUS_DIR="$TEST_STATUS" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_VSCODE_EXTENSIONS=0 \
    MAC_SYNC_GITHUB_REPOS=0 \
    MAC_SYNC_KEYCHAIN_SERVICE="mac-sync reliability test" \
    MAC_SYNC_KEYCHAIN_ACCOUNT=target \
    KEYCHAIN_FAKE_DIR="${TMP_ROOT}/keychain" \
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" run >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    TMPDIR="${TEST_TEMP}/" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_STATUS_DIR="$TEST_STATUS" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_VSCODE_EXTENSIONS=0 \
    MAC_SYNC_GITHUB_REPOS=0 \
    MAC_SYNC_KEYCHAIN_SERVICE="mac-sync reliability test" \
    MAC_SYNC_KEYCHAIN_ACCOUNT=target \
    KEYCHAIN_FAKE_DIR="${TMP_ROOT}/keychain" \
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" run >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p "$TEST_HOME" "$TEST_STATUS" "$TEST_BIN" "$TEST_TEMP" "${TMP_ROOT}/keychain"
git init --bare -b main "$TEST_REMOTE" >/dev/null
git clone "$TEST_REMOTE" "$TEST_MACHINES_REPO" >/dev/null 2>&1
git -C "$TEST_MACHINES_REPO" switch -c main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"
mkdir -p \
  "$TEST_MACHINES_REPO/machines/target/config" \
  "$TEST_MACHINES_REPO/machines/_shared/config"
printf '.bashrc\n' >"$TEST_MACHINES_REPO/machines/target/config/sync-paths.txt"
printf '.ssh/id_ed25519\n' >"$TEST_MACHINES_REPO/machines/target/config/secret-paths.txt"
printf 'age1reliabilitytestrecipient\n' \
  >"$TEST_MACHINES_REPO/machines/_shared/config/age-recipients.txt"
git -C "$TEST_MACHINES_REPO" add machines
git -C "$TEST_MACHINES_REPO" commit -m "test configuration" >/dev/null
git -C "$TEST_MACHINES_REPO" push -u origin main >/dev/null
printf 'first snapshot\n' >"$TEST_HOME/.bashrc"

cat >"$TEST_BIN/security" <<'EOF'
#!/usr/bin/env bash
exit 44
EOF
chmod +x "$TEST_BIN/security"

set +e
run_mac_sync
partial_status="$?"
set -e
[[ "$partial_status" -eq 0 ]] || fail "scheduled run with one skipped subsystem failed"
assert_file_contains "$TEST_STATUS/target.env" "result=partial"
assert_file_contains "$TEST_STATUS/target.env" "exit_status=0"
assert_file_contains "$TEST_STATUS/target.conditions.json" '"code" : "encryptedSecretsIdentityMissing"'
assert_file_contains \
  "$TEST_MACHINES_REPO/machines/target/home/.bashrc" \
  "first snapshot"

printf 'must not be published\n' >"$TEST_HOME/.bashrc"
rm -rf "$TEST_REMOTE"
set +e
run_mac_sync
failure_status="$?"
set -e

[[ "$failure_status" -ne 0 ]] || fail "scheduled run unexpectedly succeeded without a verified pull"
assert_file_contains "$TEST_STATUS/target.env" "result=failed"
assert_file_contains "$TEST_STATUS/target.conditions.json" '"code" : "remoteRefreshFailed"'
assert_file_contains "$TEST_STATUS/target.commands.json" '"attempt" : 3'
assert_file_contains "$STDERR_FILE" "sync stopped before changing snapshots"
assert_file_contains \
  "$TEST_MACHINES_REPO/machines/target/home/.bashrc" \
  "first snapshot"

printf 'reliability test passed\n'
