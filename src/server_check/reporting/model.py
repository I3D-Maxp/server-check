"""Small, typed result contract shared by all current and future checks."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal

Status = Literal["PASS", "WARN", "FAIL"]


def utc_timestamp() -> str:
    """Return an unambiguous UTC timestamp for a completed check or report."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class CheckResult:
    name: str
    status: Status
    summary: str
    details: dict[str, Any] = field(default_factory=dict)
    timestamp: str = field(default_factory=utc_timestamp)

    def __post_init__(self) -> None:
        if not self.name.strip() or not self.summary.strip():
            raise ValueError("check name and summary must be nonempty")
        if self.status not in ("PASS", "WARN", "FAIL"):
            raise ValueError(f"invalid check status: {self.status}")
        if not isinstance(self.details, dict):
            raise TypeError("check details must be a dictionary")
        if not self.timestamp.endswith("Z"):
            raise ValueError("check timestamp must be in UTC (Z)")

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "summary": self.summary,
            "details": self.details,
            "timestamp": self.timestamp,
        }


@dataclass(frozen=True)
class ServerReport:
    hostname: str
    serial: str
    checks: tuple[CheckResult, ...]
    generated_at: str = field(default_factory=utc_timestamp)

    def __post_init__(self) -> None:
        if len({check.name for check in self.checks}) != len(self.checks):
            raise ValueError("check names must be unique within a report")

    @property
    def overall_status(self) -> Status:
        if any(check.status == "FAIL" for check in self.checks):
            return "FAIL"
        if not self.checks or any(check.status == "WARN" for check in self.checks):
            return "WARN"
        return "PASS"

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": "1.0",
            "hostname": self.hostname,
            "serial": self.serial,
            "overall_status": self.overall_status,
            "generated_at": self.generated_at,
            "checks": [check.to_dict() for check in self.checks],
        }
