# server-check

Read-only Linux server diagnostics with a Debian live-build ISO definition for BMC virtual media. The shell launcher supports manual checks and a configured unattended run. The ISO build and real boot still need validation on a Linux build host.

**ISO:** [Build and boot guide](docs/iso-build.md) gives exact build, checksum, QEMU, BMC, and report retrieval steps.

**Start here:** [User guide](docs/user-guide.md) for setup, commands, configuration, reports, and result interpretation.

**Reports:** [Increment 4 reporting guide](docs/reporting-framework.md) describes the PASS/WARN/FAIL JSON and text reports. The unattended ISO writes `/reports/report.json` and `/reports/report.txt` through its approved RAM or USB destination.

**Autonomous iDRAC 9 platform design:** [Architecture](docs/platform-architecture.md), [repository structure](docs/platform-repository-structure.md), [implementation plan](docs/platform-implementation-plan.md), and [technology decisions](docs/platform-technology-decisions.md). The [server inventory template](server-list.yaml) is intentionally empty. Redfish deployment, Python health orchestration, and HTTP report collection are planned phases; the current ISO and Bash toolkit remain the working baseline.

## Run

```bash
./server-check.sh
./server-check.sh --list
./server-check.sh --check storage --check memory
./server-check.sh --check hardware-errors --check sensors --output-dir /mnt/usb/reports
./server-check.sh --mode auto --config config/server-check.conf
./server-check.sh --boot --config config/server-check.conf
./server-check.sh --dependencies
./server-check.sh --mode auto --set RUN_RAID=no --report-target temp
./server-check.sh --mode auto --report-target usb
./unattended.sh --config config/server-check.conf
```

The default report directory is `${TMPDIR:-/tmp}/server-check-reports`, which works when the toolkit itself is on read-only media. The supplied [configuration](config/server-check.conf) uses `/tmp/server-check-reports`. `REPORT_TARGET=temp` uses that temporary directory; `REPORT_TARGET=usb` chooses a filesystem already mounted read-write on a USB-transport disk and creates `server-check-reports` there; `REPORT_TARGET=path` uses `REPORT_LOCATION`. USB detection never mounts or writes to an internal server disk. If no writable USB mount exists, the run stops with exit 3 instead of silently falling back. `--output-dir` selects an explicit path; `--report-target` and `--set KEY=VALUE` override config settings. Copy temporary reports off the live environment before rebooting. Reports can contain addresses and serial numbers; new report files are created with restrictive permissions. Run as root for the fullest device, EDAC, log, and BMC access.

## Unattended and manual operation

`MODE=interactive` is the default manual CLI mode: a technician starts the launcher and can use `--check NAME` for one or more checks. `MODE=auto` runs every enabled safe check without prompts and gives each check a `CHECK_TIMEOUT_SECONDS` limit. A failed or timed-out check is recorded and the remaining checks run. The final report and console show an overall verdict and a verdict for every selected check. The ISO's tty1 service runs `iso/runtime/entrypoint.sh`; `./unattended.sh` is a manual wrapper. Both leave an interactive shell on an attached terminal after completion. Diagnostics start only when `AUTO_START=yes` and `MODE=auto`. Without a terminal, the wrapper returns the diagnostic exit status.

The configuration is literal `KEY=VALUE` text, never executed as shell code. It supports `MODE`, `AUTO_START`, `RUN_CPU`, `RUN_MEMORY`, `RUN_STORAGE`, `RUN_SMART`, `RUN_RAID`, `RUN_NETWORK`, `RUN_SENSORS`, `RUN_PCIE`, `RUN_LOG_ANALYSIS`, `RUN_FIRMWARE`, `RUN_BMC`, `REPORT_FORMAT`, `REPORT_TARGET`, `REPORT_LOCATION`, and `CHECK_TIMEOUT_SECONDS`. `RUN_STORAGE` controls block-device inventory and `RUN_SMART` controls SMART/NVMe health; the storage check runs once when both are enabled. `REPORT_FORMAT=both` is the default and requires Python 3; `text` keeps only the legacy raw report. Individual `--check` selections override the run switches for that invocation. `--check smart` runs health without general storage inventory. CLI `--mode`, `--report-target`, `--output-dir`, and repeatable `--set KEY=VALUE` take precedence over the file.

To enable unattended diagnostics outside the ISO, set `MODE=auto` and `AUTO_START=yes` in a copied config. Use `--config /path/to/config` or `SERVER_CHECK_CONFIG` to select it. The ISO definition starts diagnostics from a systemd console service and selects a mounted, labelled USB report volume or RAM. Build and boot validation on Linux is still required; RAM reports are lost on reboot.

Each check prints raw relevant evidence followed by a verdict. The complete report ends with the highest observed verdict across the selected checks:

| Verdict | Meaning | Launcher exit |
| --- | --- | --- |
| `OK` | Available health data contains no explicit fault signal | 0 |
| `INFO` | Inventory only or no usable health data | 0 |
| `WARNING` | A concerning or historical finding, or a device that could not be tested | 1 |
| `FAIL` | An explicit health failure, critical sensor signal, or uncorrected/fatal hardware event | 2 |
| Runtime error | Invalid configuration, missing launcher dependency, or report destination failure | 3 |

The summary covers only devices and sources accessible during that run. `OK` does not guarantee that all hardware is healthy. An inventory-only check emits `INFO`. The structured report maps the check to `PASS` only when its inventory was collected and explicitly says that inventory is not a health claim. A logged event can warrant investigation without proving that a component is failing now.

## Health checks

| Check | Evaluation | Raw evidence and limits |
| --- | --- | --- |
| `storage` | Per-device SATA/SAS SMART overall health and threshold flags; ATA attributes 5, 187, 197, 198, 199; SAS grown defects; NVMe critical warning, device-reported spare threshold, media errors, and endurance estimate | `lsblk`, `smartctl -a -n standby`, `nvme log smart` (with a `nvme smart-log` fallback). Every enumerated disk gets a verdict. Untested disks are identified. Cumulative error counts cause a warning, not an automatic failure. Sleeping disks are not awakened for SMART. Hardware RAID may hide member drives. |
| `memory` | EDAC controller and DIMM corrected/uncorrected counts; relevant current-boot kernel messages | `/sys/devices/system/edac/mc`, `journalctl` or `dmesg`. Corrected counts are cumulative and do not prove a DIMM is currently failing. An uncorrected event is a serious recorded event, not a DIMM diagnosis by itself. |
| `hardware-errors` | PCIe/AER, MCE, storage I/O, and memory/ECC messages | Both `journalctl -k -b` and `dmesg` are checked where readable. Relevant raw lines are shown. The same event may appear in both sources. An I/O error or corrected event is a warning for investigation; explicit uncorrected/fatal PCIe, machine-check, or memory events are failures. |
| `sensors` | Temperature, fan, voltage, and BMC status where exposed | `sensors` and `ipmitool sensor list`. Explicit `ALARM`/`FAULT` flags, reported temperature high/critical limits, fan minimums, and BMC non-critical/critical status codes affect the verdict. The scripts do not invent numeric thresholds. |
| `raid` | Linux md array state; supported HPE Smart Array and Broadcom/LSI/Dell PERC controller and virtual-disk states | `mdadm --detail`, `ssacli ... show`, and `storcli`/`perccli ... show` are read-only. Raw command output precedes findings. Unsupported controllers or failed queries are identified; generic disk SMART cannot establish hidden member health. |

Other checks (`cpu`, `network`, `pci`, `firmware`, `bmc`) currently provide read-only inventory with `INFO` verdicts. RAID vendor readers live in separate modules under [checks/raid-vendors](checks/raid-vendors/README.md); other vendors remain future work. A hardware RAID utility may require separate distribution and is not bundled here.

Install the applicable utilities for full coverage: `lsblk` (util-linux), `smartctl` (smartmontools), `nvme` (nvme-cli), `journalctl` or `dmesg`, `sensors` (lm-sensors), and `ipmitool`. Other inventory tools are optional. A missing utility or denied device access appears in the report; the other checks continue.

See [supported tools](docs/supported-tools.md) for the command inventory and [Linux testing](docs/linux-testing.md) for a real-server procedure. `./server-check.sh --dependencies` prints availability on the current host without starting diagnostics.

## Safety

All current commands read system information. They do not format or initialize disks, change partitions or RAID settings, update firmware or BMC configuration, run destructive storage tests, or reboot. Any future potentially destructive test must be a separate command requiring explicit confirmation.

The launcher uses a fixed allowlist of read-only checks. Destructive tests must never be added to unattended selection. Longer or intensive tests must have explicit enable switches and duration limits before they can join an unattended suite. The current checks are passive reads; `CHECK_TIMEOUT_SECONDS` limits how long each auto check may run.

## Development and testing

```bash
bash -n server-check.sh checks/*.sh tests/*.sh iso/runtime/*.sh tools/*iso.sh
bash tests/test_launcher.sh
bash tests/test_health.sh
bash tests/test_unattended.sh
bash tests/test_increment3.sh
bash tests/test_iso.sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

The shell health tests use mocked utilities and EDAC counters; they do not access server hardware. Run the full toolkit on representative physical hardware before relying on it operationally. The earlier Python inventory CLI under `src/server_check/` and its tests are retained. The Bash launcher now calls the independent Python reporting package when `REPORT_FORMAT=both`.

Known limits: vendor RAID output varies by controller firmware and CLI version; unsupported controllers and hidden member drives remain untested. Sensor numeric parsing covers common lm-sensors temperature, fan, and voltage lines, while other formats still rely on explicit alarm flags or BMC status. EDAC and kernel messages can be cumulative or historical. USB persistence requires media that is already mounted read-write; the toolkit does not mount it. Network upload remains future work. The ISO still needs a real Linux build and boot test.

Physical server validation still needed:

1. Run the full launcher as root and as an unprivileged user; confirm device enumeration, permission messages, and report permissions.
2. Compare SMART verdicts with `smartctl` output from real SATA and SAS disks, including sleeping disks and drives behind pass-through controllers. Check that hidden RAID member drives are marked untested.
3. Compare NVMe verdicts with both supported nvme-cli command forms and real controller health fields, including namespace behavior.
4. Confirm EDAC controller/DIMM paths and counters on an ECC-equipped server, and compare current-boot memory messages with the memory verdict.
5. Confirm `journalctl` and `dmesg` matching against real AER, MCE, storage I/O, and ECC messages when such evidence exists. Do not induce a hardware fault for this test.
6. Check lm-sensors and BMC fan, temperature, voltage, and power-supply status against hardware-reported thresholds and status codes.
7. Build the current ISO definition on Debian 13 and validate unattended boot through BMC virtual media: auto start, complete or partial report, continued checks after a tool fails, writable report location, and a persistent results screen or shell.

The SMART power-mode and exit-code behavior follows the [smartctl manual](https://manpages.debian.org/trixie/smartmontools/smartctl.8.en.html). The current NVMe command and legacy alias are described in the [nvme-cli documentation](https://github.com/linux-nvme/nvme-cli/blob/master/Documentation/nvme-smart-log.txt).
