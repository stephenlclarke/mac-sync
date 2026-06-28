#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-concurrent.XXXXXX")"
readonly TMP_ROOT
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_INSTALL="${TMP_ROOT}/bin/mac-sync"
readonly REMOTE_WORK="${TMP_ROOT}/remote-work"
readonly REMOTE_BARE="${TMP_ROOT}/machines.git"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly OTHER_CLONE="${TMP_ROOT}/other-clone"
readonly PUSH_RACE_MARKER="${TMP_ROOT}/push-race-fired"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"
readonly GIT_TEST_NAME="mac-sync test"
readonly GIT_TEST_EMAIL="mac-sync@example.invalid"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'concurrent machines test failed: %s\n' "$*" >&2
  exit 1
}

assert_stdout_contains() {
  local pattern="$1"

  grep -F -- "$pattern" "$STDOUT_FILE" >/dev/null || fail "missing stdout pattern: $pattern"
}

assert_stderr_lacks() {
  local pattern="$1"

  if grep -F -- "$pattern" "$STDERR_FILE" >/dev/null; then
    fail "unexpected stderr pattern: $pattern"
  fi
}

assert_stderr_contains() {
  local pattern="$1"

  grep -F -- "$pattern" "$STDERR_FILE" >/dev/null || fail "missing stderr pattern: $pattern"
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
    MAC_SYNC_SELF_UPDATE=0 \
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
    MAC_SYNC_SELF_UPDATE=0 \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p \
  "$TEST_HOME" \
  "$(dirname "$TEST_INSTALL")" \
  "$TEST_REPO/bin" \
  "$TEST_REPO/config" \
  "$REMOTE_WORK/machines/other/home"

cp "$SCRIPT_PATH" "$TEST_REPO/bin/mac-sync"
cp "$SCRIPT_PATH" "$TEST_INSTALL"
chmod +x "$TEST_INSTALL"

cat >"$TEST_REPO/config/sync-paths.txt" <<'EOF'
.bashrc
EOF
: >"$TEST_REPO/config/excludes.txt"

git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "$GIT_TEST_NAME"
git -C "$TEST_REPO" config user.email "$GIT_TEST_EMAIL"
git -C "$TEST_REPO" add .
git -C "$TEST_REPO" commit -m "test local repo" >/dev/null

git -C "$REMOTE_WORK" init -b main >/dev/null
git -C "$REMOTE_WORK" config user.name "$GIT_TEST_NAME"
git -C "$REMOTE_WORK" config user.email "$GIT_TEST_EMAIL"
printf 'tracked base\n' >"$REMOTE_WORK/README.md"
printf 'other-base\n' >"$REMOTE_WORK/machines/other/home/.bashrc"
git -C "$REMOTE_WORK" add .
git -C "$REMOTE_WORK" commit -m "seed other machine" >/dev/null
git clone --bare "$REMOTE_WORK" "$REMOTE_BARE" >/dev/null 2>&1
git clone "$REMOTE_BARE" "$TEST_MACHINES_REPO" >/dev/null 2>&1
git -C "$TEST_MACHINES_REPO" config user.name "$GIT_TEST_NAME"
git -C "$TEST_MACHINES_REPO" config user.email "$GIT_TEST_EMAIL"

git clone "$REMOTE_BARE" "$OTHER_CLONE" >/dev/null 2>&1
git -C "$OTHER_CLONE" config user.name "$GIT_TEST_NAME"
git -C "$OTHER_CLONE" config user.email "$GIT_TEST_EMAIL"
printf 'other-update\n' >"$OTHER_CLONE/machines/other/home/.bashrc"
git -C "$OTHER_CLONE" commit -am "sync other machine" >/dev/null
git -C "$OTHER_CLONE" push origin main >/dev/null 2>&1

cat >"$TEST_MACHINES_REPO/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ ! -e "$PUSH_RACE_MARKER" ]]; then
  touch "$PUSH_RACE_MARKER"
  printf 'other-race\n' >"$OTHER_CLONE/machines/other/home/.race"
  git -C "$OTHER_CLONE" add machines/other/home/.race >/dev/null
  git -C "$OTHER_CLONE" commit -m "race other machine" >/dev/null
  git -C "$OTHER_CLONE" push origin main >/dev/null 2>&1
fi
EOF
chmod +x "$TEST_MACHINES_REPO/.git/hooks/pre-push"

printf 'local staged edit\n' >"$TEST_MACHINES_REPO/README.md"
git -C "$TEST_MACHINES_REPO" add README.md
mkdir -p "$TEST_MACHINES_REPO/bin"
printf '#!/usr/bin/env bash\n' >"$TEST_MACHINES_REPO/bin/setup-git-ssh-signing.sh"
chmod +x "$TEST_MACHINES_REPO/bin/setup-git-ssh-signing.sh"
printf 'target-update\n' >"$TEST_HOME/.bashrc"

run_mac_sync sync

assert_stdout_contains "pulled latest machines repo changes"
assert_stdout_contains "rebased machines repo before push"
assert_stderr_contains "rebasing and retrying"
assert_stderr_lacks "machines repo has local changes; skipping pre-operation git pull"
assert_stdout_contains "pushed main to origin"

git -C "$TEST_MACHINES_REPO" fetch origin >/dev/null
read -r ahead behind < <(git -C "$TEST_MACHINES_REPO" rev-list --left-right --count HEAD...origin/main)
[[ "$ahead" = "0" && "$behind" = "0" ]] || fail "machines repo not in sync after push: ahead=$ahead behind=$behind"

grep -F "target-update" "$TEST_MACHINES_REPO/machines/target/home/.bashrc" >/dev/null \
  || fail "target machine snapshot was not written"
grep -F "other-update" "$TEST_MACHINES_REPO/machines/other/home/.bashrc" >/dev/null \
  || fail "other machine remote update was not integrated"
grep -F "other-race" "$TEST_MACHINES_REPO/machines/other/home/.race" >/dev/null \
  || fail "other machine race update was not integrated"
[[ -f "$TEST_MACHINES_REPO/bin/setup-git-ssh-signing.sh" ]] \
  || fail "unrelated untracked file was not preserved"
git -C "$TEST_MACHINES_REPO" status --porcelain | grep -F "?? bin/" >/dev/null \
  || fail "unrelated untracked file is no longer untracked"
git -C "$TEST_MACHINES_REPO" status --porcelain -- README.md | grep -F "README.md" >/dev/null \
  || fail "unrelated tracked edit was not preserved"
grep -F "local staged edit" "$TEST_MACHINES_REPO/README.md" >/dev/null \
  || fail "unrelated tracked edit contents changed"
[[ "$(git -C "$TEST_MACHINES_REPO" show HEAD:README.md)" = "tracked base" ]] \
  || fail "unrelated tracked edit was committed"
