#!/usr/bin/env bash
# Smoke test for check selection and report creation, including on a non-Linux dev host.
set -euo pipefail
export SERVER_CHECK_STRUCTURED_REPORT=no

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -f -- "$TEST_DIR"/*.txt; rmdir -- "$TEST_DIR"' EXIT

# The launcher requires Linux; this test only exercises its orchestration path.
uname() {
    if [[ ${1:-} == -s ]]; then
        printf 'Linux\n'
    else
        command uname "$@"
    fi
}
export -f uname

output=$(bash "$ROOT/server-check.sh" --check pci --output-dir "$TEST_DIR")
[[ $output == *'Checks: pci'* ]]
[[ $output == *'===== pci ====='* ]]

reports=("$TEST_DIR"/*.txt)
[[ ${#reports[@]} -eq 1 && -f ${reports[0]} ]]
grep -q 'Server diagnostic report' "${reports[0]}"
grep -q '===== pci =====' "${reports[0]}"
printf 'Launcher smoke test passed.\n'
