#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

show_command 'CPU topology and features' lscpu
info 'CPU health needs sensor and hardware-error correlation; inventory alone is not a health verdict.'
info 'VERDICT CPU: Inventory only; this check cannot establish CPU health.'
