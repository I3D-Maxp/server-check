# Implementation plan: iDRAC 9 to autonomous report

Status: design and execution order, 2026-10-21. No phase below is complete. Increment 4 has implemented the local JSON/text reporting contract and Bash adapter described in [the reporting guide](reporting-framework.md). Redfish control, full Python check migration, and network collection remain future work.

## Release gates before deployment

1. Build the current ISO on Debian 13 x86_64, verify its SHA-256, and boot it in BIOS and UEFI QEMU without an attached writable hard disk. Confirm tty1 autostart, check continuation, completion shell, and no host-disk writes.
2. Inventory an R240's iDRAC firmware, license, Redfish service root, virtual-media resources, `InsertMedia`/`EjectMedia` actions, `Cd` one-time boot support, and available reset types. Save scrubbed fixtures. Compare at least one other iDRAC 9 firmware generation before claiming broader support. Dell's own scripts note firmware-dependent media IDs and boot paths. [Dell virtual-media example](https://github.com/dell/iDRAC-Redfish-Scripting/blob/master/Redfish%20Python/InsertEjectVirtualMediaREDFISH.py), [Dell one-time boot example](https://github.com/dell/iDRAC-Redfish-Scripting/blob/master/Redfish%20Python/SetNextOneTimeBootDeviceREDFISH.py).
3. Confirm whether a designated host NIC can reach the controller's result endpoint after live boot. The iDRAC management port alone is insufficient. If no route exists, choose operator retrieval from RAM/USB and keep automatic return-to-disk disabled.

## Phase 1 — Redfish virtual media and automatic boot

**Deliverables**

- Add a Python control-plane CLI with `discover`, `preflight`, `deploy`, and `status` commands. Read `server-list.yaml` safely and resolve secrets from an external provider or environment. Log request IDs and response status without credentials.
- Implement a Redfish session with verified TLS, bounded connect/read timeouts, retries for GET and explicit idempotent recovery for mutating actions, pagination, and discovery from `@odata.id`/action `target`. A `--dry-run` prints the exact planned actions and their prerequisites without changing iDRAC state.
- Publish a validated ISO from an HTTP(S) server reachable by iDRAC; check local file checksum and HTTP response. Identify the selected virtual-CD resource by capability and current state. Abort if an unrelated image is mounted.
- Insert media, verify it by GET, set `BootSourceOverrideEnabled=Once` and `BootSourceOverrideTarget=Cd` when advertised, read back boot state, request graceful restart or `On`, then track the run. Do not change persistent boot order or use forced reset by default.
- Add an isolated Dell adapter for older firmware that requires an OEM one-time virtual-media boot action. Enable it only with a matching tested fixture, not as an undocumented fallback.
- Connect the ISO's existing autostart service to a Python agent entry point once it exists; during the first Phase 1 smoke test, the current Bash `server-check.sh --boot` provides the safe diagnostic run. Do not remove interactive/rescue menu entries.

**Acceptance**: on a lab R240, one controller command mounts the ISO, sets one-time virtual CD, restarts the machine, and the existing unattended suite reaches its completion shell. A second invocation sees the in-progress run rather than causing another reboot. A missing license, incompatible boot option, occupied media slot, unreachable ISO, or failed read-back stops before reset and records a precise reason.

**Tests**: Redfish fixture tests for older/newer iDRAC 9 URI layouts; 401/403/404/409/5xx and retry cases; allowable-value checks; no reset after failed mount or boot PATCH; state recovery after controller crash; dry-run proves zero POST/PATCH; QEMU BIOS/UEFI smoke; one physical R240 BMC boot.

## Phase 2 — Python health-check framework and JSON report

**Deliverables**

- Define `schemas/report-v1.json` and a shared result model: run ID, service tag, model, timestamps, ISO/tool versions, top-level `PASS|WARN|FAIL`, completion status, each check's status/source/evidence/devices, and capability coverage. Keep raw evidence with bounded size and timestamps.
- Implement a Python runner that executes check plugins independently with timeouts, captures command output/exit codes, and continues after exceptions. Preserve the existing Bash allowlist as a temporary adapter; migrate check-by-check only after fixture parity.
- Implement read-only collectors for CPU, memory inventory and EDAC errors, RAID controllers and virtual/physical disks, NVMe and SATA/SAS SMART, fans, PSU, temperatures, iDRAC logs, BIOS, firmware, and network adapters. Redfish and live sources retain separate provenance and can disagree without overwriting one another.
- Add a severity policy: explicit current failure or critical vendor health -> `FAIL`; warning/degraded or historical corrected evidence -> `WARN`; unavailable/unsupported/permission denied -> `UNAVAILABLE`; collector exception -> `ERROR`. Top-level status uses the architecture's deterministic mapping. Never infer a threshold absent from hardware data.
- Generate `report.json` and `report.txt` atomically from the same normalized results. Place them in RAM or approved mounted USB via the existing safe selection rules. Keep the console summary and shell.

**Acceptance**: a full run emits schema-valid JSON of the requested shape and a matching human-readable report. Missing PERC member SMART, absent PSU sensors, no EDAC device, or no NVMe controller are explicit coverage gaps; they do not abort other checks. A simulated tool failure cannot be mislabeled as a healthy component.

**Tests**: fixture matrix for PASS, WARN, FAIL, UNAVAILABLE, ERROR, conflicting sources, historical logs, malformed utility output, timeouts, empty devices, and report serialization; shell checks stay green; read-only command allowlist; R240 comparison against iDRAC inventory and real Linux commands.

## Phase 3 — result collection, durable storage, and optional return

**Deliverables**

- Select a designated diagnostic host NIC and configure only the approved DHCP/static profile in the live image. Current ISO network services are masked and `diag.network` only toggles an inventory check; change this deliberately and test that unconfigured runs remain offline.
- Add a run-specific bootstrap config with controller URL, run ID, short-lived single-run credential, trusted CA, and network profile. Generate a separate image or a validated boot-compatible config attachment; preserve a checksum and restrict HTTP access to it. Do not place long-lived fleet credentials in a reusable ISO.
- Agent writes local RAM/approved-USB files first, then uploads over verified HTTPS. The collector validates run identity, service tag, schema, payload size, checksum, and credential, writes JSON/text/evidence atomically, and acknowledges only after durable storage. Retries are idempotent by run ID and content hash.
- Expose `GET /v1/runs/{run_id}/report.json` and `.txt` on the controller. Optionally expose the same report from the live agent on a designated diagnostic interface with a per-run token while it remains booted. The agent endpoint is read-only and ephemeral.
- Implement cleanup state: default leaves the server running. If the run explicitly requests `return_to_disk`, require collector acknowledgement, verify the one-time boot override was consumed, ask iDRAC for graceful restart, confirm the live agent is gone and local boot path has resumed, then eject **only this run's** media. Uncertain state stops automatic cleanup.

**Acceptance**: with host networking, the controller has a durable validated report and the HTTP API serves it. If upload fails, the report remains locally available and the server is not automatically rebooted or ejected. If optional return is enabled, the controller never ejects a live-root ISO before the reboot has passed the safe handoff point.

**Tests**: short-lived credential expiry/replay, wrong service tag/run ID, bad hash, duplicate upload, collector restart, truncated JSON, network loss before/during/after upload, USB fallback, no host NIC route, HTTPS certificate failures, and return-to-disk failure injection. Physical R240 proof includes actual report retrieval before any cleanup.

## Phase 4 — fleet management

**Deliverables**

- Extend `server-list.yaml` validation and controller persistence to multiple targets. Add concurrency limits, maintenance windows, operator roles, per-server lock, rate limits, cancellation, and resumable jobs. Never issue concurrent reset workflows to the same iDRAC.
- Add a fleet status API and CLI export that aggregate report state and coverage without hiding missing reports. Track ISO/tool version, iDRAC firmware, and per-model capability matrix.
- Add retention, access control, audit trail, and report export. Inventory and serial numbers are sensitive operational data; avoid secrets in reports.

**Acceptance**: a small lab fleet run remains isolated per target; one failed iDRAC does not stop other servers; retry after controller restart does not double reboot; each report maps to the correct service tag and run ID. Broader Dell model support is enabled only after model/firmware fixture and physical validation.

## Milestones and dependency order

| Milestone | Depends on | Proof required |
| --- | --- | --- |
| M0 ISO baseline | Existing live-build tree | Linux build, checksum, BIOS/UEFI QEMU boot, R240 boot. |
| M1 controlled Redfish boot | M0, iDRAC fixture discovery | One-click R240 boot, safe preflight and retry behavior. |
| M2 structured health | M1 | Complete JSON/text fixtures and real hardware comparison. |
| M3 remote persistence | M2, diagnostic host network | Collector acknowledgement, failure recovery, safe optional return. |
| M4 fleet | M3 | Multi-target isolation and audit tests. |

## Operational stop conditions

Do not reset a production server when the ISO checksum is unknown, virtual media is already owned by another operator, the intended target/service tag does not match, one-time `Cd` boot cannot be verified, or a maintenance window is not active. Do not auto-return to disk or eject when the only report copy is in RAM, the upload is unacknowledged, or the live OS may still be reading the ISO. A problem with one check affects the report, not the execution of later checks.
