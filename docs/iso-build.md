# Build and use the diagnostic ISO

The image definition targets Debian 13 (trixie), x86_64, using Debian live-build. It requests an ISO hybrid image with Syslinux BIOS boot and GRUB UEFI boot. The live root is read-only media with RAM-backed runtime state. The build configuration is repeatable; exact byte-for-byte output also depends on the Debian package snapshot used by the build host. The first real ISO build and boot still need Linux validation.

## Build on Debian 13 x86_64

From the repository root:

```bash
sudo apt update
sudo apt install -y live-build debootstrap xorriso squashfs-tools \
  syslinux-common isolinux grub-efi-amd64-bin mtools dosfstools
bash tools/build-iso.sh --check-deps
sudo bash tools/build-iso.sh
```

The script creates an isolated `build/iso-work.*` directory, runs `lb config` and `lb build`, copies the image to `dist/server-check-amd64.iso`, writes `dist/server-check-amd64.iso.sha256`, and validates the ISO. It fails before building when required host commands are missing. A failed build leaves its workspace for inspection. It does not download proprietary RAID utilities.

To change the visible boot-menu countdown from its 10-second default:

```bash
sudo ISO_BOOT_TIMEOUT_SECONDS=15 bash tools/build-iso.sh
```

The accepted range is 1–60 seconds. The same value is applied to the BIOS and UEFI menus.

## Verify the image

```bash
(cd dist && sha256sum -c server-check-amd64.iso.sha256)
bash tools/validate-iso.sh dist/server-check-amd64.iso
```

Validation checks the checksum, BIOS and UEFI El Torito entries, the live filesystem, menus, toolkit, boot config, and autostart unit. A successful structural check is not a boot test.

## QEMU boot tests

Install the QEMU/OVMF packages on the Linux test host:

```bash
sudo apt install -y qemu-system-x86 ovmf
```

Legacy BIOS (SeaBIOS):

```bash
qemu-system-x86_64 -machine q35 -m 4096 -cdrom dist/server-check-amd64.iso \
  -boot d -display none -vnc 127.0.0.1:1
```

UEFI with OVMF (the common Debian 4 MB firmware path):

```bash
cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/server-check-OVMF_VARS.fd
qemu-system-x86_64 -machine q35 -m 4096 -cdrom dist/server-check-amd64.iso \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=/tmp/server-check-OVMF_VARS.fd \
  -boot d -display none -vnc 127.0.0.1:1
```

Connect a VNC viewer to `127.0.0.1:5901`. No virtual hard disk is attached. If the OVMF filenames differ, locate them with `dpkg -L ovmf | grep -E 'OVMF_(CODE|VARS).*4M.*fd'`. Check that the menu is visible, automatic diagnostics begin after the countdown, and tty1 shows a shell and report path at completion. Secure Boot support has not been validated; test with Secure Boot disabled.

## BMC virtual media

In the BMC web console, open **Virtual Media**, attach `dist/server-check-amd64.iso` as a virtual CD/DVD, set one-time boot to that virtual drive, and boot the server. Keep the BMC console open to inspect tty1. The exact web controls depend on the BMC.

For a BMC that exposes the Redfish `VirtualMedia.InsertMedia` action and can fetch an HTTPS-hosted copy of the ISO, these are the mount commands. Obtain `BMC_VM_RESOURCE` from that BMC's VirtualMedia collection and host the ISO at `ISO_HTTPS_URL` where the BMC can reach it:

```bash
BMC_BASE='https://bmc.example'
BMC_VM_RESOURCE='/redfish/v1/Managers/1/VirtualMedia/CD'
ISO_HTTPS_URL='https://images.example/server-check-amd64.iso'
read -r -p 'BMC user: ' BMC_USER
read -r -s -p 'BMC password: ' BMC_PASS; printf '\n'
INSERT_ACTION=$(curl -ksS -u "$BMC_USER:$BMC_PASS" \
  "$BMC_BASE$BMC_VM_RESOURCE" | jq -r '.Actions["#VirtualMedia.InsertMedia"].target')
test -n "$INSERT_ACTION" && test "$INSERT_ACTION" != null
case "$INSERT_ACTION" in https://*) INSERT_URL=$INSERT_ACTION ;; /*) INSERT_URL="$BMC_BASE$INSERT_ACTION" ;; *) exit 1 ;; esac
curl -ksS -u "$BMC_USER:$BMC_PASS" -H 'Content-Type: application/json' \
  -X POST "$INSERT_URL" \
  --data "$(jq -n --arg image "$ISO_HTTPS_URL" '{Image:$image,Inserted:true}')"
```

Inspect the BMC response, then set one-time virtual-CD boot in its UI. Resource paths and accepted image URI schemes vary by vendor. The toolkit itself does not change BMC settings or boot order.

## Boot modes and overrides

| Menu entry | Action |
| --- | --- |
| Automatic Safe Diagnostics | Default after the countdown; launches the standard read-only suite and leaves a shell. |
| Interactive Diagnostics | Opens a shell without running checks; start them with `bash /opt/server-check/server-check.sh`. |
| Linux Rescue Shell | Opens a shell without starting the toolkit. Host filesystems are not mounted automatically. |

The menu permits kernel parameter editing before boot. The included `/etc/server-check/boot.conf` supplies defaults. The **last** matching `diag.*` kernel parameter overrides that file. For example, append these to the kernel line in the GRUB or Syslinux menu:

```text
diag.mode=auto diag.autostart=yes diag.profile=quick diag.report_location=tmp
```

Supported parameters are `diag.mode=auto|interactive|rescue`, `diag.autostart=yes|no`, `diag.profile=quick|standard|extended`, `diag.report_location=auto|tmp|usb|/absolute/path`, `diag.shutdown=never|poweroff|reboot`, `diag.network=yes|no`, and `diag.upload=no`. Upload is not implemented; `diag.upload=yes` is rejected. `diag.network` controls the network *diagnostic check*; it does not configure an interface or start DHCP. The quick profile skips firmware, BMC, and PCI inventory; standard runs all configured safe checks; extended runs the same passive checks with a longer timeout. No stress or destructive test is included.

For manual commands after boot, `bash /opt/server-check/server-check.sh --list` lists checks and `--check NAME`, `--config FILE`, `--set KEY=VALUE`, and `--output-dir DIR` override the toolkit configuration. `bash /opt/server-check/server-check.sh --dependencies` lists available tools.

## Reports and retrieval

Automatic selection uses a **mounted** USB disk or partition labelled `SERVER_REPORTS`, with a read-write filesystem and USB transport. Otherwise it writes to RAM-backed `/run/server-check/reports`. The live entry point makes `/reports` an alias to that approved destination and writes `/reports/report.json` and `/reports/report.txt`, plus a uniquely named raw report. `diag.report_location=/path` first checks an explicitly mounted, writable tmpfs or USB path; an internal disk or network mount is refused and selection falls back to the labelled USB or RAM. `diag.report_location=usb` also falls back to RAM when no approved USB mount exists. The image does not automatically mount discovered filesystems, including a labelled USB stick. BMC virtual CD/DVD media is not a report destination.

The summary prints the full raw filename and the two fixed paths. On tty1, inspect `less /reports/report.txt` or `less /reports/report.json`. To retrieve RAM reports through a separate USB stick, first verify the device with `lsblk -o PATH,TYPE,TRAN,LABEL,MOUNTPOINT`, then mount **only** the known USB partition and copy the files:

```bash
mkdir -p /mnt/server-reports
mount -o rw /dev/disk/by-label/SERVER_REPORTS /mnt/server-reports
cp -a /run/server-check/reports/report.json /run/server-check/reports/*.txt /mnt/server-reports/
sync
```

Do not run the mount command until the label has been confirmed on a USB device. A RAM report disappears on reboot. The raw filename includes a sanitized DMI serial or model, falling back to hostname, plus UTC time and a random suffix. `diag.shutdown=poweroff|reboot` is honored only when an approved non-RAM destination has both structured reports; the default is `never`.

## Local vendor RAID tools

To add an authorised proprietary CLI, put an executable named `storcli`, `perccli`, or `ssacli` under `iso/local/raid-tools/` before building. The build copies only those names into `/usr/local/sbin` inside the image. Obtain the tool and its redistribution rights yourself, and include any required libraries. Nothing is fetched or redistributed by default.

## Isolation and current limits

The image disables kernel md autodetection, configures mdadm not to auto-assemble host arrays, masks storage activation and automount services, and masks swap activation. It does not install LVM tools, mount host filesystems, or activate networking automatically. Some firmware and initramfs behavior still requires a real boot check. Hardware RAID may hide physical drives. The memory-test menu entry is omitted until an independently bootable BIOS/UEFI tester is validated with this image. Network upload remains future work.

Build and boot details follow the [Debian live-build manual](https://live-team.pages.debian.net/live-manual/html/live-manual.en.html), [live-build configuration reference](https://manpages.debian.org/trixie/live-build/lb_config.1.en.html), and [kernel RAID autodetection documentation](https://docs.kernel.org/admin-guide/md.html).
