# Unattended mode requirement

The eventual live ISO must support a boot-and-let-go workflow for remote BMC virtual media. After Linux boots, it must invoke `server-check.sh --boot`, detect accessible hardware, run the configured safe suite without input, write a human-readable report, and leave a clear results screen or shell running for later inspection. It must not install to the server, reboot it, or power it down. Interactive/manual operation must remain available.

## Current launcher contract

- `config/server-check.conf` contains literal `KEY=VALUE` settings. `--config FILE` or `SERVER_CHECK_CONFIG` can select another file. Unknown keys and invalid values are rejected; the file is never sourced as a script.
- `MODE=auto` runs the configured suite unattended. `MODE=interactive` permits manual invocation of the full configured suite or individual `--check NAME` selections. No menu or prompt is required.
- `AUTO_START=yes` together with `MODE=auto` permits `--boot` to run the suite. Otherwise `--boot` exits cleanly and leaves the decision to the technician or boot environment.
- `RUN_CPU`, `RUN_MEMORY`, `RUN_STORAGE`, `RUN_SMART`, `RUN_RAID`, `RUN_NETWORK`, `RUN_SENSORS`, `RUN_PCIE`, `RUN_LOG_ANALYSIS`, `RUN_FIRMWARE`, and `RUN_BMC` accept `yes` or `no`. Storage inventory and SMART health can be enabled independently.
- `REPORT_FORMAT=both` (default) writes `report.json` and `report.txt` through Python 3 as well as a unique raw evidence report; `text` preserves the earlier raw-only mode. `REPORT_TARGET=temp|usb|path` chooses a local temporary directory, an already-mounted writable USB filesystem, or the explicit `REPORT_LOCATION`. A USB search never considers non-USB disks and never mounts media. New files have restrictive permissions. The console summary names the report paths.
- `CHECK_TIMEOUT_SECONDS` limits each check in auto mode. A check with a missing verdict, nonzero exit, or timeout is shown at least as `WARNING`; a reported `FAIL` is preserved. Later checks still run. The overall verdict is the highest severity observed. Exit status is 0 for `OK`/`INFO`, 1 for `WARNING`, 2 for `FAIL`.
- The launcher executes only its fixed list of read-only check modules. Destructive checks must never be placed in auto selection. Invalid configuration and report failures return 3.

## Boot integration acceptance criteria

1. Mount the ISO through BMC virtual media and boot without installing onto local disks.
2. Linux boots without technician input and starts the toolkit when auto start is configured.
3. The configured checks run without interaction. A failing, missing, or timed-out check leaves evidence in the report and does not prevent later checks.
4. The completed console prominently displays `SERVER DIAGNOSTIC COMPLETE`, overall and per-check verdicts, and the report path.
5. The system stays powered on at a usable results console or shell after completion, regardless of diagnostic exit status.
6. Manual operation remains possible when auto start is disabled or after the automatic run.
7. The report destination is writable despite read-only boot media, and there is a documented way to retrieve reports before reboot. `/tmp` is an interim volatile destination.
8. Only non-destructive checks run automatically. Any future long or intensive test needs an explicit enable setting and duration limit. Any potentially destructive test must be separate, off by default, and require explicit interactive confirmation; it cannot be invoked by auto mode.

The ISO build definition and boot-service wiring are present. The actual image build, persistent USB path on booted hardware, and BMC virtual-media validation remain to be completed on Linux.
