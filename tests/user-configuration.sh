#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
readonly TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-user-configuration.XXXXXX")"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_DATA_REPO="${TMP_ROOT}/custom/mac-sync-data"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'user configuration test failed: %s\n' "$*" >&2
  exit 1
}

run_mac_sync() {
  local command=("$SCRIPT_PATH" "$@")
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    command=("$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@")
  fi
  HOME="$TEST_HOME" \
  MAC_SYNC_MACHINE=user-config-test \
  MAC_SYNC_HOMEBREW=0 \
  MAC_SYNC_SECRETS=0 \
  MAC_SYNC_GITHUB_REPOS=0 \
  MAC_SYNC_VSCODE_EXTENSIONS=0 \
  SCRIPT_COLOUR=off \
    "${command[@]}" >"${TMP_ROOT}/stdout" 2>"${TMP_ROOT}/stderr"
}

mkdir -p \
  "${TEST_HOME}/Library/Application Support/mac-sync" \
  "${TEST_DATA_REPO}/machines/user-config-test/config"

git -C "$TEST_DATA_REPO" init -b main >/dev/null
printf '.zshrc\n' >"${TEST_DATA_REPO}/machines/user-config-test/config/sync-paths.txt"
printf '# no excludes\n' >"${TEST_DATA_REPO}/machines/user-config-test/config/excludes.txt"
cat >"${TEST_HOME}/Library/Application Support/mac-sync/config.env" <<EOF
# Managed by Mac Sync. Data repository only; credentials remain in Git/Keychain.
MAC_SYNC_DATA_REPOSITORY=${TEST_DATA_REPO}
EOF

run_mac_sync list
grep -F "data repo: ${TEST_DATA_REPO}" "${TMP_ROOT}/stdout" >/dev/null \
  || fail "persisted data repository was not used"
grep -F "paths file: ${TEST_DATA_REPO}/machines/user-config-test/config/sync-paths.txt" "${TMP_ROOT}/stdout" >/dev/null \
  || fail "machine configuration was not read from the data repository"

override_repo="${TMP_ROOT}/override/mac-sync-data"
mkdir -p "${override_repo}/machines/user-config-test/config"
git -C "$override_repo" init -b main >/dev/null
printf '.bashrc\n' >"${override_repo}/machines/user-config-test/config/sync-paths.txt"
printf '# no excludes\n' >"${override_repo}/machines/user-config-test/config/excludes.txt"
HOME="$TEST_HOME" \
MAC_SYNC_MACHINES_REPO="$override_repo" \
MAC_SYNC_MACHINE=user-config-test \
MAC_SYNC_HOMEBREW=0 \
MAC_SYNC_SECRETS=0 \
MAC_SYNC_GITHUB_REPOS=0 \
MAC_SYNC_VSCODE_EXTENSIONS=0 \
SCRIPT_COLOUR=off \
  "$SCRIPT_PATH" list >"${TMP_ROOT}/override.stdout" 2>"${TMP_ROOT}/override.stderr"
grep -F "data repo: ${override_repo}" "${TMP_ROOT}/override.stdout" >/dev/null \
  || fail "explicit MAC_SYNC_MACHINES_REPO did not override persisted configuration"
