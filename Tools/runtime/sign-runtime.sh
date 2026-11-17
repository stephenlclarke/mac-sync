#!/usr/bin/env bash
# USAGE: sign-runtime.sh APP SIGNING_IDENTITY CHILD_ENTITLEMENTS
set -euo pipefail
if [[ "$#" != 3 || "$1" != /*.app ]]; then
  printf 'usage: %s APP IDENTITY ENTITLEMENTS\n' "$0" >&2
  exit 2
fi
app="$1"
identity="$2"
entitlements="$3"
test -f "$app/Contents/Resources/Runtime/build-info.json"
while IFS= read -r -d '' executable; do
  if /usr/bin/file -b "$executable" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign --force --options runtime --sign "$identity" \
      --entitlements "$entitlements" "$executable"
  fi
done < <(/usr/bin/find "$app/Contents/Helpers" -type f -print0)
