import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GPS_TOOLBOX = ROOT / "scripts/gps-toolbox"
TOOLBOX_ROUTINES_CONFIG = ROOT / "config/toolbox-routines.json"
TOOLBOX_BACKEND = (ROOT / "components/ToolboxBackend.qml").read_text(encoding="utf-8")
TOOLBOX_WIN = (ROOT / "components/ToolboxWindow.qml").read_text(encoding="utf-8")
TOOLBOX_QML = (ROOT / "components/Toolbox.qml").read_text(encoding="utf-8")


class ToolboxRoutinesTests(unittest.TestCase):
    """Verifies GPS Toolbox Routine Builder and Workflow sequential execution (Phase 6)."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["XDG_STATE_HOME"] = self.temp_dir.name
        self.env["XDG_CONFIG_HOME"] = str(Path(self.temp_dir.name) / "config")
        self.env["GPS_TEST_NO_SYSTEMD"] = "1"
        self.state_dir = Path(self.temp_dir.name) / "gps/toolbox"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_cli(self, *args):
        cmd = [str(GPS_TOOLBOX)] + list(args)
        proc = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        return proc

    def test_shipped_routines_configuration(self):
        """Verifies default workflows configuration exists and has valid non-sample templates."""
        self.assertTrue(TOOLBOX_ROUTINES_CONFIG.is_file(), "config/toolbox-routines.json missing")
        routines = json.loads(TOOLBOX_ROUTINES_CONFIG.read_text(encoding="utf-8"))
        self.assertIsInstance(routines, list)
        self.assertGreaterEqual(len(routines), 3)

        for r in routines:
            self.assertFalse(r.get("sample", False), f"Workflow {r.get('id')} should not be sample")
            self.assertIn("steps", r)
            self.assertIsInstance(r["steps"], list)
            self.assertGreater(len(r["steps"]), 0)

    def test_workflow_list_returns_defaults(self):
        """Verifies workflow list command initializes state with shipped templates."""
        res = self.run_cli("workflow", "list")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIsInstance(data.get("routines"), list)
        self.assertGreaterEqual(len(data["routines"]), 3)

    def test_workflow_crud_lifecycle(self):
        """Verifies workflow save, modify, and delete operations."""
        wf = {
            "id": "wf_test_1",
            "name": "Quick Work Setup",
            "description": "Terminal and DND",
            "trigger": "manual",
            "onFail": "continue",
            "steps": [
                {"id": "st1", "actionId": "open_terminal", "cond": "always", "note": "Launch term"},
                {"id": "st2", "actionId": "dnd_enable", "cond": "prev_ok", "note": "Mute"}
            ]
        }
        res_save = self.run_cli("workflow", "save", json.dumps(wf))
        self.assertEqual(res_save.returncode, 0, res_save.stderr)
        saved = json.loads(res_save.stdout)
        self.assertTrue(saved.get("ok"))
        self.assertFalse(saved["workflow"].get("sample", True))

        # Check list contains it
        res_list = self.run_cli("workflow", "list")
        list_data = json.loads(res_list.stdout)
        ids = [r["id"] for r in list_data.get("routines", [])]
        self.assertIn("wf_test_1", ids)

        # Delete it
        res_del = self.run_cli("workflow", "delete", "wf_test_1")
        self.assertEqual(res_del.returncode, 0)
        res_list2 = self.run_cli("workflow", "list")
        ids2 = [r["id"] for r in json.loads(res_list2.stdout).get("routines", [])]
        self.assertNotIn("wf_test_1", ids2)

    def test_workflow_run_execution_and_journal(self):
        """Verifies workflow execution steps, run count increments, and activity logging."""
        res_run = self.run_cli("workflow", "run", "rt3")
        self.assertEqual(res_run.returncode, 0, res_run.stderr)
        run_data = json.loads(res_run.stdout)
        self.assertTrue(run_data.get("ok"))
        self.assertEqual(run_data.get("steps_executed"), 1)

        # Verify activity journal was updated
        res_hist = self.run_cli("activity", "list")
        self.assertEqual(res_hist.returncode, 0)
        hist = json.loads(res_hist.stdout)
        wf_events = [e for e in hist.get("events", []) if e.get("category") == "Workflows"]
        self.assertGreater(len(wf_events), 0)
        self.assertIn("Entertainment", wf_events[0].get("name", ""))

        # Verify run count incremented
        res_list = self.run_cli("workflow", "list")
        routines = json.loads(res_list.stdout).get("routines", [])
        rt3 = next((r for r in routines if r.get("id") == "rt3"), None)
        self.assertIsNotNone(rt3)
        self.assertGreaterEqual(rt3.get("runs", 0), 1)

    def test_qml_workflow_wiring(self):
        """Verifies ToolboxBackend and ToolboxWindow have complete Phase 6 wiring."""
        self.assertIn("property var routines:", TOOLBOX_BACKEND)
        self.assertIn("function saveRoutine(routine)", TOOLBOX_BACKEND)
        self.assertIn("function deleteRoutine(id)", TOOLBOX_BACKEND)
        self.assertIn("function runWorkflow(id)", TOOLBOX_BACKEND)

        self.assertIn("onWorkflowSaved", TOOLBOX_BACKEND)
        self.assertIn("onWorkflowRunRequested", TOOLBOX_BACKEND)

        self.assertIn("routines: backend.routines", TOOLBOX_WIN)
        self.assertIn("root.workflowRunRequested(rp.r.id)", TOOLBOX_QML)


if __name__ == "__main__":
    unittest.main()
