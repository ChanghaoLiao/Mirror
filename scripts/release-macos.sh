#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
OUTPUT="${MIRROR_RELEASE_DIR:-$PWD/.build/release-$VERSION}"
IDENTITY="${MIRROR_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${MIRROR_NOTARY_PROFILE:-}"

fail() { printf 'Mirror release: %s\n' "$*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Info.plist must contain a semantic version.'
[ -n "$IDENTITY" ] || fail 'Set MIRROR_SIGNING_IDENTITY to a Developer ID Application identity.'
[ -n "$NOTARY_PROFILE" ] || fail 'Set MIRROR_NOTARY_PROFILE to an existing notarytool keychain profile.'

MIRROR_RELEASE=1 \
MIRROR_SIGNING_IDENTITY="$IDENTITY" \
MIRROR_BUILD_PATH="${MIRROR_BUILD_PATH:-$PWD/.build/release-build-$VERSION}" \
MIRROR_DIST_DIR="$OUTPUT" \
bash scripts/build.sh

APP="$OUTPUT/Mirror.app"
SUBMISSION="$OUTPUT/Mirror.zip"
FINAL="$OUTPUT/Mirror-$VERSION-macos-arm64.zip"

xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto --norsrc -c -k --keepParent "$APP" "$FINAL"
rm "$SUBMISSION"
(
  cd "$OUTPUT"
  shasum -a 256 "$(basename "$FINAL")" > SHA256SUMS.txt
)
printf 'Release ready: %s\n' "$FINAL"
printf 'Checksum: %s/SHA256SUMS.txt\n' "$OUTPUT"
