#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

health_init
sources_read=0
all_matches=''
pattern='AER:.*(error|corrected|uncorrected|fatal)|PCIe Bus Error|pcieport.*(error|fatal)|PCIe.*(error|fatal)|MCE.*(error|exception)|machine check|hardware error|I/O error|blk_update_request|nvme.*(error|timeout|reset)|ata[0-9]+.*(error|failed|exception)|scsi.*(medium error|hardware error)|EDAC.*(error|[[:space:]]CE([[:space:]]|$)|[[:space:]]UE([[:space:]]|$))|ECC|memory.*(parity|uncorrect|corrected|hardware error)'

scan_source() {
    local label=$1 output status matches
    shift
    if ! command -v "$1" >/dev/null 2>&1; then
        health_finding INFO "$label unavailable: $1 is not installed."
        return
    fi
    output=$("$@" 2>&1)
    status=$?
    if ((status != 0)); then
        health_finding INFO "$label could not be read (exit $status): $output"
        return
    fi
    if [[ -z $output || $output == *'-- No entries --'* || $output == *'No journal files were found'* ]]; then
        health_finding INFO "$label contains no usable entries; it cannot establish a clean hardware log."
        return
    fi
    ((sources_read += 1))
    matches=$(grep -Ei "$pattern" <<< "$output" || true)
    info "Raw relevant hardware messages from $label:"
    if [[ -n $matches ]]; then
        printf '%s\n' "$matches"
        all_matches+=$'\n'"$matches"
    else
        info 'No matching lines in this source.'
    fi
}

scan_source 'journalctl current-boot kernel log' journalctl -k -b --no-pager -o short-iso
scan_source 'dmesg kernel ring buffer' dmesg --color=never

if ((sources_read == 0)); then
    health_finding INFO 'Hardware kernel errors could not be evaluated: neither log source was readable.'
elif [[ -z $all_matches ]]; then
    health_finding OK 'No matching PCIe/AER, MCE, storage I/O, or ECC messages in the accessible current-boot logs.'
elif grep -Eiq '(AER|PCIe|MCE|machine check|ECC|EDAC|memory).*(uncorrected|uncorrectable|fatal)|(uncorrected|uncorrectable|fatal).*(AER|PCIe|MCE|machine check|ECC|EDAC|memory)' <<< "$all_matches"; then
    health_finding FAIL 'An uncorrected or fatal PCIe, machine-check, or memory event is logged; inspect the raw lines and timestamps.'
else
    health_finding WARNING 'Relevant hardware messages are logged. Corrected or historical events and I/O errors need correlation with current symptoms; they do not alone prove an active component failure.'
fi

info 'journalctl and dmesg can show the same event twice; this check does not count duplicates as independent faults.'
health_finish HARDWARE-ERRORS
