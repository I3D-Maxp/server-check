"""Command-line entry point for the Linux hardware report."""

import argparse
from datetime import datetime, timezone
import json
import platform
import subprocess
import sys

from server_check.checks import cpu, disks, memory, network, pci, smart
from server_check.common import PermissionDenied, Unavailable


CHECKS = {
    "cpu": cpu.collect,
    "memory": memory.collect,
    "disks": disks.collect,
    "smart": smart.collect,
    "network": network.collect,
    "pci": pci.collect,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Detect Linux server hardware and health")
    parser.add_argument("--check", action="append", choices=CHECKS,
                        help="Run only this check (may be repeated)")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    args = parser.parse_args(argv)

    if platform.system() != "Linux":
        parser.error("server-check requires Linux")

    results = {}
    for name in dict.fromkeys(args.check or CHECKS):
        try:
            data = CHECKS[name]()
            status = "ok"
            if name == "smart":
                devices = data["devices"]
                if any(device["status"] != "ok" for device in devices):
                    status = "partial"
                elif any(device["health"] == "failed" for device in devices):
                    status = "warning"
            results[name] = {"status": status, "data": data}
        except Unavailable as exc:
            results[name] = {"status": "unavailable", "message": str(exc)}
        except (PermissionDenied, PermissionError) as exc:
            results[name] = {"status": "permission_denied", "message": str(exc)}
        except (OSError, ValueError, KeyError, TypeError, RuntimeError,
                subprocess.TimeoutExpired) as exc:
            results[name] = {"status": "error", "message": str(exc)}

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "hostname": platform.node(),
        "checks": results,
    }
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"server-check on {report['hostname']} ({report['generated_at']})")
        for name, result in results.items():
            print(f"\n{name.upper()}: {result['status']}")
            if "message" in result:
                print(f"  {result['message']}")
            else:
                print(json.dumps(result["data"], indent=2))
    return 1 if any(result["status"] != "ok" for result in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
