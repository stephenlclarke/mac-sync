#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-manifest.XXXXXX")"
readonly TMP_ROOT
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_INSTALL="${TMP_ROOT}/bin/mac-sync"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'manifest test failed: %s\n' "$*" >&2
  exit 1
}

assert_stdout_contains() {
  local pattern="$1"

  grep -F -- "$pattern" "$STDOUT_FILE" >/dev/null || fail "missing stdout pattern: $pattern"
}

assert_stdout_lacks() {
  local pattern="$1"

  if grep -F -- "$pattern" "$STDOUT_FILE" >/dev/null; then
    fail "unexpected stdout pattern: $pattern"
  fi
}

run_mac_sync() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_MANIFEST_SOURCE="${MAC_SYNC_MANIFEST_SOURCE:-auto}" \
    MAC_SYNC_SELF_UPDATE=0 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    MAC_SYNC_MANIFEST_SOURCE="${MAC_SYNC_MANIFEST_SOURCE:-auto}" \
    MAC_SYNC_SELF_UPDATE=0 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p \
  "$TEST_HOME" \
  "$TEST_REPO/bin" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO" \
  "$(dirname "$TEST_INSTALL")"

cp "$SCRIPT_PATH" "$TEST_REPO/bin/mac-sync"
cp "$SCRIPT_PATH" "$TEST_INSTALL"
chmod +x "$TEST_INSTALL"
git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "mac-sync test"
git -C "$TEST_REPO" config user.email "mac-sync@example.invalid"
git -C "$TEST_MACHINES_REPO" init -b main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"

cat >"$TEST_REPO/config/sync-paths.txt" <<'EOF'
.bashrc
EOF
: >"$TEST_REPO/config/excludes.txt"

cat >"$TEST_MACHINES_REPO/Makefile" <<'EOF'
.PHONY: print-mac-sync-paths
print-mac-sync-paths:
	@printf '%s\n' '.profile'
	@printf '%s\n' '.config/tool'
EOF

run_mac_sync list
assert_stdout_contains "manifest source: dot-files"
assert_stdout_contains "$TEST_HOME/.profile -> $TEST_MACHINES_REPO/machines/target/home/.profile"
assert_stdout_contains "$TEST_HOME/.config/tool -> $TEST_MACHINES_REPO/machines/target/home/.config/tool"
assert_stdout_lacks "$TEST_HOME/.bashrc ->"

MAC_SYNC_MANIFEST_SOURCE=config run_mac_sync list
assert_stdout_contains "manifest source: config"
assert_stdout_contains "$TEST_HOME/.bashrc -> $TEST_MACHINES_REPO/machines/target/home/.bashrc"
assert_stdout_lacks "$TEST_HOME/.profile ->"

MAC_SYNC_MANIFEST_SOURCE=dot-files run_mac_sync list
assert_stdout_contains "manifest source: dot-files"
assert_stdout_contains "$TEST_HOME/.profile -> $TEST_MACHINES_REPO/machines/target/home/.profile"
