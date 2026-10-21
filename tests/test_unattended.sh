#!/usr/bin/env bash
# Tests unattended selection, boot gating, timeouts, and completion reporting.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/server-check-auto-test.XXXXXX")
TEST_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd)
case $(cd -- "$TEST_DIR" && pwd) in
    "$TEST_ROOT"/server-check-auto-test.*) ;;
    *) printf 'Unsafe test directory: %s\n' "$TEST_DIR" >&2; exit 2 ;;
esac
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
export PATH="$TEST_DIR/bin:$PATH"

# No actual hardware is read. The first check hangs; the next must still run.
cat > "$TEST_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ ${MOCK_LSBLK_SLEEP:-yes} == yes ]]; then sleep 3; fi
if [[ " $* " == *' -dn '* ]]; then
    printf '/dev/sda disk\n'
else
    printf 'Mock lsblk complete\n'
fi
EOF
cat > "$TEST_DIR/bin/smartctl" <<'EOF'
#!/usr/bin/env bash
printf 'SMART overall-health self-assessment test result: PASSED\n'
EOF
cat > "$TEST_DIR/bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '0000:00:00.0 Mock PCI device\n'
EOF
chmod +x "$TEST_DIR/bin/"*

uname() {
    if [[ ${1:-} == -s ]]; then printf 'Linux\n'; else command uname "$@"; fi
}
export -f uname

cat > "$TEST_DIR/auto.conf" <<EOF
MODE=auto
AUTO_START=yes
RUN_CPU=no
RUN_MEMORY=no
RUN_STORAGE=yes
RUN_SMART=no
RUN_RAID=no
RUN_NETWORK=no
RUN_SENSORS=no
RUN_PCIE=yes
RUN_LOG_ANALYSIS=no
RUN_FIRMWARE=no
RUN_BMC=no
REPORT_FORMAT=text
REPORT_LOCATION=$TEST_DIR/reports
CHECK_TIMEOUT_SECONDS=1
EOF

if bash "$ROOT/server-check.sh" --boot --config "$TEST_DIR/auto.conf" > "$TEST_DIR/console.out"; then
    printf 'Expected a warning exit after a timed-out check.\n' >&2
    exit 1
else
    status=$?
    [[ $status == 1 ]] || { printf 'Expected exit 1, got %s\n' "$status" >&2; exit 1; }
fi
reports=("$TEST_DIR/reports/"*.txt)
[[ ${#reports[@]} -eq 1 && -f ${reports[0]} ]]
grep -Fq 'SERVER DIAGNOSTIC COMPLETE' "${reports[0]}"
grep -Fq 'Overall: WARNING' "${reports[0]}"
grep -Eq '^Storage:[[:space:]]+WARNING$' "${reports[0]}"
grep -Eq '^PCIe:[[:space:]]+INFO$' "${reports[0]}"
grep -Fq 'timed out after 1 seconds' "${reports[0]}"
grep -Fq 'Mock PCI device' "${reports[0]}"

sed -e 's/RUN_STORAGE=yes/RUN_STORAGE=no/' -e 's/RUN_SMART=no/RUN_SMART=yes/' -e 's/RUN_PCIE=yes/RUN_PCIE=no/' "$TEST_DIR/auto.conf" > "$TEST_DIR/smart-only.conf"
MOCK_LSBLK_SLEEP=no bash "$ROOT/server-check.sh" --config "$TEST_DIR/smart-only.conf" --output-dir "$TEST_DIR/smart-reports" > "$TEST_DIR/smart-console.out"
grep -Eq '^SMART:[[:space:]]+OK$' "$TEST_DIR/smart-console.out"
grep -Fq 'Overall: OK' "$TEST_DIR/smart-console.out"
if grep -Fq 'Block device inventory' "$TEST_DIR/smart-console.out"; then
    printf 'SMART-only mode should skip general storage inventory.\n' >&2
    exit 1
fi

sed 's/AUTO_START=yes/AUTO_START=no/' "$TEST_DIR/auto.conf" > "$TEST_DIR/manual-boot.conf"
output=$(bash "$ROOT/server-check.sh" --boot --config "$TEST_DIR/manual-boot.conf")
[[ $output == *'AUTO_START=no'* ]]

sed 's/MODE=auto/MODE=interactive/' "$TEST_DIR/auto.conf" > "$TEST_DIR/interactive.conf"
output=$(bash "$ROOT/server-check.sh" --boot --config "$TEST_DIR/interactive.conf")
[[ $output == *'MODE=interactive'* ]]

printf 'UNKNOWN_KEY=yes\n' > "$TEST_DIR/invalid.conf"
if bash "$ROOT/server-check.sh" --config "$TEST_DIR/invalid.conf" > "$TEST_DIR/invalid.out" 2>&1; then
    printf 'Unknown config keys must be rejected.\n' >&2
    exit 1
fi
if bash "$ROOT/server-check.sh" --check wipe-disk > "$TEST_DIR/unsafe.out" 2>&1; then
    printf 'An unknown/destructive check name must be rejected.\n' >&2
    exit 1
fi

printf 'Unattended mode tests passed.\n'
