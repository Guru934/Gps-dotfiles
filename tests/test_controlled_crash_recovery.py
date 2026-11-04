#!/usr/bin/env python3
"""Controlled Crash Recovery Validation Suite (Session 5 Phase 5).

Validates the GPS Watchdog's automatic recovery mode using isolated stub processes
and simulated failure scenarios. Under no circumstances touches the live desktop.

Scenarios tested:
- Scenario A: Island exits unexpectedly -> Only Island recovered
- Scenario B: Main shell exits unexpectedly -> Only Shell recovered, no duplicate watcher
- Scenario C: Device watcher exits -> Observed only, no whole-desktop restart
- Scenario D: Repeated crashes -> Bounded retries (3 in 5m), backoff (2s, 5s, 15s), circuit breaker
- Scenario E: Intentional GPS shutdown -> Zero auto-recovery attempts, clean exit
- Scenario F: Graphical session termination -> Watchdog stops and cleans up PID file
- Scenario G: Duplicate watchdog launch -> Second instance rejected, exactly one supervisor active
- Full CLI subprocess test: Real execution of scripts/gps-watchdog --mode auto in isolated env
"""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Import gps-watchdog dynamically
import importlib.machinery
import importlib.util

loader = importlib.machinery.SourceFileLoader("gps_watchdog", str(ROOT / "scripts" / "gps-watchdog"))
spec = importlib.util.spec_from_loader("gps_watchdog", loader)
gps_watchdog = importlib.util.module_from_spec(spec)
loader.exec_module(gps_watchdog)


class ControlledCrashRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_root = Path(self.temp_dir.name)

        # Isolated directories
        self.home_dir = self.test_root / "home"
        self.home_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir = self.test_root / "runtime" / "gps"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir = self.test_root / "cache" / "gps" / "logs"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.bin_dir = self.test_root / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)

        self.log_file = self.cache_dir / "watchdog.log"
        self.logger = gps_watchdog.WatchdogLogger(self.log_file)

        # Stub notify-send
        self.notif_log = self.test_root / "notifications.log"
        self.stub_notify = self.bin_dir / "notify-send"
        self.stub_notify.write_text(
            f"#!/bin/sh\necho \"$@\" >> '{self.notif_log}'\nexit 0\n"
        )
        self.stub_notify.chmod(self.stub_notify.stat().st_mode | stat.S_IEXEC)

        # Stub hyprctl
        self.stub_hyprctl = self.bin_dir / "hyprctl"
        self.stub_hyprctl.write_text(
            "#!/bin/sh\nif [ \"$1\" = \"version\" ]; then echo 'Hyprland 0.53.0'; exit 0; fi\nexit 0\n"
        )
        self.stub_hyprctl.chmod(self.stub_hyprctl.stat().st_mode | stat.S_IEXEC)

        # Stub quickshell invocation log
        self.qs_log = self.test_root / "quickshell_invocations.log"
        self.stub_quickshell = self.bin_dir / "quickshell"
        self.stub_quickshell.write_text(
            f"#!/bin/sh\necho \"$@\" >> '{self.qs_log}'\nexit 0\n"
        )
        self.stub_quickshell.chmod(self.stub_quickshell.stat().st_mode | stat.S_IEXEC)

    def tearDown(self):
        self.temp_dir.cleanup()

    # -------------------------------------------------------------------------
    # Scenario A: Island exits unexpectedly
    # -------------------------------------------------------------------------
    def test_scenario_a_island_unexpected_exit_recovers_only_island(self):
        """When Island crashes, watchdog in auto mode restarts ONLY Island with 2s backoff."""
        spawned = []
        backoffs = []
        # State: Island is dead (None), Shell is alive (101), Device watcher is alive (102)
        pids = {"island": None, "shell": 101, "device_watcher": 102}

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
            sleep_fn=lambda s: backoffs.append(s),
        )

        res = watchdog.tick(now=1000.0)

        # 1. Island recovered
        self.assertFalse(res["components"]["island"]["alive"])
        self.assertEqual(res["components"]["island"]["action"], "restarted")
        self.assertEqual(res["components"]["island"]["restart_count"], 1)

        # 2. Backoff was 2.0s (attempt 1)
        self.assertEqual(backoffs, [2.0])

        # 3. Only Island was spawned
        self.assertEqual(len(spawned), 1)
        self.assertIn("IslandProduction.qml", " ".join(spawned[0]))
        self.assertNotIn("shell.qml", " ".join(spawned[0]))

        # 4. Shell and Device Watcher remain untouched
        self.assertTrue(res["components"]["shell"]["alive"])
        self.assertEqual(res["components"]["shell"]["action"], "none")
        self.assertEqual(res["components"]["shell"]["restart_count"], 0)

        self.assertTrue(res["components"]["device_watcher"]["alive"])
        self.assertEqual(res["components"]["device_watcher"]["action"], "none")

    # -------------------------------------------------------------------------
    # Scenario B: Main shell exits unexpectedly
    # -------------------------------------------------------------------------
    def test_scenario_b_shell_unexpected_exit_recovers_only_shell(self):
        """When Shell crashes, watchdog restarts ONLY Shell; does not duplicate Island or watcher."""
        spawned = []
        backoffs = []
        # State: Island is alive (201), Shell is dead (None), Device watcher is dead (None)
        pids = {"island": 201, "shell": None, "device_watcher": None}

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
            sleep_fn=lambda s: backoffs.append(s),
        )

        res = watchdog.tick(now=2000.0)

        # 1. Shell was restarted
        self.assertFalse(res["components"]["shell"]["alive"])
        self.assertEqual(res["components"]["shell"]["action"], "restarted")
        self.assertEqual(res["components"]["shell"]["restart_count"], 1)
        self.assertEqual(backoffs, [2.0])

        # 2. Island was NOT restarted
        self.assertTrue(res["components"]["island"]["alive"])
        self.assertEqual(res["components"]["island"]["action"], "none")

        # 3. Device watcher was NOT spawned by watchdog (observed_only)
        self.assertFalse(res["components"]["device_watcher"]["alive"])
        self.assertEqual(res["components"]["device_watcher"]["action"], "observed_down")

        # 4. Only one command spawned overall (the shell)
        self.assertEqual(len(spawned), 1)
        self.assertIn("shell.qml", " ".join(spawned[0]))
        self.assertNotIn("gps-device-watcher", " ".join(spawned[0]))

    # -------------------------------------------------------------------------
    # Scenario C: Device watcher exits
    # -------------------------------------------------------------------------
    def test_scenario_c_device_watcher_exit_observed_only_no_full_restart(self):
        """When Device watcher exits, watchdog marks observed_down and does NOT restart desktop."""
        spawned = []
        pids = {"island": 301, "shell": 302, "device_watcher": None}

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

        res = watchdog.tick(now=3000.0)

        # Watcher is observed down
        self.assertFalse(res["components"]["device_watcher"]["alive"])
        self.assertEqual(res["components"]["device_watcher"]["action"], "observed_down")

        # Desktop (Island and Shell) remains active and untouched
        self.assertTrue(res["components"]["island"]["alive"])
        self.assertEqual(res["components"]["island"]["action"], "none")
        self.assertTrue(res["components"]["shell"]["alive"])
        self.assertEqual(res["components"]["shell"]["action"], "none")

        # Zero processes spawned by watchdog
        self.assertEqual(len(spawned), 0, "Watchdog must not spawn device-watcher or desktop restart")

    # -------------------------------------------------------------------------
    # Scenario D: Repeated crashes, exponential backoff, and circuit breaker
    # -------------------------------------------------------------------------
    def test_scenario_d_repeated_crashes_backoff_and_circuit_breaker(self):
        """Repeated crashes apply 2s, 5s, 15s backoff, then trip circuit breaker with alert."""
        spawned = []
        backoffs = []
        notifications = []
        pids = {"island": 401, "shell": None, "device_watcher": 402}

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
            notify_fn=lambda s, b: notifications.append((s, b)),
            sleep_fn=lambda s: backoffs.append(s),
        )

        now = 10000.0

        # Attempt 1
        res1 = watchdog.tick(now=now)
        self.assertEqual(res1["components"]["shell"]["action"], "restarted")
        self.assertEqual(backoffs, [2.0])
        self.assertEqual(len(spawned), 1)

        # Attempt 2 (10s later)
        now += 10.0
        res2 = watchdog.tick(now=now)
        self.assertEqual(res2["components"]["shell"]["action"], "restarted")
        self.assertEqual(backoffs, [2.0, 5.0])
        self.assertEqual(len(spawned), 2)

        # Attempt 3 (20s later)
        now += 20.0
        res3 = watchdog.tick(now=now)
        self.assertEqual(res3["components"]["shell"]["action"], "restarted")
        self.assertEqual(backoffs, [2.0, 5.0, 15.0])
        self.assertEqual(len(spawned), 3)

        # Attempt 4 (10s later) -> Exceeded 3 attempts in 5m!
        now += 10.0
        res4 = watchdog.tick(now=now)
        self.assertEqual(res4["components"]["shell"]["action"], "trip_circuit_breaker")
        self.assertTrue(res4["components"]["shell"]["circuit_broken"])
        self.assertEqual(len(spawned), 3, "No 4th spawn allowed")
        self.assertEqual(len(notifications), 1)
        self.assertIn("GPS Watchdog Alert", notifications[0][0])
        self.assertIn("exceeded 3 restarts", notifications[0][1])

        # Attempt 5 (5s later) -> Remains circuit broken, no duplicate alert
        now += 5.0
        res5 = watchdog.tick(now=now)
        self.assertEqual(res5["components"]["shell"]["action"], "circuit_broken_skip")
        self.assertEqual(len(spawned), 3)
        self.assertEqual(len(notifications), 1)

    # -------------------------------------------------------------------------
    # Scenario E: Intentional GPS shutdown
    # -------------------------------------------------------------------------
    def test_scenario_e_intentional_gps_shutdown_suppresses_recovery(self):
        """When watchdog-shutdown.flag is set, watchdog performs 0 restarts and exits cleanly."""
        shutdown_flag = self.runtime_dir / "watchdog-shutdown.flag"
        shutdown_flag.touch()

        spawned = []
        # All components dead during shutdown
        pids = {"island": None, "shell": None, "device_watcher": None}

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

        res = watchdog.tick(now=5000.0)
        self.assertTrue(res["shutdown"])
        self.assertEqual(len(res["components"]), 0)
        self.assertEqual(len(spawned), 0, "No components must be recovered during intentional shutdown")

        # Calling run() should exit immediately with 0
        code = watchdog.run(interval=0.01)
        self.assertEqual(code, 0)
        self.assertFalse((self.runtime_dir / "watchdog.pid").exists())

    # -------------------------------------------------------------------------
    # Scenario F: Graphical session termination
    # -------------------------------------------------------------------------
    def test_scenario_f_graphical_session_termination_cleans_up_and_exits(self):
        """When compositor teardown occurs (check_session_fn=False), watchdog exits cleanly."""
        spawned = []
        watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
            check_session_fn=lambda: False,  # compositor gone
            spawn_fn=lambda cmd: spawned.append(cmd) or True,
        )

        res = watchdog.tick(now=6000.0)
        self.assertFalse(res["session_active"])
        self.assertEqual(len(spawned), 0)

        # run loop must terminate cleanly and remove PID file
        code = watchdog.run(interval=0.01)
        self.assertEqual(code, 0)
        self.assertFalse((self.runtime_dir / "watchdog.pid").exists())

    # -------------------------------------------------------------------------
    # Scenario G: Duplicate watchdog launch
    # -------------------------------------------------------------------------
    def test_scenario_g_duplicate_watchdog_launch_rejected(self):
        """A second watchdog instance in the same runtime dir is rejected with exit code 1."""
        pid_file = self.runtime_dir / "watchdog.pid"
        # Simulate active first watchdog with current PID
        pid_file.write_text(str(os.getpid()))

        second_watchdog = gps_watchdog.GpsWatchdog(
            mode="auto",
            runtime_dir=self.runtime_dir,
            logger=self.logger,
        )

        # When second instance attempts to run, it should fail
        # To test cleanly, write an alive PID different from os.getpid() (e.g. init PID 1)
        pid_file.write_text("1")
        code = second_watchdog.run(interval=0.01)
        self.assertEqual(code, 1, "Duplicate watchdog instance must exit with error 1")

    # -------------------------------------------------------------------------
    # End-to-End CLI Subprocess Test in Isolated Sandbox
    # -------------------------------------------------------------------------
    def test_e2e_cli_auto_mode_in_isolated_environment(self):
        """Run scripts/gps-watchdog --mode auto as an actual CLI subprocess in isolated environment."""
        env = {
            **os.environ,
            "HOME": str(self.home_dir),
            "XDG_RUNTIME_DIR": str(self.runtime_dir.parent),  # runtime dir base
            "XDG_CACHE_HOME": str(self.cache_dir.parent.parent),
            "PATH": f"{self.bin_dir}:{os.environ.get('PATH', '')}",
        }

        # 1. Start watchdog via CLI in background
        proc = subprocess.Popen(
            ["python3", str(ROOT / "scripts" / "gps-watchdog"), "--mode", "auto", "--interval", "0.2"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        try:
            # Wait up to 2 seconds for watchdog.pid to be created
            pid_file = self.runtime_dir / "watchdog.pid"
            for _ in range(20):
                if pid_file.is_file():
                    break
                time.sleep(0.1)

            self.assertTrue(pid_file.is_file(), "CLI watchdog did not create watchdog.pid in isolated env")
            recorded_pid = int(pid_file.read_text().strip())
            self.assertEqual(recorded_pid, proc.pid)

            # 2. Check --status via CLI
            res_status = subprocess.run(
                ["python3", str(ROOT / "scripts" / "gps-watchdog"), "--status"],
                env=env,
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(res_status.returncode, 0)
            self.assertIn('"mode": "auto"', res_status.stdout)

            # 3. Test duplicate launch rejection via CLI
            res_dup = subprocess.run(
                ["python3", str(ROOT / "scripts" / "gps-watchdog"), "--mode", "auto"],
                env=env,
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(res_dup.returncode, 1)
            self.assertIn("already running", res_dup.stderr)

            # 4. Stop watchdog cleanly via CLI --stop
            res_stop = subprocess.run(
                ["python3", str(ROOT / "scripts" / "gps-watchdog"), "--stop"],
                env=env,
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(res_stop.returncode, 0)
            self.assertIn("stopped", res_stop.stdout)

            proc.wait(timeout=3)
            self.assertEqual(proc.returncode, 0)
            self.assertFalse(pid_file.exists(), "watchdog.pid should be unlinked after clean stop")

        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=2)
            if proc.stdout:
                proc.stdout.close()
            if proc.stderr:
                proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
