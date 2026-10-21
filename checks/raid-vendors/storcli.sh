#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../common.sh"
health_init
tool=${RAID_CLI:-storcli}

for target in /call /call/vall; do
    output=$("$tool" "$target" show 2>&1)
    status=$?
    info "Raw $tool $target show (exit $status):"
    printf '%s\n' "$output"
    if ((status != 0)) || grep -Eiq '^Status[[:space:]]*=[[:space:]]*(Failure|Failed)' <<< "$output"; then
        health_finding WARNING "$tool $target query failed; controller or virtual-disk health is incomplete."
        continue
    fi
    if grep -Eiq 'Number of Controllers[[:space:]]*=[[:space:]]*0|No Controller' <<< "$output"; then
        health_finding INFO "$tool reports no supported controller."
        break
    fi
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*[0-9]+/[0-9]+[[:space:]] ]]; then
            read -r vd type state _ <<< "$line"
            case $state in
                Optl|Optimal) health_finding OK "$tool virtual disk $vd state=$state." ;;
                Dgrd|Pdgd|Degraded|Partially) health_finding WARNING "$tool virtual disk $vd state=$state." ;;
                OfLn|Offline|Failed) health_finding FAIL "$tool virtual disk $vd state=$state." ;;
                *) health_finding WARNING "$tool virtual disk $vd has unrecognized state=$state." ;;
            esac
        elif [[ $line =~ ^[[:space:]]*Controller[[:space:]]+Status[[:space:]]*=[[:space:]]*(.*) ]]; then
            state=${BASH_REMATCH[1]}
            case $state in
                Failure|Failed|Critical|Offline) health_finding FAIL "$tool controller status=$state." ;;
                Degraded|Warning) health_finding WARNING "$tool controller status=$state." ;;
                Optimal|OK|Success) health_finding OK "$tool controller status=$state." ;;
            esac
        fi
    done <<< "$output"
done
health_finish "${tool^^}"
