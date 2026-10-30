#!/usr/bin/env python3
"""Automated failure, timeout, and reliability tests for scripts/gps-ipc (P5.3)."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GPS_IPC = ROOT / "scripts" / "gps-ipc"
ISLAND_QML = (ROOT / "island" / "Island.qml").read_text()


class GpsIpcReliabilityTests(unittest.TestCase):
    """Test suite for failure conditions, contract compliance, and error reporting in gps-ipc."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.mock_bin = self.tmp_path / "bin"
        self.mock_bin.mkdir(parents=True, exist_ok=True)
        self.log_file = self.tmp_path / "quickshell_invocations.log"

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _run_ipc(self, args, extra_env=None):
        env = {
            **os.environ,
            "PATH": f"{self.mock_bin}:{os.environ.get('PATH', '')}",
            "XDG_CONFIG_HOME": str(self.tmp_path / "config"),
            **(extra_env or {}),
        }
        return subprocess.run(
            [str(GPS_IPC)] + args,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_invalid_subcommand_returns_code_1_with_usage(self):
        res = self._run_ipc(["nonexistent_subcommand"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("Usage: gps-ipc", res.stderr)

    def test_missing_shell_arguments_returns_code_1(self):
        res = self._run_ipc(["shell"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("Usage: gps-ipc shell <target> <action>", res.stderr)

    def test_missing_island_arguments_returns_code_1(self):
        res = self._run_ipc(["island"])
        self.assertEqual(res.returncode, 1)
        self.assertIn("Usage: gps-ipc island", res.stderr)

    def test_instance_not_running_returns_code_3_with_clear_error(self):
        """When Quickshell outputs 'No running instances', gps-ipc exits code 3."""
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text("#!/bin/sh\necho 'No running instances for test.qml' >&2\nexit 255\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["shell", "dashboard", "toggle"])
        self.assertEqual(res.returncode, 3)
        self.assertIn("ERROR: Target Quickshell instance is not running", res.stderr)

    def test_ipc_timeout_returns_code_124(self):
        """When Quickshell hangs, timeout triggers exit code 124."""
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text("#!/bin/sh\nsleep 5\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["shell", "dashboard", "toggle"], extra_env={"GPS_IPC_TIMEOUT": "0.1s"})
        self.assertEqual(res.returncode, 124)
        self.assertIn("timed out", res.stderr)

    def test_pet_subcommand_routes_to_shell_target_pet(self):
        """gps-ipc pet <action> calls quickshell with target 'pet'."""
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{self.log_file}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["pet", "wave"])
        self.assertEqual(res.returncode, 0)
        logged = self.log_file.read_text()
        self.assertIn("call pet wave", logged)
        self.assertIn("shell.qml", logged)

    def test_rail_subcommand_routes_to_shell_target_rail(self):
        """gps-ipc rail <action> calls quickshell with target 'rail'."""
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{self.log_file}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["rail", "togglePower"])
        self.assertEqual(res.returncode, 0)
        logged = self.log_file.read_text()
        self.assertIn("call rail togglePower", logged)
        self.assertIn("shell.qml", logged)

    def test_clipboard_subcommand_routes_to_island(self):
        """gps-ipc clipboard routes to island clipboard function."""
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{self.log_file}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["clipboard", "toggle"])
        self.assertEqual(res.returncode, 0)
        logged = self.log_file.read_text()
        self.assertIn("call island clipboard toggle", logged)

    def test_check_command_detects_stopped_instance(self):
        mock_qs = self.mock_bin / "quickshell"
        mock_qs.write_text("#!/bin/sh\nexit 1\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self._run_ipc(["check", "shell"])
        self.assertEqual(res.returncode, 3)
        self.assertIn("shell: stopped", res.stderr)

    def test_island_qml_implements_ipc_contract(self):
        """Island.qml must implement clipboard, history, focusToggle, status, and clip."""
        self.assertIn("function clipboard(action: string)", ISLAND_QML)
        self.assertIn("function clip()", ISLAND_QML)
        self.assertIn("function history(): string", ISLAND_QML)
        self.assertIn("function focusToggle()", ISLAND_QML)
        self.assertIn("function status(): string", ISLAND_QML)


if __name__ == "__main__":
    unittest.main()
