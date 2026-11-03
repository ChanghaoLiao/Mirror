#!/bin/bash
set -euo pipefail
test_dir="$(CDPATH= cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper_dir="$test_dir/../plugins/mirror/skills/mirror/scripts"
python3 "$test_dir/install.test.py"
python3 "$test_dir/functions.test.py"
python3 "$test_dir/preview.test.py"

# Sourcing defines pure platform validation but never executes the CLI.
source "$helper_dir/mirror.sh"
passed=0
for spec in 'Linux arm64 14.0' 'Darwin x86_64 14.0' 'Darwin arm64 13.6' 'Darwin arm64 unknown'; do
    # Intentional splitting of these fixed test literals only.
    if result="$(mirror_check_platform $spec)"; then
        printf '%s\n' 'FAIL: unsupported platform was accepted' >&2
        exit 1
    fi
    [[ "$result" == *'"status":"unsupported_platform"'* ]] || exit 1
    passed=$((passed + 1))
done
mirror_check_platform Darwin arm64 14.0
mirror_check_platform Darwin arm64 26.4.1
printf 'PASS: %s platform tests; unsupported platforms stop before osascript.\n' "$((passed + 2))"
/usr/bin/osascript -l JavaScript "$test_dir/helper.test.js" "$helper_dir/mirror.js"

if "$helper_dir/mirror.sh" open --conversation '' > /dev/null; then
    printf '%s\n' 'FAIL: malformed CLI input exited successfully' >&2
    exit 1
fi
if "$helper_dir/mirror.sh" status --app /System/Applications/Calculator.app > /dev/null; then
    printf '%s\n' 'FAIL: another native app was accepted' >&2
    exit 1
fi
"$helper_dir/mirror.sh" --help > /dev/null
printf '%s\n' 'PASS: 3 CLI exit-code checks.'

# Exercise the actual NSTask transport with an isolated native fixture, never Mirror.
fixture_dir="$test_dir/../.build/plugin-transport-fixture/Fixture.app/Contents/MacOS"
mkdir -p "$fixture_dir"
/usr/bin/clang "$test_dir/transport-fixture.c" -o "$fixture_dir/Mirror"
/usr/bin/osascript -l JavaScript "$test_dir/transport.test.js" "$helper_dir/mirror.js" "$(cd "$fixture_dir/../.." && pwd -P)"
