"""Two views of the same typed server report."""

from __future__ import annotations

import json

from .model import ServerReport


def render_json(report: ServerReport) -> str:
    return json.dumps(report.to_dict(), indent=2, ensure_ascii=False) + "\n"


def render_text(report: ServerReport) -> str:
    lines = [
        "SERVER DIAGNOSTIC COMPLETE",
        f"Hostname: {report.hostname}",
        f"Serial: {report.serial}",
        f"Generated: {report.generated_at}",
        f"Overall: {report.overall_status}",
        "",
        "Checks:",
    ]
    for check in report.checks:
        lines.extend([
            f"{check.name}: {check.status}",
            f"  Summary: {check.summary}",
            f"  Timestamp: {check.timestamp}",
            "  Details:",
        ])
        if not check.details:
            lines.append("    (none)")
        else:
            for key, value in check.details.items():
                if key == "raw_evidence" and isinstance(value, str):
                    lines.append("    Raw evidence:")
                    lines.extend(f"      {line}" for line in value.splitlines())
                else:
                    display = json.dumps(value, ensure_ascii=False, sort_keys=True)
                    lines.append(f"    {key}: {display}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
