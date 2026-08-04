#!/usr/bin/env bash
# Build the MacSyncCore DocC site for local preview or the shared Pages collection.

set -euo pipefail

if (( $# != 2 )); then
    printf 'usage: %s OUTPUT_PATH HOSTING_BASE_PATH\n' "$0" >&2
    exit 2
fi

output_path="$1"
hosting_base_path="$2"
scratch_path="${DOCS_SCRATCH_PATH:-.build/docc}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_reference="${DOCS_SOURCE_REFERENCE:-${GITHUB_SHA:-main}}"
project_icon_path="$repository_root/docs/images/mac-sync-icon.png"
project_icon_url="/$hosting_base_path/theme/project-icon.png"

arguments=(
    --disable-automatic-resolution
    --scratch-path "$scratch_path"
    --allow-writing-to-directory "$output_path"
    generate-documentation
    --target MacSyncCore
    --output-path "$output_path"
    --disable-indexing
    --transform-for-static-hosting
    --hosting-base-path "$hosting_base_path"
    --source-service github
    --source-service-base-url "https://github.com/stephenlclarke/mac-sync/blob/$source_reference"
    --checkout-path "$repository_root"
)

cd "$repository_root"
swift package "${arguments[@]}"

mkdir -p "$output_path/theme"
sips -Z 192 "$project_icon_path" --out "$output_path/theme/project-icon.png" >/dev/null

stylesheets=("$output_path"/css/documentation-topic.*.css)
if [[ ! -e "${stylesheets[0]}" ]]; then
    printf 'Unable to find the generated DocC topic stylesheet\n' >&2
    exit 1
fi

for stylesheet in "${stylesheets[@]}"; do
    printf '\n' >> "$stylesheet"
    sed "s|__PROJECT_ICON_URL__|$project_icon_url|g" "$repository_root/docs/docc-theme.css" >> "$stylesheet"
done

printf '{}\n' > "$output_path/theme-settings.json"

cat > "$output_path/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="utf-8">
    <title>Mac Sync Documentation</title>
    <meta http-equiv="refresh" content="0; url=./documentation/macsynccore/">
  </head>
  <body>
    <p>If you are not redirected automatically, <a href="./documentation/macsynccore/">open the MacSyncCore documentation</a>.</p>
  </body>
</html>
EOF
