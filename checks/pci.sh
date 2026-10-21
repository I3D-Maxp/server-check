#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

show_command 'PCIe device inventory' lspci -D -nn
info 'VERDICT PCI: Inventory only; PCIe errors are evaluated in hardware-errors.'
