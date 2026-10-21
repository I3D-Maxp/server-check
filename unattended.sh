#!/usr/bin/env bash
# Manual unattended wrapper. The ISO uses iso/runtime/entrypoint.sh.
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$ROOT/server-check.sh" --boot "$@"
result=$?
printf '\nDiagnostic launcher exit: %s\n' "$result"
if [[ -t 0 && -t 1 ]]; then
    printf 'Results console ready. The system will remain running; use this shell to inspect the report.\n'
    export SERVER_CHECK_EXIT_STATUS=$result
    bash --noprofile --norc -i
fi
exit "$result"
