#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-github-repositories.XXXXXX")"
readonly TMP_ROOT
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'github repositories test failed: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  grep -F -- "$pattern" "$file" >/dev/null || fail "missing pattern in $file: $pattern"
}

assert_file_lacks() {
  local file="$1"
  local pattern="$2"

  if grep -F -- "$pattern" "$file" >/dev/null; then
    fail "unexpected pattern in $file: $pattern"
  fi
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
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

make_local_repo() {
  local name="$1"
  local remote_name="$2"
  local remote_url="$3"
  local repo_dir="${TEST_HOME}/github/${name}"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -b main >/dev/null
  git -C "$repo_dir" config user.name "mac-sync test"
  git -C "$repo_dir" config user.email "mac-sync@example.invalid"
  printf '%s\n' "$name" >"${repo_dir}/README.md"
  git -C "$repo_dir" add README.md
  git -C "$repo_dir" commit -m "seed ${name}" >/dev/null
  git -C "$repo_dir" remote add "$remote_name" "$remote_url"
}

mkdir -p \
  "$TEST_HOME/github/not-a-repo" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO"
git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "mac-sync test"
git -C "$TEST_REPO" config user.email "mac-sync@example.invalid"
git -C "$TEST_MACHINES_REPO" init -b main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"

: >"$TEST_REPO/config/sync-paths.txt"
: >"$TEST_REPO/config/excludes.txt"

make_local_repo "https-repo" origin "https://github.com/example/https-repo"
make_local_repo "ssh-repo" origin "git@github.com:example/ssh-repo.git"
make_local_repo "fallback-remote" upstream "ssh://git@ssh.github.com:443/example/fallback-remote.git"
make_local_repo "credential-repo" origin "https://token-value@github.com/example/credential-repo.git"
make_local_repo "group/nested-repo" origin "https://github.com/example/nested-repo.git"
make_local_repo "parent-repo" origin "https://github.com/example/parent-repo.git"
make_local_repo "parent-repo/vendor/cache" origin "https://github.com/example/cache.git"
make_local_repo "gitlab-repo" origin "https://gitlab.com/example/gitlab-repo.git"

run_mac_sync sync

readonly SNAPSHOT_FILE="${TEST_MACHINES_REPO}/machines/target/github-repositories/repositories.txt"
assert_file_contains "$SNAPSHOT_FILE" $'https-repo\thttps://github.com/example/https-repo.git'
assert_file_contains "$SNAPSHOT_FILE" $'ssh-repo\thttps://github.com/example/ssh-repo.git'
assert_file_contains "$SNAPSHOT_FILE" $'fallback-remote\thttps://github.com/example/fallback-remote.git'
assert_file_contains "$SNAPSHOT_FILE" $'credential-repo\thttps://github.com/example/credential-repo.git'
assert_file_contains "$SNAPSHOT_FILE" $'group/nested-repo\thttps://github.com/example/nested-repo.git'
assert_file_contains "$SNAPSHOT_FILE" $'parent-repo\thttps://github.com/example/parent-repo.git'
assert_file_lacks "$SNAPSHOT_FILE" "parent-repo/vendor/cache"
assert_file_lacks "$SNAPSHOT_FILE" "cache.git"
assert_file_lacks "$SNAPSHOT_FILE" "token-value"
assert_file_lacks "$SNAPSHOT_FILE" "gitlab-repo"
assert_file_lacks "$SNAPSHOT_FILE" "not-a-repo"
