#!/usr/bin/env bash

set -euo pipefail
unset BASH_ENV ENV

if [[ "$#" -lt 2 ]]; then
  printf 'usage: %s coverage|test TEST_NAME...\n' "$0" >&2
  exit 2
fi

readonly MODE="$1"
shift

case "$MODE" in
  coverage | test) ;;
  *)
    printf 'unsupported shell test mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

: "${MAC_SYNC_BINARY:?MAC_SYNC_BINARY is required}"
: "${MAC_SPINNER_BINARY:?MAC_SPINNER_BINARY is required}"

if [[ "$MODE" == "coverage" ]]; then
  : "${COVERAGE_PROFILE_DIR:?COVERAGE_PROFILE_DIR is required in coverage mode}"
  mkdir -p "$COVERAGE_PROFILE_DIR"
fi

readonly JOBS="${SHELL_TEST_JOBS:-4}"
if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'SHELL_TEST_JOBS must be a positive integer: %s\n' "$JOBS" >&2
  exit 2
fi

readonly WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-sync-shell-tests.XXXXXX")"
readonly ASSIGNMENT_DIR="${WORK_ROOT}/assignments"
readonly LOG_DIR="${WORK_ROOT}/logs"
readonly STATUS_DIR="${WORK_ROOT}/status"
readonly TEST_TMP_DIR="${WORK_ROOT}/tmp"
mkdir -p "$ASSIGNMENT_DIR" "$LOG_DIR" "$STATUS_DIR" "$TEST_TMP_DIR"
trap 'rm -rf "$WORK_ROOT"' EXIT INT TERM

readonly TEST_NAMES=("$@")
worker_count="$JOBS"
if (( worker_count > ${#TEST_NAMES[@]} )); then
  worker_count="${#TEST_NAMES[@]}"
fi
readonly WORKER_COUNT="$worker_count"

for ((worker_index = 0; worker_index < WORKER_COUNT; worker_index += 1)); do
  : >"${ASSIGNMENT_DIR}/${worker_index}"
done

for ((test_index = 0; test_index < ${#TEST_NAMES[@]}; test_index += 1)); do
  test_name="${TEST_NAMES[$test_index]}"
  if [[ ! "$test_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf 'unsafe shell test name: %s\n' "$test_name" >&2
    exit 2
  fi
  printf '%s\n' "$test_name" >>"${ASSIGNMENT_DIR}/$((test_index % WORKER_COUNT))"
done

run_test() {
  local test_name="$1"
  local target="$MAC_SYNC_BINARY"
  local test_tmp="${TEST_TMP_DIR}/${test_name}"

  if [[ "$test_name" == "spinner" ]]; then
    target="$MAC_SPINNER_BINARY"
  fi

  mkdir -p "$test_tmp"
  if [[ "$MODE" == "coverage" ]]; then
    TMPDIR="${test_tmp}/" \
      LLVM_PROFILE_FILE="${COVERAGE_PROFILE_DIR}/shell-${test_name}-%p.profraw" \
      bash "tests/${test_name}.sh" "$target"
  else
    TMPDIR="${test_tmp}/" bash "tests/${test_name}.sh" "$target"
  fi
}

run_worker() {
  local assignment="$1"
  local test_name
  local result

  while IFS= read -r test_name; do
    set +e
    run_test "$test_name" >"${LOG_DIR}/${test_name}" 2>&1
    result="$?"
    set -e
    printf '%s\n' "$result" >"${STATUS_DIR}/${test_name}"
  done <"$assignment"
}

worker_pids=()
for ((worker_index = 0; worker_index < WORKER_COUNT; worker_index += 1)); do
  run_worker "${ASSIGNMENT_DIR}/${worker_index}" &
  worker_pids+=("$!")
done

for worker_pid in "${worker_pids[@]}"; do
  wait "$worker_pid"
done

failed=0
for test_name in "${TEST_NAMES[@]}"; do
  if [[ "$MODE" == "coverage" ]]; then
    printf '== coverage %s ==\n' "$test_name"
  else
    printf '== %s ==\n' "$test_name"
  fi
  if [[ -s "${LOG_DIR}/${test_name}" ]]; then
    cat "${LOG_DIR}/${test_name}"
  fi
  if [[ "$(cat "${STATUS_DIR}/${test_name}")" -ne 0 ]]; then
    failed=1
  fi
done

exit "$failed"
