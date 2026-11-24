#!/usr/bin/env bash
# USAGE: update-protected-tap.sh FORMULA LABEL
# Run in the tap checkout with GH_TOKEN set. Open a signed formula PR, then
# wait up to 45 minutes for an authorised maintainer to merge it after checks.
set -euo pipefail

# Publish one formula without bypassing protected-branch reviews or checks.
main() {
  if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
    printf 'Usage: %s FORMULA LABEL\nRequires GH_TOKEN; waits up to 45 minutes for PR merge.\n' "${0##*/}"
    return 0
  fi
  if [[ "$#" != 2 || ! "$1" =~ ^mac-sync(-current)?\.rb$ ]]; then
    printf 'Expected FORMULA (mac-sync.rb or mac-sync-current.rb) and LABEL.\n' >&2
    return 2
  fi
  : "${GH_TOKEN:?GH_TOKEN is required}"
  local repo='stephenlclarke/homebrew-tap'
  local path="Formula/$1" label="$2" blob branch head existing url attempt
  test -s "$path"
  blob="$(git hash-object "$path")"
  existing="$(gh api "repos/$repo/contents/$path?ref=main" --jq .sha)"
  if [[ "$existing" == "$blob" ]]; then
    printf '%s already points at the requested asset.\n' "$path"
    return 0
  fi
  branch="release/mac-sync-${blob:0:12}"
  if ! gh api "repos/$repo/git/ref/heads/$branch" >/dev/null 2>&1; then
    head="$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)"
    gh api --method POST "repos/$repo/git/refs" \
      -f "ref=refs/heads/$branch" -f "sha=$head" >/dev/null
    jq -n --arg repo "$repo" --arg branch "$branch" --arg head "$head" \
      --arg path "$path" --arg contents "$(base64 < "$path" | tr -d '\r\n')" \
      --arg title "chore(mac-sync): update $label formula" \
      '{query: "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid } } }",
        variables: {input: {branch: {repositoryNameWithOwner: $repo, branchName: $branch},
          expectedHeadOid: $head, message: {headline: $title},
          fileChanges: {additions: [{path: $path, contents: $contents}]}}}}' |
      gh api graphql --input - >/dev/null
  fi
  # A prior interrupted run can leave a branch without its formula commit.
  existing="$(gh api "repos/$repo/contents/$path?ref=$branch" --jq .sha)"
  if [[ "$existing" != "$blob" ]]; then
    printf 'Release branch has unexpected formula content; inspect %s.\n' "$branch" >&2
    return 1
  fi
  url="$(gh pr list --repo "$repo" --head "$branch" --state open --json url --jq '.[0].url // empty')"
  if [[ -z "$url" ]]; then
    url="$(gh pr create --repo "$repo" --base main --head "$branch" \
      --title "chore(mac-sync): update $label formula" \
      --body 'Update the signed release archive and checksum. Merge only after all required checks pass. The release job waits for the exact formula on main.')"
  fi
  printf 'Awaiting reviewed formula merge: %s\n' "$url"
  for ((attempt = 1; attempt <= 180; attempt += 1)); do
    existing="$(gh api "repos/$repo/contents/$path?ref=main" --jq .sha)"
    if [[ "$existing" == "$blob" ]]; then
      printf 'Verified published formula: %s\n' "$path"
      return 0
    fi
    sleep 15
  done
  printf 'Timed out waiting for formula merge: %s\n' "$url" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
