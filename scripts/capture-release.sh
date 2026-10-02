#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Requires a graphical macOS session and Screen Recording permission for the launching app.
# Builds a separate documentation executable; never opens real Codex history.
OUTPUT="${1:-$PWD/.build/release-captures/images}"
mkdir -p "$OUTPUT"
bash scripts/swift.sh build -c release -Xswiftc -warnings-as-errors
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Sources/Mirror -name '*.swift' ! -name main.swift | sort)
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -I .build/release/Modules .build/release/MirrorCore.build/*.o \
  "${sources[@]}" scripts/ReleaseScreenshots.swift -o .build/release-screenshots
MIRROR_PREFS_SUITE=local.mirror.release.screenshots .build/release-screenshots "$OUTPUT"
