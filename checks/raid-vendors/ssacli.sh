#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../common.sh"
health_init
tool=${RAID_CLI:-ssacli}

for query in status config; do
    output=$("$tool" ctrl all show "$query" 2>&1)
    status=$?
    info "Raw $tool controller/drive $query (exit $status):"
    printf '%s\n' "$output"
    if ((status != 0)); then
        health_finding WARNING "$tool controller $query query failed; RAID health is incomplete."
        continue
    fi
    if grep -Eiq 'No controllers detected|No controllers found' <<< "$output"; then
        health_finding INFO "$tool reports no supported controller."
        continue
    fi
    while IFS= read -r line; do
        [[ $line =~ (Controller|Cache|Battery|Capacitor)[[:space:]]+Status:|logicaldrive[[:space:]]|physicaldrive[[:space:]] ]] || continue
        if grep -Eiq 'failed|offline|critical|not[[:space:]]+ok' <<< "$line"; then
            health_finding FAIL "$tool: $line"
        elif grep -Eiq 'degraded|rebuild|recover|predictive|interim|warning' <<< "$line"; then
            health_finding WARNING "$tool: $line"
        elif grep -Eiq ':[[:space:]]*OK|,[[:space:]]*OK[),]|[[:space:]]OK[)]' <<< "$line"; then
            health_finding OK "$tool: $line"
        fi
    done <<< "$output"
done
health_finish "${tool^^}"
