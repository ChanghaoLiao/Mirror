#!/bin/bash
# Install companion skills into a host-selected directory; never overwrite.
set -euo pipefail
fail() { printf '{"ok":false,"status":"%s"}\n' "$1"; exit 1; }
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
[[ $# == 2 && "$1" == --target ]] || fail invalid_arguments
target="$2"
[[ "$target" == /* && "$target" != / && "$target" != *$'\n'* && "$target" != *$'\r'* ]] || fail invalid_target

check_path() {
    local component current="" parts
    IFS=/ read -r -a parts <<< "$1"
    for component in "${parts[@]}"; do
        [[ -n "$component" && "$component" != . ]] || continue
        [[ "$component" != .. ]] || return 1
        current="$current/$component"
        [[ ! -L "$current" ]] || return 1
        [[ ! -e "$current" || -d "$current" ]] || return 1
    done
}
check_path "$target" || fail unsafe_target
for skill in mirror mirror-setup; do
    [[ -f "$source_root/$skill/SKILL.md" && ! -L "$source_root/$skill" ]] || fail incomplete_package
    [[ -z "$(/usr/bin/find "$source_root/$skill" -type l -print -quit)" ]] || fail incomplete_package
done
/bin/mkdir -p "$target" || fail registration_failed
target="$(CDPATH= cd -- "$target" && pwd -P)"
lock="$target/.mirror-skill-install.lock"
/bin/mkdir "$lock" 2>/dev/null || fail registration_in_progress
work="$(/usr/bin/mktemp -d "$target/.mirror-skills.XXXXXX")" || { /bin/rmdir "$lock"; fail registration_failed; }
cleanup() { /bin/rm -rf -- "$work"; /bin/rmdir "$lock"; }
trap cleanup EXIT
missing=()
for skill in mirror mirror-setup; do
    destination="$target/$skill"
    [[ ! -L "$destination" ]] || fail skill_conflict
    if [[ -e "$destination" ]]; then
        [[ -d "$destination" ]] || fail skill_conflict
        /usr/bin/diff -qr -x __pycache__ -x .DS_Store "$source_root/$skill" "$destination" >/dev/null 2>&1 || fail skill_conflict
    else
        missing+=("$skill")
    fi
done
if [[ ${#missing[@]} == 0 ]]; then
    printf '%s\n' '{"ok":true,"status":"reused","next":"Reload host skills if needed, then check Mirror desktop status separately."}'
    exit 0
fi
for skill in "${missing[@]}"; do
    /bin/cp -R "$source_root/$skill" "$work/$skill" || fail registration_failed
done
for skill in "${missing[@]}"; do
    [[ ! -e "$target/$skill" && ! -L "$target/$skill" ]] || fail skill_conflict
    /bin/mv -n "$work/$skill" "$target/" || fail registration_failed
    [[ ! -e "$work/$skill" ]] || fail skill_conflict
done
printf '%s\n' '{"ok":true,"status":"registered","next":"Reload host skills if needed, then check Mirror desktop status separately. The desktop app is not installed by this step."}'
