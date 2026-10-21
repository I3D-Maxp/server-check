#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/server-check-inc3.XXXXXX")
TEST_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd)
case $(cd -- "$TEST_DIR" && pwd) in
    "$TEST_ROOT"/server-check-inc3.*) ;;
    *) printf 'Unsafe test directory.\n' >&2; exit 3 ;;
esac
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/usb" "$TEST_DIR/reports"
export TEST_DIR USB_MOUNT="$TEST_DIR/usb" PATH="$TEST_DIR/bin:$PATH"

cat > "$TEST_DIR/bin/storcli" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/storcli.out"
if [[ ${RAID_FAIL:-no} == yes ]]; then exit 1; fi
EOF
cat > "$TEST_DIR/bin/ssacli" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *' show status'* ]]; then cat "$TEST_DIR/ssacli.status"; else cat "$TEST_DIR/ssacli.config"; fi
EOF
cat > "$TEST_DIR/bin/mdadm" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *'--scan'* ]]; then printf 'ARRAY /dev/md0 metadata=1.2\n'; else cat "$TEST_DIR/mdadm.out"; fi
EOF
cat > "$TEST_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *'PATH,TRAN'* ]]; then printf '/dev/sda sata\n/dev/sdb usb\n';
elif [[ $* == *'MOUNTPOINT'* ]]; then printf '%s\n' "$USB_MOUNT"; fi
EOF
cat > "$TEST_DIR/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *'OPTIONS'* ]]; then printf 'rw,relatime\n'; else printf '%s\n' "$USB_MOUNT"; fi
EOF
cat > "$TEST_DIR/bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '0000:00:00.0 Mock PCI bridge\n'
EOF
chmod +x "$TEST_DIR/bin/"*

assert_level() {
    local expected=$1 script=$2 output
    shift 2
    output=$("$@" bash "$script")
    grep -Fq "[$expected] VERDICT" <<< "$output" || { printf 'Expected %s:\n%s\n' "$expected" "$output" >&2; exit 1; }
}

printf '0/0 RAID1 Optl RW\n' > "$TEST_DIR/storcli.out"
assert_level OK "$ROOT/checks/raid-vendors/storcli.sh" env RAID_CLI=storcli
printf '0/0 RAID1 Dgrd RW\n' > "$TEST_DIR/storcli.out"
assert_level WARNING "$ROOT/checks/raid-vendors/storcli.sh" env RAID_CLI=storcli
output=$(RAID_CLI=storcli bash "$ROOT/checks/raid-vendors/storcli.sh")
grep -Fq '0/0 RAID1 Dgrd RW' <<< "$output"
printf '0/0 RAID1 OfLn RW\n' > "$TEST_DIR/storcli.out"
assert_level FAIL "$ROOT/checks/raid-vendors/storcli.sh" env RAID_CLI=storcli
output=$(RAID_CLI=storcli bash "$ROOT/checks/raid-vendors/storcli.sh")
grep -Fq '0/0 RAID1 OfLn RW' <<< "$output"
assert_level WARNING "$ROOT/checks/raid-vendors/storcli.sh" env RAID_CLI=storcli RAID_FAIL=yes

printf 'Controller Status: OK\n' > "$TEST_DIR/ssacli.status"
printf 'logicaldrive 1 (1.0 TB, RAID 1, OK)\n' > "$TEST_DIR/ssacli.config"
assert_level OK "$ROOT/checks/raid-vendors/ssacli.sh" env RAID_CLI=ssacli
printf 'logicaldrive 1 (1.0 TB, RAID 1, Degraded)\n' > "$TEST_DIR/ssacli.config"
assert_level WARNING "$ROOT/checks/raid-vendors/ssacli.sh" env RAID_CLI=ssacli
printf 'Controller Status: Failed\n' > "$TEST_DIR/ssacli.status"
assert_level FAIL "$ROOT/checks/raid-vendors/ssacli.sh" env RAID_CLI=ssacli

printf 'Personalities : [raid1]\nmd0 : active raid1 sda1[0] sdb1[1]\n      [2/2] [UU]\n' > "$TEST_DIR/mdstat"
printf 'State : clean\n' > "$TEST_DIR/mdadm.out"
printf '0/0 RAID1 Optl RW\n' > "$TEST_DIR/storcli.out"
printf 'Controller Status: OK\n' > "$TEST_DIR/ssacli.status"
printf 'logicaldrive 1 (1.0 TB, RAID 1, OK)\n' > "$TEST_DIR/ssacli.config"
assert_level OK "$ROOT/checks/raid.sh" env SERVER_CHECK_MDSTAT="$TEST_DIR/mdstat"
printf 'State : degraded\n' > "$TEST_DIR/mdadm.out"
assert_level FAIL "$ROOT/checks/raid.sh" env SERVER_CHECK_MDSTAT="$TEST_DIR/mdstat"

uname() { if [[ ${1:-} == -s ]]; then printf 'Linux\n'; else command uname "$@"; fi; }
export -f uname
bash "$ROOT/server-check.sh" --check pci --report-target usb > "$TEST_DIR/console.out"
grep -Fq "Report: $TEST_DIR/usb/server-check-reports/" "$TEST_DIR/console.out"
usb_reports=("$TEST_DIR/usb/server-check-reports/"*.txt)
[[ ${#usb_reports[@]} -eq 1 && -f ${usb_reports[0]} ]]

USB_MOUNT=/missing bash "$ROOT/server-check.sh" --check pci --report-target usb > "$TEST_DIR/missing.out" 2>&1 && exit 1 || status=$?
[[ $status == 3 ]]

bash "$ROOT/server-check.sh" --config "$ROOT/config/server-check.conf" --mode auto --set RUN_CPU=no --check pci --output-dir "$TEST_DIR/reports" > "$TEST_DIR/override.out"
grep -Fq 'Mode: auto' "$TEST_DIR/override.out"
grep -Fq 'Report target: path' "$TEST_DIR/override.out"

bash "$ROOT/unattended.sh" --mode auto --set AUTO_START=yes --check pci --output-dir "$TEST_DIR/reports" > "$TEST_DIR/wrapper.out"
grep -Fq 'SERVER DIAGNOSTIC COMPLETE' "$TEST_DIR/wrapper.out"
grep -Fq 'Diagnostic launcher exit: 0' "$TEST_DIR/wrapper.out"

if bash "$ROOT/server-check.sh" --set RUN_CPU=maybe --check pci > "$TEST_DIR/bad-config.out" 2>&1; then exit 1; else status=$?; fi
[[ $status == 3 ]]

bash "$ROOT/server-check.sh" --dependencies > "$TEST_DIR/deps.out"
grep -Fq 'smartctl' "$TEST_DIR/deps.out"

printf 'Increment 3 fixture tests passed.\n'
