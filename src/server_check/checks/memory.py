"""Physical memory and swap statistics."""

from server_check.common import read_text


def collect() -> dict:
    values = {}
    for line in read_text("/proc/meminfo").splitlines():
        if ":" in line:
            key, amount = line.split(":", 1)
            parts = amount.split()
            if parts:
                values[key] = int(parts[0]) * (1024 if len(parts) > 1 and parts[1] == "kB" else 1)

    total = values["MemTotal"]
    available = values.get("MemAvailable", values.get("MemFree", 0))
    swap_total = values.get("SwapTotal", 0)
    swap_free = values.get("SwapFree", 0)
    return {
        "total_bytes": total,
        "available_bytes": available,
        "used_bytes": total - available,
        "swap_total_bytes": swap_total,
        "swap_used_bytes": swap_total - swap_free,
    }
