#!/bin/bash
# Requires only macOS tools. Native commands control Mirror views; system permissions remain manual.
set -u

mirror_check_platform() {
    local os="$1" arch="$2" version="$3" major="${3%%.*}"
    if [[ "$os" != Darwin || "$arch" != arm64 || ! "$major" =~ ^[0-9]+$ ]]; then
        printf '%s\n' '{"ok":false,"status":"unsupported_platform","message":"Mirror requires macOS 14 or later on Apple Silicon."}'
        return 1
    fi
    if (( 10#$major < 14 )); then
        printf '%s\n' '{"ok":false,"status":"unsupported_platform","message":"Mirror requires macOS 14 or later on Apple Silicon."}'
        return 1
    fi
}

mirror_main() {
    local os arch version script_dir
    os="$(/usr/bin/uname -s)" || return 1
    arch="$(/usr/bin/uname -m)" || return 1
    version="0"
    if [[ "$os" == Darwin ]]; then
        version="$(/usr/bin/sw_vers -productVersion)" || return 1
    fi
    mirror_check_platform "$os" "$arch" "$version" || return 1
    script_dir="$(CDPATH= cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    exec /usr/bin/osascript -l JavaScript "$script_dir/mirror.js" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    mirror_main "$@"
fi
