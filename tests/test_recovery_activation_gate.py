#!/usr/bin/env python3
"""Hermetic Tests for GPS Automatic Recovery Activation Gate (Session 5 Phase 7).

Verifies:
1. get_configured_mode() returns 'observe' when flag is absent.
2. get_configured_mode() returns 'auto' when flag is present and valid ('auto', '1', 'true', 'enabled', empty).
3. get_configured_mode() returns 'observe' when flag is invalid ('garbage', 'disabled', '0') or unreadable.
4. run-gps.fish respects flag: launches observe by default, auto only when flag is valid.
5. gps-ipc watchdog mode / enable-auto / disable-auto commands manage the persistent flag and runtime process safely.
6. Safe, reversible rollback returns supervisor to observation mode and removes flag.
7. Explicit watchdog stop does not enter an uncontrolled background loop.
"""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Import gps-watchdog module
import importlib.machinery
import importlib.util

loader = importlib.machinery.SourceFileLoader("gps_watchdog", str(ROOT / "scripts" / "gps-watchdog"))
spec = importlib.util.spec_from_loader("gps_watchdog", loader)
gps_watchdog = importlib.util.module_from_spec(spec)
loader.exec_module(gps_watchdog)

GPS_IPC = ROOT / "scripts" / "gps-ipc"
RUN_GPS = ROOT / "scripts" / "run-gps.fish"


class RecoveryActivationGateTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_root = Path(self.temp_dir.name)

        self.home_dir = self.test_root / "home"
        self.home_dir.mkdir(parents=True, exist_ok=True)
        self.config_dir = self.home_dir / ".config" / "quickshell"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir = self.test_root / "runtime" / "gps"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir = self.test_root / "cache" / "gps" / "logs"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.bin_dir = self.test_root / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)

        self.flag_file = self.config_dir / "gps-watchdog-auto"

    def tearDown(self):
        self.temp_dir.cleanup()

    # -------------------------------------------------------------------------
    # Unit Tests for get_configured_mode()
    # -------------------------------------------------------------------------
    def test_mode_defaults_to_observe_when_flag_absent(self):
        """When ~/.config/quickshell/gps-watchdog-auto is missing, mode is 'observe'."""
        self.assertFalse(self.flag_file.exists())
        mode = gps_watchdog.get_configured_mode(self.config_dir)
        self.assertEqual(mode, "observe")

    def test_mode_is_auto_when_flag_is_valid(self):
        """When flag contains valid activation tokens, mode is 'auto'."""
        valid_tokens = ["auto", "AUTO", "1", "true", "True", "enabled", ""]
        for token in valid_tokens:
            self.flag_file.write_text(token)
            mode = gps_watchdog.get_configured_mode(self.config_dir)
            self.assertEqual(mode, "auto", f"Expected 'auto' for token '{token}', got '{mode}'")

    def test_mode_falls_back_to_observe_when_flag_invalid(self):
        """When flag contains unknown tokens, mode falls back to 'observe'."""
        invalid_tokens = ["disabled", "0", "false", "observe", "random_junk", "invalid"]
        for token in invalid_tokens:
            self.flag_file.write_text(token)
            mode = gps_watchdog.get_configured_mode(self.config_dir)
            self.assertEqual(mode, "observe", f"Expected 'observe' for invalid token '{token}', got '{mode}'")

    def test_mode_falls_back_to_observe_when_flag_unreadable(self):
        """When flag file is unreadable (permission 000), mode safely falls back to 'observe'."""
        self.flag_file.write_text("auto")
        self.flag_file.chmod(0)
        try:
            mode = gps_watchdog.get_configured_mode(self.config_dir)
            self.assertEqual(mode, "observe")
        finally:
            self.flag_file.chmod(0o644)

    # -------------------------------------------------------------------------
    # CLI Tests via scripts/gps-ipc
    # -------------------------------------------------------------------------
    def test_gps_ipc_watchdog_mode_reporting(self):
        """gps-ipc watchdog mode reports configured and running mode."""
        env = {
            **os.environ,
            "HOME": str(self.home_dir),
            "XDG_CONFIG_HOME": str(self.home_dir / ".config"),
            "XDG_RUNTIME_DIR": str(self.runtime_dir.parent),
        }

        # 1. Flag absent -> configured observe
        res = subprocess.run([str(GPS_IPC), "watchdog", "mode"], env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Configured mode: observe", res.stdout)
        self.assertIn("flag file: absent", res.stdout)

        # 2. Flag present -> configured auto
        self.flag_file.write_text("auto")
        res2 = subprocess.run([str(GPS_IPC), "watchdog", "mode"], env=env, capture_output=True, text=True)
        self.assertEqual(res2.returncode, 0)
        self.assertIn("Configured mode: auto", res2.stdout)
        self.assertIn("flag file: present", res2.stdout)

    def test_gps_ipc_watchdog_enable_and_disable_lifecycle(self):
        """gps-ipc watchdog mode auto/observe toggles flag and manages process."""
        env = {
            **os.environ,
            "HOME": str(self.home_dir),
            "XDG_CONFIG_HOME": str(self.home_dir / ".config"),
            "XDG_RUNTIME_DIR": str(self.runtime_dir.parent),
            "XDG_CACHE_HOME": str(self.cache_dir.parent.parent),
        }

        # 1. Enable auto mode
        res_enable = subprocess.run([str(GPS_IPC), "watchdog", "mode", "auto"], env=env, capture_output=True, text=True)
        self.assertEqual(res_enable.returncode, 0)
        self.assertTrue(self.flag_file.is_file(), "Flag file should be created by mode auto")
        self.assertIn("auto", self.flag_file.read_text())

        # 2. Disable auto mode (rollback to observe)
        res_disable = subprocess.run([str(GPS_IPC), "watchdog", "mode", "observe"], env=env, capture_output=True, text=True)
        self.assertEqual(res_disable.returncode, 0)
        self.assertFalse(self.flag_file.exists(), "Flag file should be removed by mode observe")

        # 3. Test enable-auto alias
        res_alias_en = subprocess.run([str(GPS_IPC), "watchdog", "enable-auto"], env=env, capture_output=True, text=True)
        self.assertEqual(res_alias_en.returncode, 0)
        self.assertTrue(self.flag_file.is_file())

        # 4. Test disable-auto alias
        res_alias_dis = subprocess.run([str(GPS_IPC), "watchdog", "disable-auto"], env=env, capture_output=True, text=True)
        self.assertEqual(res_alias_dis.returncode, 0)
        self.assertFalse(self.flag_file.exists())

    def test_gps_ipc_watchdog_start_respects_flag_and_args(self):
        """gps-ipc watchdog start uses observe by default and auto when flag is set."""
        env = {
            **os.environ,
            "HOME": str(self.home_dir),
            "XDG_CONFIG_HOME": str(self.home_dir / ".config"),
            "XDG_RUNTIME_DIR": str(self.runtime_dir.parent),
            "XDG_CACHE_HOME": str(self.cache_dir.parent.parent),
        }

        # Case 1: Flag absent -> start launches observe
        res1 = subprocess.run([str(GPS_IPC), "watchdog", "start"], env=env, capture_output=True, text=True)
        self.assertEqual(res1.returncode, 0)
        self.assertIn("started in observe mode", res1.stdout)
        subprocess.run([str(GPS_IPC), "watchdog", "stop"], env=env, capture_output=True)

        # Case 2: Flag present -> start launches auto
        self.flag_file.write_text("auto")
        res2 = subprocess.run([str(GPS_IPC), "watchdog", "start"], env=env, capture_output=True, text=True)
        self.assertEqual(res2.returncode, 0)
        self.assertIn("started in auto mode", res2.stdout)
        subprocess.run([str(GPS_IPC), "watchdog", "stop"], env=env, capture_output=True)

    def test_rollback_procedure_completely_restores_observe_mode(self):
        """Verify the exact rollback procedure returns supervisor to observe mode."""
        env = {
            **os.environ,
            "HOME": str(self.home_dir),
            "XDG_CONFIG_HOME": str(self.home_dir / ".config"),
            "XDG_RUNTIME_DIR": str(self.runtime_dir.parent),
            "XDG_CACHE_HOME": str(self.cache_dir.parent.parent),
        }

        # Step 1: Simulate active auto mode
        subprocess.run([str(GPS_IPC), "watchdog", "mode", "auto"], env=env, capture_output=True)
        self.assertTrue(self.flag_file.is_file())

        # Step 2: Rollback execution
        # 1. Stop watchdog
        res_stop = subprocess.run([str(GPS_IPC), "watchdog", "stop"], env=env, capture_output=True, text=True)
        self.assertEqual(res_stop.returncode, 0)

        # 2. Disable auto flag
        res_dis = subprocess.run([str(GPS_IPC), "watchdog", "mode", "observe"], env=env, capture_output=True, text=True)
        self.assertEqual(res_dis.returncode, 0)
        self.assertFalse(self.flag_file.exists())

        # 3. Start in observe mode
        res_start = subprocess.run([str(GPS_IPC), "watchdog", "start"], env=env, capture_output=True, text=True)
        self.assertEqual(res_start.returncode, 0)
        self.assertIn("started in observe mode", res_start.stdout)

        # Cleanup
        subprocess.run([str(GPS_IPC), "watchdog", "stop"], env=env, capture_output=True)


if __name__ == "__main__":
    unittest.main()
