#!/usr/bin/env bash
# Fixture tests for the shell health classifiers. No real hardware is accessed.
set -euo pipefail
export SERVER_CHECK_STRUCTURED_REPORT=no

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/server-check-health-test.XXXXXX")
TEST_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd)
case $(cd -- "$TEST_DIR" && pwd) in
    "$TEST_ROOT"/server-check-health-test.*) ;;
    *) printf 'Unsafe test directory: %s\n' "$TEST_DIR" >&2; exit 2 ;;
esac
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/edac/mc0"
export TEST_DIR SERVER_CHECK_EDAC_ROOT="$TEST_DIR/edac"
export PATH="$TEST_DIR/bin:$PATH"

cat > "$TEST_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' -dn '* ]]; then
    cat "$TEST_DIR/devices"
else
    printf 'Mock block device inventory\n'
fi
EOF
cat > "$TEST_DIR/bin/smartctl" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/smart.out"
exit "$(cat "$TEST_DIR/smart.status")"
EOF
cat > "$TEST_DIR/bin/nvme" <<'EOF'
#!/usr/bin/env bash
if [[ ${NVME_NEW_FAIL:-0} == 1 && $1 == log && $2 == smart ]]; then
    printf 'Unknown command: log smart\n' >&2
    exit 1
fi
cat "$TEST_DIR/nvme.out"
exit "$(cat "$TEST_DIR/nvme.status")"
EOF
cat > "$TEST_DIR/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/kernel.out"
EOF
cat > "$TEST_DIR/bin/dmesg" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/kernel.out"
EOF
cat > "$TEST_DIR/bin/sensors" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/sensors.out"
EOF
cat > "$TEST_DIR/bin/ipmitool" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_DIR/ipmi.out"
EOF
chmod +x "$TEST_DIR/bin/"*

cat > "$TEST_DIR/devices" <<'EOF'
/dev/sda disk
/dev/nvme0n1 disk
EOF
cat > "$TEST_DIR/smart.pass" <<'EOF'
SMART overall-health self-assessment test result: PASSED
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
197 Current_Pending_Sector  0x0012   100   100   000    Old_age   Always       -       0
EOF
cp "$TEST_DIR/smart.pass" "$TEST_DIR/smart.out"
cat > "$TEST_DIR/nvme.pass" <<'EOF'
critical_warning                    : 0x0
temperature                         : 35 C
available_spare                     : 100%
available_spare_threshold           : 10%
percentage_used                     : 2%
media_errors                        : 0
num_err_log_entries                 : 0
EOF
cp "$TEST_DIR/nvme.pass" "$TEST_DIR/nvme.out"
printf '0\n' > "$TEST_DIR/smart.status"
printf '0\n' > "$TEST_DIR/nvme.status"
: > "$TEST_DIR/kernel.out"
printf '0\n' > "$TEST_DIR/edac/mc0/ce_count"
printf '0\n' > "$TEST_DIR/edac/mc0/ue_count"
printf 'Core 0: +44 C (high = +90 C, crit = +100 C)\n' > "$TEST_DIR/sensors.out"
printf 'Fan1 | 4500 | RPM | ok | 0 | 0\n' > "$TEST_DIR/ipmi.out"

assert_verdict() {
    local script=$1 level=$2 label=$3 output
    output=$(bash "$ROOT/checks/$script.sh")
    if ! grep -Fq "[$level] VERDICT $label:" <<< "$output"; then
        printf 'Expected %s verdict from %s. Output:\n%s\n' "$level" "$script" "$output" >&2
        exit 1
    fi
}

assert_verdict storage OK STORAGE
output=$(bash "$ROOT/checks/storage.sh")
grep -Fq '[OK] VERDICT DEVICE /dev/sda:' <<< "$output"
grep -Fq '[OK] VERDICT DEVICE /dev/nvme0n1:' <<< "$output"
NVME_NEW_FAIL=1 assert_verdict storage OK STORAGE
printf 'SMART Health Status: OK\nElements in grown defect list: 1\n' > "$TEST_DIR/smart.out"
assert_verdict storage WARNING STORAGE
cp "$TEST_DIR/smart.pass" "$TEST_DIR/smart.out"
awk '{if ($1 == 197) $10 = 2; print}' "$TEST_DIR/smart.pass" > "$TEST_DIR/smart.out"
assert_verdict storage WARNING STORAGE
cp "$TEST_DIR/smart.pass" "$TEST_DIR/smart.out"
sed 's/result: PASSED/result: FAILED!/' "$TEST_DIR/smart.pass" > "$TEST_DIR/smart.out"
printf '8\n' > "$TEST_DIR/smart.status"
assert_verdict storage FAIL STORAGE
cp "$TEST_DIR/smart.pass" "$TEST_DIR/smart.out"
printf '0\n' > "$TEST_DIR/smart.status"
sed 's/0x0/0x2/' "$TEST_DIR/nvme.pass" > "$TEST_DIR/nvme.out"
assert_verdict storage FAIL STORAGE
cp "$TEST_DIR/nvme.pass" "$TEST_DIR/nvme.out"
sed 's/100%/5%/' "$TEST_DIR/nvme.pass" > "$TEST_DIR/nvme.out"
assert_verdict storage FAIL STORAGE
cp "$TEST_DIR/nvme.pass" "$TEST_DIR/nvme.out"
printf 'Permission denied\n' > "$TEST_DIR/smart.out"
printf '2\n' > "$TEST_DIR/smart.status"
assert_verdict storage WARNING STORAGE
output=$(bash "$ROOT/checks/storage.sh")
grep -Fq 'Permission denied' <<< "$output"
grep -Fq '[WARNING] VERDICT DEVICE /dev/sda:' <<< "$output"
cp "$TEST_DIR/smart.pass" "$TEST_DIR/smart.out"
printf '0\n' > "$TEST_DIR/smart.status"

assert_verdict memory OK MEMORY
printf '3\n' > "$TEST_DIR/edac/mc0/ce_count"
assert_verdict memory WARNING MEMORY
printf '1\n' > "$TEST_DIR/edac/mc0/ue_count"
assert_verdict memory FAIL MEMORY
printf '0\n' > "$TEST_DIR/edac/mc0/ce_count"
printf '0\n' > "$TEST_DIR/edac/mc0/ue_count"
SERVER_CHECK_EDAC_ROOT="$TEST_DIR/no-edac" assert_verdict memory INFO MEMORY
printf 'EDAC MC0: 1 CE memory error\n' > "$TEST_DIR/kernel.out"
SERVER_CHECK_EDAC_ROOT="$TEST_DIR/no-edac" assert_verdict memory WARNING MEMORY
: > "$TEST_DIR/kernel.out"

printf 'Linux version mock\n' > "$TEST_DIR/kernel.out"
assert_verdict hardware-errors OK HARDWARE-ERRORS
: > "$TEST_DIR/kernel.out"
assert_verdict hardware-errors INFO HARDWARE-ERRORS
printf 'pcieport 0000:01:00.0: AER: Corrected error received\n' > "$TEST_DIR/kernel.out"
assert_verdict hardware-errors WARNING HARDWARE-ERRORS
printf 'blk_update_request: I/O error on dev sda\n' > "$TEST_DIR/kernel.out"
assert_verdict hardware-errors WARNING HARDWARE-ERRORS
printf 'mce: Machine check: Uncorrected hardware error\n' > "$TEST_DIR/kernel.out"
assert_verdict hardware-errors FAIL HARDWARE-ERRORS
: > "$TEST_DIR/kernel.out"

assert_verdict sensors OK SENSORS
printf 'No sensors found!\n' > "$TEST_DIR/sensors.out"
: > "$TEST_DIR/ipmi.out"
assert_verdict sensors INFO SENSORS
printf 'Fan1 | 4500 | RPM | ok | 0 | 0\n' > "$TEST_DIR/ipmi.out"
printf 'Core 0: +98 C ALARM (crit = +100 C)\n' > "$TEST_DIR/sensors.out"
assert_verdict sensors WARNING SENSORS
printf 'in0: +0.90 V (min = +0.95 V, max = +1.05 V)\n' > "$TEST_DIR/sensors.out"
assert_verdict sensors WARNING SENSORS
printf 'Core 0: +44 C (crit = +100 C)\n' > "$TEST_DIR/sensors.out"
printf 'Fan1 | 1000 | RPM | nc | 0 | 0\n' > "$TEST_DIR/ipmi.out"
assert_verdict sensors WARNING SENSORS
printf 'Fan1 | 0 | RPM | cr | 0 | 0\n' > "$TEST_DIR/ipmi.out"
assert_verdict sensors FAIL SENSORS
printf 'Fan1 | 4500 | RPM | ok | 0 | 0\n' > "$TEST_DIR/ipmi.out"
printf 'Core 0: +98 C (high = +90 C, crit = +100 C)\n' > "$TEST_DIR/sensors.out"
assert_verdict sensors WARNING SENSORS
printf 'Core 0: +101 C (high = +90 C, crit = +100 C)\n' > "$TEST_DIR/sensors.out"
assert_verdict sensors FAIL SENSORS
printf 'fan1: 500 RPM (min = 900 RPM)\n' > "$TEST_DIR/sensors.out"
printf 'PSU1 | 0 | Discrete | nc | na | na\n' > "$TEST_DIR/ipmi.out"
assert_verdict sensors WARNING SENSORS

sed 's/result: PASSED/result: FAILED!/' "$TEST_DIR/smart.pass" > "$TEST_DIR/smart.out"
printf '8\n' > "$TEST_DIR/smart.status"
uname() {
    if [[ ${1:-} == -s ]]; then printf 'Linux\n'; else command uname "$@"; fi
}
export -f uname
mkdir "$TEST_DIR/reports"
if bash "$ROOT/server-check.sh" --check storage --output-dir "$TEST_DIR/reports" > "$TEST_DIR/launcher.out"; then
    printf 'Launcher should return nonzero for a FAIL verdict.\n' >&2
    exit 1
else
    status=$?
    [[ $status == 2 ]] || { printf 'Expected launcher exit 2, got %s\n' "$status" >&2; exit 1; }
fi
reports=("$TEST_DIR/reports/"*.txt)
[[ ${#reports[@]} -eq 1 && -f ${reports[0]} ]]
grep -Fq 'SERVER DIAGNOSTIC COMPLETE' "${reports[0]}"
grep -Fq 'Overall: FAIL' "${reports[0]}"
grep -Eq '^Storage:[[:space:]]+FAIL$' "${reports[0]}"
grep -Fq 'SMART overall-health self-assessment test result: FAILED!' "${reports[0]}"

printf 'Health fixture tests passed (SMART/NVMe, EDAC, logs, sensors, and launcher report).\n'
