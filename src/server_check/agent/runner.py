"""Explicit, fail-open-to-next-check runner for read-only diagnostic plugins."""

from __future__ import annotations

from typing import Protocol, Sequence

from server_check.reporting import CheckResult


class CheckPlugin(Protocol):
    name: str

    def run(self) -> CheckResult:
        """Return a complete check result without modifying server state."""


def run_plugins(plugins: Sequence[CheckPlugin]) -> tuple[CheckResult, ...]:
    """Run registered checks in order; one exception cannot stop the suite."""
    results: list[CheckResult] = []
    for plugin in plugins:
        try:
            result = plugin.run()
            if result.name != plugin.name:
                raise ValueError(f"plugin returned {result.name!r}, expected {plugin.name!r}")
        except Exception as exc:
            result = CheckResult(
                name=plugin.name,
                status="WARN",
                summary=f"{plugin.name} could not be completed.",
                details={"error_type": type(exc).__name__, "error": str(exc)},
            )
        results.append(result)
    return tuple(results)
