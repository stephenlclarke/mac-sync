#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Tools/release/update-protected-tap.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-tap-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/Formula"
cp "$ROOT/Tools/release/mac-sync.rb.in" "$TEST_DIR/Formula/mac-sync.rb"
cd "$TEST_DIR"
export GH_TOKEN='test-only'
BLOB="$(git hash-object Formula/mac-sync.rb)"

# Simulate GitHub without using credentials, network access or real branches.
gh() {
  printf '%s\n' "$*" >> "$TEST_DIR/calls"
  case "$*" in
    'api repos/stephenlclarke/homebrew-tap/contents/Formula/mac-sync.rb?ref=main --jq .sha')
      if [[ "$MODE" == existing || ( -f "$TEST_DIR/created" && "$MODE" != timeout ) ]]; then
        printf '%s\n' "$BLOB"
      else
        printf 'old-blob\n'
      fi ;;
    'api repos/stephenlclarke/homebrew-tap/git/ref/heads/release/'*)
      [[ "$MODE" == reuse || "$MODE" == mismatch ]] ;;
    'api repos/stephenlclarke/homebrew-tap/git/ref/heads/main --jq .object.sha')
      printf '%040d\n' 1 ;;
    'api --method POST repos/stephenlclarke/homebrew-tap/git/refs '*) ;;
    'api graphql --input -')
      jq -e --arg content "$(base64 < Formula/mac-sync.rb | tr -d '\r\n')" \
        '.variables.input.fileChanges.additions[0].contents == $content and
         .variables.input.branch.repositoryNameWithOwner == "stephenlclarke/homebrew-tap"' >/dev/null ;;
    'api repos/stephenlclarke/homebrew-tap/contents/Formula/mac-sync.rb?ref=release/'*)
      if [[ "$MODE" == mismatch ]]; then printf 'wrong-blob\n'; else printf '%s\n' "$BLOB"; fi ;;
    'pr list '*)
      if [[ "$MODE" == reuse ]]; then
        touch "$TEST_DIR/created"
        printf 'https://example.invalid/pr/1\n'
      fi ;;
    'pr create '*)
      touch "$TEST_DIR/created"
      printf 'https://example.invalid/pr/1\n' ;;
    *) printf 'Unexpected GitHub request: %s\n' "$*" >&2; return 1 ;;
  esac
}

# Do not delay deterministic timeout coverage.
sleep() { :; }

for MODE in existing create reuse mismatch timeout; do
  : > "$TEST_DIR/calls"
  rm -f "$TEST_DIR/created"
  if [[ "$MODE" == mismatch || "$MODE" == timeout ]]; then
    if (main mac-sync.rb Stable) > "$TEST_DIR/output" 2>&1; then
      printf 'Expected %s to fail.\n' "$MODE" >&2
      exit 1
    fi
  else
    (main mac-sync.rb Stable) > "$TEST_DIR/output" 2>&1
  fi
  if [[ "$MODE" == existing || "$MODE" == reuse || "$MODE" == mismatch ]]; then
    if grep -Eq 'graphql|pr create' "$TEST_DIR/calls"; then exit 1; fi
  fi
  printf 'PASS protected tap: %s\n' "$MODE"
done
main --help >/dev/null
if (main unrelated.rb Stable) >/dev/null 2>&1; then exit 1; fi
