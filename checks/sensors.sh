#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

health_init

number_at_least() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
number_below() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }

check_reported_limits() {
    local line label reading limit
    while IFS= read -r line; do
        [[ $line =~ ^([^:]+):[[:space:]]*([+-]?[0-9]+([.][0-9]+)?) ]] || continue
        label=${BASH_REMATCH[1]}
        reading=${BASH_REMATCH[2]}
        if [[ $line == *'°C'* || $line == *' C '* ]]; then
            if [[ $line =~ crit[[:space:]]*=[[:space:]]*\+?([0-9]+([.][0-9]+)?) ]]; then
                limit=${BASH_REMATCH[1]}
                number_at_least "$reading" "$limit" && health_finding FAIL "$label temperature $reading reached its reported critical limit $limit."
            fi
            if [[ $line =~ high[[:space:]]*=[[:space:]]*\+?([0-9]+([.][0-9]+)?) ]]; then
                limit=${BASH_REMATCH[1]}
                number_at_least "$reading" "$limit" && health_finding WARNING "$label temperature $reading reached its reported high limit $limit."
            fi
        elif [[ ${label,,} == fan* && $line =~ min[[:space:]]*=[[:space:]]*([0-9]+([.][0-9]+)?) ]]; then
            limit=${BASH_REMATCH[1]}
            number_below "$reading" "$limit" && health_finding WARNING "$label speed $reading is below its reported minimum $limit."
        elif [[ $line == *' V '* ]]; then
            if [[ $line =~ min[[:space:]]*=[[:space:]]*\+?([0-9]+([.][0-9]+)?) ]]; then
                limit=${BASH_REMATCH[1]}
                number_below "$reading" "$limit" && health_finding WARNING "$label voltage $reading is below its reported minimum $limit."
            fi
            if [[ $line =~ max[[:space:]]*=[[:space:]]*\+?([0-9]+([.][0-9]+)?) ]]; then
                limit=${BASH_REMATCH[1]}
                number_at_least "$reading" "$limit" && health_finding WARNING "$label voltage $reading reached its reported maximum $limit."
            fi
        fi
    done <<< "$1"
}

if command -v sensors >/dev/null 2>&1; then
    sensor_output=$(sensors 2>&1)
    sensor_status=$?
    info "Raw lm-sensors temperature, fan, and voltage readings (exit $sensor_status):"
    printf '%s\n' "$sensor_output"
    if ((sensor_status == 0)) && [[ -n $sensor_output ]] && [[ $sensor_output != *'No sensors found'* ]]; then
        check_reported_limits "$sensor_output"
        if grep -Eiq '(^|[[:space:]])FAULT([[:space:]]|$)' <<< "$sensor_output"; then
            health_finding FAIL 'lm-sensors reports an explicit FAULT flag; inspect the affected sensor above.'
        elif grep -Eiq '(^|[[:space:]])ALARM([[:space:]]|$)' <<< "$sensor_output"; then
            health_finding WARNING 'lm-sensors reports an explicit ALARM flag; inspect its device-provided limits above.'
        else
            health_finding OK 'lm-sensors returned readings with no explicit FAULT or ALARM flag.'
        fi
    else
        health_finding INFO 'lm-sensors readings could not be collected; this does not imply healthy sensors.'
    fi
else
    health_finding INFO 'lm-sensors is not installed; local sensor readings are unavailable.'
fi

if command -v ipmitool >/dev/null 2>&1; then
    ipmi_output=$(ipmitool sensor list 2>&1)
    ipmi_status=$?
    info "Raw BMC sensor readings, including fans and power supplies when exposed (exit $ipmi_status):"
    printf '%s\n' "$ipmi_output"
    if ((ipmi_status == 0)) && [[ -n $ipmi_output ]]; then
        ipmi_non_ok=0
        ipmi_usable=0
        while IFS='|' read -r name reading units state remainder; do
            [[ -n $state ]] || continue
            state=${state//[[:space:]]/}
            case ${state,,} in
                cr|nr|lcr|ucr|lnr|unr)
                    ipmi_non_ok=1
                    ipmi_usable=1
                    health_finding FAIL "BMC sensor ${name//[[:space:]]/ } reports critical/non-recoverable status $state."
                    ;;
                nc|lnc|unc)
                    ipmi_non_ok=1
                    ipmi_usable=1
                    health_finding WARNING "BMC sensor ${name//[[:space:]]/ } reports non-critical status $state."
                    ;;
                na)
                    health_finding INFO "BMC sensor ${name//[[:space:]]/ } has no usable status/reading."
                    ;;
                ok)
                    ipmi_usable=1
                    ;;
            esac
        done <<< "$ipmi_output"
        if ((ipmi_usable == 0)); then
            health_finding INFO 'BMC output contained no usable sensor status.'
        elif ((ipmi_non_ok == 0)); then
            health_finding OK 'BMC sensor readings contain no explicit critical or non-critical status.'
        fi
    else
        health_finding INFO 'BMC sensor readings could not be collected (access or BMC support may be limited).'
    fi
else
    health_finding INFO 'ipmitool is not installed; BMC sensor readings are unavailable.'
fi

info 'No temperature, fan, or voltage threshold is invented here. Only flags and limits reported by the sensor provider affect the verdict.'
health_finish SENSORS
