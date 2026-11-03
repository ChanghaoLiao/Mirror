#!/bin/bash
# Pinned public preview installation. Gatekeeper and Accessibility remain human decisions.
set -euo pipefail
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/preview.conf"
fail() { printf '{"ok":false,"status":"%s"}\n' "$1"; exit 1; }
bundle=""
replace=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle) [[ $# -ge 2 && -z "$bundle" ]] || fail invalid_arguments; bundle="$2"; shift 2;;
        --replace) $replace && fail invalid_arguments; replace=true; shift;;
        *) fail invalid_arguments;;
    esac
done
source "$script_dir/mirror.sh"
mirror_check_platform "$(/usr/bin/uname -s)" "$(/usr/bin/uname -m)" "$(/usr/bin/sw_vers -productVersion)" || exit 1
[[ "$MIRROR_PREVIEW_SHA256" =~ ^[a-f0-9]{64}$ && "$MIRROR_PREVIEW_CDHASH" =~ ^[a-f0-9]{40}$ ]] || fail release_unavailable

verify_preview() {
    local app="$1" identity
    [[ -d "$app" && ! -L "$app" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.mirror.companion ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$MIRROR_PREVIEW_VERSION" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$MIRROR_PREVIEW_BUILD" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
    identity="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)" || return 1
    printf '%s\n' "$identity" | /usr/bin/grep -Fx "CDHash=$MIRROR_PREVIEW_CDHASH" >/dev/null
}

parent="$HOME/Applications"
target="$parent/Mirror.app"
[[ ! -L "$HOME" && ! -L "$parent" && ! -L "$target" ]] || fail unsafe_install_path
if [[ -e "$target" ]] && ! verify_preview "$target"; then
    $replace || fail replacement_confirmation_required
fi
# Do not add another copy beside an already running Mirror, including other locations.
/usr/bin/pgrep -x Mirror >/dev/null && fail quit_mirror_required
/bin/mkdir -p "$parent"
lock="$parent/.mirror-preview-install.lock"
/bin/mkdir "$lock" 2>/dev/null || fail installation_in_progress
work="$(/usr/bin/mktemp -d "$parent/.mirror-preview.XXXXXX")" || { /bin/rmdir "$lock"; fail install_failed; }
cleanup() { /bin/rm -rf -- "$work"; /bin/rmdir "$lock"; }
trap cleanup EXIT
if [[ -e "$target" ]] && verify_preview "$target"; then
    : # Same pinned app, never replaced.
else
    if [[ -n "$bundle" ]]; then
        [[ "$bundle" == /* && -d "$bundle" && ! -L "$bundle" ]] || fail invalid_arguments
        /usr/bin/ditto "$bundle" "$work/Mirror.app" || fail extraction_failed
    else
        [[ "$MIRROR_PREVIEW_AVAILABLE" == true ]] || fail release_unavailable
        [[ "$MIRROR_PREVIEW_URL" == https://github.com/ChanghaoLiao/Mirror/releases/download/* ]] || fail invalid_release_url
        /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 --retry 2 \
            "$MIRROR_PREVIEW_URL" -o "$work/Mirror.zip" || fail download_failed
        [[ "$(/usr/bin/shasum -a 256 "$work/Mirror.zip" | /usr/bin/awk '{print $1}')" == "$MIRROR_PREVIEW_SHA256" ]] || fail checksum_failed
        /usr/bin/unzip -Z1 "$work/Mirror.zip" > "$work/entries" || fail invalid_archive
        /usr/bin/awk 'BEGIN {bad=0; count=0} {count++; if ($0 !~ /^Mirror\.app\// || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /\\/) bad=1} END {exit (bad || count==0)}' "$work/entries" || fail invalid_archive
        /usr/bin/ditto -x -k "$work/Mirror.zip" "$work" || fail extraction_failed
    fi
    # Finder/cloud providers can attach harmless FinderInfo to copied bundles.
    # Clean only that annotation on the staged copy, never quarantine or originals.
    /usr/bin/xattr -dr com.apple.FinderInfo "$work/Mirror.app" 2>/dev/null || true
    verify_preview "$work/Mirror.app" || fail signature_failed
    backup="$parent/Mirror-backup-$(/bin/date +%Y%m%d%H%M%S)-$$.app"
    if [[ -e "$target" ]]; then /bin/mv "$target" "$backup" || fail install_failed; fi
    if ! /bin/mv "$work/Mirror.app" "$target"; then
        [[ ! -e "$backup" ]] || /bin/mv "$backup" "$target"
        fail install_failed
    fi
fi
# Downloading with curl does not set quarantine. Preserve any downloaded bundle flag;
# add it when absent so preview installation never quietly skips the system review.
if ! /usr/bin/xattr -p com.apple.quarantine "$target" >/dev/null 2>&1; then
    /usr/bin/xattr -w com.apple.quarantine "0083;$(/bin/date +%s);MirrorPreview;" "$target" || fail quarantine_failed
fi
/usr/bin/open -g "$target" >/dev/null 2>&1 || true
printf '%s\n' '{"ok":true,"status":"manual_open_required","preview":true,"notarized":false,"next":"Mirror is installed. This preview is not Apple notarized. Complete the macOS first-open decision yourself; if blocked, review System Settings > Privacy & Security. Then run mirror.sh status. Accessibility for window following is a separate optional human authorization."}'
