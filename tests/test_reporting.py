"""Reporting contract, legacy adapter, and local publication tests."""

from contextlib import redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from server_check.reporting import (  # noqa: E402
    CheckResult, LocalReportSink, ServerReport, publish_report, render_json, render_text,
)
from server_check.reporting.__main__ import main as report_main  # noqa: E402
from server_check.reporting.legacy import (  # noqa: E402
    from_legacy_report, parse_result_argument,
)
from server_check.agent import run_plugins  # noqa: E402

TIME = "2026-10-21T12:00:00Z"


def check(name: str, status: str) -> CheckResult:
    return CheckResult(name, status, f"{name} summary", {"value": 1}, TIME)


class ReportingModelTests(unittest.TestCase):
    def test_every_check_has_required_fields(self):
        fields = check("memory", "PASS").to_dict()
        self.assertEqual(set(fields), {"name", "status", "summary", "details", "timestamp"})
        self.assertEqual(fields["timestamp"], TIME)

    def test_overall_status_precedence(self):
        for statuses, expected in [
            (["PASS", "PASS"], "PASS"),
            (["PASS", "WARN"], "WARN"),
            (["WARN", "FAIL"], "FAIL"),
            ([], "WARN"),
        ]:
            with self.subTest(statuses=statuses):
                report = ServerReport("server01", "ABC123", tuple(
                    check(f"check-{i}", status) for i, status in enumerate(statuses)
                ), TIME)
                self.assertEqual(report.overall_status, expected)
                self.assertEqual(report.to_dict()["overall_status"], expected)

    def test_invalid_or_duplicate_results_are_rejected(self):
        with self.assertRaises(ValueError):
            CheckResult("memory", "UNKNOWN", "summary")
        with self.assertRaises(ValueError):
            ServerReport("host", "serial", (check("memory", "PASS"), check("memory", "WARN")))

    def test_json_and_text_come_from_same_model(self):
        report = ServerReport("server01", "ABC123", (check("memory", "WARN"),), TIME)
        parsed = json.loads(render_json(report))
        text = render_text(report)
        self.assertEqual(parsed["schema_version"], "1.0")
        self.assertEqual(parsed["hostname"], "server01")
        self.assertEqual(parsed["checks"][0]["status"], "WARN")
        self.assertIn("Overall: WARN", text)
        self.assertIn("memory: WARN", text)

    def test_local_sink_and_pluggable_sink_receive_identical_rendering(self):
        received = []

        class CaptureSink:
            def publish(self, report, rendered):
                received.append((report, rendered))

        with tempfile.TemporaryDirectory() as directory:
            report = ServerReport("server01", "ABC123", (check("memory", "PASS"),), TIME)
            rendered = publish_report(report, LocalReportSink(Path(directory)), CaptureSink())
            self.assertEqual((Path(directory) / "report.json").read_text(), rendered.json_text)
            self.assertEqual((Path(directory) / "report.txt").read_text(), rendered.text)
            self.assertIs(received[0][0], report)
            self.assertIs(received[0][1], rendered)
            if os.name == "posix":
                self.assertEqual((Path(directory) / "report.json").stat().st_mode & 0o777, 0o600)

    def test_pluggable_checks_continue_after_failure(self):
        class Broken:
            name = "broken"

            def run(self):
                raise RuntimeError("sensor absent")

        class Working:
            name = "working"

            def run(self):
                return check("working", "PASS")

        results = run_plugins([Broken(), Working()])
        self.assertEqual([result.status for result in results], ["WARN", "PASS"])
        self.assertEqual(results[0].details["error_type"], "RuntimeError")


class LegacyAdapterTests(unittest.TestCase):
    RAW = """Server diagnostic report
===== cpu =====
[INFO] CPU topology and features
[INFO] VERDICT CPU: Inventory only; this check cannot establish CPU health.
===== memory =====
[INFO] Raw EDAC mc0 ce_count=1
[WARNING] VERDICT MEMORY: One historical corrected error.
===== storage =====
[INFO] Raw SMART: FAILED
[FAIL] VERDICT STORAGE: Device reports failure.

SERVER DIAGNOSTIC COMPLETE
Overall: FAIL
"""

    def test_legacy_evidence_and_verdicts(self):
        report = from_legacy_report(self.RAW, [
            ("cpu", "INFO", TIME), ("memory", "WARNING", TIME),
            ("storage", "FAIL", TIME),
        ], hostname="server01", serial="ABC123", generated_at=TIME)
        self.assertEqual([c.status for c in report.checks], ["PASS", "WARN", "FAIL"])
        self.assertEqual(report.overall_status, "FAIL")
        self.assertIn("Raw SMART: FAILED", report.checks[2].details["raw_evidence"])
        self.assertEqual(report.checks[1].summary, "One historical corrected error.")
        self.assertIn("Raw evidence:", render_text(report))

    def test_unavailable_health_and_inventory_are_warnings(self):
        raw = """===== memory =====
[INFO] VERDICT MEMORY: No usable health data was available.
===== pci =====
[INFO] PCI listing unavailable (lspci is not installed).
[INFO] VERDICT PCI: Inventory only.
SERVER DIAGNOSTIC COMPLETE
"""
        report = from_legacy_report(raw, [
            ("memory", "INFO", TIME), ("pci", "INFO", TIME),
        ], hostname="host", serial="unknown")
        self.assertEqual([c.status for c in report.checks], ["WARN", "WARN"])
        self.assertIn("unavailable", report.checks[0].summary.lower())

    def test_missing_evidence_is_not_pass(self):
        report = from_legacy_report("SERVER DIAGNOSTIC COMPLETE", [
            ("cpu", "OK", TIME),
        ], hostname="host", serial="unknown")
        self.assertEqual(report.overall_status, "WARN")

    def test_result_argument_validation(self):
        self.assertEqual(parse_result_argument(f"memory=WARNING@{TIME}"),
                         ("memory", "WARNING", TIME))
        for argument in ("memory=UNKNOWN@" + TIME, "../../disk=OK@" + TIME, "memory=OK"):
            with self.subTest(argument=argument), self.assertRaises(ValueError):
                parse_result_argument(argument)

    def test_cli_writes_fixed_report_names(self):
        with tempfile.TemporaryDirectory() as directory:
            raw_path = Path(directory) / "raw.txt"
            raw_path.write_text(self.RAW, encoding="utf-8")
            output = Path(directory) / "reports"
            stdout = StringIO()
            with redirect_stdout(stdout):
                status = report_main([
                    "--legacy-report", str(raw_path), "--output-dir", str(output),
                    "--hostname", "server01", "--serial", "ABC123",
                    "--result", f"memory=WARNING@{TIME}",
                ])
            self.assertEqual(status, 1)
            self.assertEqual(json.loads((output / "report.json").read_text())["serial"], "ABC123")
            self.assertIn("memory: WARN", (output / "report.txt").read_text())
            self.assertIn("Structured overall: WARN", stdout.getvalue())

    def test_cli_reports_write_failure_as_runtime_error(self):
        with tempfile.TemporaryDirectory() as directory:
            raw_path = Path(directory) / "raw.txt"
            raw_path.write_text(self.RAW, encoding="utf-8")
            occupied = Path(directory) / "occupied"
            occupied.write_text("not a directory", encoding="utf-8")
            with patch("sys.stderr", new_callable=StringIO):
                with self.assertRaises(SystemExit) as failure:
                    report_main([
                        "--legacy-report", str(raw_path), "--output-dir", str(occupied),
                        "--result", f"memory=WARNING@{TIME}",
                    ])
            self.assertEqual(failure.exception.code, 3)

    @unittest.skipUnless(platform.system() == "Linux", "live launcher requires Linux")
    def test_linux_launcher_handoff(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["bash", str(root / "server-check.sh"), "--check", "cpu",
                 "--output-dir", directory],
                cwd=root, text=True, capture_output=True, timeout=60,
                env={**os.environ, "SERVER_CHECK_STRUCTURED_REPORT": "yes"},
            )
            self.assertIn(result.returncode, (0, 1), result.stderr)
            data = json.loads((Path(directory) / "report.json").read_text())
            self.assertEqual(data["checks"][0]["name"], "cpu")
            self.assertEqual(data["overall_status"], data["checks"][0]["status"])
            self.assertTrue((Path(directory) / "report.txt").is_file())


if __name__ == "__main__":
    unittest.main()
