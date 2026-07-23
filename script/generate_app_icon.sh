#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/Design/MacSync-AppIcon.png"
DESTINATION_ICON="$ROOT_DIR/Sources/MacSyncApp/Resources/MacSync.icns"
WORK_DIR="$(mktemp -d /tmp/mac-sync-iconset.XXXXXX)"
ICONSET_DIR="$WORK_DIR/MacSync.iconset"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_ICON" ]]; then
  printf 'Missing app icon source: %s\n' "$SOURCE_ICON" >&2
  exit 2
fi

mkdir -p "$ICONSET_DIR"

render_icon() {
  local size="$1"
  local filename="$2"

  /usr/bin/sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$DESTINATION_ICON"
