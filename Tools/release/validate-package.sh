#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 5 ]]; then
  printf 'usage: %s ARCHIVE VERSION BUILD LANE COMMIT\n' "$0" >&2
  exit 2
fi

archive="$1"
expected_version="$2"
expected_build="$3"
expected_lane="$4"
expected_commit="$5"
checksum_file="${archive}.sha256"

test -f "$archive"
test -f "$checksum_file"

archive_directory="$(cd "$(dirname "$archive")" && pwd)"
(
  cd "$archive_directory"
  shasum -a 256 -c "$(basename "$checksum_file")"
)

while IFS= read -r member; do
  if [[ "$member" = /* || "$member" == *"../"* || "$member" != mac-sync/* ]]; then
    printf 'unsafe or unexpected archive member: %s\n' "$member" >&2
    exit 1
  fi
done < <(tar -tzf "$archive")

package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT
tar -xzf "$archive" -C "$package_root"
payload="$package_root/mac-sync"
app="$payload/MacSync.app"

test -x "$payload/bin/mac-sync"
test -x "$payload/bin/mac-spinner"
test -x "$app/Contents/MacOS/MacSync"
test -x "$app/Contents/Resources/mac-sync"
test -f "$app/Contents/Resources/MacSync.icns"
test -f "$payload/resources/build-info.json"

"$payload/bin/mac-sync" --help >/dev/null
"$payload/bin/mac-spinner" --message package-smoke --pending >/dev/null
plutil -lint "$app/Contents/Info.plist"

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
[[ "$actual_version" == "$expected_version" ]]
[[ "$actual_build" == "$expected_build" ]]

python3 - "$payload/resources/build-info.json" "$expected_version" "$expected_build" "$expected_lane" "$expected_commit" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "version": sys.argv[2],
    "build": sys.argv[3],
    "lane": sys.argv[4],
    "commit": sys.argv[5],
    "buildType": "release",
    "source": "stephenlclarke/mac-sync",
}
for key, value in expected.items():
    if metadata.get(key) != value:
        raise SystemExit(f"unexpected {key}: {metadata.get(key)!r} != {value!r}")
PY

if codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
  printf 'Package validation passed; app bundle has a valid code signature.\n'
else
  printf 'Package validation passed; app bundle is unsigned for Homebrew distribution.\n'
fi
