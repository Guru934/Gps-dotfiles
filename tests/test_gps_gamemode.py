"""Unit tests for GPS Game Mode Controller."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import importlib.machinery
import importlib.util

script_path = Path(__file__).resolve().parent.parent / "scripts" / "gps-gamemode"
loader = importlib.machinery.SourceFileLoader("gps_gamemode", str(script_path))
spec = importlib.util.spec_from_loader("gps_gamemode", loader)
gm = importlib.util.module_from_spec(spec)
loader.exec_module(gm)


class TestGpsGameMode(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.state_file = Path(self.tmp_dir.name) / "gps" / "gamemode_state.json"
        self.patcher = patch.object(gm, "get_state_path", return_value=self.state_file)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()
        self.tmp_dir.cleanup()

    def test_parse_gap_value(self):
        self.assertEqual(gm.parse_gap_value({"int": 10}, 5), 10)
        self.assertEqual(gm.parse_gap_value({"css": "15 15 15 15"}, 5), 15)
        self.assertEqual(gm.parse_gap_value({"other": "xyz"}, 5), 5)
        self.assertEqual(gm.parse_gap_value({}, 5), 5)

    @patch.object(gm, "eval_hypr_lua", return_value=True)
    @patch.object(gm, "query_hypr_option")
    def test_enable_creates_snapshot_and_disables_features(self, mock_query, mock_eval):
        def query_side_effect(opt):
            if opt == "animations:enabled":
                return {"bool": True}
            if opt == "decoration:blur:enabled":
                return {"bool": True}
            if opt == "decoration:shadow:enabled":
                return {"bool": True}
            if opt == "general:gaps_in":
                return {"css": "7 7 7 7"}
            if opt == "general:gaps_out":
                return {"css": "22 22 22 22"}
            return {}

        mock_query.side_effect = query_side_effect

        self.assertFalse(gm.is_active())
        res = gm.enable_gamemode()
        self.assertTrue(res)
        self.assertTrue(gm.is_active())

        # Verify snapshot contents
        self.assertTrue(self.state_file.is_file())
        snap = json.loads(self.state_file.read_text(encoding="utf-8"))
        self.assertEqual(snap["animations_enabled"], True)
        self.assertEqual(snap["blur_enabled"], True)
        self.assertEqual(snap["shadow_enabled"], True)
        self.assertEqual(snap["gaps_in"], 7)
        self.assertEqual(snap["gaps_out"], 22)

        # Verify lua evaluation called with zeroes/false
        mock_eval.assert_called_once()
        eval_call = mock_eval.call_args[0][0]
        self.assertIn("animations = { enabled = false }", eval_call)
        self.assertIn("blur = { enabled = false }", eval_call)
        self.assertIn("shadow = { enabled = false }", eval_call)
        self.assertIn("gaps_in = 0, gaps_out = 0", eval_call)

    @patch.object(gm, "eval_hypr_lua", return_value=True)
    def test_disable_restores_snapshot_and_removes_state(self, mock_eval):
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps({
            "animations_enabled": True,
            "blur_enabled": True,
            "shadow_enabled": False,
            "gaps_in": 8,
            "gaps_out": 24
        }), encoding="utf-8")

        self.assertTrue(gm.is_active())
        res = gm.disable_gamemode()
        self.assertTrue(res)
        self.assertFalse(gm.is_active())

        mock_eval.assert_called_once()
        eval_call = mock_eval.call_args[0][0]
        self.assertIn("animations = { enabled = true }", eval_call)
        self.assertIn("blur = { enabled = true }", eval_call)
        self.assertIn("shadow = { enabled = false }", eval_call)
        self.assertIn("gaps_in = 8, gaps_out = 24", eval_call)


if __name__ == "__main__":
    unittest.main()
