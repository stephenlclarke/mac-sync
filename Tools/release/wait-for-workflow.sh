#!/bin/bash

set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 4 ]]; then
  printf 'usage: %s WORKFLOW COMMIT [ATTEMPTS] [INTERVAL_SECONDS]\n' "$0" >&2
  exit 2
fi

: "${GH_REPO:?GH_REPO is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

workflow="$1"
commit="$2"
attempts="${3:-80}"
interval="${4:-30}"

for ((attempt = 1; attempt <= attempts; attempt += 1)); do
  runs="$(
    gh run list \
      --repo "$GH_REPO" \
      --workflow "$workflow" \
      --commit "$commit" \
      --limit 20 \
      --json conclusion,createdAt,status,url
  )"
  latest="$(jq -c 'sort_by(.createdAt) | last // empty' <<<"$runs")"
  if [[ -n "$latest" ]]; then
    status="$(jq -r '.status' <<<"$latest")"
    conclusion="$(jq -r '.conclusion // ""' <<<"$latest")"
    url="$(jq -r '.url' <<<"$latest")"
    if [[ "$status" == "completed" && "$conclusion" == "success" ]]; then
      printf '%s\n' "$url"
      exit 0
    fi
    if [[ "$status" == "completed" ]]; then
      printf '%s failed for %s with conclusion %s: %s\n' "$workflow" "$commit" "$conclusion" "$url" >&2
      exit 1
    fi
    printf 'Waiting for %s on %s (%s, attempt %s/%s)\n' "$workflow" "$commit" "$status" "$attempt" "$attempts" >&2
  else
    printf 'Waiting for %s to start on %s (attempt %s/%s)\n' "$workflow" "$commit" "$attempt" "$attempts" >&2
  fi
  sleep "$interval"
done

printf 'Timed out waiting for %s on %s\n' "$workflow" "$commit" >&2
exit 1
