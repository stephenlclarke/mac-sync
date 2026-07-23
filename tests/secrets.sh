#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

readonly SCRIPT_PATH="${1:-$(pwd)/.build/debug/mac-sync}"
readonly SCRIPT_RUNNER="${MAC_SYNC_TEST_RUNNER:-}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-secrets.XXXXXX")"
readonly TMP_ROOT
readonly TEST_REPO="${TMP_ROOT}/repo"
readonly TEST_MACHINES_REPO="${TMP_ROOT}/machines-repo"
readonly TEST_HOME="${TMP_ROOT}/home"
readonly FAKE_BIN="${TMP_ROOT}/fake-bin"
readonly FAKE_KEYCHAIN="${TMP_ROOT}/keychain"
readonly STDOUT_FILE="${TMP_ROOT}/stdout"
readonly STDERR_FILE="${TMP_ROOT}/stderr"

trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

fail() {
  printf 'secrets test failed: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  grep -F "$pattern" "$file" >/dev/null || fail "missing pattern in $file: $pattern"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "$file" ]] || fail "missing file: $file"
  ! grep -F "$pattern" "$file" >/dev/null || fail "unexpected pattern in $file: $pattern"
}

assert_file_contents() {
  local file="$1"
  local expected="$2"
  local actual

  [[ -f "$file" ]] || fail "missing file: $file"
  actual="$(cat "$file")"
  [[ "$actual" == "$expected" ]] || fail "unexpected contents in $file: $actual"
}

assert_stdout_contains() {
  local pattern="$1"

  grep -F "$pattern" "$STDOUT_FILE" >/dev/null || fail "missing stdout pattern: $pattern"
}

run_mac_sync() {
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    AGE_KEYGEN_FAIL="${AGE_KEYGEN_FAIL:-0}" \
    AGE_DECRYPT_FAIL="${AGE_DECRYPT_FAIL:-0}" \
    KEYCHAIN_FAKE_DIR="$FAKE_KEYCHAIN" \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  else
    HOME="$TEST_HOME" \
    MAC_SYNC_REPO="$TEST_REPO" \
    MAC_SYNC_MACHINES_REPO="$TEST_MACHINES_REPO" \
    MAC_SYNC_MACHINE=target \
    MAC_SYNC_DYNAMIC_REFS=0 \
    MAC_SYNC_HOMEBREW=0 \
    AGE_KEYGEN_FAIL="${AGE_KEYGEN_FAIL:-0}" \
    AGE_DECRYPT_FAIL="${AGE_DECRYPT_FAIL:-0}" \
    KEYCHAIN_FAKE_DIR="$FAKE_KEYCHAIN" \
    PATH="${FAKE_BIN}:$PATH" \
    SCRIPT_COLOUR=off \
      "$SCRIPT_PATH" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  fi
}

run_mac_sync_expect_failure() {
  set +e
  run_mac_sync "$@"
  local status="$?"
  set -e
  [[ "$status" -ne 0 ]] || fail "expected command to fail: $*"
}

mkdir -p \
  "$FAKE_BIN" \
  "$FAKE_KEYCHAIN" \
  "$TEST_REPO/config" \
  "$TEST_MACHINES_REPO/machines/source/home" \
  "$TEST_HOME/.ssh" \
  "$TEST_HOME/.secrets"

cat >"$FAKE_BIN/age-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${AGE_KEYGEN_FAIL:-0}" == "1" ]]; then
  printf '%s\n' 'forced age-keygen failure' >&2
  exit 1
fi

case "$1" in
  -o)
    [[ ! -e "$2" ]] || {
      printf 'refusing to overwrite %s\n' "$2" >&2
      exit 1
    }
    {
      printf '%s\n' '# public key: age1fakepublicrecipient'
      printf '%s\n' 'AGE-SECRET-KEY-FAKEIDENTITY'
    } >"$2"
    ;;
  -y)
    printf '%s\n' 'age1fakepublicrecipient'
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"$FAKE_BIN/age" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-d" ]]; then
  if [[ "${AGE_DECRYPT_FAIL:-0}" == "1" ]]; then
    printf '%s\n' 'forced age decryption failure' >&2
    exit 42
  fi
  archive=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -d)
        shift
        ;;
      -i)
        shift 2
        ;;
      *)
        archive="$1"
        shift
        ;;
    esac
  done
  cat "$archive"
  exit 0
fi

out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -R)
      shift 2
      ;;
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$out" ]] || exit 2
[[ ! -e "$out" ]] || {
  printf 'refusing to overwrite %s\n' "$out" >&2
  exit 1
}
cat >"$out"
EOF

cat >"$FAKE_BIN/gtar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=()
for arg in "$@"; do
  case "$arg" in
    --ignore-failed-read)
      ;;
    --sort=*|--warning=*)
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

exec tar "${args[@]}"
EOF

cat >"$FAKE_BIN/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

store="${KEYCHAIN_FAKE_DIR:?KEYCHAIN_FAKE_DIR is not set}"
command_name="$1"
shift
account=""
service=""
password=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -a)
      account="$2"
      shift 2
      ;;
    -s)
      service="$2"
      shift 2
      ;;
    -w)
      if [[ "$#" -gt 1 && "${2:0:1}" != "-" ]]; then
        password="$2"
        shift 2
      else
        shift
      fi
      ;;
    -U)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

key="${account}__${service}"
key="${key//[^A-Za-z0-9_.-]/_}"
path="${store}/${key}"

case "$command_name" in
  add-generic-password)
    printf '%s\n' "$password" >"$path"
    ;;
  find-generic-password)
    [[ -f "$path" ]] || exit 44
    cat "$path"
    ;;
  *)
    exit 2
    ;;
esac
EOF

chmod +x "$FAKE_BIN/age-keygen" "$FAKE_BIN/age" "$FAKE_BIN/gtar" "$FAKE_BIN/security"
git -C "$TEST_REPO" init -b main >/dev/null
git -C "$TEST_REPO" config user.name "mac-sync test"
git -C "$TEST_REPO" config user.email "mac-sync@example.invalid"
git -C "$TEST_MACHINES_REPO" init -b main >/dev/null
git -C "$TEST_MACHINES_REPO" config user.name "mac-sync test"
git -C "$TEST_MACHINES_REPO" config user.email "mac-sync@example.invalid"

cat >"$TEST_REPO/config/sync-paths.txt" <<'EOF'
.bashrc
EOF

cat >"$TEST_REPO/config/excludes.txt" <<'EOF'
.DS_Store
EOF

printf 'home bash\n' >"$TEST_HOME/.bashrc"
printf 'Host example\n' >"$TEST_HOME/.ssh/config"
printf 'private-key\n' >"$TEST_HOME/.ssh/id_ed25519"
printf 'token-value\n' >"$TEST_HOME/.secrets/token"

run_mac_sync_expect_failure secrets test
assert_file_contains "$STDERR_FILE" "missing Keychain age identity"

AGE_KEYGEN_FAIL=1 run_mac_sync_expect_failure secrets init
assert_file_contains "$STDERR_FILE" "forced age-keygen failure"
assert_file_not_contains "$STDERR_FILE" "unbound variable"

run_mac_sync secrets init
assert_file_contains "$TEST_REPO/config/secret-paths.txt" ".ssh"
assert_file_contains "$TEST_REPO/config/secret-paths.txt" ".secrets"
assert_file_contains "$TEST_REPO/config/age-recipients.txt" "age1fakepublicrecipient"

run_mac_sync secrets sync
assert_file_contains "$TEST_MACHINES_REPO/machines/target/secrets/included-paths.txt" ".ssh"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/secrets/included-paths.txt" ".secrets"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/secrets/recipients.txt" "age1fakepublicrecipient"
[[ -f "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age" ]] || fail "missing encrypted archive"

archive_checksum="$(cksum "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age")"
run_mac_sync secrets sync
assert_stdout_contains "encrypted secrets snapshot unchanged"
[[ "$(cksum "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age")" == "$archive_checksum" ]] \
  || fail "unchanged secrets sync rewrote the archive"

# Adding a trusted Mac must re-encrypt the existing archive even if the secret
# files themselves have not changed. The public recipient manifest makes this
# deterministic for both new and legacy snapshots.
printf '%s\n' 'age1anothertrustedrecipient' >>"$TEST_REPO/config/age-recipients.txt"
run_mac_sync secrets sync
assert_stdout_contains "updated encrypted secrets snapshot"
assert_file_contains "$TEST_MACHINES_REPO/machines/target/secrets/recipients.txt" "age1anothertrustedrecipient"
archive_checksum="$(cksum "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age")"

printf 'changed-token-value\n' >"$TEST_HOME/.secrets/token"
AGE_DECRYPT_FAIL=1 run_mac_sync_expect_failure secrets sync
assert_file_contains "$STDERR_FILE" "existing encrypted secrets snapshot cannot be decrypted; refusing to replace it"
[[ "$(cksum "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age")" == "$archive_checksum" ]] \
  || fail "undecryptable secrets snapshot was replaced"
printf 'token-value\n' >"$TEST_HOME/.secrets/token"

run_mac_sync secrets list
assert_stdout_contains ".ssh/config"
assert_stdout_contains ".ssh/id_ed25519"
assert_stdout_contains ".secrets/token"

run_mac_sync_expect_failure secrets restore
assert_file_contains "$STDERR_FILE" "secret restore would overwrite existing files"

rm -rf "$TEST_HOME/.ssh" "$TEST_HOME/.secrets"
run_mac_sync secrets restore
assert_file_not_contains "$STDOUT_FILE" "$TEST_MACHINES_REPO/machines/target/secrets/secrets.tar.gz.age"
assert_file_contents "$TEST_HOME/.ssh/config" "Host example"
assert_file_contents "$TEST_HOME/.ssh/id_ed25519" "private-key"
assert_file_contents "$TEST_HOME/.secrets/token" "token-value"

run_mac_sync secrets test
assert_stdout_contains "Keychain identity has a configured public recipient."
assert_stdout_contains "Current machine encrypted secrets snapshot can be decrypted."

run_mac_sync restore
assert_stdout_contains "Encrypted secrets snapshot found:"
assert_stdout_contains "mac-sync secrets list --from target"

# The one-repository layout keeps all trusted recipients in a shared registry,
# rather than leaving a secret archive readable only by its source machine.
TEST_DATA_REPO="${TMP_ROOT}/mac-sync-data"
mkdir -p "$TEST_DATA_REPO/machines/target/config"
git -C "$TEST_DATA_REPO" init -b main >/dev/null
git -C "$TEST_DATA_REPO" config user.name "mac-sync test"
git -C "$TEST_DATA_REPO" config user.email "mac-sync@example.invalid"

run_single_repo_mac_sync() {
  local command=("$SCRIPT_PATH" "$@")
  if [[ -n "$SCRIPT_RUNNER" ]]; then
    command=("$SCRIPT_RUNNER" "$SCRIPT_PATH" "$@")
  fi
  HOME="$TEST_HOME" \
  MAC_SYNC_MACHINES_REPO="$TEST_DATA_REPO" \
  MAC_SYNC_MACHINE=target \
  MAC_SYNC_DYNAMIC_REFS=0 \
  MAC_SYNC_HOMEBREW=0 \
  MAC_SYNC_GITHUB_REPOS=0 \
  KEYCHAIN_FAKE_DIR="$FAKE_KEYCHAIN" \
  PATH="${FAKE_BIN}:$PATH" \
  SCRIPT_COLOUR=off \
    "${command[@]}" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

run_single_repo_mac_sync secrets init
assert_file_contains "$TEST_DATA_REPO/machines/_shared/config/age-recipients.txt" "age1fakepublicrecipient"
assert_file_contains "$TEST_DATA_REPO/machines/target/config/secret-paths.txt" ".ssh"
git -C "$TEST_DATA_REPO" show --format= --name-only HEAD >"${TMP_ROOT}/single-repo-commit-paths"
assert_file_contains "${TMP_ROOT}/single-repo-commit-paths" "machines/_shared/config/age-recipients.txt"
