#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/bin/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-homebrew.XXXXXX")"
readonly TMP_ROOT
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly TEST_INSTALL="${TMP_ROOT}/bin/mac-sync"
readonly FAKE_BIN="${TMP_ROOT}/fake-bin"
readonly BREW_BUNDLE_LOG="${TMP_ROOT}/brew-bundle.log"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'homebrew test failed: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  grep -F "$pattern" "$file" >/dev/null || fail "missing pattern in $file: $pattern"
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

run_mac_sync() {
  local mode="$1"
  shift

  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_VSCODE_EXTENSIONS=0 \
    BREW_FAKE_MODE="$mode" \
    BREW_FAKE_BUNDLE_LOG="$BREW_BUNDLE_LOG" \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_INSTALL_PATH="$TEST_INSTALL" \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_VSCODE_EXTENSIONS=0 \
    BREW_FAKE_MODE="$mode" \
    BREW_FAKE_BUNDLE_LOG="$BREW_BUNDLE_LOG" \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

mkdir -p \
  "$FAKE_BIN" \
  "$TEST_REPO/bin" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO/machines/source/home" \
  "$TEST_HOME"

cat >"$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${BREW_FAKE_MODE:-sync}"

case "$1" in
  bundle)
    printf '%s\n' "$*" >>"${BREW_FAKE_BUNDLE_LOG:?BREW_FAKE_BUNDLE_LOG is not set}"
    ;;
  tap)
    case "$mode" in
      sync)
        printf '%s\n' homebrew/cask stephenlclarke/tools
        ;;
      diff)
        printf '%s\n' homebrew/cask
        ;;
      match)
        printf '%s\n' homebrew/cask homebrew/services
        ;;
    esac
    ;;
  list)
    case "$2" in
      --formula)
        case "$mode" in
          sync)
            printf '%s\n' jq ripgrep
            ;;
          diff)
            printf '%s\n' jq ripgrep
            ;;
          match)
            printf '%s\n' jq ripgrep shellcheck
            ;;
        esac
        ;;
      --cask)
        case "$mode" in
          sync)
            printf '%s\n' rectangle
            ;;
          diff)
            printf '%s\n' iterm2
            ;;
          match)
            printf '%s\n' iterm2 rectangle visual-studio-code
            ;;
        esac
        ;;
    esac
    ;;
  outdated)
    case "$2" in
      --formula)
        [[ "$mode" == "diff" ]] && printf '%s\n' jq
        ;;
      --cask)
        [[ "$mode" == "diff" ]] && printf '%s\n' iterm2
        ;;
    esac
    ;;
esac
EOF
chmod +x "$FAKE_BIN/brew"

cp "$SCRIPT_PATH" "$TEST_REPO/bin/mac-sync"
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
printf 'home bash\n' >"$TEST_HOME/.bashrc"

run_mac_sync sync sync
assert_stdout_contains $'\342\240\223 updating Homebrew package snapshot'
assert_stdout_contains $'\342\234\224\357\270\216 updated Homebrew package snapshot: '"$TEST_MACHINES_REPO/machines/target/homebrew"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/taps.txt" "homebrew/cask"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/taps.txt" "stephenlclarke/tools"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/formulae.txt" "jq"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/formulae.txt" "ripgrep"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/casks.txt" "rectangle"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/Brewfile" 'tap "homebrew/cask"'
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/Brewfile" 'brew "jq"'
assert_file_contains "$TEST_MACHINES_REPO/machines/target/homebrew/Brewfile" 'cask "rectangle"'

cat >"$TEST_MACHINES_REPO/machines/source/dynamic-sync-paths.txt" <<'EOF'
# Generated by mac-sync. Do not edit.
EOF

printf 'source bash\n' >"$TEST_MACHINES_REPO/machines/source/home/.bashrc"
mkdir -p "$TEST_MACHINES_REPO/machines/source/homebrew"

cat >"$TEST_MACHINES_REPO/machines/source/homebrew/taps.txt" <<'EOF'
# Generated by mac-sync. Do not edit.
homebrew/cask
homebrew/services
EOF

cat >"$TEST_MACHINES_REPO/machines/source/homebrew/formulae.txt" <<'EOF'
# Generated by mac-sync. Do not edit.
jq
ripgrep
shellcheck
EOF

cat >"$TEST_MACHINES_REPO/machines/source/homebrew/casks.txt" <<'EOF'
# Generated by mac-sync. Do not edit.
iterm2
rectangle
visual-studio-code
EOF

cat >"$TEST_MACHINES_REPO/machines/source/homebrew/Brewfile" <<'EOF'
# Generated by mac-sync. Do not edit.
tap "homebrew/cask"
tap "homebrew/services"
brew "jq"
brew "ripgrep"
brew "shellcheck"
cask "iterm2"
cask "rectangle"
cask "visual-studio-code"
EOF

run_mac_sync diff restore --from source
assert_stdout_contains "Homebrew packages differ from the source snapshot."
assert_stdout_contains "  brew update"
assert_stdout_contains "  brew tap homebrew/services"
assert_stdout_contains "  brew install shellcheck"
assert_stdout_contains "  brew install --cask rectangle visual-studio-code"
assert_stdout_contains "  brew upgrade jq"
assert_stdout_contains "  brew upgrade --cask iterm2"

run_mac_sync match restore --from source
assert_stdout_lacks "Homebrew packages differ"
assert_stdout_lacks "  brew update"

run_mac_sync diff packages diff --from source
assert_stdout_contains "Homebrew packages differ from the source snapshot."
assert_stdout_contains "  brew install shellcheck"

run_mac_sync diff packages list --from source
assert_stdout_contains "$TEST_MACHINES_REPO/machines/source/homebrew/Brewfile"
assert_stdout_contains 'brew "shellcheck"'

run_mac_sync diff packages install --from source --formulae-only
grep -F 'bundle install --file=' "$BREW_BUNDLE_LOG" >/dev/null \
  || fail "brew bundle install was not called"
