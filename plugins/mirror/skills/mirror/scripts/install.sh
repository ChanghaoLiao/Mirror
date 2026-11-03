#!/bin/bash
# Local Codex first-run installer; no sudo, quarantine removal or permission changes.
set -euo pipefail

installer_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$installer_dir/release.conf"

fail() { printf '{"ok":false,"status":"%s"}\n' "$1"; exit 1; }
installer_cleanup() {
    /bin/rm -rf -- "$installer_work"
    /bin/rmdir "$installer_lock"
}
version_supported() {
    local a b c x y z
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r a b c <<< "$1"
    IFS=. read -r x y z <<< "$MIRROR_INSTALL_VERSION"
    (( 10#$a > 10#$x || (10#$a == 10#$x && 10#$b > 10#$y) || (10#$a == 10#$x && 10#$b == 10#$y && 10#$c >= 10#$z) ))
}
verify_app() {
    local app="$1" version identity assessment
    [[ ! -L "$app" && -d "$app" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.mirror.companion ]] || return 1
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" || return 1
    version_supported "$version" || return 1
    /usr/bin/codesign --verify --deep --strict "$app" || return 1
    identity="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)" || return 1
    printf '%s\n' "$identity" | /usr/bin/grep -Fx "TeamIdentifier=$MIRROR_INSTALL_TEAM" >/dev/null || return 1
    assessment="$(/usr/sbin/spctl --assess --type execute --verbose=2 "$app" 2>&1)" || return 1
    printf '%s\n' "$assessment" | /usr/bin/grep -F 'source=Notarized Developer ID' >/dev/null
}
install_main() {
    local replace=false target parent work lock backup version
    [[ $# == 0 || ( $# == 1 && "$1" == --replace ) ]] || fail invalid_arguments
    [[ $# == 0 ]] || replace=true
    source "$installer_dir/mirror.sh"
    mirror_check_platform "$(/usr/bin/uname -s)" "$(/usr/bin/uname -m)" "$(/usr/bin/sw_vers -productVersion)" || return 1
    # Pins are enabled only after the signed public download has been verified.
    [[ "$MIRROR_INSTALL_PUBLISHED" == true && "$MIRROR_INSTALL_SHA256" =~ ^[a-f0-9]{64}$ && "$MIRROR_INSTALL_TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail release_unavailable
    parent="$HOME/Applications"
    target="$parent/Mirror.app"
    [[ ! -L "$parent" && ! -L "$target" ]] || fail unsafe_install_path
    /bin/mkdir -p "$parent"
    lock="$parent/.mirror-install.lock"
    /bin/mkdir "$lock" 2>/dev/null || fail installation_in_progress
    work="$(/usr/bin/mktemp -d "$parent/.mirror-install.XXXXXX")" || { /bin/rmdir "$lock"; fail install_failed; }
    installer_work="$work"
    installer_lock="$lock"
    trap installer_cleanup EXIT
    if [[ -e "$target" ]]; then
        if verify_app "$target"; then
            /usr/bin/open -g "$target" || fail launch_failed
            printf '%s\n' '{"ok":true,"status":"reused"}'
            return
        fi
        $replace || fail replacement_confirmation_required
        # Never replace a live application, including copies outside Applications.
        if /usr/bin/pgrep -x Mirror >/dev/null; then fail quit_mirror_required; fi
    fi
    /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 --retry 2 \
        "https://github.com/ChanghaoLiao/Mirror/releases/download/v$MIRROR_INSTALL_VERSION/Mirror-$MIRROR_INSTALL_VERSION-macos-arm64.zip" \
        -o "$work/Mirror.zip" || fail download_failed
    [[ "$(/usr/bin/shasum -a 256 "$work/Mirror.zip" | /usr/bin/awk '{print $1}')" == "$MIRROR_INSTALL_SHA256" ]] || fail checksum_failed
    /usr/bin/unzip -Z1 "$work/Mirror.zip" > "$work/entries" || fail invalid_archive
    /usr/bin/awk 'BEGIN {bad=0; count=0} {count++; if ($0 !~ /^Mirror\.app\// || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /\\/) bad=1} END {exit (bad || count==0)}' "$work/entries" || fail invalid_archive
    /usr/bin/ditto -x -k "$work/Mirror.zip" "$work/extracted" || fail extraction_failed
    verify_app "$work/extracted/Mirror.app" || fail signature_or_notarization_failed
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/extracted/Mirror.app/Contents/Info.plist")"
    [[ "$version" == "$MIRROR_INSTALL_VERSION" ]] || fail version_mismatch
    backup="$parent/Mirror-backup-$(/bin/date +%Y%m%d%H%M%S)-$$.app"
    if [[ -e "$target" ]]; then /bin/mv "$target" "$backup" || fail install_failed; fi
    if ! /bin/mv "$work/extracted/Mirror.app" "$target"; then
        [[ ! -e "$backup" ]] || /bin/mv "$backup" "$target"
        fail install_failed
    fi
    /usr/bin/open -g "$target" || fail launch_failed
    printf '%s\n' '{"ok":true,"status":"installed","next":"Run mirror.sh status; macOS permissions remain manual."}'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then install_main "$@"; fi
