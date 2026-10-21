"""Local report sink; later HTTP/SMB sinks use the same publish interface."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import tempfile
from typing import Protocol

from .model import ServerReport
from .render import render_json, render_text


@dataclass(frozen=True)
class RenderedReport:
    json_text: str
    text: str


class ReportSink(Protocol):
    def publish(self, report: ServerReport, rendered: RenderedReport) -> None:
        """Persist or transport a rendered report."""


def _atomic_write(path: Path, content: str) -> None:
    """Replace a report file without exposing a partially written version."""
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=path.parent,
            prefix=f".{path.name}.", delete=False,
        ) as output:
            temporary = output.name
            os.chmod(temporary, 0o600)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


@dataclass(frozen=True)
class LocalReportSink:
    directory: Path = Path("/reports")

    def publish(self, report: ServerReport, rendered: RenderedReport) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        _atomic_write(self.directory / "report.json", rendered.json_text)
        _atomic_write(self.directory / "report.txt", rendered.text)


def publish_report(report: ServerReport, *sinks: ReportSink) -> RenderedReport:
    """Render once and send identical content to local or future transport sinks."""
    rendered = RenderedReport(render_json(report), render_text(report))
    for sink in sinks:
        sink.publish(report, rendered)
    return rendered
