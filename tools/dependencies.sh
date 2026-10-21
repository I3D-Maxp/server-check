#!/usr/bin/env bash
# Print availability of supported read-only diagnostic utilities.
set -u
printf 'Supported tools (availability on this host)\n'
printf 'Core: bash, date, hostname, mktemp, tee, grep, lsblk, timeout, findmnt\n'
printf 'Health: smartctl, nvme, mdadm, storcli, perccli, ssacli, sensors, ipmitool, journalctl, dmesg\n'
printf 'Inventory: lscpu, free, lspci, ip, ethtool, dmidecode, lshw\n\n'
for tool in bash date hostname mktemp tee grep lsblk timeout findmnt smartctl nvme mdadm storcli perccli ssacli sensors ipmitool journalctl dmesg lscpu free lspci ip ethtool dmidecode lshw; do
    if path=$(command -v "$tool" 2>/dev/null); then
        printf 'AVAILABLE %-12s %s\n' "$tool" "$path"
    else
        printf 'MISSING   %-12s\n' "$tool"
    fi
done
