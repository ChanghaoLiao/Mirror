#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MIRROR_OUTPUT="${MIRROR_DIST_DIR:-$PWD/dist}"
MIRROR_BUILD="${MIRROR_BUILD_PATH:-$PWD/.build}"
MIRROR_IDENTITY="${MIRROR_SIGNING_IDENTITY:--}"
MIRROR_RELEASE="${MIRROR_RELEASE:-0}"

fail() { printf 'Mirror build: %s\n' "$*" >&2; exit 1; }

case "$MIRROR_RELEASE" in
  0|1) ;;
  *) fail 'MIRROR_RELEASE must be 0 (local preview) or 1 (Developer ID release).' ;;
esac
if [ "$MIRROR_RELEASE" = 1 ] && [ "$MIRROR_IDENTITY" = - ]; then
  fail 'A release requires MIRROR_SIGNING_IDENTITY for an installed Developer ID Application certificate. Ad-hoc signing cannot preserve identity across builds.'
fi

mkdir -p "$MIRROR_OUTPUT"
MIRROR_OUTPUT="$(cd "$MIRROR_OUTPUT" && pwd -P)"
APP="$MIRROR_OUTPUT/Mirror.app"

require_stopped_target() {
  local running
  # Read-only process metadata; no window access or Accessibility permission.
  if ! running="$(osascript -l JavaScript - "$APP" <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');
function run(argv) {
    const target = ObjC.unwrap($(argv[0]).stringByStandardizingPath.stringByResolvingSymlinksInPath);
    const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
    for (let i = 0; i < apps.count; i++) {
        const url = apps.objectAtIndex(i).bundleURL;
        if (url && !url.isNil() && ObjC.unwrap(url.path.stringByStandardizingPath.stringByResolvingSymlinksInPath) === target) {
            return 'true';
        }
    }
    return 'false';
}
JXA
)"; then
    fail 'Could not check whether the target app is running. No application was replaced.'
  fi
  case "$running" in
    false) ;;
    true) fail "Refusing to replace running $APP. Quit Mirror normally, or set MIRROR_DIST_DIR to a separate build directory." ;;
    *) fail 'Unexpected process-check result. No application was replaced.' ;;
  esac
}

require_stopped_target
mkdir -p "$MIRROR_BUILD"
MIRROR_BUILD="$(cd "$MIRROR_BUILD" && pwd -P)"
bash scripts/swift.sh build --scratch-path "$MIRROR_BUILD" -c release -Xswiftc -warnings-as-errors
mkdir -p "$PWD/.build"
STAGING_ROOT="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGING="$STAGING_ROOT/Mirror.app"
mkdir -p "$STAGING/Contents/MacOS"
cp "$MIRROR_BUILD/release/Mirror" "$STAGING/Contents/MacOS/Mirror"
cp scripts/Info.plist "$STAGING/Contents/Info.plist"
if [ -d "$MIRROR_BUILD/release/Mirror_Mirror.bundle" ]; then
  mkdir -p "$STAGING/Contents/Resources"
  ditto "$MIRROR_BUILD/release/Mirror_Mirror.bundle" "$STAGING/Contents/Resources/Mirror_Mirror.bundle"
fi
SIGNING_OPTIONS=(--force --sign "$MIRROR_IDENTITY" --identifier local.mirror.companion)
if [ "$MIRROR_RELEASE" = 1 ]; then
  SIGNING_OPTIONS+=(--options runtime --timestamp)
fi
# Build the distributable away from Finder's live bundle annotations.
for attempt in 1 2 3; do
  xattr -cr "$STAGING"
  if codesign "${SIGNING_OPTIONS[@]}" "$STAGING" && codesign --verify --strict "$STAGING"; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then exit 1; fi
done
if [ "$MIRROR_RELEASE" = 1 ]; then
  # Verify the actual signed certificate, not its configurable display name.
  codesign --verify --strict --test-requirement \
    'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$STAGING" \
    || fail 'The signed app does not have a valid Apple Developer ID Application signature.'
fi
# A developer may have launched the previous app while compilation was running.
require_stopped_target
ditto --norsrc -c -k --keepParent "$STAGING" "$MIRROR_OUTPUT/Mirror.zip"
ditto --norsrc "$STAGING" "$APP"
xattr -cr "$APP"
printf 'Built %s\n' "$APP"
if [ "$MIRROR_IDENTITY" = - ]; then
  printf 'Local preview: ad-hoc signed. Changed builds may need macOS permission again.\n'
fi
if [ "$MIRROR_RELEASE" = 1 ]; then
  printf 'Developer ID signature verified. Notarization is a separate release step.\n'
fi
