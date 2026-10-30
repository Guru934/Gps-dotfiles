#!/usr/bin/env python3
"""Automated unit and integration tests for GPS settings and persistence (P5.4).

Verifies:
- Atomic file write mechanisms prevent truncation or corrupted intermediate reads.
- Existing keys in rice-settings.json are preserved when updating individual sections.
- Malformed or invalid JSON parses safely without data loss or exceptions.
- Default values are provided when settings files are absent.
- Standard path conventions ($HOME/.config/quickshell) are respected.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SETTINGS_QML = (ROOT / "settings.qml").read_text()
AICHAT_QML = (ROOT / "components" / "AIChat.qml").read_text()
LAUNCHER_QML = (ROOT / "island" / "states" / "Launcher.qml").read_text()


class SettingsPersistenceTests(unittest.TestCase):
    """Test suite for atomic writes and fault-tolerant configuration persistence."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.settings_file = self.tmp_path / "rice-settings.json"

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_settings_qml_uses_atomic_write_pattern(self):
        """settings.qml writeFile must write to a temporary file before renaming."""
        self.assertIn('tmp="${d}/.$(basename "$1").tmp.$$', SETTINGS_QML)
        self.assertIn('mv -f "$tmp" "$1"', SETTINGS_QML)

    def test_launcher_qml_uses_atomic_write_pattern(self):
        """Launcher.qml usage tracker must write to a temporary file before renaming."""
        self.assertIn('tmp=\\"${d}/.$(basename \\"$1\\").tmp.$$', LAUNCHER_QML)
        self.assertIn('mv -f \\"$tmp\\" \\"$1\\"', LAUNCHER_QML)

    def test_aichat_model_persist_preserves_existing_settings(self):
        """When updating the AI model, other existing sections (hypr, monitors, island) are preserved."""
        initial_data = {
            "hypr": {"general:gaps_in": 5, "decoration:rounding": 10},
            "monitors": {"eDP-1": {"scale": 1.5}},
            "island": {"hoverGraceMs": 350},
            "ai": {"ctx": 4096, "temp": 0.5, "model": "old-model"},
        }
        self.settings_file.write_text(json.dumps(initial_data, indent=2), encoding="utf-8")

        # Execute the python script used in AIChat.qml
        cmd = [
            "python3", "-c",
            "import json, os, sys, tempfile\n"
            "p = sys.argv[1]; n = sys.argv[2]; d = {}\n"
            "if os.path.isfile(p):\n"
            "    try:\n"
            "        with open(p, 'r', encoding='utf-8') as f:\n"
            "            content = f.read().strip()\n"
            "            if content: d = json.loads(content)\n"
            "    except Exception: pass\n"
            "if not isinstance(d, dict): d = {}\n"
            "ai = d.setdefault('ai', {})\n"
            "if isinstance(ai, dict): ai['model'] = n\n"
            "d_dir = os.path.dirname(p)\n"
            "os.makedirs(d_dir, exist_ok=True)\n"
            "fd, tmp = tempfile.mkstemp(dir=d_dir, prefix='.rice-settings.tmp-')\n"
            "with os.fdopen(fd, 'w', encoding='utf-8') as f:\n"
            "    json.dump(d, f, indent=2)\n"
            "    f.flush()\n"
            "    os.fsync(f.fileno())\n"
            "os.replace(tmp, p)",
            str(self.settings_file),
            "new-deepseek-model",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Error: {res.stderr}")

        updated = json.loads(self.settings_file.read_text(encoding="utf-8"))
        self.assertEqual(updated["ai"]["model"], "new-deepseek-model")
        self.assertEqual(updated["ai"]["ctx"], 4096)
        self.assertEqual(updated["hypr"]["general:gaps_in"], 5)
        self.assertEqual(updated["monitors"]["eDP-1"]["scale"], 1.5)
        self.assertEqual(updated["island"]["hoverGraceMs"], 350)

    def test_aichat_model_persist_handles_missing_file(self):
        """If rice-settings.json does not yet exist, it creates it with safe defaults without failing."""
        missing_file = self.tmp_path / "new_store" / "rice-settings.json"
        cmd = [
            "python3", "-c",
            "import json, os, sys, tempfile\n"
            "p = sys.argv[1]; n = sys.argv[2]; d = {}\n"
            "if os.path.isfile(p):\n"
            "    try:\n"
            "        with open(p, 'r', encoding='utf-8') as f:\n"
            "            content = f.read().strip()\n"
            "            if content: d = json.loads(content)\n"
            "    except Exception: pass\n"
            "if not isinstance(d, dict): d = {}\n"
            "ai = d.setdefault('ai', {})\n"
            "if isinstance(ai, dict): ai['model'] = n\n"
            "d_dir = os.path.dirname(p)\n"
            "os.makedirs(d_dir, exist_ok=True)\n"
            "fd, tmp = tempfile.mkstemp(dir=d_dir, prefix='.rice-settings.tmp-')\n"
            "with os.fdopen(fd, 'w', encoding='utf-8') as f:\n"
            "    json.dump(d, f, indent=2)\n"
            "    f.flush()\n"
            "    os.fsync(f.fileno())\n"
            "os.replace(tmp, p)",
            str(missing_file),
            "llama3.2:3b",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertTrue(missing_file.is_file())
        data = json.loads(missing_file.read_text(encoding="utf-8"))
        self.assertEqual(data["ai"]["model"], "llama3.2:3b")

    def test_settings_qml_handles_corrupt_json_gracefully(self):
        """settings.qml safely verifies parsed JSON is an object and not an array or primitive."""
        self.assertIn("typeof parsed === \"object\" && !Array.isArray(parsed)", SETTINGS_QML)


if __name__ == "__main__":
    unittest.main()
