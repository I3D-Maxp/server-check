#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

health_init
show_command 'Memory capacity and usage' free -h
show_command 'DIMM configuration from SMBIOS (may require root)' dmidecode --type memory
show_command 'EDAC utility summary, if installed' ras-mc-ctl --summary

edac_root=${SERVER_CHECK_EDAC_ROOT:-/sys/devices/system/edac/mc}
edac_seen=0
for controller in "$edac_root"/mc*; do
    [[ -d $controller ]] || continue
    label=${controller##*/}
    for kind in ce ue; do
        counter=$controller/${kind}_count
        if [[ -r $counter ]]; then
            read -r count < "$counter" || count=''
            if [[ $count =~ ^[0-9]+$ ]]; then
                edac_seen=1
                info "Raw EDAC $label ${kind}_count=$count (cumulative since driver initialization)."
                if ((10#$count > 0)); then
                    if [[ $kind == ue ]]; then
                        health_finding FAIL "$label recorded $count uncorrected ECC error(s); investigate the event and affected hardware."
                    else
                        health_finding WARNING "$label recorded $count corrected ECC error(s); this cumulative count alone does not prove a DIMM is currently failing."
                    fi
                else
                    health_finding OK "$label ${kind}_count is zero."
                fi
            fi
        fi
    done
    for dimm in "$controller"/dimm*; do
        [[ -d $dimm ]] || continue
        dimm_name=${dimm##*/}
        [[ -r $dimm/dimm_label ]] && { read -r value < "$dimm/dimm_label"; info "$label/$dimm_name label=$value"; }
        for kind in dimm_ce_count dimm_ue_count; do
            [[ -r $dimm/$kind ]] || continue
            read -r value < "$dimm/$kind" || value='unreadable'
            info "Raw EDAC $label/$dimm_name $kind=$value (may be included in controller count)."
            if [[ $value =~ ^[0-9]+$ ]]; then
                edac_seen=1
                if ((10#$value > 0)); then
                    if [[ $kind == dimm_ue_count ]]; then
                        health_finding FAIL "$label/$dimm_name recorded $value uncorrected ECC error(s); investigate this DIMM and event."
                    else
                        health_finding WARNING "$label/$dimm_name recorded $value corrected ECC error(s); a cumulative count is not proof of a currently failing DIMM."
                    fi
                fi
            fi
        done
    done
done
if ((edac_seen == 0)); then
    health_finding INFO 'EDAC controller counters are unavailable; absence of counters is not a memory health pass.'
fi

# Prefer current-boot journal records. dmesg is a fallback on non-systemd live images.
log_source='current-boot journalctl kernel log'
log_output=''
log_status=1
if command -v journalctl >/dev/null 2>&1; then
    log_output=$(journalctl -k -b --no-pager -o short-iso 2>&1)
    log_status=$?
fi
if ((log_status != 0)); then
    log_source='dmesg kernel ring buffer'
    if command -v dmesg >/dev/null 2>&1; then
        log_output=$(dmesg --color=never 2>&1)
        log_status=$?
    fi
fi
if ((log_status == 0)); then
    matches=$(grep -Ei 'EDAC.*(error|[[:space:]]CE([[:space:]]|$)|[[:space:]]UE([[:space:]]|$))|ECC|MCE.*(error|exception)|machine check|memory.*(parity|uncorrect|corrected|hardware error)' <<< "$log_output" || true)
    info "Raw memory-related evidence from $log_source:"
    if [[ -n $matches ]]; then
        printf '%s\n' "$matches"
        if grep -Eiq 'uncorrect(ed|able)|fatal.*(ECC|memory|MCE)|MCE.*fatal' <<< "$matches"; then
            health_finding FAIL 'Kernel log records an uncorrected or fatal memory-related event in this boot; correlate timestamp and DIMM location.'
        elif grep -Eiq 'corrected|EDAC.*error|EDAC.*[[:space:]]CE([[:space:]]|$)|ECC.*error|MCE|machine check' <<< "$matches"; then
            health_finding WARNING 'Memory-related kernel events were logged in this boot; corrected events are historical evidence, not proof of a currently failing DIMM.'
        else
            health_finding INFO 'Memory-related kernel messages were found; inspect their context above.'
        fi
    else
        info 'No matching memory-related messages in the accessible kernel log.'
    fi
else
    health_finding INFO 'Kernel memory messages could not be read from journalctl or dmesg.'
fi

health_finish MEMORY
