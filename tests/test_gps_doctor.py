#!/usr/bin/env python3
"""Automated unit and contract tests for scripts/gps-doctor and polkit autostart."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tests.helpers import HermeticTestCase
DOCTOR_SCRIPT = ROOT / "scripts" / "gps-doctor"
RUN_GPS_SCRIPT = ROOT / "scripts" / "run-gps.fish"
GPS_IPC_SCRIPT = ROOT / "scripts" / "gps-ipc"

# Dynamically import scripts/gps-doctor as a module
loader = importlib.machinery.SourceFileLoader("gps_doctor", str(DOCTOR_SCRIPT))
spec = importlib.util.spec_from_loader("gps_doctor", loader)
doc = importlib.util.module_from_spec(spec)
loader.exec_module(doc)


class DoctorVersionParsersTests(unittest.TestCase):
    """Unit tests for system version and path resolution parsers."""

    def test_hyprland_version_parser(self):
        sample_output = (
            "Hyprland 0.57.0 built from branch v0.57.0 at commit 0aa6745f clean.\n"
            "Date: Wed Oct 28 10:37:05 2026\n"
        )
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["hyprctl", "version"], returncode=0, stdout=sample_output
        ))
        self.assertEqual(doc.get_hyprland_version(runner=mock_runner), "0.57.0")

    def test_hyprland_version_parser_fallback(self):
        mock_runner = MagicMock(side_effect=Exception("command failed"))
        self.assertEqual(doc.get_hyprland_version(runner=mock_runner), "unknown")

    def test_quickshell_version_parser(self):
        sample_output = "Quickshell 0.3.2 (revision 4f508be500dea6e5732cc3d50382a0048b17e7b1)\n"
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["quickshell", "--version"], returncode=0, stdout=sample_output
        ))
        self.assertEqual(doc.get_quickshell_version(runner=mock_runner), "0.3.2")

    def test_kernel_version_parser(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["uname", "-r"], returncode=0, stdout="7.3.0-4-cachyos\n"
        ))
        self.assertEqual(doc.get_kernel_version(runner=mock_runner), "7.3.0-4-cachyos")

    def test_get_gps_root_env_override(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.dict(os.environ, {"GPS_ROOT": tmpdir}):
                self.assertEqual(str(doc.get_gps_root()), str(Path(tmpdir).resolve()))


class DoctorCheckersTests(unittest.TestCase):
    """Unit tests for low-level process and service probe helpers."""

    def test_is_process_running_found(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["pgrep"], returncode=0, stdout="1234\n5678\n"
        ))
        alive, pids = doc.is_process_running("dummy", runner=mock_runner)
        self.assertTrue(alive)
        self.assertEqual(pids, [1234, 5678])

    def test_is_process_running_not_found(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["pgrep"], returncode=1, stdout=""
        ))
        alive, pids = doc.is_process_running("dummy", runner=mock_runner)
        self.assertFalse(alive)
        self.assertEqual(pids, [])

    def test_is_systemd_user_active_true(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["systemctl"], returncode=0, stdout="active\n"
        ))
        self.assertTrue(doc.is_systemd_user_active("test.service", runner=mock_runner))

    def test_is_systemd_user_active_false(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["systemctl"], returncode=3, stdout="inactive\n"
        ))
        self.assertFalse(doc.is_systemd_user_active("test.service", runner=mock_runner))

    def test_is_dbus_name_active_true(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["busctl"], returncode=0, stdout="name info"
        ))
        self.assertTrue(doc.is_dbus_name_active("org.test.Name", runner=mock_runner))

    def test_is_dbus_name_active_false(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["busctl"], returncode=1, stdout="not found"
        ))
        self.assertFalse(doc.is_dbus_name_active("org.test.Name", runner=mock_runner))


class DoctorPolkitAndLogTests(unittest.TestCase):
    """Unit tests for polkit probe check and log error extraction."""

    def test_check_polkit_probe_no_agent(self):
        mock_runner = MagicMock(return_value=subprocess.CompletedProcess(
            args=["pkcheck"],
            returncode=2,
            stdout="",
            stderr="polkit\\56result=auth_admin\nAuthorization requires authentication but no agent is available.\n",
        ))
        handled, msg = doc.check_polkit_probe(runner=mock_runner)
        self.assertFalse(handled)
        self.assertEqual(msg, "no agent is available")

    def test_check_polkit_probe_agent_registered_timeout(self):
        mock_runner = MagicMock(side_effect=subprocess.TimeoutExpired(cmd=["pkcheck"], timeout=2))
        handled, msg = doc.check_polkit_probe(runner=mock_runner)
        self.assertTrue(handled)
        self.assertIn("agent waiting", msg)

    def test_extract_log_errors_empty(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("INFO: start\nINFO: loop normal\n")
            log_path = f.name
        try:
            errs = doc.extract_log_errors(log_path)
            self.assertEqual(errs, [])
        finally:
            os.unlink(log_path)

    def test_extract_log_errors_matches_warn_and_error(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("INFO: booting\nWARN: deprecated property used\nERROR: socket disconnected\nINFO: ok\n")
            log_path = f.name
        try:
            errs = doc.extract_log_errors(log_path)
            self.assertEqual(len(errs), 2)
            self.assertIn("WARN: deprecated property used", errs)
            self.assertIn("ERROR: socket disconnected", errs)
        finally:
            os.unlink(log_path)


class DoctorAuditReportTests(unittest.TestCase):
    """Integration unit tests for audit_session evaluation and exit codes."""

    def test_audit_session_all_healthy(self):
        """When all essential components are active, report.ok is True and status is OK."""
        def mock_runner(cmd, **kwargs):
            first = cmd[0]
            if first == "pgrep":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="1001\n")
            if first == "systemctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="active\n")
            if first == "busctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="name active\n")
            if first == "pacman":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="qt6-wayland 6.12.0\n")
            if first == "hyprctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="Hyprland 0.57.0\n")
            if first == "quickshell":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="Quickshell 0.3.2\n")
            if first == "uname":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="7.3.0\n")
            if first == "pkcheck":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="authorized\n")
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="")

        with patch.object(doc, "find_portal_config", return_value=("/etc/portals.conf", "hyprland;gtk")):
            rep = doc.audit_session(repo_root=str(ROOT), runner=mock_runner)
            self.assertTrue(rep["ok"])
            self.assertEqual(rep["status"], "OK")
            self.assertEqual(rep["summary"]["missing"], 0)

    def test_audit_session_essential_missing_sets_ok_false(self):
        """When an essential service (e.g. pipewire or polkit) is missing, report.ok is False."""
        def mock_runner(cmd, **kwargs):
            first = cmd[0]
            # Simulate pipewire down
            if first == "pgrep" and "pipewire" in cmd:
                return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="")
            if first == "systemctl" and "pipewire.service" in cmd:
                return subprocess.CompletedProcess(args=cmd, returncode=3, stdout="inactive\n")
            # All other checks active
            if first == "pgrep":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="2002\n")
            if first == "systemctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="active\n")
            if first == "busctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="active\n")
            if first == "pacman":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="qt6-wayland\n")
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="")

        rep = doc.audit_session(repo_root=str(ROOT), runner=mock_runner)
        self.assertFalse(rep["ok"])
        self.assertEqual(rep["status"], "MISSING")
        pw_check = next(c for c in rep["checks"] if c["name"] == "pipewire")
        self.assertEqual(pw_check["status"], "MISSING")
        self.assertIn("systemctl --user enable --now pipewire.service", rep["recommended_actions"])

    def test_audit_session_non_essential_warn_keeps_ok_true(self):
        """Non-essential components (system-tray, hypridle, awatcher) generate WARN without failing exit status."""
        def mock_runner(cmd, **kwargs):
            first = cmd[0]
            # System tray D-Bus check returns inactive
            if first == "busctl" and "StatusNotifier" in " ".join(cmd):
                return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="")
            # hypridle inactive
            if first == "pgrep" and "hypridle" in cmd:
                return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="")
            # Other checks active
            if first == "pgrep":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="3003\n")
            if first == "systemctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="active\n")
            if first == "busctl":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="active\n")
            if first == "pacman":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="qt6-wayland\n")
            if first == "pkcheck":
                return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="authorized\n")
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="")

        with patch.object(doc, "find_portal_config", return_value=("/etc/portals.conf", "hyprland;gtk")):
            rep = doc.audit_session(repo_root=str(ROOT), runner=mock_runner)
            self.assertTrue(rep["ok"])
            self.assertEqual(rep["status"], "WARN")
            tray_check = next(c for c in rep["checks"] if c["name"] == "system-tray")
            self.assertEqual(tray_check["status"], "WARN")


class DoctorCliContractTests(HermeticTestCase):
    """Contract tests for scripts/gps-doctor CLI execution and --json output."""

    def test_gps_doctor_executable(self):
        self.assertTrue(DOCTOR_SCRIPT.is_file())
        self.assertTrue(os.access(DOCTOR_SCRIPT, os.X_OK))

    def test_gps_doctor_json_schema(self):
        res = self.hermetic.run([str(DOCTOR_SCRIPT), "--json"], capture_output=True, text=True)
        # Even if exit code is 1 (due to current session state), stdout must be valid JSON
        data = json.loads(res.stdout)
        self.assertIn("status", data)
        self.assertIn("ok", data)
        self.assertIn("summary", data)
        self.assertIn("environment", data)
        self.assertIn("quickshell", data)
        self.assertIn("checks", data)
        self.assertIn("logs", data)
        self.assertIn("recommended_actions", data)

        # Check required fields in environment
        env = data["environment"]
        self.assertIn("hyprland_version", env)
        self.assertIn("quickshell_version", env)
        self.assertIn("kernel_version", env)
        self.assertIn("gps_root", env)

        # Check that checks is a list containing expected check items
        check_names = {c["name"] for c in data["checks"]}
        self.assertIn("pipewire", check_names)
        self.assertIn("wireplumber", check_names)
        self.assertIn("xdg-desktop-portal", check_names)
        self.assertIn("polkit-agent", check_names)
        self.assertIn("qt6-wayland", check_names)
        self.assertIn("secrets-service", check_names)
        self.assertIn("system-tray", check_names)
        self.assertIn("notifications", check_names)

    def test_gps_ipc_doctor_command(self):
        res = self.hermetic.run([str(GPS_IPC_SCRIPT), "health", "--json"], capture_output=True, text=True)
        data = json.loads(res.stdout)
        self.assertIn("checks", data)


class PolkitAutostartContractTests(unittest.TestCase):
    """Unit and contract tests for polkit authentication agent autostart in run-gps.fish."""

    def test_run_gps_contains_polkit_autostart_and_deduplication(self):
        script_text = RUN_GPS_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("polkit_pat", script_text)
        self.assertIn("hyprpolkitagent", script_text)
        self.assertIn("polkit-kde-authentication-agent-1", script_text)
        self.assertIn("pgrep", script_text)
        self.assertIn("not duplicating", script_text)


if __name__ == "__main__":
    unittest.main()
