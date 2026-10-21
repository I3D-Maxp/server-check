"""Adapter for the existing Bash check output; health checks stay unchanged."""

from __future__ import annotations

import re
from typing import Sequence

from .model import CheckResult, ServerReport, Status, utc_timestamp

_SECTION = re.compile(r"^===== ([a-z][a-z0-9-]*) =====$")
_VERDICT = re.compile(r"^\[(INFO|OK|WARNING|FAIL)\] VERDICT (?!DEVICE\b)[^:]+: (.+)$")
_RUNTIME_WARNING = re.compile(
    r"^\[WARNING\] .+ (?:timed out|exited with code|did not provide a completed verdict)"
)
_HEALTH_CHECKS = frozenset({
    "memory", "storage", "smart", "raid", "sensors", "hardware-errors",
})
_STATUS: dict[str, Status] = {
    "OK": "PASS", "INFO": "PASS", "WARNING": "WARN", "FAIL": "FAIL",
}


def parse_result_argument(argument: str) -> tuple[str, str, str]:
    """Parse a launcher-provided name=verdict@UTC-timestamp result."""
    name, separator, remainder = argument.partition("=")
    verdict, timestamp_separator, timestamp = remainder.partition("@")
    if not separator or not timestamp_separator or not _SECTION.fullmatch(
        f"===== {name} ====="
    ) or verdict not in _STATUS or not timestamp.endswith("Z"):
        raise ValueError(f"invalid check result argument: {argument!r}")
    return name, verdict, timestamp


def _sections(raw_report: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    name: str | None = None
    lines: list[str] = []
    for line in raw_report.splitlines():
        match = _SECTION.fullmatch(line)
        if match:
            if name is not None:
                sections[name] = "\n".join(lines).strip()
            name, lines = match.group(1), []
        elif name is not None and line == "SERVER DIAGNOSTIC COMPLETE":
            sections[name] = "\n".join(lines).strip()
            name = None
            break
        elif name is not None:
            lines.append(line)
    if name is not None:
        sections[name] = "\n".join(lines).strip()
    return sections


def from_legacy_report(
    raw_report: str,
    results: Sequence[tuple[str, str, str]],
    *,
    hostname: str,
    serial: str,
    generated_at: str | None = None,
) -> ServerReport:
    """Normalize selected Bash check results while preserving their full evidence."""
    sections = _sections(raw_report)
    checks: list[CheckResult] = []
    for name, verdict, timestamp in results:
        if verdict not in _STATUS:
            raise ValueError(f"invalid legacy verdict: {verdict}")
        evidence = sections.get(name, "")
        status = _STATUS[verdict]
        if verdict == "INFO" and name in _HEALTH_CHECKS:
            status = "WARN"
        elif verdict == "INFO" and (
            "unavailable (" in evidence or "could not be collected" in evidence
        ):
            status = "WARN"
        if not evidence:
            status = "WARN"
            summary = "Check produced no captured evidence."
        else:
            verdict_summaries = [
                match.group(2) for line in evidence.splitlines()
                if (match := _VERDICT.match(line))
            ]
            summary = verdict_summaries[-1] if verdict_summaries else "Check did not provide a completed verdict."
            runtime_notes = [line.removeprefix("[WARNING] ") for line in evidence.splitlines()
                             if _RUNTIME_WARNING.match(line)]
            if runtime_notes:
                summary = f"{summary} {runtime_notes[-1]}"
            if verdict == "INFO" and name in _HEALTH_CHECKS:
                summary = f"Health data unavailable: {summary}"
            elif verdict == "INFO" and status == "WARN":
                summary = f"Inventory incomplete: {summary}"
        checks.append(CheckResult(
            name=name,
            status=status,
            summary=summary,
            details={"source_verdict": verdict, "raw_evidence": evidence},
            timestamp=timestamp,
        ))
    return ServerReport(
        hostname=hostname or "unknown",
        serial=serial or "unknown",
        checks=tuple(checks),
        generated_at=generated_at or utc_timestamp(),
    )
