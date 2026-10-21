"""Command-line reporting and check isolation."""

from contextlib import redirect_stdout
from io import StringIO
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from server_check import cli
from server_check.common import Unavailable


class CliTests(unittest.TestCase):
    @patch("server_check.cli.platform.system", return_value="Linux")
    def test_one_failed_check_does_not_stop_the_next(self, _system):
        def unavailable():
            raise Unavailable("lsblk is not installed")

        output = StringIO()
        with patch.dict(cli.CHECKS, {"cpu": unavailable, "memory": lambda: {"total_bytes": 1}}, clear=True):
            with redirect_stdout(output):
                exit_code = cli.main(["--json"])
        report = json.loads(output.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertEqual(report["checks"]["cpu"]["status"], "unavailable")
        self.assertEqual(report["checks"]["memory"]["data"]["total_bytes"], 1)

    @patch("server_check.cli.platform.system", return_value="Linux")
    def test_smart_failure_sets_warning_status(self, _system):
        output = StringIO()
        devices = {"devices": [{"status": "ok", "health": "failed"}]}
        with patch.dict(cli.CHECKS, {"smart": lambda: devices}, clear=True):
            with redirect_stdout(output):
                exit_code = cli.main(["--json", "--check", "smart"])
        self.assertEqual(exit_code, 1)
        self.assertEqual(json.loads(output.getvalue())["checks"]["smart"]["status"], "warning")


if __name__ == "__main__":
    unittest.main()
