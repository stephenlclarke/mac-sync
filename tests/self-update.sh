#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-self-update.XXXXXX")"
readonly TMP_ROOT
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_INSTALL="${TMP_ROOT}/bin/mac-sync"
readonly REMOTE_WORK="${TMP_ROOT}/remote-work"
readonly REMOTE_BARE="${TMP_ROOT}/remote.git"
readonly MARKER_FILE="${TMP_ROOT}/marker"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'self-update test failed: %s\n' "$*" >&2
  exit 1
}

run_installed() {
  local status=0

  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_SELF_UPDATE_REMOTE="$REMOTE_BARE" \
    MAC_SYNC_SELF_UPDATE_REF=main \
    MAC_SYNC_SELF_UPDATE="${MAC_SYNC_SELF_UPDATE:-1}" \
    MAC_SYNC_SELF_UPDATE_MODE="${MAC_SYNC_SELF_UPDATE_MODE:-restart}" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_SELF_UPDATE_TEST_MARKER="$MARKER_FILE" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$TEST_INSTALL" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_SELF_UPDATE_REMOTE="$REMOTE_BARE" \
    MAC_SYNC_SELF_UPDATE_REF=main \
    MAC_SYNC_SELF_UPDATE="${MAC_SYNC_SELF_UPDATE:-1}" \
    MAC_SYNC_SELF_UPDATE_MODE="${MAC_SYNC_SELF_UPDATE_MODE:-restart}" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_SELF_UPDATE_TEST_MARKER="$MARKER_FILE" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$TEST_INSTALL" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?
  fi

  return "$status"
}

write_remote_script() {
  cat >"$REMOTE_WORK/bin/mac-sync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'updated script executed: %s\n' "$*" >"${MAC_SYNC_SELF_UPDATE_TEST_MARKER:?}"
EOF
  chmod +x "$REMOTE_WORK/bin/mac-sync"
}

mkdir -p \
  "$TEST_HOME" \
  "$TEST_REPO/bin" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO" \
  "$(dirname "$TEST_INSTALL")" \
  "$REMOTE_WORK/bin"

cp "$SCRIPT_PATH" "$TEST_INSTALL"
chmod +x "$TEST_INSTALL"
cp "$SCRIPT_PATH" "$TEST_REPO/bin/mac-sync"
: >"$TEST_REPO/config/sync-paths.txt"
: >"$TEST_REPO/config/excludes.txt"

git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "mac-sync test"
git -C "$TEST_REPO" config user.email "mac-sync@example.invalid"
git -C "$TEST_REPO" add .
git -C "$TEST_REPO" commit -m "test local repo" >/dev/null

git -C "$TEST_MACHINES_REPO" init -b main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"

git -C "$REMOTE_WORK" init -b main >/dev/null
git -C "$REMOTE_WORK" config user.name "mac-sync test"
git -C "$REMOTE_WORK" config user.email "mac-sync@example.invalid"
write_remote_script
cat >"$REMOTE_WORK/bin/mac-spinner" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$REMOTE_WORK/bin/mac-spinner"
git -C "$REMOTE_WORK" add .
git -C "$REMOTE_WORK" commit -m "test remote update" >/dev/null
git clone --bare "$REMOTE_WORK" "$REMOTE_BARE" >/dev/null 2>&1

run_installed sync || fail "restart mode should run updated script"
grep -F "updated script executed: sync" "$MARKER_FILE" >/dev/null \
  || fail "updated script was not re-executed"
cmp -s "$REMOTE_WORK/bin/mac-sync" "$TEST_INSTALL" \
  || fail "installed script was not replaced from remote"
cmp -s "$REMOTE_WORK/bin/mac-spinner" "${TMP_ROOT}/bin/mac-spinner" \
  || fail "spinner helper was not replaced from remote"

rm -f "$MARKER_FILE"
cp "$SCRIPT_PATH" "$TEST_INSTALL"
chmod +x "$TEST_INSTALL"
if MAC_SYNC_SELF_UPDATE_MODE=exit run_installed sync; then
  fail "exit mode should stop after installing the update"
else
  status=$?
  [[ "$status" -eq 75 ]] || fail "exit mode returned $status, expected 75"
fi
[[ ! -f "$MARKER_FILE" ]] || fail "exit mode should not re-execute updated script"
cmp -s "$REMOTE_WORK/bin/mac-sync" "$TEST_INSTALL" \
  || fail "exit mode did not install remote script"

cp "$SCRIPT_PATH" "$TEST_INSTALL"
chmod +x "$TEST_INSTALL"
MAC_SYNC_SELF_UPDATE=0 run_installed sync || fail "disabled self-update sync failed"
[[ ! -f "$MARKER_FILE" ]] || fail "disabled self-update still ran remote script"
cmp -s "$SCRIPT_PATH" "$TEST_INSTALL" \
  || fail "disabled self-update changed installed script"
