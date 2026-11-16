import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GPS_TOOLBOX = ROOT / "scripts/gps-toolbox"
TOOLBOX_PRESETS_CONFIG = ROOT / "config/toolbox-presets.json"
TOOLBOX_AUTOS_CONFIG = ROOT / "config/toolbox-automations.json"
TOOLBOX_BACKEND = (ROOT / "components/ToolboxBackend.qml").read_text(encoding="utf-8")
TOOLBOX_WIN = (ROOT / "components/ToolboxWindow.qml").read_text(encoding="utf-8")


class ToolboxAutomationsPresetsTests(unittest.TestCase):
    """Verifies GPS Toolbox Automations, systemd user timer sync, and Workspace Presets (Phase 5)."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["XDG_STATE_HOME"] = self.temp_dir.name
        self.env["XDG_CONFIG_HOME"] = str(Path(self.temp_dir.name) / "config")
        self.env["GPS_TEST_NO_SYSTEMD"] = "1"
        self.state_dir = Path(self.temp_dir.name) / "gps/toolbox"
        self.systemd_user_dir = Path(self.temp_dir.name) / "config/systemd/user"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_cli(self, *args):
        cmd = [str(GPS_TOOLBOX)] + list(args)
        proc = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        return proc

    def test_shipped_default_configurations(self):
        """Verifies default presets and automations configurations are valid and marked non-sample."""
        self.assertTrue(TOOLBOX_PRESETS_CONFIG.is_file(), "config/toolbox-presets.json missing")
        self.assertTrue(TOOLBOX_AUTOS_CONFIG.is_file(), "config/toolbox-automations.json missing")

        presets = json.loads(TOOLBOX_PRESETS_CONFIG.read_text(encoding="utf-8"))
        self.assertIsInstance(presets, list)
        self.assertGreaterEqual(len(presets), 4)
        preset_ids = [p["id"] for p in presets]
        self.assertIn("p1", preset_ids)
        self.assertIn("p2", preset_ids)
        self.assertIn("p3", preset_ids)
        self.assertIn("p4", preset_ids)
        for p in presets:
            self.assertFalse(p.get("sample", False), f"Preset {p['id']} should not be marked sample")

        autos = json.loads(TOOLBOX_AUTOS_CONFIG.read_text(encoding="utf-8"))
        self.assertIsInstance(autos, list)
        self.assertGreaterEqual(len(autos), 3)
        for a in autos:
            self.assertFalse(a.get("sample", False), f"Automation {a['id']} should not be marked sample")
            self.assertEqual(a.get("state"), "paused")

    def test_automation_list_returns_defaults(self):
        """Verifies automation list loads default automations when user state is initialized."""
        res = self.run_cli("automation", "list")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIsInstance(data.get("automations"), list)
        self.assertGreaterEqual(len(data["automations"]), 3)

    def test_automation_lifecycle_and_systemd_sync(self):
        """Verifies automation creation, systemd timer compilation, state changes, and deletion."""
        new_auto = {
            "id": "test_morning",
            "name": "Morning Briefing",
            "description": "Opens development workspace on weekdays",
            "ttype": "schedule",
            "ttime": "08:30",
            "tdays": ["Mon", "Tue", "Wed", "Thu", "Fri"],
            "actions": ["open_dev_ws"],
            "state": "enabled"
        }
        res = self.run_cli("automation", "save", json.dumps(new_auto))
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))

        # Verify systemd timer unit files were written
        timer_file = self.systemd_user_dir / "gps-auto-test_morning.timer"
        service_file = self.systemd_user_dir / "gps-auto-test_morning.service"
        self.assertTrue(timer_file.is_file(), "Systemd timer file was not created")
        self.assertTrue(service_file.is_file(), "Systemd service file was not created")

        timer_content = timer_file.read_text(encoding="utf-8")
        self.assertIn("OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 08:30:00", timer_content)

        service_content = service_file.read_text(encoding="utf-8")
        self.assertIn("automation run test_morning", service_content)

        # Pause automation - timer unit files should be removed
        res_pause = self.run_cli("automation", "set-state", "test_morning", "paused")
        self.assertEqual(res_pause.returncode, 0)
        self.assertFalse(timer_file.exists(), "Timer file should be removed when paused")
        self.assertFalse(service_file.exists(), "Service file should be removed when paused")

        # Delete automation
        res_del = self.run_cli("automation", "delete", "test_morning")
        self.assertEqual(res_del.returncode, 0)
        res_list = self.run_cli("automation", "list")
        list_data = json.loads(res_list.stdout)
        auto_ids = [a["id"] for a in list_data.get("automations", [])]
        self.assertNotIn("test_morning", auto_ids)

    def test_automation_test_execution_and_journal(self):
        """Verifies testing an automation runs actions safely and records Activity event."""
        res = self.run_cli("automation", "test", "a2")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIn("Test run succeeded", data.get("result", ""))

        # Check history journal
        res_hist = self.run_cli("activity", "list")
        self.assertEqual(res_hist.returncode, 0)
        hist_data = json.loads(res_hist.stdout)
        events = hist_data.get("events", [])
        self.assertGreater(len(events), 0)
        latest = events[0]
        self.assertEqual(latest.get("trigger"), "Test")
        self.assertEqual(latest.get("automation"), "Bedtime Reminder")

    def test_preset_list_and_activate(self):
        """Verifies preset listing and activation dispatch."""
        res_list = self.run_cli("preset", "list")
        self.assertEqual(res_list.returncode, 0, res_list.stderr)
        presets_data = json.loads(res_list.stdout)
        self.assertTrue(presets_data.get("ok"))
        presets = presets_data.get("presets", [])
        self.assertGreaterEqual(len(presets), 4)

        # Activate Study preset
        res_act = self.run_cli("preset", "activate", "p2")
        self.assertEqual(res_act.returncode, 0, res_act.stderr)
        act_data = json.loads(res_act.stdout)
        self.assertTrue(act_data.get("ok"))
        self.assertEqual(act_data["preset"]["id"], "p2")

        # Check history journal for preset event
        res_hist = self.run_cli("activity", "list")
        hist_data = json.loads(res_hist.stdout)
        preset_events = [e for e in hist_data.get("events", []) if e.get("category") == "Presets"]
        self.assertGreater(len(preset_events), 0)
        self.assertIn("Study", preset_events[0].get("name", ""))

    def test_qml_wiring_and_contract(self):
        """Verifies ToolboxBackend and ToolboxWindow have all Phase 5 bindings."""
        self.assertIn("property var automations:", TOOLBOX_BACKEND)
        self.assertIn("property var presets:", TOOLBOX_BACKEND)
        self.assertIn("function saveAutomation(automation)", TOOLBOX_BACKEND)
        self.assertIn("function deleteAutomation(id)", TOOLBOX_BACKEND)
        self.assertIn("function setAutomationState(id, enabled)", TOOLBOX_BACKEND)
        self.assertIn("function testAutomation(id)", TOOLBOX_BACKEND)
        self.assertIn("function activatePreset(id)", TOOLBOX_BACKEND)

        self.assertIn("onAutomationSaved", TOOLBOX_BACKEND)
        self.assertIn("onAutomationDeleted", TOOLBOX_BACKEND)
        self.assertIn("onAutomationStateChangeRequested", TOOLBOX_BACKEND)
        self.assertIn("onAutomationTestRequested", TOOLBOX_BACKEND)
        self.assertIn("onScheduleCancelRequested", TOOLBOX_BACKEND)
        self.assertIn("onPresetActivateRequested", TOOLBOX_BACKEND)

        self.assertIn("automations: backend.automations", TOOLBOX_WIN)
        self.assertIn("presets: backend.presets", TOOLBOX_WIN)


if __name__ == "__main__":
    unittest.main()

