#!/usr/bin/env bash
# Static and mocked ISO boot tests; no block device or ISO build is used.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/server-check-iso-test.XXXXXX")
base=$(cd -- "${TMPDIR:-/tmp}" && pwd)
case $(cd -- "$tmp" && pwd) in "$base"/server-check-iso-test.*) ;; *) exit 3 ;; esac
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run" "$tmp/usb" "$tmp/internal" "$tmp/mock-root/iso"

bash -n "$root/server-check.sh" "$root/unattended.sh" "$root/iso/runtime/"*.sh "$root/tools/build-iso.sh" "$root/tools/validate-iso.sh"
bash "$root/tools/validate-iso.sh" --static > "$tmp/static.out"

cp "$root/iso/config/includes.chroot/etc/server-check/boot.conf" "$tmp/boot.conf"
printf 'quiet diag.mode=interactive diag.profile=quick diag.report_location=usb diag.mode=auto\n' > "$tmp/cmdline"
bash "$root/iso/runtime/parse-cmdline.sh" "$tmp/boot.conf" "$tmp/cmdline" "$tmp/parsed.env"
source "$tmp/parsed.env"
[[ $MODE == auto && $PROFILE == quick && $REPORT_LOCATION == usb && $AUTO_START == yes ]]
printf 'diag.upload=yes\n' > "$tmp/cmdline"
if bash "$root/iso/runtime/parse-cmdline.sh" "$tmp/boot.conf" "$tmp/cmdline" "$tmp/bad.env" > "$tmp/bad.out" 2>&1; then exit 1; fi

cat > "$tmp/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' PATH,LABEL '*) [[ ${MOCK_USB:-no} == yes ]] && printf '/dev/sdb1 SERVER_REPORTS\n' ;;
    *' -no TYPE '*) printf 'part\n' ;;
    *' -sno TRAN '*) [[ $* == *sdb1* ]] && printf 'usb\n' || printf 'sata\n' ;;
    *' -o MOUNTPOINT '*) printf '%s\n' "$USB_MOUNT" ;;
esac
EOF
cat > "$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' -o TARGET --mountpoint '*) printf '%s\n' "${*: -1}" ;;
    *' -o OPTIONS --mountpoint '*) printf 'rw,relatime\n' ;;
    *' -o SOURCE --mountpoint '*) printf '/dev/sda1\n' ;;
    *' -o FSTYPE --mountpoint '*) printf 'ext4\n' ;;
    *' -o TARGET --target '*) printf '%s\n' "$INTERNAL_MOUNT" ;;
    *' -o FSTYPE --target '*) printf 'tmpfs\n' ;;
esac
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" USB_MOUNT="$tmp/usb" INTERNAL_MOUNT="$tmp/internal"
export SERVER_CHECK_TMP_ROOT="$tmp/run/reports"

MOCK_USB=no bash "$root/iso/runtime/select-report.sh" auto "$tmp/report.env" > "$tmp/select.out" 2>&1
source "$tmp/report.env"
[[ $REPORT_TARGET == temp && $REPORT_LOCATION == "$tmp/run/reports" ]]

MOCK_USB=yes bash "$root/iso/runtime/select-report.sh" auto "$tmp/report.env" > "$tmp/select.out" 2>&1
source "$tmp/report.env"
[[ $REPORT_TARGET == path && $REPORT_LOCATION == "$tmp/usb/server-check-reports" ]]

MOCK_USB=no bash "$root/iso/runtime/select-report.sh" "$tmp/internal/reports" "$tmp/report.env" > "$tmp/select.out" 2>&1
source "$tmp/report.env"
[[ $REPORT_TARGET == temp && $REPORT_LOCATION == "$tmp/run/reports" ]]

cp -a "$root/iso/runtime" "$tmp/mock-root/iso/"
mkdir -p "$tmp/mock-root/config"
cp "$root/config/server-check.conf" "$tmp/mock-root/config/server-check.conf"
cat > "$tmp/mock-root/server-check.sh" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --dependencies ]]; then printf 'Mock utility inventory\n'; exit 0; fi
printf 'MOCK LAUNCHER ARGS: %s\n' "$*"
printf 'SERVER DIAGNOSTIC COMPLETE\nOverall: WARNING\nReport: /run/server-check/reports/mock.txt\n'
exit 1
EOF
printf 'diag.mode=auto diag.autostart=yes diag.profile=standard\n' > "$tmp/cmdline"
if SERVER_CHECK_ROOT="$tmp/mock-root" SERVER_CHECK_BOOT_CONFIG="$tmp/boot.conf" \
    SERVER_CHECK_CMDLINE="$tmp/cmdline" SERVER_CHECK_STATE_DIR="$tmp/state" MOCK_USB=no \
    bash "$root/iso/runtime/entrypoint.sh" > "$tmp/entry.out" 2>&1; then exit 1; else status=$?; fi
[[ $status == 1 ]]
grep -Fq 'MOCK LAUNCHER ARGS: --boot' "$tmp/entry.out"
grep -Fq 'SERVER DIAGNOSTIC COMPLETE' "$tmp/entry.out"
grep -Fq 'Server Check console ready. Diagnostic exit: 1' "$tmp/entry.out"

printf 'dummy ISO bytes\n' > "$tmp/sample.iso"
(cd "$tmp" && sha256sum sample.iso > sample.iso.sha256)
bash "$root/tools/validate-iso.sh" --checksum-only "$tmp/sample.iso" > "$tmp/checksum.out"
printf 'changed\n' >> "$tmp/sample.iso"
if bash "$root/tools/validate-iso.sh" --checksum-only "$tmp/sample.iso" > "$tmp/tampered.out" 2>&1; then exit 1; fi

if bash "$root/tools/build-iso.sh" --check-deps > "$tmp/deps.out" 2>&1; then
    # This branch is valid when tests run on a fully equipped Linux build host.
    :
else
    grep -Eq 'Missing build dependency|ISO builds require' "$tmp/deps.out"
fi
printf 'ISO static and mocked boot tests passed.\n'
