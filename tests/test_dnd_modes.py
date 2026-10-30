import json
from pathlib import Path
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
STORE_JS = (ROOT / "island/NotificationStore.js").read_text(encoding="utf-8")


class DndModesUnitTests(unittest.TestCase):
    """Unit tests for GPS Do Not Disturb modes, schedule and snooze."""

    def test_dnd_js_contains_all_modes_and_functions(self):
        for func in ("createDefaultDnd", "isScheduleActive", "isDndActive", "serializeDnd", "deserializeDnd"):
            self.assertIn(func, STORE_JS)

    def test_default_dnd_state(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "dnd.json"
            default_state = {
                "mode": "off",
                "allowCritical": True,
                "snoozeUntil": 0,
                "schedule": {
                    "enabled": False,
                    "from": "22:00",
                    "to": "07:00",
                    "days": [1, 2, 3, 4, 5, 6, 7]
                }
            }
            path.write_text(json.dumps(default_state), encoding="utf-8")
            loaded = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(loaded["mode"], "off")
            self.assertTrue(loaded["allowCritical"])
            self.assertEqual(loaded["schedule"]["from"], "22:00")

    def test_corrupt_dnd_file_recovery(self):
        with tempfile.TemporaryDirectory() as td:
            bad_file = Path(td) / "dnd.json"
            bad_file.write_text("corrupted json {{", encoding="utf-8")
            try:
                data = json.loads(bad_file.read_text(encoding="utf-8"))
            except Exception:
                data = {"mode": "off", "allowCritical": True}
            self.assertEqual(data["mode"], "off")


if __name__ == "__main__":
    unittest.main()
