# Repository structure for the autonomous platform

Status: incremental implementation. **Existing** paths are in this repository; `agent/` and `reporting/` now contain the Increment 4 plugin and reporting contracts. Other empty scaffolds and **planned** files describe later implementation. The working Bash toolkit and ISO build remain in place.

```text
server-check/
├── README.md                         existing project entry point
├── server-list.yaml                  design-stage fleet inventory template; no secrets
├── pyproject.toml                    existing Python package metadata; extend later
├── server-check.sh                   existing read-only Bash launcher
├── unattended.sh                     existing manual unattended wrapper
├── checks/                         existing Bash health checks and RAID vendor modules
├── config/server-check.conf          existing Bash check settings
├── iso/
│   ├── auto/config                   existing Debian live-build configuration
│   ├── config/                       existing menus, packages, isolation, systemd service
│   ├── runtime/                      existing Bash boot parser and safe report selection
│   └── local/raid-tools/             existing local-only optional vendor binary location
├── src/server_check/
│   ├── checks/                       existing Python inventory collectors; expand cautiously
│   ├── control/                      empty scaffold: orchestrator, run state, ISO publication
│   ├── redfish/                      empty scaffold: discovery and firmware-aware adapter
│   ├── agent/                        plugin runner; live HTTP endpoint planned
│   ├── reporting/                    report model, renderers, sink, Bash adapter
│   └── fleet/                        empty scaffold: scheduling and multi-server policy
├── schemas/                         empty scaffold; report-v1.json planned
├── tests/
│   ├── fixtures/redfish/             empty scaffold: scrubbed iDRAC 9 responses
│   ├── fixtures/hardware/            empty scaffold: utility, EDAC, sensor responses
│   ├── test_iso.sh                   existing ISO static and mocked tests
│   └── test_*.py                     inventory and reporting unit tests
├── tools/
│   ├── build-iso.sh                  existing live-build command
│   ├── validate-iso.sh               existing ISO structure/checksum validator
│   └── ...                           planned per-run image preparation and QEMU harness
├── docs/
│   ├── platform-architecture.md      this design's system boundaries and data flow
│   ├── platform-repository-structure.md
│   ├── platform-implementation-plan.md
│   ├── platform-technology-decisions.md
│   └── iso-build.md                  existing manual ISO build/boot guide
├── build/                          generated, ignored
├── dist/                           generated ISO and SHA-256, ignored
└── reports/                        local report output, never customer data disks
```

## Ownership rules

- `control/` is the only place that makes Redfish state-changing requests. Its client first discovers action targets and allowable values; no hard-coded iDRAC URI is treated as universal.
- `agent/` runs inside the live image. It owns passive in-band checks, RAM/approved-USB report files, delivery, and the optional read-only HTTP endpoint. It cannot request resets, firmware changes, or media ejection.
- `reporting/` defines one normalized finding model for the live checks and future Redfish checks. Reports carry a schema version so a future controller can reject incompatible output.
- `checks/` Bash scripts remain usable throughout migration. The existing Python collectors are inventory-oriented; they are **not** already equivalent to the richer Bash health checks. Each migrated check needs fixture parity and physical-hardware verification before it replaces a Bash module.
- `iso/` continues to use the existing Debian live-build workflow. The build now stages the Python reporting package; run-specific bootstrap config remains future work.
- `server-list.yaml` holds target identifiers and secret **references**, never usernames/passwords or embedded authentication tokens. Generated run credentials and reports belong in ignored state directories or an external secret/report store.

## Initial inventory format

The committed [server-list.yaml](../server-list.yaml) is intentionally empty and cannot trigger a deployment. A future controller must reject duplicate BMC URLs, missing ISO/collector configuration, and targets without an explicit diagnostic network route. An operator can add an R240 like this when Phase 1 implementation is ready:

```yaml
servers:
  - name: r240-lab-01
    bmc_url: https://idrac-r240.example.net
    expected_service_tag: EXAMPLE123
    credential_ref: env:IDRAC_R240_LAB
    enabled: true
    diagnostic_network:
      interface_mac: "00:11:22:33:44:55"
      address_method: dhcp
    return_to_disk: false
```

`credential_ref` is a future controller convention; the example is not a working deployment command. The R240 must be tested before enabling additional Dell models or firmware families.
