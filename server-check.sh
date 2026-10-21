#!/usr/bin/env bash
# Read-only diagnostic launcher. The static check list is the unattended allowlist.
set -u
set -o pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AVAILABLE=(cpu memory storage raid network pci sensors hardware-errors firmware bmc)
SELECTED=()
RESULT_NAMES=()
RESULT_VERDICTS=()
CLI_CONFIG=''
CLI_MODE=''
CLI_OUTPUT=''
CLI_TARGET=''
CLI_SETTINGS=()
EXPLICIT_SELECTION=no
BOOT_ENTRY=no

usage() {
    cat <<'EOF'
Usage: ./server-check.sh [--config FILE] [--mode auto|interactive]
                         [--all | --check NAME ...] [--output-dir DIR]
                         [--report-target temp|usb|path] [--set KEY=VALUE ...]
       ./server-check.sh --boot [--config FILE]
       ./server-check.sh --list
       ./server-check.sh --dependencies

No arguments run the configured suite. --check selects an individual safe check.
--boot is the live-image entry point and honors AUTO_START.
EOF
}

known_check() {
    local candidate
    [[ $1 == smart ]] && return 0
    for candidate in "${AVAILABLE[@]}"; do
        [[ $candidate == "$1" ]] && return 0
    done
    return 1
}

append_check() {
    local candidate
    for candidate in "${SELECTED[@]}"; do
        [[ $candidate == "$1" ]] && return
    done
    SELECTED+=("$1")
}

display_name() {
    case $1 in
        cpu) printf CPU ;;
        memory) printf Memory ;;
        storage) printf Storage ;;
        smart) printf SMART ;;
        raid) printf RAID ;;
        network) printf Network ;;
        sensors) printf Sensors ;;
        pci) printf PCIe ;;
        hardware-errors) printf 'Hardware errors' ;;
        firmware) printf Firmware ;;
        bmc) printf BMC ;;
    esac
}

trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

set_config_value() {
    local key=$1 value=$2
    case $key in
        MODE|AUTO_START|RUN_CPU|RUN_MEMORY|RUN_STORAGE|RUN_SMART|RUN_RAID|RUN_NETWORK|RUN_SENSORS|RUN_PCIE|RUN_LOG_ANALYSIS|RUN_FIRMWARE|RUN_BMC|REPORT_FORMAT|REPORT_LOCATION|REPORT_TARGET|CHECK_TIMEOUT_SECONDS)
            printf -v "$key" '%s' "$value" ;;
        *) printf 'Unknown config key %s.\n' "$key" >&2; return 3 ;;
    esac
}

find_usb_report_dir() {
    local disk transport mount actual options
    command -v lsblk >/dev/null 2>&1 && command -v findmnt >/dev/null 2>&1 || return 1
    while read -r disk transport; do
        [[ $transport == usb && $disk == /dev/* ]] || continue
        while IFS= read -r mount; do
            [[ $mount == /* && $mount != / ]] || continue
            actual=$(findmnt -rn -o TARGET --mountpoint "$mount" 2>/dev/null) || continue
            [[ $actual == "$mount" ]] || continue
            options=$(findmnt -rn -o OPTIONS --mountpoint "$mount" 2>/dev/null) || continue
            [[ ,$options, == *,rw,* && -w $mount ]] || continue
            printf '%s/server-check-reports\n' "${mount%/}"
            return 0
        done < <(lsblk -nr -o MOUNTPOINT "$disk" 2>/dev/null)
    done < <(lsblk -dn -o PATH,TRAN 2>/dev/null)
    return 1
}

while (($#)); do
    case $1 in
        --config)
            (($# >= 2)) && [[ -n $2 ]] || { printf 'Missing --config file.\n' >&2; exit 3; }
            CLI_CONFIG=$2; shift 2 ;;
        --mode)
            (($# >= 2)) && [[ -n $2 ]] || { printf 'Missing --mode value.\n' >&2; exit 3; }
            CLI_MODE=$2; shift 2 ;;
        --all)
            EXPLICIT_SELECTION=yes
            SELECTED=("${AVAILABLE[@]}")
            shift ;;
        --check)
            (($# >= 2)) && known_check "$2" || { printf 'Unknown or missing check: %s\n' "${2:-}" >&2; exit 3; }
            EXPLICIT_SELECTION=yes
            append_check "$2"
            shift 2 ;;
        --output-dir)
            (($# >= 2)) && [[ -n $2 ]] || { printf 'Missing --output-dir value.\n' >&2; exit 3; }
            CLI_OUTPUT=$2; shift 2 ;;
        --report-target)
            (($# >= 2)) && [[ -n $2 ]] || { printf 'Missing --report-target value.\n' >&2; exit 3; }
            CLI_TARGET=$2; shift 2 ;;
        --set)
            (($# >= 2)) && [[ $2 == *=* ]] || { printf 'Expected --set KEY=VALUE.\n' >&2; exit 3; }
            CLI_SETTINGS+=("$2"); shift 2 ;;
        --boot) BOOT_ENTRY=yes; shift ;;
        --list) printf '%s\n' "${AVAILABLE[@]}" smart; exit 0 ;;
        --dependencies) exec bash "$SCRIPT_DIR/tools/dependencies.sh" ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 3 ;;
    esac
done

# Literal values only: configuration is never sourced or evaluated as shell code.
MODE=interactive
AUTO_START=no
RUN_CPU=yes
RUN_MEMORY=yes
RUN_STORAGE=yes
RUN_SMART=yes
RUN_RAID=yes
RUN_NETWORK=yes
RUN_SENSORS=yes
RUN_PCIE=yes
RUN_LOG_ANALYSIS=yes
RUN_FIRMWARE=yes
RUN_BMC=yes
REPORT_FORMAT=text
REPORT_LOCATION=${TMPDIR:-/tmp}/server-check-reports
REPORT_TARGET=path
CHECK_TIMEOUT_SECONDS=300
CONFIG_FILE=${CLI_CONFIG:-${SERVER_CHECK_CONFIG:-$SCRIPT_DIR/config/server-check.conf}}

if [[ -f $CONFIG_FILE ]]; then
    line_number=0
    while IFS= read -r line || [[ -n $line ]]; do
        ((line_number += 1))
        line=${line%$'\r'}
        line=$(trim "$line")
        [[ -z $line || $line == \#* ]] && continue
        if [[ $line != *=* ]]; then
            printf 'Invalid config line %s in %s (expected KEY=VALUE).\n' "$line_number" "$CONFIG_FILE" >&2
            exit 3
        fi
        key=$(trim "${line%%=*}")
        value=$(trim "${line#*=}")
        set_config_value "$key" "$value" || exit 3
    done < "$CONFIG_FILE"
elif [[ -n $CLI_CONFIG || -n ${SERVER_CHECK_CONFIG:-} ]]; then
    printf 'Config file not found: %s\n' "$CONFIG_FILE" >&2
    exit 3
fi

for setting in "${CLI_SETTINGS[@]}"; do
    set_config_value "$(trim "${setting%%=*}")" "$(trim "${setting#*=}")" || exit 3
done
[[ -n $CLI_MODE ]] && MODE=$CLI_MODE
[[ -n ${SERVER_CHECK_REPORT_DIR:-} ]] && REPORT_LOCATION=$SERVER_CHECK_REPORT_DIR
if [[ -n $CLI_OUTPUT ]]; then REPORT_LOCATION=$CLI_OUTPUT; REPORT_TARGET=path; fi
[[ -n $CLI_TARGET ]] && REPORT_TARGET=$CLI_TARGET
case $MODE in auto|interactive) ;; *) printf 'MODE must be auto or interactive.\n' >&2; exit 3 ;; esac
for key in AUTO_START RUN_CPU RUN_MEMORY RUN_STORAGE RUN_SMART RUN_RAID RUN_NETWORK RUN_SENSORS RUN_PCIE RUN_LOG_ANALYSIS RUN_FIRMWARE RUN_BMC; do
    value=${!key}
    case $value in yes|no) ;; *) printf '%s must be yes or no.\n' "$key" >&2; exit 3 ;; esac
done
[[ $REPORT_FORMAT == text ]] || { printf 'Only REPORT_FORMAT=text is supported.\n' >&2; exit 3; }
[[ -n $REPORT_LOCATION ]] || { printf 'REPORT_LOCATION cannot be empty.\n' >&2; exit 3; }
case $REPORT_TARGET in temp|usb|path) ;; *) printf 'REPORT_TARGET must be temp, usb, or path.\n' >&2; exit 3 ;; esac
[[ $CHECK_TIMEOUT_SECONDS =~ ^[0-9]+$ ]] && ((10#$CHECK_TIMEOUT_SECONDS >= 1 && 10#$CHECK_TIMEOUT_SECONDS <= 86400)) || {
    printf 'CHECK_TIMEOUT_SECONDS must be between 1 and 86400.\n' >&2; exit 3;
}

if [[ $BOOT_ENTRY == yes ]]; then
    if [[ $AUTO_START != yes ]]; then
        printf 'AUTO_START=no: boot entry point did not start diagnostics.\n'
        exit 0
    fi
    if [[ $MODE != auto ]]; then
        printf 'MODE=interactive: boot entry point leaves diagnostics for the technician to start manually.\n'
        exit 0
    fi
fi

if [[ $(uname -s) != Linux ]]; then
    printf 'server-check.sh requires Linux.\n' >&2
    exit 3
fi
if [[ $MODE == auto ]] && ! command -v timeout >/dev/null 2>&1; then
    printf 'Unattended mode requires the coreutils timeout command.\n' >&2
    exit 3
fi

case $REPORT_TARGET in
    temp) REPORT_LOCATION=${TMPDIR:-/tmp}/server-check-reports ;;
    usb)
        if ! REPORT_LOCATION=$(find_usb_report_dir); then
            printf 'No mounted writable USB filesystem was found; no server disk was used.\n' >&2
            exit 3
        fi ;;
    path)
        [[ $REPORT_LOCATION == /* ]] || { printf 'REPORT_LOCATION must be an absolute path.\n' >&2; exit 3; }
        # An explicit path is an operator choice; require an existing parent.
        [[ -d ${REPORT_LOCATION%/*} ]] || { printf 'Report path parent does not exist: %s\n' "$REPORT_LOCATION" >&2; exit 3; } ;;
esac

if [[ $EXPLICIT_SELECTION == no ]]; then
    [[ $RUN_CPU == yes ]] && append_check cpu
    [[ $RUN_MEMORY == yes ]] && append_check memory
    if [[ $RUN_STORAGE == yes ]]; then
        append_check storage
    elif [[ $RUN_SMART == yes ]]; then
        append_check smart
    fi
    [[ $RUN_RAID == yes ]] && append_check raid
    [[ $RUN_NETWORK == yes ]] && append_check network
    [[ $RUN_SENSORS == yes ]] && append_check sensors
    [[ $RUN_PCIE == yes ]] && append_check pci
    [[ $RUN_LOG_ANALYSIS == yes ]] && append_check hardware-errors
    [[ $RUN_FIRMWARE == yes ]] && append_check firmware
    [[ $RUN_BMC == yes ]] && append_check bmc
fi

if ! mkdir -p -- "$REPORT_LOCATION"; then
    printf 'Cannot create report directory: %s\n' "$REPORT_LOCATION" >&2
    exit 3
fi
if [[ $REPORT_TARGET == temp || $REPORT_TARGET == usb ]]; then
    report_base=${REPORT_LOCATION%/server-check-reports}
    physical_base=$(cd -P -- "$report_base" && pwd -P) || exit 3
    physical_report=$(cd -P -- "$REPORT_LOCATION" && pwd -P) || exit 3
    if [[ -L $REPORT_LOCATION || $physical_report != "$physical_base/server-check-reports" ]]; then
        printf 'Refusing a redirected %s report directory: %s\n' "$REPORT_TARGET" "$REPORT_LOCATION" >&2
        exit 3
    fi
fi
identity=${SERVER_CHECK_REPORT_ID:-}
if [[ -z $identity ]]; then
    for identity_file in /sys/class/dmi/id/product_serial /sys/class/dmi/id/product_name; do
        if [[ -r $identity_file ]]; then
            read -r identity < "$identity_file" || true
            [[ -n $identity && $identity != 'To Be Filled By O.E.M.' ]] && break
        fi
    done
fi
[[ -n $identity ]] || identity=$(hostname 2>/dev/null || printf unknown)
identity=${identity//[^[:alnum:]._-]/_}
identity=${identity:0:48}
[[ -n $identity ]] || identity=unknown
if ! REPORT=$(mktemp "$REPORT_LOCATION/server-check-$identity-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX.txt"); then
    printf 'Cannot create report in: %s\n' "$REPORT_LOCATION" >&2
    exit 3
fi

{
    printf 'Server diagnostic report\n'
    printf 'UTC time: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Host: %s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'Kernel: %s\n' "$(uname -srmo)"
    printf 'Mode: %s\n' "$MODE"
    printf 'Report target: %s\n' "$REPORT_TARGET"
    printf 'Config: %s\n' "$CONFIG_FILE"
    printf 'Checks: %s\n' "${SELECTED[*]:-(none)}"
    printf 'Notes: INFO is inventory; WARNING can indicate unavailable access. Logged errors need correlation with current symptoms.\n'
} | tee "$REPORT"
((PIPESTATUS[1] == 0)) || { printf 'Could not write report header.\n' >&2; exit 3; }

bash "$SCRIPT_DIR/tools/dependencies.sh" | tee -a "$REPORT"
((PIPESTATUS[1] == 0)) || { printf 'Could not write tool inventory.\n' >&2; exit 3; }

for check in "${SELECTED[@]}"; do
    script=$check
    inventory=yes
    smart=yes
    section_label=${check^^}
    if [[ $check == storage ]]; then
        if [[ $EXPLICIT_SELECTION == no ]]; then
            inventory=$RUN_STORAGE
            smart=$RUN_SMART
        fi
    elif [[ $check == smart ]]; then
        script=storage
        inventory=no
        smart=yes
    fi
    printf '\n===== %s =====\n' "$check" | tee -a "$REPORT"
    ((PIPESTATUS[1] == 0)) || { printf 'Could not write report section.\n' >&2; exit 3; }
    if ! CHECK_OUTPUT=$(mktemp "$REPORT_LOCATION/.server-check-XXXXXX"); then
        printf 'Could not create temporary result file for %s.\n' "$check" >&2
        exit 3
    fi
    if [[ $MODE == auto ]]; then
        SERVER_CHECK_STORAGE_INVENTORY=$inventory SERVER_CHECK_SMART_ENABLED=$smart SERVER_CHECK_SECTION_LABEL=$section_label \
            timeout --signal=TERM --kill-after=5s "${CHECK_TIMEOUT_SECONDS}s" bash "$SCRIPT_DIR/checks/$script.sh" 2>&1 | tee -a "$REPORT" "$CHECK_OUTPUT"
        pipeline_status=("${PIPESTATUS[@]}")
    else
        SERVER_CHECK_STORAGE_INVENTORY=$inventory SERVER_CHECK_SMART_ENABLED=$smart SERVER_CHECK_SECTION_LABEL=$section_label \
            bash "$SCRIPT_DIR/checks/$script.sh" 2>&1 | tee -a "$REPORT" "$CHECK_OUTPUT"
        pipeline_status=("${PIPESTATUS[@]}")
    fi
    check_exit=${pipeline_status[0]}
    ((pipeline_status[1] == 0)) || { printf 'Could not write report data.\n' >&2; exit 3; }
    if grep -Eq '^\[FAIL\] VERDICT ' "$CHECK_OUTPUT"; then
        verdict=FAIL
    elif grep -Eq '^\[WARNING\] VERDICT ' "$CHECK_OUTPUT"; then
        verdict=WARNING
    elif grep -Eq '^\[OK\] VERDICT ' "$CHECK_OUTPUT"; then
        verdict=OK
    elif grep -Eq '^\[INFO\] VERDICT ' "$CHECK_OUTPUT"; then
        verdict=INFO
    else
        verdict=WARNING
        printf '[WARNING] %s did not provide a completed verdict.\n' "$check" | tee -a "$REPORT"
    fi
    if ((check_exit != 0)); then
        [[ $verdict == FAIL ]] || verdict=WARNING
        if ((check_exit == 124)); then
            printf '[WARNING] %s timed out after %s seconds; remaining checks continue.\n' "$check" "$CHECK_TIMEOUT_SECONDS" | tee -a "$REPORT"
        else
            printf '[WARNING] %s exited with code %s; remaining checks continue.\n' "$check" "$check_exit" | tee -a "$REPORT"
        fi
    fi
    rm -f -- "$CHECK_OUTPUT"
    RESULT_NAMES+=("$check")
    RESULT_VERDICTS+=("$verdict")
done

overall=INFO
exit_status=0
for verdict in "${RESULT_VERDICTS[@]}"; do
    case $verdict in
        FAIL) overall=FAIL; exit_status=2; break ;;
        WARNING) overall=WARNING; exit_status=1 ;;
        OK) [[ $overall == INFO ]] && overall=OK ;;
    esac
done
{
    printf '\nSERVER DIAGNOSTIC COMPLETE\n'
    printf 'Overall: %s\n' "$overall"
    for index in "${!RESULT_NAMES[@]}"; do
        printf '%-18s %s\n' "$(display_name "${RESULT_NAMES[index]}"):" "${RESULT_VERDICTS[index]}"
    done
    ((${#RESULT_NAMES[@]})) || printf 'No checks were enabled.\n'
    printf 'Report: %s\n' "$REPORT"
    printf 'The system remains running. Review the report and raw evidence before acting.\n'
} | tee -a "$REPORT"
((PIPESTATUS[1] == 0)) || { printf 'Could not write report summary.\n' >&2; exit 3; }
exit "$exit_status"
