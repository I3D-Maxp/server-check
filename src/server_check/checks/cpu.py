"""CPU identification and current utilization."""

import os
import time
from pathlib import Path

from server_check.common import read_text


def _ticks() -> tuple[int, int]:
    fields = read_text("/proc/stat").splitlines()[0].split()
    if fields[0] != "cpu" or len(fields) < 5:
        raise RuntimeError("unexpected /proc/stat format")
    # Guest time is already included in user/nice; counting it again skews usage.
    values = [int(value) for value in fields[1:9]]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle


def collect() -> dict:
    entries = []
    for block in read_text("/proc/cpuinfo").split("\n\n"):
        fields = dict(
            line.split(":", 1) for line in block.splitlines() if ":" in line
        )
        if fields:
            entries.append({key.strip(): value.strip() for key, value in fields.items()})

    first = entries[0] if entries else {}
    start_total, start_idle = _ticks()
    time.sleep(0.1)
    end_total, end_idle = _ticks()
    elapsed = end_total - start_total
    utilization = round(100 * (1 - (end_idle - start_idle) / elapsed), 1) if elapsed > 0 else None

    temperatures = []
    for zone in Path("/sys/class/thermal").glob("thermal_zone*"):
        try:
            kind = (zone / "type").read_text().strip()
            if not any(token in kind.lower() for token in ("cpu", "package", "x86_pkg_temp", "soc_thermal")):
                continue
            celsius = int((zone / "temp").read_text().strip()) / 1000
        except (OSError, ValueError):
            continue
        temperatures.append({"sensor": kind, "celsius": celsius})

    return {
        "model": first.get("model name") or first.get("Hardware") or first.get("Processor"),
        "logical_cpus": os.cpu_count(),
        "load_average_1_5_15m": list(os.getloadavg()),
        "utilization_percent": utilization,
        "temperatures_celsius": temperatures,
    }
