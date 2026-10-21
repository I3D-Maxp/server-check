"""Convert one completed Bash run to fixed-name JSON and text reports."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import socket

from .legacy import from_legacy_report, parse_result_argument
from .writer import LocalReportSink, publish_report


def _serial() -> str:
    if os.environ.get("SERVER_CHECK_SERIAL"):
        return os.environ["SERVER_CHECK_SERIAL"].strip()
    try:
        value = Path("/sys/class/dmi/id/product_serial").read_text(
            encoding="utf-8", errors="replace"
        ).strip()
    except (OSError, PermissionError):
        value = ""
    if not value or value.lower() in {"none", "unknown", "to be filled by o.e.m."}:
        return "unknown"
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write unified server health reports")
    parser.add_argument("--legacy-report", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("/reports"))
    parser.add_argument("--result", action="append", default=[], metavar="NAME=VERDICT@TIME")
    parser.add_argument("--hostname", default=None)
    parser.add_argument("--serial", default=None)
    args = parser.parse_args(argv)
    try:
        results = [parse_result_argument(value) for value in args.result]
        raw_report = args.legacy_report.read_text(encoding="utf-8", errors="replace")
        report = from_legacy_report(
            raw_report, results,
            hostname=args.hostname or socket.gethostname(),
            serial=args.serial if args.serial is not None else _serial(),
        )
        publish_report(report, LocalReportSink(args.output_dir))
    except (OSError, ValueError, TypeError) as exc:
        parser.exit(3, f"Could not write structured reports: {exc}\n")
    print(f"Structured overall: {report.overall_status}")
    print(f"JSON report: {args.output_dir / 'report.json'}")
    print(f"Text report: {args.output_dir / 'report.txt'}")
    return {"PASS": 0, "WARN": 1, "FAIL": 2}[report.overall_status]


if __name__ == "__main__":
    raise SystemExit(main())
