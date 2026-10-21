#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

show_command 'Machine manufacturer, model, and serial (may require root)' dmidecode --type system
show_command 'System firmware information (may require root)' dmidecode --type bios
show_command 'Hardware summary' lshw -short
info 'VERDICT FIRMWARE: Inventory only; firmware health is not classified.'
