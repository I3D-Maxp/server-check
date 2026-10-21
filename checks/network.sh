#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

show_command 'Network links' ip -brief link show
show_command 'Network addresses' ip -brief address show
if [[ -d /sys/class/net ]]; then
    info 'Interface operational state and negotiated speed (where exposed by the driver)'
    for path in /sys/class/net/*; do
        [[ -e $path ]] || continue
        name=${path##*/}
        state=unknown
        speed=unknown
        if [[ -r $path/operstate ]]; then
            read -r state < "$path/operstate" || state=unknown
        fi
        if [[ -r $path/speed ]]; then
            read -r speed < "$path/speed" 2>/dev/null || speed=unknown
            [[ -n $speed ]] || speed=unknown
        fi
        printf '%s: state=%s speed=%s Mb/s\n' "$name" "$state" "$speed"
    done
fi
info 'A down link may be intentionally disconnected; this inventory does not classify it as a failure.'
info 'VERDICT NETWORK: Link and address inventory only; a down port is not automatically a fault.'
