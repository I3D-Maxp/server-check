"""Block device inventory and mounted filesystem capacity."""

import os

from server_check.common import command_json


def _flatten(devices: list[dict]) -> list[dict]:
    result = []
    for device in devices:
        result.append(device)
        result.extend(_flatten(device.get("children") or []))
    return result


def collect() -> dict:
    listing = command_json(
        "lsblk", "--json", "--bytes", "--output",
        "NAME,PATH,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL",
    )
    devices = listing["blockdevices"]
    filesystems = []
    seen = set()
    for device in _flatten(devices):
        mountpoint = device.get("mountpoint")
        if not mountpoint or mountpoint in seen:
            continue
        seen.add(mountpoint)
        try:
            stats = os.statvfs(mountpoint)
        except OSError:
            continue
        filesystems.append({
            "mountpoint": mountpoint,
            "source": device.get("path"),
            "filesystem": device.get("fstype"),
            "total_bytes": stats.f_blocks * stats.f_frsize,
            "available_bytes": stats.f_bavail * stats.f_frsize,
            "used_bytes": (stats.f_blocks - stats.f_bfree) * stats.f_frsize,
        })
    return {"block_devices": devices, "filesystems": filesystems}
