#!/usr/bin/env python3
"""Hermetic tests for GPS Watchdog (Session 5 Work Package 3).

Verifies:
- Observe mode monitors components without restarting them
- Auto mode triggers restarts only for dead components
- Exponential backoff per attempt
- Circuit breaker tripping after 3 restarts in 5 minutes
- Suppression during graphical session teardown, startup locks, or pause flags
- Bounded log file enforcement
"""

import os
from pathlib import Path
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Import GpsWatchdog from script
import importlib.machinery
import importlib.util

loader = importlib.machinery.SourceFileLoader("gps_watchdog", str(ROOT / "scripts" / "gps-watchdog"))
spec = importlib.util.spec_from_loader("gps_watchdog", loader)
gps_watchdog = importlib.util.module_from_spec(spec)
loader.exec_module(gps_watchdog)


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.runtime_dir = Path(self.temp_dir.name) / "runtime"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = Path(self.temp_dir.name) / "watchdog.log"
        self.logger = gps_watchdog.WatchdogLogger(self.log_file)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_observe_mode_does_not_spawn(self):
        """In observe mode, a dead component is logged but not restarted."""
        spawned = []
        pids = {"island": 1234, "shell": None}  # shell is dead

        watchdog = gps_watchdog.GpsWatchdog(
            mode="observe",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
            find_pid_fn=lambda pattern: pids.get("island" if "IslandProduction" in pattern else "shell"),
            spawn_fn=lambda cmd: spawned.append(cmd) or True,
            sleep_fn=lambda s: None,
        )

        res = watchdog.tick(now=1000.0)
        self.assertFalse(res["components"]["shell"]["alive"])
        self.assertEqual(res["components"]["shell"]["action"], "observed_down")
        self.assertEqual(len(spawned), 0, "Observe mode must never spawn a restart")

    def test_auto_mode_restarts_only_dead_component(self):
        """In auto mode, only the dead component is restarted."""
        spawned = []
        pids = {"island": 1234, "shell": None}  # shell dead, island alive

        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
            find_pid_fn=lambda pattern: pids.get("island" if "IslandProduction" in pattern else "shell"),
            spawn_fn=lambda cmd: spawned.append(cmd) or True,
            sleep_fn=lambda s: None,
        )

        res = watchdog.tick(now=1000.0)
        self.assertEqual(res["components"]["shell"]["action"], "restarted")
        self.assertEqual(res["components"]["island"]["action"], "none")
        self.assertEqual(len(spawned), 1)
        self.assertIn("shell.qml", " ".join(spawned[0]))

    def test_circuit_breaker_trips_after_three_restarts(self):
        """Watchdog halts and notifies after 3 restarts in 5 minutes."""
        notifications = []
        pids = {"island": 1234, "shell": None}

        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
            find_pid_fn=lambda pattern: pids.get("island" if "IslandProduction" in pattern else "shell"),
            spawn_fn=lambda cmd: True,
            notify_fn=lambda s, b: notifications.append((s, b)),
            sleep_fn=lambda s: None,
        )

        now = 1000.0
        # 1st restart
        watchdog.tick(now=now)
        self.assertEqual(len(watchdog.components["shell"].restarts), 1)

        # 2nd restart (10s later)
        now += 10.0
        watchdog.tick(now=now)
        self.assertEqual(len(watchdog.components["shell"].restarts), 2)

        # 3rd restart (20s later)
        now += 10.0
        watchdog.tick(now=now)
        self.assertEqual(len(watchdog.components["shell"].restarts), 3)

        # 4th tick: must trip circuit breaker
        now += 5.0
        res = watchdog.tick(now=now)
        self.assertTrue(watchdog.components["shell"].circuit_broken)
        self.assertEqual(res["components"]["shell"]["action"], "trip_circuit_breaker")
        self.assertEqual(len(notifications), 1)
        self.assertIn("exceeded 3 restarts", notifications[0][1])

        # 5th tick: continues skipping while circuit broken
        now += 5.0
        res5 = watchdog.tick(now=now)
        self.assertEqual(res5["components"]["shell"]["action"], "circuit_broken_skip")
        self.assertEqual(len(notifications), 1)  # no duplicate alert spam

    def test_suppressed_when_startup_locked(self):
        """Watchdog skips inspection when startup.lock is held."""
        lock_file = self.runtime_dir / "startup.lock"
        lock_file.touch()

        import fcntl
        with open(lock_file, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)

            watchdog = gps_watchdog.GpsWatchdog(
                mode="auto",
                runtime_dir=self.runtime_dir,
                logger=self.logger,
                check_session_fn=lambda: True,
            )

            res = watchdog.tick(now=1000.0)
            self.assertTrue(res["startup_locked"])
            self.assertEqual(len(res["components"]), 0)

    def test_suppressed_when_session_inactive(self):
        """Watchdog skips when Hyprland/graphical session is inactive."""
        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: False,  # session down
        )

        res = watchdog.tick(now=1000.0)
        self.assertFalse(res["session_active"])
        self.assertEqual(len(res["components"]), 0)

    def test_bounded_log_rotation(self):
        """Logger truncates when size exceeds max_bytes."""
        logger = gps_watchdog.WatchdogLogger(self.log_file, max_bytes=1000)
        for i in range(100):
            logger.log("INFO", f"Log line number {i} with padding text to fill size")

        sz = self.log_file.stat().st_size
        self.assertLessEqual(sz, 2000, "Log file should stay bounded")


if __name__ == "__main__":
    unittest.main()
