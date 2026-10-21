"""PCI device inventory."""

from server_check.common import run, PermissionDenied


def collect() -> dict:
    completed = run("lspci", "-D", "-nn")
    if completed.returncode:
        detail = (completed.stderr or completed.stdout).strip()
        if "permission denied" in detail.lower():
            raise PermissionDenied(detail)
        raise RuntimeError(detail or "lspci failed")
    devices = []
    for line in completed.stdout.splitlines():
        address, separator, description = line.partition(" ")
        if separator:
            devices.append({"address": address, "description": description.strip()})
    return {"devices": devices}
