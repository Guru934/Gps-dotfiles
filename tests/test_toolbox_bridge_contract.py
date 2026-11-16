import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GPS_TOOLBOX = ROOT / "scripts/gps-toolbox"
TOOLBOX_ACTIONS_CONFIG = ROOT / "config/toolbox-actions.json"


class ToolboxBridgeContractTests(unittest.TestCase):
    """Hermetic contract tests for GPS Bridge rice-side extensions (Phase 1)."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["XDG_STATE_HOME"] = self.temp_dir.name
        self.env["GPS_ROOT"] = str(ROOT)
        self.state_dir = Path(self.temp_dir.name) / "gps/toolbox"
        self.history_file = self.state_dir / "history.jsonl"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_cli(self, *args, env_override=None):
        cmd = [str(GPS_TOOLBOX)] + list(args)
        run_env = env_override or self.env
        proc = subprocess.run(cmd, capture_output=True, text=True, env=run_env)
        return proc

    # 1. Describe Subcommand ───────────────────────────────────────────────────

    def test_describe_json_contract(self):
        """Verifies describe --json outputs structured metadata without leaking executables."""
        res = self.run_cli("describe", "--json")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertGreaterEqual(data.get("count", 0), 25)

        actions = data.get("actions", [])
        self.assertIsInstance(actions, list)

        action_map = {act["id"]: act for act in actions}

        # Check required fields and lack of executable leakage
        for act in actions:
            self.assertIn("id", act)
            self.assertIn("title", act)
            self.assertIn("description", act)
            self.assertIn("category", act)
            self.assertIn("param_schema", act)
            self.assertIn("risk", act)
            self.assertIn("confirm", act)
            self.assertIn("assistant_allowed", act)
            self.assertIn("ui_only", act)

            # Security: Must NOT leak internal executable
            self.assertNotIn("executable", act)

        # Alias: action describe --json must also succeed with identical count
        res_alias = self.run_cli("action", "describe", "--json")
        self.assertEqual(res_alias.returncode, 0)
        data_alias = json.loads(res_alias.stdout)
        self.assertEqual(data_alias.get("count"), data.get("count"))

        # Verify power actions are strictly blocked from assistant
        for power_act in ("suspend", "reboot", "shutdown"):
            self.assertIn(power_act, action_map)
            self.assertFalse(action_map[power_act]["assistant_allowed"])
            self.assertFalse(action_map[power_act]["ui_only"])
            self.assertEqual(action_map[power_act]["risk"], "destructive")

        # Verify medium-risk actions require voice confirmation
        for med_act in ("lock_screen", "record", "scrcpy_launch"):
            self.assertIn(med_act, action_map)
            self.assertTrue(action_map[med_act]["assistant_allowed"])
            self.assertTrue(action_map[med_act]["confirm"])
            self.assertEqual(action_map[med_act]["risk"], "medium")
            self.assertFalse(action_map[med_act]["ui_only"])

        # Verify UI-only actions
        ui_only_expected = [
            "toggle_toolbox", "open_toolbox", "close_toolbox",
            "toggle_media_hub", "open_media_hub", "close_media_hub",
            "toggle_dashboard", "open_dashboard", "close_dashboard",
            "toggle_notif_center", "toggle_clipboard",
            "open_wallpaper_picker", "wallpaper_next", "wallpaper_prev",
            "set_volume", "set_brightness", "dnd_enable", "audio_controls"
        ]
        for ui_act in ui_only_expected:
            self.assertIn(ui_act, action_map, f"Missing expected action: {ui_act}")
            self.assertTrue(action_map[ui_act]["ui_only"], f"{ui_act} should be ui_only: True")
            self.assertTrue(action_map[ui_act]["assistant_allowed"])
            self.assertEqual(action_map[ui_act]["risk"], "safe")

    # 2. Status Subcommand & Fault Isolation ────────────────────────────────────

    def test_status_json_contract(self):
        """Verifies status --json aggregates live desktop state."""
        res = self.run_cli("status", "--json")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIn("timestamp", data)

        required_sections = [
            "hyprland", "notifications", "focus", "wallpaper",
            "audio", "brightness", "recording", "devices",
            "quickshell", "lock"
        ]
        for sec in required_sections:
            self.assertIn(sec, data)
            self.assertIsInstance(data[sec], dict)
            self.assertIn("available", data[sec])

    def test_status_hermetic_fault_isolation(self):
        """Verifies status --json succeeds with exit 0 and per-field unavailable if probes fail."""
        # Run with empty PATH so external CLI tools are missing
        stripped_env = self.env.copy()
        stripped_env["PATH"] = "/bin:/usr/bin"
        stripped_env["HYPRLAND_INSTANCE_SIGNATURE"] = ""

        res = self.run_cli("status", "--json", env_override=stripped_env)
        self.assertEqual(res.returncode, 0, "status must never crash or exit non-zero on probe failures")
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))

        # Every section is still a dict with available boolean
        for key in ["hyprland", "notifications", "focus", "wallpaper", "audio", "brightness", "recording", "devices", "quickshell", "lock"]:
            self.assertIn(key, data)
            self.assertIsInstance(data[key], dict)
            self.assertIn("available", data[key])

    # 3. Action Run with --source assistant ─────────────────────────────────────

    def test_assistant_source_allowed_action(self):
        """Verifies running an allowed action with --source assistant logs correct trigger and details."""
        res = self.run_cli("action", "run", "toggle_toolbox", "--source", "assistant", "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertEqual(data.get("event", {}).get("trigger"), "Assistant")
        self.assertEqual(data.get("event", {}).get("source"), "assistant")
        self.assertIn("via assistant", data.get("event", {}).get("details", ""))

        # Verify entry in history.jsonl
        self.assertTrue(self.history_file.exists())
        lines = self.history_file.read_text(encoding="utf-8").strip().splitlines()
        event = json.loads(lines[-1])
        self.assertEqual(event.get("trigger"), "Assistant")
        self.assertEqual(event.get("source"), "assistant")
        self.assertIn("via assistant", event.get("details", ""))

    def test_assistant_source_rejects_unallowed_action(self):
        """Verifies power actions and unallowed actions are rejected when source is assistant."""
        for power_act in ("suspend", "reboot", "shutdown"):
            res = self.run_cli("action", "run", power_act, "--source", "assistant", "--dry-run")
            self.assertNotEqual(res.returncode, 0)
            data = json.loads(res.stdout)
            self.assertFalse(data.get("ok"))
            self.assertTrue(data.get("assistant_rejected"))
            self.assertIn("not permitted for assistant execution", data.get("error", ""))

    def test_assistant_source_medium_risk_requires_confirm(self):
        """Verifies medium actions require explicit confirmation."""
        res = self.run_cli("action", "run", "record", "--source", "assistant")
        self.assertNotEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertFalse(data.get("ok"))
        self.assertTrue(data.get("requires_confirm"))

        res_lock = self.run_cli("action", "run", "lock_screen", "--source", "assistant")
        self.assertNotEqual(res_lock.returncode, 0)
        data_lock = json.loads(res_lock.stdout)
        self.assertFalse(data_lock.get("ok"))
        self.assertTrue(data_lock.get("requires_confirm"))

    # 4. Whitelist Immutability & Action Definition Integrity ───────────────────

    def test_whitelist_immutability(self):
        """Verifies running actions has zero capability to alter config/toolbox-actions.json."""
        orig_content = TOOLBOX_ACTIONS_CONFIG.read_text(encoding="utf-8")
        orig_mtime = TOOLBOX_ACTIONS_CONFIG.stat().st_mtime_ns

        # Run several actions (allowed, disallowed, dry-run, invalid)
        self.run_cli("action", "run", "toggle_toolbox", "--source", "assistant", "--dry-run")
        self.run_cli("action", "run", "suspend", "--source", "assistant")
        self.run_cli("action", "run", "set_volume", json.dumps({"level": "50"}), "--dry-run")

        new_content = TOOLBOX_ACTIONS_CONFIG.read_text(encoding="utf-8")
        new_mtime = TOOLBOX_ACTIONS_CONFIG.stat().st_mtime_ns

        self.assertEqual(orig_content, new_content, "toolbox-actions.json content must never be mutated")
        self.assertEqual(orig_mtime, new_mtime, "toolbox-actions.json mtime must remain unchanged")

    def test_all_whitelist_actions_validity(self):
        """Verifies every action in config/toolbox-actions.json defines valid attributes."""
        config = json.loads(TOOLBOX_ACTIONS_CONFIG.read_text(encoding="utf-8"))
        actions = config.get("actions", {})
        self.assertGreaterEqual(len(actions), 25)

        for act_id, act_def in actions.items():
            self.assertIn("name", act_def, f"Action {act_id} missing name")
            self.assertIn("category", act_def, f"Action {act_id} missing category")
            self.assertIn("purpose", act_def, f"Action {act_id} missing purpose")
            self.assertIn("executable", act_def, f"Action {act_id} missing executable")
            self.assertIsInstance(act_def["executable"], list)
            self.assertGreater(len(act_def["executable"]), 0)
            self.assertIn("risk", act_def, f"Action {act_id} missing risk")
            self.assertIn(act_def["risk"], ("safe", "medium", "destructive"))
            self.assertIn("assistant_allowed", act_def, f"Action {act_id} missing assistant_allowed")
            self.assertIsInstance(act_def["assistant_allowed"], bool)
            self.assertIn("ui_only", act_def, f"Action {act_id} missing ui_only")
            self.assertIsInstance(act_def["ui_only"], bool)


if __name__ == "__main__":
    unittest.main()
