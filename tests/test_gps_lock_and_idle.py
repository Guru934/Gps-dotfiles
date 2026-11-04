#!/usr/bin/env python3
"""Automated unit and contract tests for unified lock wrapper (gps-lock) and idle controller (gps-idle)."""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tests.helpers import HermeticTestCase

SCRIPTS_DIR = ROOT / "scripts"
GPS_LOCK_SCRIPT = SCRIPTS_DIR / "gps-lock"
GPS_IDLE_SCRIPT = SCRIPTS_DIR / "gps-idle"


class GpsLockWrapperTests(HermeticTestCase):
    """Unit tests for scripts/gps-lock wrapper."""

    def setUp(self):
        super().setUp()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.mock_bin_dir = self.tmp_path / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = self.tmp_path / "lock_invocations.log"

    def tearDown(self):
        self.tmp_dir.cleanup()
        super().tearDown()

    def test_gps_lock_script_exists_and_executable(self):
        self.assertTrue(GPS_LOCK_SCRIPT.is_file())
        self.assertTrue(os.access(GPS_LOCK_SCRIPT, os.X_OK))

    def test_duplicate_guard_prevents_stacking(self):
        """When hyprlock is already running according to pidof, gps-lock exits 0 immediately."""
        mock_pidof = self.mock_bin_dir / "pidof"
        mock_pidof.write_text("#!/bin/sh\nexit 0\n")
        mock_pidof.chmod(mock_pidof.stat().st_mode | stat.S_IEXEC)

        mock_hyprlock = self.mock_bin_dir / "hyprlock"
        mock_hyprlock.write_text(f"#!/bin/sh\necho 'SPAWNED' >> '{self.log_file}'\n")
        mock_hyprlock.chmod(mock_hyprlock.stat().st_mode | stat.S_IEXEC)

        env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
        }

        res = subprocess.run([str(GPS_LOCK_SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertFalse(self.log_file.exists(), "hyprlock should not have been spawned when already running")

    def test_launches_resolved_executable_with_verified_config(self):
        """When not running, gps-lock executes hyprlock passing --config."""
        mock_pidof = self.mock_bin_dir / "pidof"
        mock_pidof.write_text("#!/bin/sh\nexit 1\n")
        mock_pidof.chmod(mock_pidof.stat().st_mode | stat.S_IEXEC)

        mock_hyprlock = self.mock_bin_dir / "hyprlock"
        mock_hyprlock.write_text(f"#!/bin/sh\necho \"$@\" >> '{self.log_file}'\n")
        mock_hyprlock.chmod(mock_hyprlock.stat().st_mode | stat.S_IEXEC)

        env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
        }

        res = subprocess.run([str(GPS_LOCK_SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.log_file.exists())
        invoked_args = self.log_file.read_text().strip()
        self.assertIn("--config", invoked_args)
        self.assertIn("hyprlock.conf", invoked_args)

    def test_reports_hyprlock_startup_failure_and_preserves_exit_status(self):
        mock_pidof = self.mock_bin_dir / "pidof"
        mock_pidof.write_text("#!/bin/sh\nexit 1\n")
        mock_pidof.chmod(mock_pidof.stat().st_mode | stat.S_IEXEC)

        mock_hyprlock = self.mock_bin_dir / "hyprlock"
        mock_hyprlock.write_text("#!/bin/sh\necho 'mock startup failure' >&2\nexit 42\n")
        mock_hyprlock.chmod(mock_hyprlock.stat().st_mode | stat.S_IEXEC)

        # Keep the hermetic failure-path test from posting into the user's live
        # notification server when the test runner inherits the desktop bus.
        mock_notify = self.mock_bin_dir / "notify-send"
        mock_notify.write_text("#!/bin/sh\nexit 0\n")
        mock_notify.chmod(mock_notify.stat().st_mode | stat.S_IEXEC)

        env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
            "XDG_CACHE_HOME": str(self.tmp_path / "cache"),
        }
        res = subprocess.run([str(GPS_LOCK_SCRIPT)], env=env, capture_output=True, text=True)

        self.assertEqual(res.returncode, 42)
        self.assertIn("hyprlock exited with status 42", res.stderr)
        self.assertIn("mock startup failure", res.stderr)
        failure_log = self.tmp_path / "cache/gps/logs/gps-lock.log"
        self.assertIn("mock startup failure", failure_log.read_text(encoding="utf-8"))

    def test_initializes_missing_avatar_conf_and_removes_legacy_symlink(self):
        """gps-lock creates ~/.config/gps/lock-avatar.conf if missing and unlinks legacy hypr symlink."""
        mock_pidof = self.mock_bin_dir / "pidof"
        mock_pidof.write_text("#!/bin/sh\nexit 1\n")
        mock_pidof.chmod(mock_pidof.stat().st_mode | stat.S_IEXEC)

        mock_hyprlock = self.mock_bin_dir / "hyprlock"
        mock_hyprlock.write_text(f"#!/bin/sh\necho 'LOCK_OK' >> '{self.log_file}'\nexit 0\n")
        mock_hyprlock.chmod(mock_hyprlock.stat().st_mode | stat.S_IEXEC)

        config_dir = self.tmp_path / "config"
        cache_dir = self.tmp_path / "cache"
        legacy_dir = config_dir / "hypr"
        legacy_dir.mkdir(parents=True, exist_ok=True)
        legacy_link = legacy_dir / "lock-avatar.conf"
        dummy_target = self.tmp_path / "dummy_repo_avatar.conf"
        dummy_target.write_text("# placeholder", encoding="utf-8")
        legacy_link.symlink_to(dummy_target)

        target_conf = config_dir / "gps" / "lock-avatar.conf"
        self.assertFalse(target_conf.exists())

        env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
            "XDG_CONFIG_HOME": str(config_dir),
            "XDG_CACHE_HOME": str(cache_dir),
        }

        res = subprocess.run([str(GPS_LOCK_SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.log_file.exists())
        self.assertFalse(legacy_link.exists() or legacy_link.is_symlink())
        self.assertTrue(target_conf.is_file())
        self.assertIn("$avatar =", target_conf.read_text(encoding="utf-8"))

    def test_handles_missing_or_failing_avatar_tool_without_failing_lock(self):
        """gps-lock still spawns hyprlock even if the avatar initialization tool fails."""
        mock_pidof = self.mock_bin_dir / "pidof"
        mock_pidof.write_text("#!/bin/sh\nexit 1\n")
        mock_pidof.chmod(mock_pidof.stat().st_mode | stat.S_IEXEC)

        mock_hyprlock = self.mock_bin_dir / "hyprlock"
        mock_hyprlock.write_text(f"#!/bin/sh\necho 'SPAWNED' >> '{self.log_file}'\nexit 0\n")
        mock_hyprlock.chmod(mock_hyprlock.stat().st_mode | stat.S_IEXEC)

        config_dir = self.tmp_path / "config"
        cache_dir = self.tmp_path / "cache"
        target_conf = config_dir / "gps" / "lock-avatar.conf"

        # Mock an avatar tool that crashes
        mock_avatar = self.mock_bin_dir / "gps-lock-avatar"
        mock_avatar.write_text("#!/bin/sh\nexit 1\n")
        mock_avatar.chmod(mock_avatar.stat().st_mode | stat.S_IEXEC)

        env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
            "XDG_CONFIG_HOME": str(config_dir),
            "XDG_CACHE_HOME": str(cache_dir),
        }

        res = subprocess.run([str(GPS_LOCK_SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.log_file.exists())
        self.assertTrue(target_conf.is_file())
        content = target_conf.read_text(encoding="utf-8")
        self.assertIn("$avatar =", content)
        # Verify the fallback image file actually exists on disk
        avatar_line = [l for l in content.splitlines() if l.startswith("$avatar =")][0]
        fallback_path = Path(avatar_line.split("=", 1)[1].strip())
        self.assertTrue(fallback_path.is_file(), f"Fallback avatar image must exist at {fallback_path}")
        self.assertGreater(fallback_path.stat().st_size, 0)


class GpsIdleControllerTests(HermeticTestCase):
    """Unit tests for scripts/gps-idle lifecycle management."""

    def setUp(self):
        super().setUp()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.pid_file = self.tmp_path / "gps-hypridle.pid"
        self.mock_bin_dir = self.tmp_path / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)

        # Mock hypridle binary that sleeps when launched
        self.mock_idle = self.mock_bin_dir / "hypridle"
        self.mock_idle.write_text("#!/usr/bin/env bash\nwhile :; do sleep 1; done\n")
        self.mock_idle.chmod(self.mock_idle.stat().st_mode | stat.S_IEXEC)

        self.env = {
            **self.hermetic.env,
            "PATH": f"{self.mock_bin_dir}:{self.hermetic.env.get('PATH', '')}",
            "GPS_IDLE_PID_FILE": str(self.pid_file),
        }

    def tearDown(self):
        # Stop any mock process if running
        if self.pid_file.exists():
            try:
                p = int(self.pid_file.read_text().strip())
                os.kill(p, 9)
            except Exception:
                pass
        self.tmp_dir.cleanup()
        super().tearDown()

    def test_gps_idle_script_exists_and_executable(self):
        self.assertTrue(GPS_IDLE_SCRIPT.is_file())
        self.assertTrue(os.access(GPS_IDLE_SCRIPT, os.X_OK))

    def test_idle_status_when_stopped(self):
        res = subprocess.run([str(GPS_IDLE_SCRIPT), "status"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("state=stopped", res.stdout)

    def test_idle_start_stop_lifecycle_and_pid_file(self):
        # 1. Start
        res_start = subprocess.run([str(GPS_IDLE_SCRIPT), "start"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res_start.returncode, 0)
        self.assertTrue(self.pid_file.exists())
        pid_str = self.pid_file.read_text().strip()
        pid = int(pid_str)
        self.assertGreater(pid, 0)

        # 2. Status while running
        res_status = subprocess.run([str(GPS_IDLE_SCRIPT), "status"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res_status.returncode, 0)
        self.assertIn(f"state=running pid={pid}", res_status.stdout)

        # 3. is-running command
        res_is_run = subprocess.run([str(GPS_IDLE_SCRIPT), "is-running"], env=self.env)
        self.assertEqual(res_is_run.returncode, 0)

        # 4. Stop
        res_stop = subprocess.run([str(GPS_IDLE_SCRIPT), "stop"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res_stop.returncode, 0)
        self.assertFalse(self.pid_file.exists())

        # Verify process is terminated (either gone or zombie waiting for init reap)
        def is_running_active(p):
            status_path = Path(f"/proc/{p}/status")
            if not status_path.exists():
                return False
            try:
                for line in status_path.read_text().splitlines():
                    if line.startswith("State:"):
                        return "Z" not in line
            except OSError:
                return False
            return True

        self.assertFalse(is_running_active(pid), "Mock hypridle process should have been terminated")

    def test_idle_env_status_output_format(self):
        res = subprocess.run([str(GPS_IDLE_SCRIPT), "env-status"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        lines = res.stdout.strip().split("\n")
        props = dict(line.split("=", 1) for line in lines if "=" in line)
        self.assertEqual(props.get("has_idle"), "1")
        self.assertIn(props.get("idle_run"), ["0", "1"])
        self.assertIn(props.get("idle_t"), ["150", "300"])


if __name__ == "__main__":
    unittest.main()
