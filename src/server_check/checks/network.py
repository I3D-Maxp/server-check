"""Network interface addresses, state, speed, and counters."""

from pathlib import Path

from server_check.common import command_json, read_text, PermissionDenied, Unavailable


def _optional(path: Path) -> str | None:
    try:
        return read_text(str(path)).strip()
    except (Unavailable, PermissionDenied, OSError):
        return None


def collect() -> dict:
    try:
        listing = command_json("ip", "-json", "address", "show")
        address_source = "ip"
    except Unavailable:
        listing = [{"ifname": path.name} for path in Path("/sys/class/net").iterdir()]
        address_source = "unavailable"
    interfaces = []
    for item in listing:
        name = item["ifname"]
        sysfs = Path("/sys/class/net") / name
        speed = _optional(sysfs / "speed")
        interfaces.append({
            "name": name,
            "state": _optional(sysfs / "operstate") or item.get("operstate"),
            "mac_address": item.get("address"),
            "addresses": [
                {"family": address.get("family"), "address": address.get("local"),
                 "prefix_length": address.get("prefixlen")}
                for address in item.get("addr_info", [])
            ],
            "speed_mbps": int(speed) if speed and speed.isdigit() else None,
            "rx_bytes": _number(_optional(sysfs / "statistics/rx_bytes")),
            "tx_bytes": _number(_optional(sysfs / "statistics/tx_bytes")),
        })
    return {"address_source": address_source, "interfaces": interfaces}


def _number(value: str | None) -> int | None:
    return int(value) if value and value.isdigit() else None
