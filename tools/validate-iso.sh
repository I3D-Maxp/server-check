#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

static_layout() {
    local required
    for required in \
        iso/auto/config \
        iso/config/package-lists/server-check.list.chroot \
        src/server_check/reporting/model.py \
        src/server_check/reporting/render.py \
        src/server_check/reporting/writer.py \
        src/server_check/reporting/legacy.py \
        src/server_check/reporting/__main__.py \
        iso/config/bootloaders/isolinux/isolinux.cfg \
        iso/config/bootloaders/syslinux_common/live.cfg.in \
        iso/config/bootloaders/grub-pc/grub.cfg \
        iso/config/includes.chroot/etc/systemd/system/server-check-console.service \
        iso/config/includes.chroot/etc/server-check/boot.conf \
        iso/config/includes.chroot/etc/mdadm/mdadm.conf \
        iso/config/hooks/live/9000-server-check-isolation.hook.chroot \
        iso/runtime/parse-cmdline.sh iso/runtime/select-report.sh iso/runtime/entrypoint.sh; do
        [[ -s $root/$required ]] || { printf 'Missing ISO source: %s\n' "$required" >&2; return 3; }
    done
    grep -Fxq python3 "$root/iso/config/package-lists/server-check.list.chroot" || {
        printf 'ISO package list is missing python3.\n' >&2; return 3;
    }
    for title in 'Automatic Safe Diagnostics' 'Interactive Diagnostics' 'Linux Rescue Shell'; do
        grep -Fq "$title" "$root/iso/config/bootloaders/syslinux_common/live.cfg.in"
        grep -Fq "$title" "$root/iso/config/bootloaders/grub-pc/grub.cfg"
    done
    printf 'ISO source layout passed.\n'
}

checksum() {
    local iso=$1 directory name
    directory=$(cd -- "$(dirname -- "$iso")" && pwd)
    name=$(basename -- "$iso")
    [[ -f $directory/$name.sha256 ]] || { printf 'Missing checksum file.\n' >&2; return 3; }
    (cd "$directory" && sha256sum -c "$name.sha256")
}

if [[ ${1:-} == --static ]]; then static_layout; exit $?; fi
if [[ ${1:-} == --checksum-only ]]; then
    [[ $# == 2 ]] || exit 3
    checksum "$2"
    exit $?
fi
[[ $# == 1 && -f $1 ]] || { printf 'Usage: bash tools/validate-iso.sh [--static|--checksum-only ISO|ISO]\n' >&2; exit 3; }
static_layout
checksum "$1"
for tool in xorriso unsquashfs; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'ISO validation requires %s.\n' "$tool" >&2; exit 3; }
done
boot=$(xorriso -indev "$1" -report_el_torito plain 2>&1)
grep -Eiq 'BIOS' <<< "$boot" || { printf 'No BIOS boot entry found.\n' >&2; exit 3; }
grep -Eiq 'UEFI|EFI' <<< "$boot" || { printf 'No UEFI boot entry found.\n' >&2; exit 3; }
listing=$(xorriso -indev "$1" -ls_r / 2>&1)
for name in filesystem.squashfs isolinux.cfg grub.cfg vmlinuz initrd.img; do
    grep -Fq "$name" <<< "$listing" || { printf 'ISO is missing %s.\n' "$name" >&2; exit 3; }
done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/server-check-iso-verify.XXXXXX")
trap 'rm -f -- "$tmp/filesystem.squashfs"; rmdir -- "$tmp"' EXIT
xorriso -osirrox on -indev "$1" -extract /live/filesystem.squashfs "$tmp/filesystem.squashfs" >/dev/null 2>&1
contents=$(unsquashfs -ll "$tmp/filesystem.squashfs")
for name in opt/server-check/server-check.sh opt/server-check/src/server_check/reporting/model.py opt/server-check/src/server_check/reporting/__main__.py opt/server-check/iso/runtime/entrypoint.sh etc/systemd/system/server-check-console.service etc/server-check/boot.conf; do
    grep -Fq "$name" <<< "$contents" || { printf 'Live filesystem is missing %s.\n' "$name" >&2; exit 3; }
done
printf 'ISO structure, BIOS/UEFI entries, live contents, and checksum passed.\n'
