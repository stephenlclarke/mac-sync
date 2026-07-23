#!/usr/bin/env bash

set -euo pipefail

MODE="run"
if [[ "$#" -gt 0 ]]; then
  MODE="$1"
fi
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacSync"
BUNDLE_ID="tools.xyzzy.mac-sync"
APP_BUNDLE="$ROOT_DIR/dist/mac-sync/MacSync.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

make -C "$ROOT_DIR" app-debug

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
  sleep 1
  # The development bundle is not an installation. Keep it out of Launchpad so
  # the installed copy in /Applications remains the only user-facing app.
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
  *)
    printf 'usage: %s [run|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
    exit 2
    ;;
esac
