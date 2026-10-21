# Supported tools

Run `./server-check.sh --dependencies` on Linux to see which commands are available. Missing optional tools reduce coverage; missing launcher basics such as `bash`, `mktemp`, `tee`, or `timeout` in auto mode prevent a complete run.

| Area | Commands and data | Status |
| --- | --- | --- |
| Launcher/report | bash, coreutils (`date`, `mktemp`, `timeout`), `tee`, `grep`, `hostname` | Required for launcher or auto mode |
| USB report choice | `lsblk`, `findmnt` | Required only for `REPORT_TARGET=usb` |
| SATA/SAS SMART | `lsblk`, `smartctl` | Supported, read-only |
| NVMe health | `lsblk`, `nvme` | Supported, read-only |
| Linux software RAID | `/proc/mdstat`, `mdadm` | Supported, read-only |
| Broadcom/LSI and Dell PERC RAID | `storcli` or `perccli` | Supported status queries; utility supplied separately |
| HPE Smart Array RAID | `ssacli` | Supported status queries; utility supplied separately |
| ECC/EDAC | `/sys/devices/system/edac/mc`, `journalctl` or `dmesg` | Supported where exposed |
| Hardware errors | `journalctl`, `dmesg` | Supported current-boot evidence |
| Sensors and BMC | `sensors`, `ipmitool` | Supported where exposed |
| Inventory | `lscpu`, `free`, `lspci`, `ip`, `ethtool`, `dmidecode`, `lshw` | Optional |

Vendor RAID command forms follow the [Broadcom StorCLI manual](https://docs.broadcom.com/doc/12352476) and [HPE SSACLI command examples](https://www.hpe.com/jp/ja/collaterals/collateral.a50013828jpn.html). Linux md status uses [mdadm detail](https://man7.org/linux/man-pages/man8/mdadm.8.html).
