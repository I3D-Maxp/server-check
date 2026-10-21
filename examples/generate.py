"""Regenerate synthetic example reports using the production renderers."""

from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from server_check.reporting import CheckResult, LocalReportSink, ServerReport, publish_report  # noqa: E402

TIME = "2026-10-21T12:00:00Z"


def main() -> None:
    report = ServerReport(
        hostname="server01",
        serial="ABC123",
        generated_at=TIME,
        checks=(
            CheckResult(
                "cpu", "PASS", "CPU inventory collected; no CPU health claim.",
                {"sockets": 1, "model": "Example Xeon", "source_verdict": "INFO"}, TIME,
            ),
            CheckResult(
                "memory", "PASS", "No memory errors detected in available data.",
                {"edac_uncorrected": 0, "edac_corrected": 0}, TIME,
            ),
            CheckResult(
                "storage", "WARN", "One drive could not be tested behind PERC.",
                {"device": "/dev/sda", "raw_evidence": "[WARNING] SMART passthrough unavailable for /dev/sda."}, TIME,
            ),
        ),
    )
    publish_report(report, LocalReportSink(Path(__file__).resolve().parent))


if __name__ == "__main__":
    main()
