#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

show_command 'Local BMC identity (may require root)' ipmitool mc info
show_command 'Chassis status (may require root)' ipmitool chassis status
info 'VERDICT BMC: Local BMC information only; sensor health is evaluated in sensors.'
