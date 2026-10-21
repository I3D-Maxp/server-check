#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

health_init
mdstat=${SERVER_CHECK_MDSTAT:-/proc/mdstat}
if [[ -r $mdstat ]]; then
    info "Raw Linux software RAID state ($mdstat):"
    cat "$mdstat"
    while IFS= read -r pattern; do
        [[ $pattern == *_* ]] && health_finding WARNING "Software RAID member pattern $pattern shows a missing member."
    done < <(grep -Eo '\[[U_]+\]' "$mdstat" || true)
    grep -Eiq '(^|[[:space:]])(inactive|recovery|resync|reshape)[[:space:]]' "$mdstat" &&
        health_finding WARNING 'Software RAID is inactive or has an operation in progress; inspect mdstat above.'
else
    health_finding INFO 'Linux software RAID state is unavailable.'
fi

if command -v mdadm >/dev/null 2>&1; then
    arrays=$(mdadm --detail --scan 2>&1)
    scan_status=$?
    info "Raw mdadm array discovery (exit $scan_status):"
    printf '%s\n' "$arrays"
    if ((scan_status != 0)); then
        health_finding WARNING 'mdadm array discovery failed; software RAID could not be fully assessed.'
    else
        while IFS= read -r line; do
            [[ $line == ARRAY\ * ]] || continue
            read -r _ array _ <<< "$line"
            [[ $array == /dev/* ]] || continue
            detail=$(mdadm --detail "$array" 2>&1)
            detail_status=$?
            info "Raw mdadm detail for $array (exit $detail_status):"
            printf '%s\n' "$detail"
            if ((detail_status != 0)); then
                health_finding WARNING "$array detail could not be read."
            elif grep -Eiq 'State[[:space:]]*:[[:space:]]*.*(inactive|failed|degraded)' <<< "$detail"; then
                health_finding FAIL "$array reports an inactive, failed, or degraded state."
            elif grep -Eiq 'State[[:space:]]*:[[:space:]]*.*(recover|resync|reshape|check)' <<< "$detail"; then
                health_finding WARNING "$array reports an operation in progress; inspect its state."
            elif grep -Eiq 'State[[:space:]]*:[[:space:]]*(clean|active)' <<< "$detail"; then
                health_finding OK "$array reports a clean or active state."
            else
                health_finding WARNING "$array state was not recognized; inspect mdadm detail."
            fi
        done <<< "$arrays"
    fi
fi

vendor_seen=0
for tool in storcli perccli ssacli; do
    command -v "$tool" >/dev/null 2>&1 || continue
    ((vendor_seen += 1))
    if [[ $tool == ssacli ]]; then module=ssacli; else module=storcli; fi
    output=$(RAID_CLI="$tool" bash "$(dirname -- "${BASH_SOURCE[0]}")/raid-vendors/$module.sh" 2>&1)
    module_status=$?
    printf '%s\n' "$output"
    if grep -Eq '^\[FAIL\] VERDICT ' <<< "$output"; then
        health_finding FAIL "$tool reported a RAID controller or drive failure."
    elif grep -Eq '^\[WARNING\] VERDICT ' <<< "$output" || ((module_status != 0)); then
        health_finding WARNING "$tool reported a RAID warning or its query failed."
    elif grep -Eq '^\[OK\] VERDICT ' <<< "$output"; then
        health_finding OK "$tool reported healthy accessible RAID state."
    else
        health_finding INFO "$tool did not expose usable RAID health state."
    fi
done

if ((vendor_seen == 0)) && command -v lspci >/dev/null 2>&1; then
    pci_raid=$(lspci -nn 2>/dev/null | grep -Ei 'RAID bus controller|MegaRAID|Smart Array|PERC' || true)
    if [[ -n $pci_raid ]]; then
        info 'Raw PCI RAID-controller evidence:'
        printf '%s\n' "$pci_raid"
        health_finding WARNING 'A RAID controller is visible but no supported read-only vendor utility is installed; virtual disks could not be tested.'
    fi
fi

if ((health_rank == 0)); then
    health_finding INFO 'No evaluable RAID array or supported controller health data was available.'
fi
health_finish RAID
