#!/usr/bin/env bash
# USAGE: install-runtime.sh BUILT_APP BUILT_RUNTIME_DIRECTORY
set -euo pipefail
if [[ "$#" != 2 || "$1" != /*.app ]]; then
  printf 'usage: %s BUILT_APP BUILT_RUNTIME_DIRECTORY\n' "$0" >&2
  exit 2
fi
app="$1"
runtime="$2"
test -f "$runtime/build-info.json"
test "$(/usr/libexec/PlistBuddy -c 'Print :MacSyncDistribution' "$app/Contents/Info.plist")" = app-store
destination="$app/Contents/Resources/Runtime"
if [[ -e "$destination" ]]; then
  # Replace only our generated payload; never merge obsolete source/tool versions.
  test ! -L "$destination"
  test -f "$destination/build-info.json"
  /bin/rm -r "$destination"
fi
/bin/mkdir -p "$app/Contents/Helpers" "$destination"
for executable in git rsync age age-keygen gtar; do
  /bin/cp "$runtime/bin/$executable" "$app/Contents/Helpers/$executable"
done
for executable in git-remote-http git-remote-https git-credential-osxkeychain; do
  /bin/cp "$runtime/libexec/git-core/$executable" "$app/Contents/Helpers/$executable"
done
for directory in Notices Sources share; do
  /usr/bin/ditto "$runtime/$directory" "$destination/$directory"
done
/bin/cp "$runtime/build-info.json" "$runtime/sources.json" "$destination/"
