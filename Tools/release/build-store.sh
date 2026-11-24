#!/usr/bin/env bash
# USAGE: build-store.sh [--signed|--export]
# Build a self-contained Xcode archive; export requires Apple Distribution signing.
# MAC_SYNC_STORE_TEAM selects the authorised Apple team for signed archives/exports.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPOSITORY_ROOT
readonly ARCHIVE="$REPOSITORY_ROOT/.build/MacSyncStore.xcarchive"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf 'usage: %s [--signed|--export]\nSet MAC_SYNC_STORE_TEAM for signing/export. Default: unsigned CI archive.\n' "$(basename "$0")"
  exit 0
fi
if [[ "$#" -gt 1 || ( "$#" == 1 && "$1" != --export && "$1" != --signed ) ]]; then
  printf 'usage: %s [--signed|--export]\n' "$(basename "$0")" >&2
  exit 2
fi
if [[ "${1:-}" == --export ]]; then
  : "${MAC_SYNC_STORE_TEAM:?Set the authorised Apple team; export needs a signed archive and Store distribution assets}"
  cp "$REPOSITORY_ROOT/Store/ExportOptions.plist" "$REPOSITORY_ROOT/.build/StoreExportOptions.plist"
  /usr/libexec/PlistBuddy -c "Add :teamID string $MAC_SYNC_STORE_TEAM" "$REPOSITORY_ROOT/.build/StoreExportOptions.plist"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$REPOSITORY_ROOT/.build/StoreExportOptions.plist" \
    -exportPath "$REPOSITORY_ROOT/dist/app-store" -allowProvisioningUpdates
  exit 0
fi
signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "${1:-}" == --signed ]]; then
  : "${MAC_SYNC_STORE_TEAM:?Set the authorised Apple team before creating a signed archive}"
  signing=(CODE_SIGNING_ALLOWED=YES "DEVELOPMENT_TEAM=$MAC_SYNC_STORE_TEAM")
fi
command -v xcodegen >/dev/null
python3 "$REPOSITORY_ROOT/Tools/runtime/build_runtime.py"
MAC_SYNC_SOURCE_ROOT="$REPOSITORY_ROOT" xcodegen generate \
  --spec "$REPOSITORY_ROOT/Store/project.yml" --project-root "$REPOSITORY_ROOT" \
  --project "$REPOSITORY_ROOT"
# An unsigned archive supports CI/package auditing. It is not an upload artefact.
# Xcode export must apply Apple Distribution signing and a matching profile.
xcodebuild -project "$REPOSITORY_ROOT/MacSyncStore.xcodeproj" \
  -scheme MacSyncStore -configuration Release -archivePath "$ARCHIVE" \
  -derivedDataPath "$REPOSITORY_ROOT/.build/store-derived" -jobs 2 ARCHS=arm64 \
  MARKETING_VERSION="${MAC_SYNC_VERSION:-1.3.1}" \
  CURRENT_PROJECT_VERSION="${MAC_SYNC_BUILD:-1}" "${signing[@]}" archive
