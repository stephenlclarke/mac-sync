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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  ! grep -F -- "$pattern" "$file" >/dev/null || fail "unexpected pattern in $file: $pattern"
}

run_mac_sync() {
  local action="${1:-run}"
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
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_KEYCHAIN_SERVICE="mac-sync reliability test" \
    MAC_SYNC_KEYCHAIN_ACCOUNT=target \
    MAC_SYNC_RELIABILITY_REMOTE="$TEST_REMOTE" \
    KEYCHAIN_FAKE_DIR="${TMP_ROOT}/keychain" \
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$action" >"$STDOUT_FILE" 2>"$STDERR_FILE"
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
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_KEYCHAIN_SERVICE="mac-sync reliability test" \
    MAC_SYNC_KEYCHAIN_ACCOUNT=target \
    MAC_SYNC_RELIABILITY_REMOTE="$TEST_REMOTE" \
    KEYCHAIN_FAKE_DIR="${TMP_ROOT}/keychain" \
    PATH="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$action" >"$STDOUT_FILE" 2>"$STDERR_FILE"
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
touch "${KEYCHAIN_FAKE_DIR:?KEYCHAIN_FAKE_DIR is not set}/unexpected-access"
exit 44
EOF
chmod +x "$TEST_BIN/security"

set +e
run_mac_sync
partial_status="$?"
set -e
[[ "$partial_status" -eq 0 ]] || fail "scheduled run failed"
assert_file_contains "$TEST_STATUS/target.env" "result=success"
assert_file_contains "$TEST_STATUS/target.env" "exit_status=0"
assert_file_not_contains "$TEST_STATUS/target.conditions.json" '"code" : "encryptedSecretsIdentityMissing"'
[[ ! -e "${TMP_ROOT}/keychain/unexpected-access" ]] \
  || fail "unattended sync accessed Keychain"
assert_file_contains \
  "$TEST_MACHINES_REPO/machines/target/home/.bashrc" \
  "first snapshot"

git -C "$TEST_MACHINES_REPO" remote set-url origin \
  "https://github.com/example/mac-sync-data.git"
cat >"$TEST_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly REAL_GIT=/usr/bin/git

if [[ "$1" == "ls-remote" && "$2" == "git@github.com:example/mac-sync-data.git" ]]; then
  printf '%s\tHEAD\n' "$("$REAL_GIT" -C "$MAC_SYNC_MACHINES_REPO" rev-parse HEAD)"
  exit 0
fi

if [[ "$1" == "-C" && "$2" == "$MAC_SYNC_MACHINES_REPO" && "$3" == "pull" ]]; then
  printf 'fatal: could not read Username for https://github.com\n' >&2
  exit 1
fi

if [[ "$1" == "-c" && "$3" == "-C" && "$4" == "$MAC_SYNC_MACHINES_REPO" && "$5" == "pull" ]]; then
  "$REAL_GIT" -C "$MAC_SYNC_MACHINES_REPO" remote set-url origin \
    "$MAC_SYNC_RELIABILITY_REMOTE"
  exec "$REAL_GIT" -C "$MAC_SYNC_MACHINES_REPO" pull --ff-only
fi

exec "$REAL_GIT" "$@"
EOF
chmod +x "$TEST_BIN/git"

run_mac_sync
assert_file_contains "$TEST_STATUS/target.env" "result=success"
assert_file_contains "$TEST_STATUS/target.commands.json" "using SSH"
assert_file_contains "$STDOUT_FILE" "using verified SSH access"
rm -f "$TEST_BIN/git"

# A failed branch command is not a detached HEAD. Fail before snapshots or
# commits change, retain the actual diagnostic, and allow the next manual retry.
cat >"$TEST_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$3" == "symbolic-ref" || ( "$3" == "branch" && "$4" == "--show-current" ) ]]; then
  if [[ -n "${MAC_SYNC_TEST_BRANCH_PROBE:-}" && ! -e "$MAC_SYNC_TEST_BRANCH_PROBE" ]]; then
    touch "$MAC_SYNC_TEST_BRANCH_PROBE"
    exec /usr/bin/git "$@"
  fi
  if [[ "$MAC_SYNC_TEST_BRANCH_STATUS" != 0 ]]; then
    printf 'fatal: injected branch lookup failure\n' >&2
  fi
  exit "$MAC_SYNC_TEST_BRANCH_STATUS"
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$TEST_BIN/git"
branch_test_head="$(git -C "$TEST_MACHINES_REPO" rev-parse HEAD)"
printf 'waiting for branch check\n' >"$TEST_HOME/.bashrc"
for MAC_SYNC_TEST_BRANCH_STATUS in 128 124 1 0; do
  export MAC_SYNC_TEST_BRANCH_STATUS
  if run_mac_sync sync; then
    fail "branch lookup failure was reported as successful"
  fi
  assert_file_contains "$TEST_STATUS/target.env" 'result=failed'
  assert_file_contains "$TEST_STATUS/target.conditions.json" 'Git could not read the repository branch'
  assert_file_not_contains "$TEST_STATUS/target.conditions.json" '"title" : "The repository is on a detached commit"'
  assert_file_contains "$TEST_STATUS/target.commands.json" "\"exitStatus\" : $MAC_SYNC_TEST_BRANCH_STATUS"
  assert_file_contains "$TEST_MACHINES_REPO/machines/target/home/.bashrc" 'first snapshot'
  [[ "$(git -C "$TEST_MACHINES_REPO" rev-parse HEAD)" == "$branch_test_head" ]] \
    || fail "branch lookup failure created a commit"
done

# If the initial probe passed but the final check fails, keep copied snapshots
# available for retry without creating a new commit or claiming publication.
export MAC_SYNC_TEST_BRANCH_STATUS=128
export MAC_SYNC_TEST_BRANCH_PROBE="${TMP_ROOT}/branch-probe"
if run_mac_sync sync; then
  fail "late branch lookup failure was reported as successful"
fi
assert_file_contains "$TEST_STATUS/target.env" 'result=failed'
assert_file_contains "$TEST_MACHINES_REPO/machines/target/home/.bashrc" 'waiting for branch check'
[[ "$(git -C "$TEST_MACHINES_REPO" rev-parse HEAD)" == "$branch_test_head" ]] \
  || fail "late branch lookup failure created a commit"
unset MAC_SYNC_TEST_BRANCH_STATUS MAC_SYNC_TEST_BRANCH_PROBE
rm -f "$TEST_BIN/git"

# Confirm a real detached HEAD separately; never commit snapshots onto it or
# switch branches automatically. The fixture alone returns to its main branch.
git -C "$TEST_MACHINES_REPO" switch --detach >/dev/null 2>&1
if run_mac_sync sync; then
  fail "detached HEAD was reported as successful"
fi
assert_file_contains "$TEST_STATUS/target.env" 'result=failed'
assert_file_contains "$TEST_STATUS/target.conditions.json" 'The repository is on a detached commit'
[[ "$(git -C "$TEST_MACHINES_REPO" rev-parse HEAD)" == "$branch_test_head" ]] \
  || fail "detached HEAD run created a commit"
git -C "$TEST_MACHINES_REPO" switch main >/dev/null 2>&1
run_mac_sync sync
assert_file_contains "$TEST_STATUS/target.env" 'exit_status=0'
[[ "$(git -C "$TEST_MACHINES_REPO" rev-parse HEAD)" == "$(git --git-dir="$TEST_REMOTE" rev-parse main)" ]] \
  || fail "retry did not publish the pending snapshot"
run_mac_sync sync
assert_file_contains "$TEST_STATUS/target.env" 'result=success'

# A push outage preserves the local commit. A later run rebases it over a
# peer's update, rather than requiring a user to repair a divergent branch.
cat >"$TEST_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$3" == "push" ]]; then
  printf 'fatal: requested URL returned error: 503\n' >&2
  exit 1
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$TEST_BIN/git"
printf 'pending offline snapshot\n' >"$TEST_HOME/.bashrc"
set +e
run_mac_sync
push_status="$?"
set -e
[[ "$push_status" -ne 0 ]] || fail "push outage was reported as successful"
assert_file_contains "$TEST_STATUS/target.env" "result=deferred"
rm -f "$TEST_BIN/git"
git clone "$TEST_REMOTE" "${TMP_ROOT}/peer" >/dev/null 2>&1
git -C "${TMP_ROOT}/peer" config user.name "peer test"
git -C "${TMP_ROOT}/peer" config user.email "peer@example.invalid"
printf 'peer snapshot\n' >"${TMP_ROOT}/peer/peer.txt"
git -C "${TMP_ROOT}/peer" add peer.txt
git -C "${TMP_ROOT}/peer" commit -m "test: peer update" >/dev/null
git -C "${TMP_ROOT}/peer" push >/dev/null 2>&1
run_mac_sync sync
assert_file_contains "$TEST_MACHINES_REPO/peer.txt" "peer snapshot"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/home/.bashrc" "pending offline snapshot"
assert_file_contains "$TEST_STATUS/target.env" "result=success"
assert_file_contains "$TEST_STATUS/target.background.json" '"consecutiveFailures":0'
assert_file_not_contains "$TEST_STATUS/target.background.json" '"nextAttempt"'
run_mac_sync
assert_file_contains "$STDOUT_FILE" "pulling latest"

printf 'must not be published\n' >"$TEST_HOME/.bashrc"
rm -rf "$TEST_REMOTE"
set +e
run_mac_sync
failure_status="$?"
set -e

[[ "$failure_status" -ne 0 ]] || fail "scheduled run unexpectedly succeeded without a verified pull"
assert_file_contains "$TEST_STATUS/target.env" "result=failed"
assert_file_contains "$TEST_STATUS/target.conditions.json" '"code" : "remoteRefreshFailed"'
assert_file_contains "$TEST_STATUS/target.commands.json" '"attempt" : 1'
assert_file_contains "$STDERR_FILE" "sync stopped before changing snapshots"
assert_file_contains \
  "$TEST_MACHINES_REPO/machines/target/home/.bashrc" \
  "pending offline snapshot"

# The next scheduled invocation honours the persisted backoff, without Git I/O.
run_mac_sync
assert_file_contains "$STDOUT_FILE" "Waiting to retry GitHub connectivity"
assert_file_not_contains "$STDOUT_FILE" "pulling latest"

printf 'reliability test passed\n'
