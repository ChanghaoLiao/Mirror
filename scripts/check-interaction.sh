#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Interactive local verification, synthetic windows only; no dialogue, image or audio export.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
MIRROR_INTERACTION_BUILD="${MIRROR_INTERACTION_BUILD:-$PWD/.build/blackboard-tests}"
MIRROR_INTERACTION_OUTPUT="$PWD/.build/interaction-performance"
mkdir -p "$MIRROR_INTERACTION_OUTPUT"
bash scripts/swift.sh build --scratch-path "$MIRROR_INTERACTION_BUILD" -c release -Xswiftc -warnings-as-errors
sources=(Sources/Mirror/UI/BlackboardMaterial.swift Sources/Mirror/UI/MirrorStyle.swift Sources/Mirror/UI/ReadingBlock.swift Sources/Mirror/UI/ConversationReader.swift)
objects=("$MIRROR_INTERACTION_BUILD"/release/MirrorCore.build/*.o)
for mode in baseline optimized frames; do
  flags=(-D BASELINE)
  source=scripts/interaction-performance/Typography.swift
  if [[ "$mode" = optimized ]]; then flags=(-D OPTIMIZED); fi
  if [[ "$mode" = frames ]]; then source=scripts/interaction-performance/AnimationFrames.swift; fi
  xcrun swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -I "$MIRROR_INTERACTION_BUILD/release/Modules" "${objects[@]}" "${sources[@]}" \
    "$MIRROR_INTERACTION_BUILD/release/Mirror.build/DerivedSources/resource_bundle_accessor.swift" \
    "${flags[@]}" "$source" -o "$MIRROR_INTERACTION_OUTPUT/$mode"
  MIRROR_PREFS_SUITE="local.mirror.performance.$mode" "$MIRROR_INTERACTION_OUTPUT/$mode" | tee "$MIRROR_INTERACTION_OUTPUT/$mode.log"
done
