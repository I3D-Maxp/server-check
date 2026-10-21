# Manual test on a physical Linux server

Use a maintenance window and a writable USB stick or a known writable mounted report path. These commands are read-only diagnostics; do not run unrelated controller setup commands.

1. Boot an existing Linux environment, log in as root, copy the toolkit to a suitable location, and run `bash -n server-check.sh unattended.sh checks/*.sh checks/raid-vendors/*.sh tools/*.sh`.
2. Run `./server-check.sh --dependencies`. Record missing utilities and install or stage only the packages needed for the hardware under test.
3. Run `./server-check.sh --check storage --check raid --check memory --check hardware-errors --check sensors --report-target temp`. Read each raw output block, per-device verdict, final summary, and exit status (`echo $?`). Compare disk counts with `lsblk` and controller counts with vendor inventory.
4. Compare SATA/SAS SMART findings with `smartctl -a -n standby /dev/DEVICE` and NVMe findings with `nvme log smart /dev/nvmeXnY`. Check an inaccessible or sleeping disk is identified as untested. Do not start self-tests or wake sleeping disks for this comparison.
5. Compare RAID state with `/proc/mdstat`, `mdadm --detail /dev/mdX`, and the appropriate installed vendor CLI's read-only `show` output. Verify virtual-disk/controller states and note any hidden member drives.
6. Compare EDAC counters with `/sys/devices/system/edac/mc`, log findings with `journalctl -k -b` or `dmesg`, and fan, temperature, and PSU findings with `sensors` and `ipmitool sensor list`. Check timestamps and distinguish old corrected events from current symptoms. Do not induce faults.
7. Mount a known USB filesystem read-write, then run `./server-check.sh --check pci --report-target usb`. Verify the reported path is on that USB mount. Remove the USB mount from consideration and confirm the command exits 3 without writing to an internal disk.
8. Use a copied config with `MODE=auto` and `AUTO_START=yes`. Run `./unattended.sh --config /path/to/copy.conf` on a terminal. Confirm no prompts, a complete summary, continued execution after a missing utility or permission failure, and a usable shell after completion. Copy the report away before rebooting.

The actual BMC virtual-media boot path, persistent console, and report export need validation after ISO integration. Network upload is future work.
