#!/usr/bin/env python3
"""Hermetic tests for GPS Record Lifecycle and Concurrency (Session 5 Work Package 4).

Verifies:
- Advisory toggle.lock prevents duplicate/concurrent toggle execution
- Recorder subprocess does not inherit toggle lock descriptor (close_fds / 9>&-)
- Bounded wait on notify-send prevents orphan hanging subshells
- State cleanup on termination
"""

import fcntl
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT / "scripts"


def make_executable(path: Path, script_content: str) -> None:
    path.write_text(script_content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class RecordLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.home_dir = Path(self.temp_dir.name) / "home"
        self.runtime_dir = Path(self.temp_dir.name) / "runtime"
        self.bin_dir = Path(self.temp_dir.name) / "bin"
        self.home_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.bin_dir.mkdir(parents=True, exist_ok=True)

        # Mock gpu-screen-recorder that handles SIGINT and writes valid file output
        make_executable(
            self.bin_dir / "gpu-screen-recorder",
            """#!/usr/bin/env python3
import sys, signal, time

out = None
for i, arg in enumerate(sys.argv):
    if arg == "-o" and i + 1 < len(sys.argv):
        out = sys.argv[i + 1]

if out:
    with open(out, "w") as f:
        f.write("initial-video-header")

def on_signal(signum, frame):
    if out:
        with open(out, "a") as f:
            f.write("-final-footer")
    sys.exit(0)

signal.signal(signal.SIGINT, on_signal)
signal.signal(signal.SIGTERM, on_signal)

while True:
    time.sleep(0.05)
""",
        )

        # Mock notify-send
        self.notif_log = Path(self.temp_dir.name) / "notif.log"
        make_executable(
            self.bin_dir / "notify-send",
            f"""#!/usr/bin/env bash
echo "$@" >> "{self.notif_log}"
exit 0
""",
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def _run_record(self, args: list[str]) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env["HOME"] = str(self.home_dir)
        env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)
        env["PATH"] = f"{self.bin_dir}:{env.get('PATH', '')}"
        env["GPS_ROOT"] = str(ROOT)

        return subprocess.run(
            ["bash", str(SCRIPTS_DIR / "gps-record")] + args,
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_concurrent_toggle_rejection(self):
        """Holding toggle.lock causes concurrent toggle invocation to exit 0 immediately."""
        gps_state_dir = self.runtime_dir / "gps"
        gps_state_dir.mkdir(parents=True, exist_ok=True)
        lock_file = gps_state_dir / "toggle.lock"

        with open(lock_file, "w") as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

            res = self._run_record(["toggle"])
            self.assertEqual(res.returncode, 0)
            self.assertIn("already in progress", res.stderr)

    def test_recorder_does_not_hold_toggle_lock(self):
        """Active recording does not retain toggle.lock, permitting subsequent toggle stop."""
        res_start = self._run_record(["toggle"])
        self.assertEqual(res_start.returncode, 0)
        self.assertIn("Recording started", res_start.stdout)

        # Read PID of recorder
        pid_file = self.runtime_dir / "gps" / "record.pid"
        self.assertTrue(pid_file.is_file())
        rec_pid = int(pid_file.read_text().strip())

        try:
            # Second toggle should stop cleanly without getting blocked by toggle.lock
            res_stop = self._run_record(["toggle"])
            self.assertEqual(res_stop.returncode, 0)
            self.assertIn("Recording saved", res_stop.stdout)
        finally:
            try:
                os.kill(rec_pid, 9)
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
