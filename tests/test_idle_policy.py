#!/usr/bin/env python3
"""Automated unit and contract tests for GPS idle management and hypridle configuration."""
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
DOTS_HYPR_DIR = ROOT / "dots" / "hypr"
HYPRIDLE_CONF = DOTS_HYPR_DIR / "hypridle.conf"
IDLE_BRIGHT_SCRIPT = SCRIPTS_DIR / "gps-idle-bright"
IDLE_SUSPEND_SCRIPT = SCRIPTS_DIR / "gps-idle-suspend"


class HypridleConfigTests(HermeticTestCase):
    """Contract tests for hypridle.conf configuration file."""

    def test_hypridle_conf_exists(self):
        self.assertTrue(HYPRIDLE_CONF.is_file(), f"{HYPRIDLE_CONF} must exist")

    def test_hypridle_conf_syntax_and_registration(self):
        """Verify hypridle can parse the config and registers all four expected rules."""
        res = self.hermetic.run(
            ["hypridle", "-c", str(HYPRIDLE_CONF), "-v"],
            capture_output=True,
            text=True,
        )
        combined = (res.stdout or "") + (res.stderr or "")
        self.assertIn("Registered timeout rule for 150s", combined)
        self.assertIn("Registered timeout rule for 300s", combined)
        self.assertIn("Registered timeout rule for 330s", combined)
        self.assertIn("Registered timeout rule for 1200s", combined)
        self.assertIn("gps-idle-bright dim", combined)
        self.assertIn("gps-idle-bright restore", combined)
        self.assertIn("loginctl lock-session", combined)
        self.assertIn("hl.dsp.dpms({action = \"off\"})", combined)
        self.assertIn("hl.dsp.dpms({action = \"on\"})", combined)
        self.assertIn("gps-idle-suspend", combined)

    def test_temporary_idle_config_with_harmless_actions(self):
        """Verify temporary test config with harmless actions can be validated."""
        with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as f:
            f.write(
                "general {\n"
                "    lock_cmd = true\n"
                "    inhibit_sleep = 2\n"
                "}\n"
                "listener {\n"
                "    timeout = 1\n"
                "    on-timeout = true\n"
                "}\n"
            )
            temp_path = f.name
        try:
            res = self.hermetic.run(
                ["hypridle", "-c", temp_path, "-v"],
                capture_output=True,
                text=True,
            )
            combined = (res.stdout or "") + (res.stderr or "")
            self.assertIn("Registered timeout rule for 1s", combined)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)


class BrightnessSaveRestoreTests(HermeticTestCase):
    """Unit tests for gps-idle-bright save/restore logic with mocked brightnessctl."""

    def setUp(self):
        super().setUp()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.state_file = self.tmp_path / "saved_bright.state"
        self.log_file = self.tmp_path / "mock_log.txt"

        # Create mock brightnessctl executable
        self.mock_bin = self.tmp_path / "mock_brightnessctl"
        self.current_brightness = 180
        self.max_brightness = 254
        self.device = "intel_backlight"

        mock_script = (
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            f"LOG='{self.log_file}'\n"
            "echo \"$*\" >> \"$LOG\"\n"
            "case \"${1:-}\" in\n"
            "    -m)\n"
            f"        printf '{self.device},backlight,{self.current_brightness},71%%,{self.max_brightness}\\n'\n"
            "        ;;\n"
            "    -d)\n"
            "        case \"${3:-}\" in\n"
            f"            g) echo '{self.current_brightness}' ;;\n"
            f"            m) echo '{self.max_brightness}' ;;\n"
            "            -q) ;;\n"
            "        esac\n"
            "        ;;\n"
            "esac\n"
        )
        self.mock_bin.write_text(mock_script)
        self.mock_bin.chmod(self.mock_bin.stat().st_mode | stat.S_IEXEC)

        self.env = {
            **self.hermetic.env,
            "GPS_IDLE_STATE_FILE": str(self.state_file),
            "GPS_IDLE_BRIGHTNESS_BIN": str(self.mock_bin),
        }

    def tearDown(self):
        self.tmp_dir.cleanup()
        super().tearDown()

    def test_dim_saves_initial_brightness_and_dims_non_zero(self):
        res = subprocess.run(
            [str(IDLE_BRIGHT_SCRIPT), "dim"],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.state_file.exists())
        saved_text = self.state_file.read_text().strip()
        self.assertEqual(saved_text, f"{self.device} {self.current_brightness}")

        log = self.log_file.read_text()
        # Verify dim command set a safe non-zero brightness (10% of 254 = 25)
        self.assertIn(f"-d {self.device} -q set 25", log)

    def test_overlapping_dim_cycle_does_not_overwrite_saved_state(self):
        # Initial dim
        subprocess.run([str(IDLE_BRIGHT_SCRIPT), "dim"], env=self.env, check=True)
        initial_saved = self.state_file.read_text().strip()
        self.assertEqual(initial_saved, f"{self.device} {self.current_brightness}")

        # Modify current brightness in mock to simulate dimmed level
        mock_script_dimmed = (
            "#!/usr/bin/env bash\n"
            f"case \"${{1:-}}\" in\n"
            f"    -m) printf '{self.device},backlight,25,10%%,{self.max_brightness}\\n' ;;\n"
            f"    -d) case \"${{3:-}}\" in g) echo '25' ;; m) echo '{self.max_brightness}' ;; esac ;;\n"
            "esac\n"
        )
        self.mock_bin.write_text(mock_script_dimmed)

        # Second dim (overlapping cycle)
        subprocess.run([str(IDLE_BRIGHT_SCRIPT), "dim"], env=self.env, check=True)
        # Verify state file was NOT overwritten with 25
        self.assertEqual(self.state_file.read_text().strip(), f"{self.device} {self.current_brightness}")

    def test_restore_recovers_original_brightness_and_cleans_state(self):
        # Setup pre-existing state
        self.state_file.write_text(f"{self.device} {self.current_brightness}\n")

        res = subprocess.run(
            [str(IDLE_BRIGHT_SCRIPT), "restore"],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        self.assertFalse(self.state_file.exists())

        log = self.log_file.read_text()
        self.assertIn(f"-d {self.device} -q set {self.current_brightness}", log)

    def test_restore_without_saved_state_is_safe_noop(self):
        res = subprocess.run(
            [str(IDLE_BRIGHT_SCRIPT), "restore"],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)


class BatterySuspendTelemetryTests(HermeticTestCase):
    """Unit tests for gps-idle-suspend battery detection and safety checks."""

    def setUp(self):
        super().setUp()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.power_dir = self.tmp_path / "power_supply"
        self.power_dir.mkdir(parents=True, exist_ok=True)
        self.suspend_log = self.tmp_path / "suspend.log"

        # Mock suspend binary
        self.mock_suspend = self.tmp_path / "mock_suspend"
        self.mock_suspend.write_text(f"#!/bin/sh\necho 'SUSPEND_CALLED' >> '{self.suspend_log}'\n")
        self.mock_suspend.chmod(self.mock_suspend.stat().st_mode | stat.S_IEXEC)

        self.env = {
            **self.hermetic.env,
            "GPS_POWER_SUPPLY_DIR": str(self.power_dir),
            "GPS_IDLE_SUSPEND_BIN": str(self.mock_suspend),
        }

    def tearDown(self):
        self.tmp_dir.cleanup()
        super().tearDown()

    def _setup_power_devices(self, ac_online=1, bat_status="Charging"):
        ac_dir = self.power_dir / "ACAD"
        ac_dir.mkdir(parents=True, exist_ok=True)
        (ac_dir / "type").write_text("Mains\n")
        (ac_dir / "online").write_text(f"{ac_online}\n")

        if bat_status is not None:
            bat_dir = self.power_dir / "BAT1"
            bat_dir.mkdir(parents=True, exist_ok=True)
            (bat_dir / "type").write_text("Battery\n")
            (bat_dir / "status").write_text(f"{bat_status}\n")

    def test_ac_online_never_suspends(self):
        self._setup_power_devices(ac_online=1, bat_status="Charging")
        res = subprocess.run([str(IDLE_SUSPEND_SCRIPT), "check"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 1)
        self.assertIn("power_state=ac", res.stdout)

        # Run suspend command
        subprocess.run([str(IDLE_SUSPEND_SCRIPT)], env=self.env, check=True)
        self.assertFalse(self.suspend_log.exists())

    def test_discharging_battery_triggers_suspend(self):
        self._setup_power_devices(ac_online=0, bat_status="Discharging")
        res = subprocess.run([str(IDLE_SUSPEND_SCRIPT), "check"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("power_state=battery", res.stdout)

        # Run suspend command
        subprocess.run([str(IDLE_SUSPEND_SCRIPT)], env=self.env, check=True)
        self.assertTrue(self.suspend_log.exists())
        self.assertEqual(self.suspend_log.read_text().strip(), "SUSPEND_CALLED")

    def test_desktop_no_battery_never_suspends(self):
        self._setup_power_devices(ac_online=1, bat_status=None)
        res = subprocess.run([str(IDLE_SUSPEND_SCRIPT), "check"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 1)
        self.assertIn("power_state=ac", res.stdout)

        subprocess.run([str(IDLE_SUSPEND_SCRIPT)], env=self.env, check=True)
        self.assertFalse(self.suspend_log.exists())

    def test_ambiguous_telemetry_never_suspends(self):
        self._setup_power_devices(ac_online=0, bat_status="Unknown")
        res = subprocess.run([str(IDLE_SUSPEND_SCRIPT), "check"], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("power_state=unknown", res.stdout)

        subprocess.run([str(IDLE_SUSPEND_SCRIPT)], env=self.env, check=True)
        self.assertFalse(self.suspend_log.exists())


if __name__ == "__main__":
    unittest.main()
