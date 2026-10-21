#!/usr/bin/env bash
# systemd tty1 entry point for the live image.
set -u
root=${SERVER_CHECK_ROOT:-/opt/server-check}
runtime="$root/iso/runtime"
boot_config=${SERVER_CHECK_BOOT_CONFIG:-/etc/server-check/boot.conf}
cmdline=${SERVER_CHECK_CMDLINE:-/proc/cmdline}
state_dir=${SERVER_CHECK_STATE_DIR:-/run/server-check}
mkdir -p -- "$state_dir"

shell_or_exit() {
    local status=$1
    printf '\nServer Check console ready. Diagnostic exit: %s\n' "$status"
    printf 'Use this shell to inspect reports. No automatic reboot or poweroff is scheduled.\n'
    export SERVER_CHECK_EXIT_STATUS=$status
    if [[ -t 0 && -t 1 ]]; then
        exec bash --noprofile --norc -i
    fi
    exit "$status"
}

if ! bash "$runtime/parse-cmdline.sh" "$boot_config" "$cmdline" "$state_dir/boot.env"; then
    printf 'ISO boot settings could not be loaded.\n' >&2
    shell_or_exit 3
fi
source "$state_dir/boot.env"
printf 'Server Check: mode=%s profile=%s autostart=%s network=%s\n' "$MODE" "$PROFILE" "$AUTO_START" "$NETWORK"

if [[ $MODE == rescue ]]; then
    printf 'Rescue shell: no diagnostics or host disk mounts were started.\n'
    shell_or_exit 0
fi
if [[ $MODE == interactive || $AUTO_START == no ]]; then
    printf 'Interactive shell. Run bash %s/server-check.sh --dependencies or select checks manually.\n' "$root"
    shell_or_exit 0
fi

if ! bash "$runtime/select-report.sh" "$REPORT_LOCATION" "$state_dir/report.env"; then
    printf 'No safe report destination is available.\n' >&2
    shell_or_exit 3
fi
source "$state_dir/report.env"

settings=(--set "RUN_NETWORK=$NETWORK")
case $PROFILE in
    quick)
        settings+=(--set RUN_FIRMWARE=no --set RUN_BMC=no --set RUN_PCIE=no)
        settings+=(--set CHECK_TIMEOUT_SECONDS=120) ;;
    standard) ;;
    extended)
        # Current extended profile keeps the same passive checks but allows slow hardware.
        settings+=(--set CHECK_TIMEOUT_SECONDS=600) ;;
esac

printf '\nAvailable diagnostic utilities:\n'
bash "$root/server-check.sh" --dependencies || true
printf '\nStarting safe diagnostics.\n'
bash "$root/server-check.sh" --boot --config "$root/config/server-check.conf" \
    --mode auto --set AUTO_START=yes --output-dir "$REPORT_LOCATION" "${settings[@]}"
status=$?

# Explicit shutdown is accepted only after a durable report was written.
if [[ $SHUTDOWN != never ]]; then
    if [[ $REPORT_TARGET == path && -d $REPORT_LOCATION ]]; then
        printf 'Explicit diag.shutdown=%s requested; report is at %s\n' "$SHUTDOWN" "$REPORT_LOCATION"
        systemctl "$SHUTDOWN"
        exit 3
    fi
    printf 'Ignoring diag.shutdown=%s because the report is RAM-backed.\n' "$SHUTDOWN" >&2
fi
shell_or_exit "$status"
