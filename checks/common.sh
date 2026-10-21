#!/usr/bin/env bash
# Shared output helpers. Missing tools and access errors are not hardware failures.

info() {
    printf '[INFO] %s\n' "$*"
}

warning() {
    printf '[WARNING] %s\n' "$*"
}

# Health checks record evidence before a single conservative section verdict.
# Severity order is INFO < OK < WARNING < FAIL. An unavailable test is WARNING.
health_init() {
    health_rank=0
    health_reasons=()
}

health_finding() {
    local level=$1 message=$2 rank=0
    case $level in
        OK) rank=1 ;;
        WARNING) rank=2 ;;
        FAIL) rank=3 ;;
        INFO) rank=0 ;;
        *) printf 'Invalid finding level: %s\n' "$level" >&2; return 2 ;;
    esac
    printf '[%s] %s\n' "$level" "$message"
    if ((rank > health_rank)); then
        health_rank=$rank
    fi
    if ((rank >= 2)); then
        health_reasons+=("$message")
    fi
}

health_finish() {
    local label=$1 level reason
    case $health_rank in
        3) level=FAIL ;;
        2) level=WARNING ;;
        1) level=OK ;;
        *) level=INFO ;;
    esac
    if ((${#health_reasons[@]})); then
        reason=${health_reasons[*]}
    elif [[ $level == OK ]]; then
        reason='No explicit fault found in the available health data.'
    else
        reason='No usable health data was available.'
    fi
    printf '[%s] VERDICT %s: %s\n' "$level" "$label" "$reason"
}

show_command() {
    local label=$1 status
    shift
    if ! command -v "$1" >/dev/null 2>&1; then
        info "$label unavailable ($1 is not installed)."
        return 0
    fi
    info "$label"
    "$@"
    status=$?
    if ((status != 0)); then
        warning "$label could not be collected (exit $status); access or tool support may be limited."
    fi
    return 0
}
