#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-dynamic.XXXXXX")"
readonly TMP_ROOT
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'dynamic test failed: %s\n' "$*" >&2
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

assert_file_lacks() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
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
    MAC_SYNC_DYNAMIC_REFS=1 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=1 \
    MAC_SYNC_HOMEBREW=0 \
    MAC_SYNC_SECRETS=0 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO" \
  "$TEST_HOME/.config/tool" \
  "$TEST_HOME/.config/gh" \
  "$TEST_HOME/.ssh" \
  "$TEST_HOME/.tmux/plugins/tpm" \
  "$TEST_HOME/bin"

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

cat >"$TEST_HOME/.bashrc" <<EOF
source "\$HOME/.config/tool/settings.json"
. "\$HOME/bin/helper"
. "\$HOME/.ssh/config"
. "\$HOME/.ssh/id_rsa"
. "\$HOME/.config/gh/hosts.yml"
. "~/.tmux/plugins/tpm/plugin.conf"
for shell_config in zshrc aliases; do
  :
done
EOF
printf 'tool=true\n' >"$TEST_HOME/.config/tool/settings.json"
printf '#!/usr/bin/env bash\n' >"$TEST_HOME/bin/helper"
printf 'Host example\n' >"$TEST_HOME/.ssh/config"
printf 'private-key-placeholder\n' >"$TEST_HOME/.ssh/id_rsa"
printf 'oauth_token: redacted\n' >"$TEST_HOME/.config/gh/hosts.yml"
printf 'plugin=true\n' >"$TEST_HOME/.tmux/plugins/tpm/plugin.conf"
printf 'zsh config\n' >"$TEST_HOME/.zshrc"
printf 'aliases\n' >"$TEST_HOME/.aliases"

run_mac_sync sync

readonly DYNAMIC_FILE="$TEST_MACHINES_REPO/machines/target/dynamic-sync-paths.txt"
assert_file_contains "$DYNAMIC_FILE" ".config/tool"
assert_file_contains "$DYNAMIC_FILE" ".ssh/config"
assert_file_contains "$DYNAMIC_FILE" ".tmux/plugins/tpm"
assert_file_contains "$DYNAMIC_FILE" ".zshrc"
assert_file_contains "$DYNAMIC_FILE" ".aliases"
assert_file_contains "$DYNAMIC_FILE" "bin/helper"
assert_file_lacks "$DYNAMIC_FILE" ".ssh/id_rsa"
assert_file_lacks "$DYNAMIC_FILE" ".config/gh/hosts.yml"
[[ -f "$TEST_MACHINES_REPO/machines/target/home/.config/tool/settings.json" ]] \
  || fail "missing dynamic config snapshot"

printf 'no dynamic references now\n' >"$TEST_HOME/.bashrc"
run_mac_sync sync
[[ ! -e "$TEST_MACHINES_REPO/machines/target/home/.config/tool" ]] \
  || fail "stale dynamic config snapshot was not pruned"
assert_file_lacks "$DYNAMIC_FILE" ".config/tool"
