#!/usr/bin/env bash
# Read literal ISO config, then apply the last matching kernel diag.* parameter.
set -euo pipefail
config=${1:-/etc/server-check/boot.conf}
cmdline=${2:-/proc/cmdline}
output=${3:-/run/server-check/boot.env}

MODE=auto
AUTO_START=yes
PROFILE=standard
REPORT_LOCATION=auto
SHUTDOWN=never
NETWORK=no
UPLOAD=no

set_value() {
    case $1 in
        MODE|AUTO_START|PROFILE|REPORT_LOCATION|SHUTDOWN|NETWORK|UPLOAD)
            printf -v "$1" '%s' "$2" ;;
        *) printf 'Unknown ISO setting: %s\n' "$1" >&2; return 3 ;;
    esac
}

if [[ -f $config ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || { printf 'Invalid ISO config line: %s\n' "$line" >&2; exit 3; }
        key=${line%%=*}
        value=${line#*=}
        set_value "$key" "$value" || exit 3
    done < "$config"
fi

[[ -r $cmdline ]] || { printf 'Cannot read kernel command line: %s\n' "$cmdline" >&2; exit 3; }
read -r -a parameters < "$cmdline" || true
for parameter in "${parameters[@]}"; do
    case $parameter in
        diag.mode=*) set_value MODE "${parameter#*=}" ;;
        diag.autostart=*) set_value AUTO_START "${parameter#*=}" ;;
        diag.profile=*) set_value PROFILE "${parameter#*=}" ;;
        diag.report_location=*) set_value REPORT_LOCATION "${parameter#*=}" ;;
        diag.shutdown=*) set_value SHUTDOWN "${parameter#*=}" ;;
        diag.network=*) set_value NETWORK "${parameter#*=}" ;;
        diag.upload=*) set_value UPLOAD "${parameter#*=}" ;;
    esac
done

case $MODE in auto|interactive|rescue) ;; *) printf 'Invalid diag.mode: %s\n' "$MODE" >&2; exit 3 ;; esac
case $AUTO_START in yes|no) ;; *) printf 'Invalid diag.autostart.\n' >&2; exit 3 ;; esac
case $PROFILE in quick|standard|extended) ;; *) printf 'Invalid diag.profile.\n' >&2; exit 3 ;; esac
case $REPORT_LOCATION in auto|tmp|usb|/*) ;; *) printf 'Invalid diag.report_location.\n' >&2; exit 3 ;; esac
case $SHUTDOWN in never|poweroff|reboot) ;; *) printf 'Invalid diag.shutdown.\n' >&2; exit 3 ;; esac
case $NETWORK in yes|no) ;; *) printf 'Invalid diag.network.\n' >&2; exit 3 ;; esac
case $UPLOAD in no) ;; *) printf 'Report upload is not implemented; diag.upload must be no.\n' >&2; exit 3 ;; esac

mkdir -p -- "$(dirname -- "$output")"
umask 077
{
    for key in MODE AUTO_START PROFILE REPORT_LOCATION SHUTDOWN NETWORK UPLOAD; do
        printf '%s=%q\n' "$key" "${!key}"
    done
} > "$output"
