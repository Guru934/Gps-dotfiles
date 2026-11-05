import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GPS_TOOLBOX = ROOT / "scripts/gps-toolbox"
TOOLBOX_ACTIONS_CONFIG = ROOT / "config/toolbox-actions.json"
TOOLBOX_BACKEND = (ROOT / "components/ToolboxBackend.qml").read_text(encoding="utf-8")
TOOLBOX_WIN = (ROOT / "components/ToolboxWindow.qml").read_text(encoding="utf-8")


class ToolboxActionsTests(unittest.TestCase):
    """Verifies GPS Toolbox action whitelist, parameter validation, confirmation safety, and journal."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["XDG_STATE_HOME"] = self.temp_dir.name
        self.state_dir = Path(self.temp_dir.name) / "gps/toolbox"
        self.history_file = self.state_dir / "history.jsonl"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_cli(self, *args):
        cmd = [str(GPS_TOOLBOX)] + list(args)
        proc = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        return proc

    def test_whitelist_configuration_structure(self):
        """Verifies shipped config/toolbox-actions.json exists and defines expected actions."""
        self.assertTrue(TOOLBOX_ACTIONS_CONFIG.is_file())
        config = json.loads(TOOLBOX_ACTIONS_CONFIG.read_text(encoding="utf-8"))
        self.assertEqual(config.get("version"), 1)
        actions = config.get("actions", {})

        required_actions = [
            "lock_screen", "open_terminal", "open_browser", "open_dev_ws",
            "focus_start", "audio_controls", "scrcpy_launch", "set_volume",
            "set_brightness", "dnd_enable", "notify", "show_reminder",
            "screenshot", "record", "picker", "suspend", "reboot", "shutdown"
        ]
        for act_id in required_actions:
            self.assertIn(act_id, actions, f"Missing required whitelisted action: {act_id}")
            act = actions[act_id]
            self.assertIn("executable", act)
            self.assertIsInstance(act["executable"], list)
            self.assertGreater(len(act["executable"]), 0)
            self.assertIn("name", act)
            self.assertIn("category", act)

    def test_action_list_command(self):
        """Verifies action list subcommand returns all registered IDs."""
        res = self.run_cli("action", "list")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIn("lock_screen", data.get("available_ids", []))
        self.assertIn("open_terminal", data.get("available_ids", []))
        self.assertIn("focus_start", data.get("available_ids", []))

    def test_action_run_dry_run_and_journal_logging(self):
        """Verifies dry-run execution succeeds and appends an entry to history.jsonl."""
        self.assertFalse(self.history_file.exists())

        res = self.run_cli("action", "run", "lock_screen", "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertTrue(data.get("dry_run"))
        self.assertEqual(data.get("action"), "lock_screen")

        # Verify history file was written
        self.assertTrue(self.history_file.exists())
        lines = self.history_file.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 1)
        event = json.loads(lines[0])
        self.assertEqual(event.get("name"), "Lock Screen")
        self.assertEqual(event.get("result"), "completed")
        self.assertEqual(event.get("category"), "Desktop")

        # Verify activity list subcommand returns the event
        res_act = self.run_cli("activity", "list")
        self.assertEqual(res_act.returncode, 0)
        act_data = json.loads(res_act.stdout)
        self.assertEqual(act_data.get("count"), 1)
        self.assertEqual(act_data["events"][0]["name"], "Lock Screen")

    def test_action_run_parameter_validation(self):
        """Verifies action parameters are validated against regex schema."""
        # Valid volume level
        res_ok = self.run_cli("action", "run", "set_volume", json.dumps({"level": "75"}), "--dry-run")
        self.assertEqual(res_ok.returncode, 0, res_ok.stderr)

        # Invalid volume level (out of bounds or letters)
        res_bad1 = self.run_cli("action", "run", "set_volume", json.dumps({"level": "150"}), "--dry-run")
        self.assertNotEqual(res_bad1.returncode, 0)
        data_bad1 = json.loads(res_bad1.stdout)
        self.assertFalse(data_bad1.get("ok"))
        self.assertIn("pattern", data_bad1.get("error", ""))

        res_bad2 = self.run_cli("action", "run", "set_volume", json.dumps({"level": "abc"}), "--dry-run")
        self.assertNotEqual(res_bad2.returncode, 0)

    def test_destructive_action_confirmation_guard(self):
        """Verifies power actions require explicit confirmation flag."""
        # Run suspend without confirmation -> must be rejected
        res_unconfirmed = self.run_cli("action", "run", "suspend")
        self.assertNotEqual(res_unconfirmed.returncode, 0)
        data = json.loads(res_unconfirmed.stdout)
        self.assertFalse(data.get("ok"))
        self.assertTrue(data.get("requires_confirm"))

        # Run suspend with --dry-run or --confirmed -> permitted
        res_dry = self.run_cli("action", "run", "suspend", "--dry-run")
        self.assertEqual(res_dry.returncode, 0)

        # Parameter confirmed: true allows dry-run or confirmed dispatch
        res_param_confirm = self.run_cli("action", "run", "suspend", json.dumps({"confirmed": True}), "--dry-run")
        self.assertEqual(res_param_confirm.returncode, 0)

    def test_unregistered_action_rejected(self):
        """Verifies arbitrary actions not in whitelist are rejected."""
        res = self.run_cli("action", "run", "rm_rf_everything", "--dry-run")
        self.assertNotEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertFalse(data.get("ok"))
        self.assertIn("not registered", data.get("error", ""))

    def test_qml_action_and_activity_wiring(self):
        """Verifies ToolboxBackend and ToolboxWindow have action whitelist and activity processes."""
        self.assertIn("property var availableActionIds: []", TOOLBOX_BACKEND)
        self.assertIn("property var activityEvents: []", TOOLBOX_BACKEND)
        self.assertIn("listActionsProc", TOOLBOX_BACKEND)
        self.assertIn("listActivityProc", TOOLBOX_BACKEND)
        self.assertIn("runActionProc", TOOLBOX_BACKEND)
        self.assertIn("function runAction(actionId, params)", TOOLBOX_BACKEND)
        self.assertIn("availableActionIds: backend.availableActionIds", TOOLBOX_WIN)
        self.assertIn("activityEvents: backend.activityEvents", TOOLBOX_WIN)


if __name__ == "__main__":
    unittest.main()

