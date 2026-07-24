#!/bin/bash

set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

[[ "$GH_REPO" == "stephenlclarke/mac-sync" ]]

latest_stable="$(
  gh api "repos/${GH_REPO}/releases/latest" --jq '.tag_name' 2>/dev/null || true
)"

while IFS=$'\t' read -r release_id release_tag; do
  if [[ "$release_tag" == "current" || -n "$latest_stable" && "$release_tag" == "$latest_stable" ]]; then
    printf 'Retaining assets for %s\n' "$release_tag"
    continue
  fi

  while IFS=$'\t' read -r asset_id asset_name; do
    [[ -n "$asset_id" ]] || continue
    printf 'Removing superseded asset %s from release %s\n' "$asset_name" "$release_tag"
    gh api --method DELETE "repos/${GH_REPO}/releases/assets/${asset_id}"
  done < <(
    gh api \
      --paginate \
      "repos/${GH_REPO}/releases/${release_id}/assets" \
      --jq '.[] | [.id, .name] | @tsv'
  )
done < <(
  gh api \
    --paginate \
    "repos/${GH_REPO}/releases" \
    --jq '.[] | [.id, .tag_name] | @tsv'
)
