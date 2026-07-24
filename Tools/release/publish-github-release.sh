#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 8 ]]; then
  printf 'usage: %s MODE TAG COMMIT TITLE NOTES ARCHIVE CHECKSUM LATEST\n' "$0" >&2
  exit 2
fi

: "${GH_REPO:?GH_REPO is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

mode="$1"
tag="$2"
commit="$3"
title="$4"
notes="$5"
archive="$6"
checksum="$7"
latest="$8"

[[ "$GH_REPO" == "stephenlclarke/mac-sync" ]]
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
test -s "$notes"
test -f "$archive"
test -f "$checksum"

push_url="$(git remote get-url --push origin)"
if [[ ! "$push_url" =~ ^(https://github\.com/|git@github\.com:)stephenlclarke/mac-sync(\.git)?$ ]]; then
  printf 'refusing release publication through unexpected origin: %s\n' "$push_url" >&2
  exit 1
fi

release_exists() {
  gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1
}

verify_asset() {
  local path="$1"
  local name
  local expected
  local published
  name="$(basename "$path")"
  expected="$(shasum -a 256 "$path" | awk '{print $1}')"
  published="$(
    gh release view "$tag" \
      --repo "$GH_REPO" \
      --json assets \
      --jq ".assets[] | select(.name == \"${name}\") | .digest"
  )"
  if [[ "$published" != "sha256:${expected}" ]]; then
    printf 'published digest mismatch for %s: %s\n' "$name" "${published:-missing}" >&2
    exit 1
  fi
}

create_release() {
  local release_args=(
    release create "$tag"
    --repo "$GH_REPO"
    --verify-tag
    --target "$commit"
    --title "$title"
    --notes-file "$notes"
  )
  if [[ "$mode" != "stable" ]]; then
    release_args+=(--prerelease)
  fi
  if [[ "$latest" == "true" ]]; then
    release_args+=(--latest)
  fi
  release_args+=("$archive" "$checksum")
  gh "${release_args[@]}"
}

case "$mode" in
  stable)
    if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf 'stable release tag must be semantic: %s\n' "$tag" >&2
      exit 1
    fi
    remote_commit="$(git ls-remote origin "refs/tags/${tag}" | awk '{print $1}')"
    if [[ "$remote_commit" != "$commit" ]]; then
      printf 'stable tag %s resolves to %s, expected %s\n' "$tag" "${remote_commit:-missing}" "$commit" >&2
      exit 1
    fi
    if release_exists; then
      verify_asset "$archive"
      verify_asset "$checksum"
      printf 'Immutable release %s already exists with matching assets.\n' "$tag"
      exit 0
    fi
    create_release
    ;;
  current-stage)
    if [[ "$tag" != "current" ]]; then
      printf 'mutable publication is restricted to the current tag\n' >&2
      exit 1
    fi
    if ! git ls-remote --exit-code origin "refs/tags/${tag}" >/dev/null 2>&1; then
      git tag "$tag" "$commit"
      git push origin "refs/tags/${tag}"
    fi
    if release_exists; then
      gh release upload "$tag" --repo "$GH_REPO" "$archive" "$checksum" --clobber
    else
      create_release
    fi
    verify_asset "$archive"
    verify_asset "$checksum"
    ;;
  current-finalize)
    if [[ "$tag" != "current" ]]; then
      printf 'mutable publication is restricted to the current tag\n' >&2
      exit 1
    fi
    git tag --force "$tag" "$commit"
    git push --force origin "refs/tags/${tag}"
    if release_exists; then
      gh release delete "$tag" --repo "$GH_REPO" --yes
    fi
    create_release
    verify_asset "$archive"
    verify_asset "$checksum"
    ;;
  *)
    printf 'unsupported publication mode: %s\n' "$mode" >&2
    exit 2
    ;;
esac
