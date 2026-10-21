#!/usr/bin/env bash
# Select only explicitly approved mounts, labelled USB mounts, or RAM-backed /run.
set -euo pipefail
request=${1:-auto}
output=${2:-/run/server-check/report.env}
tmp_root=${SERVER_CHECK_TMP_ROOT:-/run/server-check/reports}

mount_is_rw() {
    local target=$1 actual options
    actual=$(findmnt -rn -o TARGET --mountpoint "$target" 2>/dev/null) || return 1
    [[ $actual == "$target" ]] || return 1
    options=$(findmnt -rn -o OPTIONS --mountpoint "$target" 2>/dev/null) || return 1
    [[ ,$options, == *,rw,* ]]
}

usb_device() {
    local transport
    transport=$(lsblk -sno TRAN "$1" 2>/dev/null) || return 1
    grep -qx usb <<< "$transport"
}

mounted_usb() {
    local device label kind mount
    while read -r device label; do
        [[ $label == SERVER_REPORTS && $device == /dev/* ]] || continue
        kind=$(lsblk -no TYPE "$device" 2>/dev/null) || continue
        [[ $kind == part || $kind == disk ]] || continue
        usb_device "$device" || continue
        mount=$(lsblk -nr -o MOUNTPOINT "$device" 2>/dev/null | head -n 1)
        [[ $mount == /* && $mount != / ]] || continue
        mount_is_rw "$mount" || continue
        [[ -w $mount ]] || continue
        [[ ! -L $mount/server-check-reports ]] || continue
        printf '%s/server-check-reports\n' "${mount%/}"
        return 0
    done < <(lsblk -pnro PATH,LABEL 2>/dev/null)
    return 1
}

explicit_path() {
    local parent mount source fstype physical_parent physical_mount
    [[ $1 == /* && $1 != / ]] || return 1
    parent=$(dirname -- "$1")
    [[ -d $parent && -w $parent && ! -L $1 ]] || return 1
    mount=$(findmnt -rn -o TARGET --target "$parent" 2>/dev/null) || return 1
    [[ $mount == /* && $mount != / ]] || return 1
    mount_is_rw "$mount" || return 1
    physical_parent=$(realpath -e -- "$parent") || return 1
    physical_mount=$(realpath -e -- "$mount") || return 1
    [[ $physical_parent == "$physical_mount" || $physical_parent == "$physical_mount"/* ]] || return 1
    source=$(findmnt -rn -o SOURCE --mountpoint "$mount" 2>/dev/null) || return 1
    fstype=$(findmnt -rn -o FSTYPE --mountpoint "$mount" 2>/dev/null) || return 1
    case $fstype in
        tmpfs|ramfs) ;;
        nfs*|cifs|smb*|sshfs) return 1 ;;
        *) [[ $source == /dev/* ]] && usb_device "$source" || return 1 ;;
    esac
    printf '%s\n' "$1"
}

target=temp
location=$tmp_root
case $request in
    tmp) ;;
    auto|usb)
        if candidate=$(mounted_usb); then
            target=path
            location=$candidate
        fi ;;
    /*)
        if candidate=$(explicit_path "$request"); then
            target=path
            location=$candidate
        elif candidate=$(mounted_usb); then
            target=path
            location=$candidate
        fi ;;
    *) printf 'Invalid report request: %s\n' "$request" >&2; exit 3 ;;
esac

# /run is tmpfs in the live image. Reject unsafe fallback on other systems.
if [[ $target == temp ]]; then
    fstype=$(findmnt -rn -o FSTYPE --target "$(dirname -- "$tmp_root")" 2>/dev/null || true)
    [[ $fstype == tmpfs ]] || { printf 'RAM-backed report storage is unavailable.\n' >&2; exit 3; }
fi
umask 077
mkdir -p -- "$(dirname -- "$output")"
printf 'REPORT_TARGET=%q\nREPORT_LOCATION=%q\n' "$target" "$location" > "$output"
printf 'Report destination: %s (%s)\n' "$location" "$target" >&2
