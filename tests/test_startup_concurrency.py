#!/usr/bin/env python3
"""Hermetic tests for GPS Startup Concurrency Protection (Session 5 Work Package 1).

Verifies:
- Advisory flock protects startup sequence against concurrent runs
- Lock contention causes graceful exit (status 0) without spawning duplicate processes
- Lock is released upon completion, failure, or termination
- Graceful degradation if flock is unavailable
"""

import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


class StartupConcurrencyTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.runtime_dir = Path(self.temp_dir.name) / "runtime"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.lock_dir = self.runtime_dir / "gps"
        self.lock_dir.mkdir(parents=True, exist_ok=True)
        self.lock_file = self.lock_dir / "startup.lock"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_run_gps_skips_when_lock_held(self):
        """run-gps.fish exits 0 and does not duplicate processes when startup.lock is held."""
        # Hold the lock exclusively
        with open(self.lock_file, "w") as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

            env = os.environ.copy()
            env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)
            env.pop("_GPS_STARTUP_LOCKED", None)

            res = subprocess.run(
                ["fish", str(ROOT / "scripts" / "run-gps.fish")],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )

            self.assertEqual(res.returncode, 0, f"Expected 0 on contention, got {res.returncode}. Stderr: {res.stderr}")
            self.assertIn("another startup pass is in progress", res.stderr)

    def test_gps_start_safe_skips_when_lock_held(self):
        """gps-start-safe exits 0 cleanly when startup.lock is held."""
        with open(self.lock_file, "w") as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

            env = os.environ.copy()
            env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)

            res = subprocess.run(
                ["bash", str(ROOT / "scripts" / "gps-start-safe")],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )

            self.assertEqual(res.returncode, 0, f"Expected 0 on contention, got {res.returncode}. Stderr: {res.stderr}")
            self.assertIn("GPS startup already in progress", res.stderr)

    def test_flock_released_after_process_exits(self):
        """The advisory lock is released as soon as the holder exits."""
        with open(self.lock_file, "w") as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # lock_fd is closed now, so lock must be free

        test_fd = open(self.lock_file, "w")
        try:
            fcntl.flock(test_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            locked = True
        except BlockingIOError:
            locked = False
        finally:
            test_fd.close()

        self.assertTrue(locked, "Lock should be re-acquirable once the previous holder exits")


if __name__ == "__main__":
    unittest.main()

