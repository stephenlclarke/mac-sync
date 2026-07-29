#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s GITHUB_OUTPUT\n' "$0" >&2
  exit 2
fi

github_output="$1"
certificate_base64="${MAC_SYNC_DEVELOPER_ID_CERTIFICATE_P12:-}"
certificate_password="${MAC_SYNC_DEVELOPER_ID_CERTIFICATE_PASSWORD:-}"

if [[ -z "$certificate_base64" ]]; then
  {
    printf 'enabled=false\n'
    printf 'require_developer_id=0\n'
    printf 'status=unsigned\n'
  } >> "$github_output"
  exit 0
fi

if [[ -z "$certificate_password" ]]; then
  printf 'MAC_SYNC_DEVELOPER_ID_CERTIFICATE_PASSWORD is required when a certificate is configured.\n' >&2
  exit 2
fi

temporary_directory="$(mktemp -d "${RUNNER_TEMP:-/tmp}/mac-sync-signing.XXXXXX")"
certificate_path="$temporary_directory/developer-id.p12"
keychain_path="$temporary_directory/mac-sync-signing.keychain-db"
keychain_password="$(openssl rand -hex 24)"

printf '%s' "$certificate_base64" | base64 --decode > "$certificate_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" \
  -k "$keychain_path" \
  -P "$certificate_password" \
  -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path"

existing_keychains=()
while IFS= read -r existing_keychain; do
  existing_keychain="${existing_keychain#\"}"
  existing_keychain="${existing_keychain%\"}"
  [[ -n "$existing_keychain" ]] && existing_keychains+=("$existing_keychain")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
security list-keychain -d user -s "$keychain_path" "${existing_keychains[@]}"

identity="$(security find-identity -v -p codesigning "$keychain_path" | awk -F '"' '/Developer ID Application:/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
  printf 'The configured certificate does not contain a Developer ID Application signing identity.\n' >&2
  exit 1
fi

rm -f "$certificate_path"
{
  printf 'enabled=true\n'
  printf 'identity=%s\n' "$identity"
  printf 'require_developer_id=1\n'
  printf 'status=developer-id-signed\n'
} >> "$github_output"
