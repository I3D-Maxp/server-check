# Server-check user guide

This guide describes the toolkit on an existing Linux installation or live Linux environment. The [ISO build definition](iso-build.md) is now available; an actual ISO build and BMC boot have not yet been validated.

## Quick start on Linux

1. Copy the `server-check` directory to the Linux environment and open a shell in that directory. Use root when possible so disk health, EDAC, kernel logs, sensors, and BMC data are accessible.
2. Check which utilities are available:

   ```bash
   bash server-check.sh --dependencies
   ```

3. Run the configured suite manually. The supplied config is in manual mode and writes JSON, text, and a raw evidence report under `/tmp/server-check-reports`. Python 3 is required for the structured reports:

   ```bash
   bash server-check.sh
   echo $?
   ```

4. At completion, read the `Overall` and per-check verdicts, then open the fixed reports or the unique raw evidence path printed after `Report:`:

   ```bash
   less /tmp/server-check-reports/report.txt
   less /tmp/server-check-reports/report.json
   ```

   The raw report has a unique filename printed by the launcher. Both fixed reports include the evidence behind each finding. Save any `/tmp` report elsewhere before rebooting.

The toolkit does not format disks, change RAID or firmware, run destructive storage tests, or reboot. It writes only the report to the selected destination.

## Run a specific check

Use `--list` to see valid check names. Repeat `--check` to run several checks in one report:

```bash
bash server-check.sh --list
bash server-check.sh --check cpu --check memory
bash server-check.sh --check storage --check raid
bash server-check.sh --check hardware-errors --check sensors
bash server-check.sh --check smart
```

`storage` includes block-device inventory and SMART/NVMe health. `smart` runs health without the general storage inventory. Explicit `--check` selections run even if their `RUN_*` switch is `no` in the config. `--all` runs every supported safe check. The CPU, network, PCIe, firmware, and BMC checks mainly provide inventory; PCIe/AER health events are evaluated by `hardware-errors`.

## Choose where the report goes

| Choice | Command | Behavior |
| --- | --- | --- |
| Temporary local storage | `bash server-check.sh --report-target temp` | Creates a report under `${TMPDIR:-/tmp}/server-check-reports`; it may disappear after reboot. |
| Mounted USB storage | `bash server-check.sh --report-target usb` | Selects an already-mounted, writable USB filesystem and creates a `server-check-reports` directory there. It does not mount a device. If none qualifies, the command exits 3 without falling back to an internal disk. |
| Explicit path | `bash server-check.sh --output-dir /mnt/diag-usb/reports` | Writes to that absolute path. Its parent directory must already exist. Choose the mount deliberately; an explicit path can point to a server disk. |

The completion summary gives the exact raw report filename and the fixed `report.json` and `report.txt` paths. New report files use restrictive permissions because inventory may contain serial numbers and addresses. There is no network upload option yet.

## Configure a repeatable run

The supplied [config file](../config/server-check.conf) is safe for a manual first run: `MODE=interactive`, `AUTO_START=no`, all read-only checks enabled, and reports under `/tmp`. Copy it before changing settings:

```bash
cp config/server-check.conf /tmp/server-check-auto.conf
```

Edit the copy as literal `KEY=VALUE` lines. Do not add shell quotes or shell commands; the launcher never executes the file. A sample for an unattended run that saves to a mounted USB filesystem is:

```text
MODE=auto
AUTO_START=yes
REPORT_TARGET=usb
RUN_CPU=yes
RUN_MEMORY=yes
RUN_STORAGE=yes
RUN_SMART=yes
RUN_RAID=yes
RUN_NETWORK=yes
RUN_SENSORS=yes
RUN_PCIE=yes
RUN_LOG_ANALYSIS=yes
CHECK_TIMEOUT_SECONDS=300
```

These are the main settings:

| Setting | Meaning |
| --- | --- |
| `MODE=interactive|auto` | Manual invocation or an unattended configured run. “Interactive” means the technician chooses when and what to run; there is no menu prompt. |
| `AUTO_START=yes|no` | Whether `--boot` may launch the auto run. It has no effect on a direct `bash server-check.sh` invocation. |
| `RUN_CPU`, `RUN_MEMORY`, `RUN_STORAGE`, `RUN_SMART`, `RUN_RAID`, `RUN_NETWORK`, `RUN_SENSORS`, `RUN_PCIE`, `RUN_LOG_ANALYSIS` | Each accepts `yes` or `no` for the configured suite. `RUN_STORAGE` controls inventory and `RUN_SMART` controls health queries. |
| `RUN_FIRMWARE`, `RUN_BMC` | Optional inventory checks, also `yes` or `no`. |
| `REPORT_TARGET=temp|usb|path` | Destination selection described above. |
| `REPORT_LOCATION=/absolute/path` | Used when `REPORT_TARGET=path`. The default is `/tmp/server-check-reports`. |
| `REPORT_FORMAT=both|text` | `both` (default) writes JSON and human-readable text through the Python reporter; `text` keeps only the unique legacy raw report. |
| `CHECK_TIMEOUT_SECONDS=300` | Per-check limit in auto mode, from 1 to 86400 seconds. No long-running stress tests are included. |

Run with a copied config:

```bash
bash server-check.sh --config /tmp/server-check-auto.conf
```

Command-line options override the file for that run:

```bash
bash server-check.sh --config /tmp/server-check-auto.conf --mode interactive --set RUN_RAID=no --report-target temp
```

`--set KEY=VALUE` can override any supported config key and can be repeated. `--output-dir` selects an explicit path; if both `--output-dir` and `--report-target` are supplied, the explicit `--report-target` determines the destination type. `SERVER_CHECK_CONFIG` can supply a config path when `--config` is absent; `SERVER_CHECK_REPORT_DIR` can override the configured path.

## Run unattended on an existing Linux console

To try the boot workflow without mounting the ISO, use the wrapper on a terminal:

```bash
bash unattended.sh --config /tmp/server-check-auto.conf
```

The config must contain `MODE=auto` and `AUTO_START=yes`. The wrapper invokes the safe suite without prompts, prints a completion summary, and leaves a shell available on an attached terminal. A failed or timed-out individual check is recorded and later checks continue. If no terminal is attached, the wrapper returns the diagnostic status to its caller. The ISO build and shell handoff still need validation on Linux and physical hardware; see the [ISO guide](iso-build.md).

Inside the completion shell, `echo "$SERVER_CHECK_EXIT_STATUS"` shows the diagnostic exit code.

For a one-off unattended run without changing the config file:

```bash
bash unattended.sh --mode auto --set AUTO_START=yes --report-target temp
```

## Read the results

The report contains a block for each selected check, raw evidence, findings, and a final summary. For storage, look for `VERDICT DEVICE /dev/...` lines before the overall storage verdict.

| Result | Interpretation | Exit status |
| --- | --- | --- |
| `OK` | No explicit fault in the accessible health data | 0 |
| `INFO` | Inventory or no usable health data | 0 |
| `WARNING` | A concerning finding, historical error, or unavailable test | 1 |
| `FAIL` | An explicit failure signal or serious uncorrected/fatal event | 2 |
| Toolkit/runtime error | Invalid settings, required launcher tool missing, or report destination/write failure | 3 |

The exit status is the highest severity across the selected checks. A corrected ECC event or cumulative SMART error count merits investigation but does not, by itself, prove an active component failure. An `OK` result covers only data the tools could read. Compare `WARNING` and `FAIL` lines with the raw output and timestamps before replacing hardware.

## If a check cannot run

Run `bash server-check.sh --dependencies` and look for `MISSING` utilities. A disk behind hardware RAID may not be visible to `smartctl`; use the appropriate read-only RAID utility if available. If device access is denied, run as root or check the live environment's permissions. If `--report-target usb` exits 3, verify that the USB filesystem is already mounted read-write and try again. The toolkit does not initialize or mount storage for you.

For physical-server verification, follow the [manual test procedure](linux-testing.md). See [supported tools](supported-tools.md) and [unattended requirements](unattended-mode.md) for deeper details.
