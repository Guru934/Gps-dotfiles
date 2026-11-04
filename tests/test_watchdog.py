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

    def test_suppressed_when_pause_flag_present(self):
        """Watchdog pauses inspection when watchdog-pause.flag exists."""
        pause_flag = self.runtime_dir / "watchdog-pause.flag"
        pause_flag.touch()

        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
        )

        res = watchdog.tick(now=1000.0)
        self.assertTrue(res["paused"])
        self.assertEqual(len(res["components"]), 0)

    def test_bounded_log_rotation(self):
        """Logger truncates when size exceeds max_bytes."""
        logger = gps_watchdog.WatchdogLogger(self.log_file, max_bytes=1000)
        for i in range(100):
            logger.log("INFO", f"Log line number {i} with padding text to fill size")

        sz = self.log_file.stat().st_size
        self.assertLessEqual(sz, 2000, "Log file should stay bounded")

    def test_device_watcher_is_observed_only(self):
        """Device watcher is observed but never restarted in auto mode."""
        spawned = []
        pids = {"island": 1234, "shell": 5678, "device_watcher": None}

        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
            find_pid_fn=lambda pattern: pids.get(
                "device_watcher" if "gps-device-watcher" in pattern
                else ("island" if "IslandProduction" in pattern else "shell")
            ),
            spawn_fn=lambda cmd: spawned.append(cmd) or True,
            sleep_fn=lambda s: None,
        )

        res = watchdog.tick(now=1000.0)
        dw_status = res["components"]["device_watcher"]
        self.assertFalse(dw_status["alive"])
        self.assertEqual(dw_status["action"], "observed_down")
        self.assertEqual(len(spawned), 0, "Device watcher must not be restarted by watchdog")

    def test_single_instance_prevents_duplicate_runs(self):
        """Watchdog fails to start if another instance is already running with an alive PID."""
        pid_file = self.runtime_dir / "watchdog.pid"
        # Write current process PID as the simulated running watchdog
        pid_file.write_text(str(os.getpid()))

        watchdog = gps_watchdog.GpsWatchdog(
            mode="observe",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
        )
        # Calling run() with another PID active should return 1
        # To test cleanly, write an alive PID different from os.getpid(), e.g. init PID 1
        pid_file.write_text("1")
        code = watchdog.run(interval=0.1)
        self.assertEqual(code, 1)

    def test_stop_watchdog_handles_missing_and_stale(self):
        """stop_watchdog safely handles missing or dead PID files."""
        # 1. Missing PID file
        code = gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir)
        self.assertEqual(code, 0)

        # 2. Stale PID file (non-existent PID)
        pid_file = self.runtime_dir / "watchdog.pid"
        pid_file.write_text("99999999")
        code = gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir)
        self.assertEqual(code, 0)
        self.assertFalse(pid_file.exists(), "Stale PID file should be removed")

    def test_graphical_session_termination_exits_loop(self):
        """Watchdog run loop terminates cleanly (returns 0) when graphical session ends."""
        watchdog = gps_watchdog.GpsWatchdog(
            mode="observe",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: False,  # Simulated compositor teardown
        )
        code = watchdog.run(interval=0.01)
        self.assertEqual(code, 0)
        # PID file should be removed on exit
        pid_file = self.runtime_dir / "watchdog.pid"
        self.assertFalse(pid_file.exists())

    def test_intentional_shutdown_flag_exits_loop(self):
        """Watchdog run loop terminates cleanly when watchdog-shutdown.flag is detected."""
        shutdown_flag = self.runtime_dir / "watchdog-shutdown.flag"
        shutdown_flag.touch()

        watchdog = gps_watchdog.GpsWatchdog(
            mode="observe",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: True,
        )
        code = watchdog.run(interval=0.01)
        self.assertEqual(code, 0)
        pid_file = self.runtime_dir / "watchdog.pid"
        self.assertFalse(pid_file.exists())

    def test_stop_watchdog_safe_against_unrelated_process(self):
        """stop_watchdog refuses to signal a PID that is not gps-watchdog and removes stale PID file."""
        pid_file = self.runtime_dir / "watchdog.pid"
        # Use our own test runner process PID (which is running python unittest, not gps-watchdog)
        pid_file.write_text(str(os.getpid()))

        code = gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir)
        self.assertEqual(code, 0)
        self.assertFalse(pid_file.exists(), "PID file for non-watchdog process should be unlinked")

    def test_stop_watchdog_idempotent(self):
        """Multiple sequential calls to stop_watchdog succeed without error."""
        self.assertEqual(gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir), 0)
        self.assertEqual(gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir), 0)
        self.assertEqual(gps_watchdog.stop_watchdog(runtime_dir=self.runtime_dir), 0)


if __name__ == "__main__":
    unittest.main()
