"""Collector behavior with representative Linux command output."""

import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from server_check.checks import cpu, disks, memory, smart
from server_check.common import PermissionDenied


class CollectorTests(unittest.TestCase):
    @patch("server_check.checks.memory.read_text")
    def test_memory_values_are_bytes(self, read_text):
        read_text.return_value = (
            "MemTotal: 1000 kB\nMemAvailable: 400 kB\n"
            "SwapTotal: 200 kB\nSwapFree: 50 kB\n"
        )
        self.assertEqual(memory.collect(), {
            "total_bytes": 1024000,
            "available_bytes": 409600,
            "used_bytes": 614400,
            "swap_total_bytes": 204800,
            "swap_used_bytes": 153600,
        })

    @patch("server_check.checks.cpu.time.sleep")
    @patch("server_check.checks.cpu.os.getloadavg", return_value=(1.0, 2.0, 3.0))
    @patch("server_check.checks.cpu.os.cpu_count", return_value=4)
    @patch("server_check.checks.cpu.read_text")
    def test_cpu_utilization_uses_two_samples(self, read_text, _count, _load, _sleep):
        read_text.side_effect = [
            "processor : 0\nmodel name : Test CPU\n",
            "cpu  10 0 10 80 0\n",
            "cpu  30 0 20 150 0\n",
        ]
        result = cpu.collect()
        self.assertEqual(result["model"], "Test CPU")
        self.assertEqual(result["utilization_percent"], 30.0)

    @patch("server_check.checks.disks.os.statvfs")
    @patch("server_check.checks.disks.command_json")
    def test_disks_include_mounted_filesystem(self, command_json, statvfs):
        command_json.return_value = {"blockdevices": [{
            "name": "sda", "path": "/dev/sda", "type": "disk",
            "children": [{"name": "sda1", "path": "/dev/sda1",
                          "type": "part", "mountpoint": "/"}],
        }]}
        statvfs.return_value = SimpleNamespace(f_blocks=100, f_bfree=40,
                                                f_bavail=30, f_frsize=4096)
        result = disks.collect()
        self.assertEqual(result["filesystems"][0]["used_bytes"], 60 * 4096)
        self.assertEqual(result["filesystems"][0]["available_bytes"], 30 * 4096)

    @patch("server_check.checks.smart.run")
    @patch("server_check.checks.smart.command_json")
    def test_smart_health_failure_is_reported_even_with_nonzero_exit(self, listing, run):
        listing.return_value = {"blockdevices": [{"path": "/dev/sda", "type": "disk"}]}
        run.return_value = SimpleNamespace(returncode=4, stderr="", stdout=json.dumps({
            "smartctl": {"messages": []}, "smart_status": {"passed": False},
            "temperature": {"current": 55},
        }))
        device = smart.collect()["devices"][0]
        self.assertEqual(device["status"], "ok")
        self.assertEqual(device["health"], "failed")
        self.assertEqual(device["smartctl_exit_status"], 4)

    @patch("server_check.checks.smart.run")
    @patch("server_check.checks.smart.command_json")
    def test_smart_permission_denial_is_visible(self, listing, run):
        listing.return_value = {"blockdevices": [{"path": "/dev/sda", "type": "disk"}]}
        run.return_value = SimpleNamespace(returncode=2, stdout="", stderr="Permission denied")
        with self.assertRaises(PermissionDenied):
            smart.collect()


if __name__ == "__main__":
    unittest.main()
