"""SMART health for physical block devices."""

import json

from server_check.common import command_json, run, PermissionDenied


def collect() -> dict:
    listing = command_json("lsblk", "--json", "--output", "PATH,TYPE")
    paths = [item["path"] for item in listing["blockdevices"]
             if item.get("type") == "disk" and item.get("path")]
    devices = []
    for path in paths:
        completed = run("smartctl", "--json", "--all", path)
        try:
            report = json.loads(completed.stdout)
        except json.JSONDecodeError:
            report = {}
        messages = [item.get("string", "") for item in report.get("smartctl", {}).get("messages", [])]
        detail = " ".join(messages) or completed.stderr.strip()
        if not report or completed.returncode & 3:
            status = "permission_denied" if "permission denied" in detail.lower() else "error"
            devices.append({"path": path, "status": status,
                            "message": detail or f"smartctl exited with code {completed.returncode}"})
            continue

        passed = report.get("smart_status", {}).get("passed")
        attributes = report.get("ata_smart_attributes", {}).get("table", [])
        devices.append({
            "path": path,
            "status": "ok",
            "model": report.get("model_name"),
            "serial_number": report.get("serial_number"),
            "health": "passed" if passed is True else "failed" if passed is False else "unknown",
            "temperature_celsius": report.get("temperature", {}).get("current"),
            "power_on_hours": report.get("power_on_time", {}).get("hours"),
            "smartctl_exit_status": completed.returncode,
            "attributes": [
                {"id": item.get("id"), "name": item.get("name"),
                 "value": item.get("value"), "raw_value": item.get("raw", {}).get("value")}
                for item in attributes
            ],
        })
    if devices and all(item["status"] == "permission_denied" for item in devices):
        raise PermissionDenied("SMART access denied for every detected disk")
    return {"devices": devices}
