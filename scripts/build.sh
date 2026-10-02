#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift.sh build -c release -Xswiftc -warnings-as-errors
APP="$PWD/dist/Mirror.app"
STAGING_ROOT="$(mktemp -d "$PWD/.build/package.XXXXXX")"
STAGING="$STAGING_ROOT/Mirror.app"
mkdir -p "$STAGING/Contents/MacOS" "$PWD/dist"
cp .build/release/Mirror "$STAGING/Contents/MacOS/Mirror"
cp scripts/Info.plist "$STAGING/Contents/Info.plist"
# Build the distributable away from Finder's live bundle annotations.
for attempt in 1 2 3; do
  xattr -cr "$STAGING"
  if codesign --force --sign - --identifier local.mirror.companion "$STAGING" && codesign --verify --strict "$STAGING"; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then exit 1; fi
done
ditto --norsrc -c -k --keepParent "$STAGING" "$PWD/dist/Mirror.zip"
ditto --norsrc "$STAGING" "$APP"
xattr -cr "$APP"
printf 'Built %s\n' "$APP"
