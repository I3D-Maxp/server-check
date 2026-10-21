#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

health_init
section_label=${SERVER_CHECK_SECTION_LABEL:-STORAGE}
if [[ ${SERVER_CHECK_STORAGE_INVENTORY:-yes} == yes ]]; then
    show_command 'Block device inventory' lsblk -o NAME,PATH,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL
fi
if [[ ${SERVER_CHECK_SMART_ENABLED:-yes} != yes ]]; then
    health_finding INFO 'SMART/NVMe health is disabled by configuration; storage inventory only.'
    health_finish "$section_label"
    exit 0
fi

# nvme-cli uses text output here so no JSON parser is needed in the live image.
nvme_field() {
    local line
    line=$(grep -im1 -E "^[[:space:]]*$2[[:space:]]*:" <<< "$1" || true)
    line=${line#*:}
    if [[ $line =~ (0[xX][[:xdigit:]]+|[0-9][0-9,]*) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

as_number() {
    local value=${1//,/}
    if [[ $value == 0x* || $value == 0X* ]]; then
        printf '%d' "$((value))"
    elif [[ $value =~ ^[0-9]+$ ]]; then
        printf '%d' "$((10#$value))"
    fi
}

check_nvme() {
    local device=$1 output status raw critical media spare threshold used errors command_name
    if ! command -v nvme >/dev/null 2>&1; then
        health_finding WARNING "$device NVMe health not tested: nvme-cli is not installed."
        return
    fi
    command_name='nvme log smart'
    output=$(nvme log smart "$device" 2>&1)
    status=$?
    if ((status != 0)); then
        info "First NVMe health query for $device (nvme log smart, exit $status):"
        printf '%s\n' "$output"
        command_name='nvme smart-log (legacy)'
        output=$(nvme smart-log "$device" 2>&1)
        status=$?
    fi
    info "Raw NVMe SMART/health evidence for $device ($command_name, exit $status):"
    printf '%s\n' "$output"
    if ((status != 0)); then
        health_finding WARNING "$device NVMe health not tested: both current and legacy nvme-cli queries failed (access or controller support may be limited)."
        return
    fi

    raw=$(nvme_field "$output" critical_warning)
    if [[ -z $raw ]]; then
        health_finding WARNING "$device NVMe health not tested: critical_warning was absent."
        return
    fi
    critical=$(as_number "$raw")
    if ((critical > 0)); then
        health_finding FAIL "$device reports NVMe critical_warning=$raw (current controller health signal)."
    else
        health_finding OK "$device reports no NVMe critical warning."
    fi

    raw=$(nvme_field "$output" media_errors)
    if [[ -n $raw ]]; then
        media=$(as_number "$raw")
        if ((media > 0)); then
            health_finding WARNING "$device has $media cumulative NVMe media/data-integrity errors; check trend and logs."
        fi
    fi
    raw=$(nvme_field "$output" num_err_log_entries)
    if [[ -n $raw ]]; then
        errors=$(as_number "$raw")
        if ((errors > 0)); then
            health_finding INFO "$device has $errors cumulative NVMe error-log entries; these alone do not prove media failure."
        fi
    fi
    raw=$(nvme_field "$output" percentage_used)
    if [[ -n $raw ]]; then
        used=$(as_number "$raw")
        if ((used >= 100)); then
            health_finding WARNING "$device reports percentage_used=$used%; estimated endurance is exhausted."
        fi
    fi
    raw=$(nvme_field "$output" available_spare)
    spare=$(as_number "$raw")
    raw=$(nvme_field "$output" available_spare_threshold)
    threshold=$(as_number "$raw")
    if [[ -n $spare && -n $threshold ]] && ((spare < threshold)); then
        health_finding FAIL "$device available spare ($spare%) is below its device-reported threshold ($threshold%)."
    fi
}

check_smart() {
    local device=$1 output status health_line defect_line defect_count id name flag value worst threshold kind updated when raw rest
    if ! command -v smartctl >/dev/null 2>&1; then
        health_finding WARNING "$device SMART health not tested: smartctl is not installed."
        return
    fi
    # Avoid waking an intentionally sleeping disk. A skipped disk is reported as untested.
    output=$(smartctl -a -n standby "$device" 2>&1)
    status=$?
    info "Raw SMART evidence for $device (smartctl -a -n standby, exit $status):"
    printf '%s\n' "$output"

    if ((status & 7)); then
        health_finding WARNING "$device SMART health not fully tested: smartctl reported a command/device/read error (exit $status)."
    fi
    if ((status & 8 || status & 16)); then
        health_finding FAIL "$device SMART reports a failing health status or threshold crossing (exit $status)."
    elif ((status & 32)); then
        health_finding WARNING "$device SMART reports an old-age attribute threshold event (exit $status); inspect raw evidence."
    fi
    if ((status & 64 || status & 128)); then
        health_finding WARNING "$device SMART error/self-test log contains an event (exit $status); it may be historical."
    fi

    health_line=$(grep -Ei 'SMART overall-health self-assessment test result:|SMART Health Status:' <<< "$output" | tail -n 1 || true)
    if [[ $health_line =~ [Ff][Aa][Ii][Ll]([Ee][Dd])? || $health_line =~ [Bb][Aa][Dd] ]]; then
        health_finding FAIL "$device explicit SMART health result: $health_line"
    elif [[ $health_line =~ [Pp][Aa][Ss][Ss][Ee][Dd] || $health_line =~ [Oo][Kk] ]]; then
        health_finding OK "$device explicit SMART health result: $health_line"
    elif ((!(status & 8) && !(status & 16))); then
        health_finding WARNING "$device SMART health not confirmed: no overall health result was returned."
    fi

    defect_line=$(grep -im1 'Elements in grown defect list:' <<< "$output" || true)
    if [[ $defect_line =~ :[[:space:]]*([0-9]+) ]]; then
        defect_count=${BASH_REMATCH[1]}
        if ((10#$defect_count > 0)); then
            health_finding WARNING "$device SAS grown defect list contains $defect_count element(s); this is cumulative evidence, not a current failure verdict."
        fi
    fi

    # ATA table fields: ID NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE.
    while read -r id name flag value worst threshold kind updated when raw rest; do
        [[ $id =~ ^[0-9]+$ ]] || continue
        if [[ $when == FAILING_NOW ]]; then
            health_finding FAIL "$device SMART attribute $id ($name) is FAILING_NOW."
        elif [[ $when == In_the_past ]]; then
            health_finding WARNING "$device SMART attribute $id ($name) crossed a threshold in the past."
        fi
        case $id in
            5|187|197|198|199)
                if [[ $raw =~ ^[0-9]+$ ]] && ((10#$raw > 0)); then
                    health_finding WARNING "$device SMART attribute $id ($name) raw=$raw; cumulative or pending errors need review."
                fi
                ;;
        esac
    done <<< "$output"
}

if ! command -v lsblk >/dev/null 2>&1; then
    health_finding WARNING 'Storage health not tested: lsblk is not installed, so devices cannot be enumerated.'
    health_finish "$section_label"
    exit 0
fi

listing=$(lsblk -dn -o PATH,TYPE 2>&1)
status=$?
info "Raw physical-device enumeration (lsblk -dn -o PATH,TYPE, exit $status):"
printf '%s\n' "$listing"
if ((status != 0)); then
    health_finding WARNING 'Storage health not tested: device enumeration failed.'
    health_finish "$section_label"
    exit 0
fi

device_count=0
overall_rank=0
overall_reasons=()
while read -r device kind; do
    [[ $kind == disk && $device == /dev/* ]] || continue
    ((device_count += 1))
    health_init
    if [[ $device == /dev/nvme*n* ]]; then
        check_nvme "$device"
    else
        check_smart "$device"
    fi
    health_finish "DEVICE $device"
    ((health_rank > overall_rank)) && overall_rank=$health_rank
    overall_reasons+=("${health_reasons[@]}")
done <<< "$listing"

health_rank=$overall_rank
health_reasons=("${overall_reasons[@]}")
if ((device_count == 0)); then
    health_finding INFO 'No physical block devices were listed; storage health could not be evaluated.'
fi
info 'Hardware RAID may hide member drives. Vendor-specific read-only RAID checks belong in separate modules.'
health_finish "$section_label"
