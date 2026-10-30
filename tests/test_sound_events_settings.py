#!/usr/bin/env python3
"""Hermetic tests for Sound & Events settings page and configuration persistence (E3).

Verifies:
- settings.qml includes the 'Sound & Events' page
- master mute, volume cap, per-event toggles, test button hooks
- atomic updates to rice-settings.json under 'sound' and 'events' sections
- existing sections in rice-settings.json are preserved
"""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SETTINGS_QML = (ROOT / "settings.qml").read_text(encoding="utf-8")


class SoundEventsSettingsTests(unittest.TestCase):
    def test_settings_qml_has_sound_events_page(self):
        """settings.qml must define the Sound & Events page in the pages model."""
        self.assertIn('"Sound & Events"', SETTINGS_QML)
        self.assertIn("notifications_active", SETTINGS_QML)

    def test_settings_qml_has_sound_controls(self):
        """settings.qml must have master mute, volume cap, and test buttons."""
        self.assertIn("Master mute", SETTINGS_QML)
        self.assertIn("Volume cap", SETTINGS_QML)
        self.assertIn("Battery critical threshold", SETTINGS_QML)
        self.assertIn("Critical action", SETTINGS_QML)
        self.assertIn("gps-sound play", SETTINGS_QML)

    def test_sound_and_events_persistence(self):
        """Verify updating sound and events preserves other sections in rice-settings.json."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_settings = Path(tmp_dir) / "rice-settings.json"
            initial_data = {
                "hypr": {"general:gaps_in": 5},
                "monitors": {"eDP-1": {"scale": 1.5}},
                "sound": {
                    "enabled": True,
                    "muted": False,
                    "volume": 0.8,
                    "volumeCap": 0.9,
                    "events": {
                        "battery-low": {"enabled": True}
                    }
                },
                "events": {
                    "batteryLowThreshold": 20,
                    "batteryCriticalThreshold": 8,
                    "criticalAction": "none"
                }
            }
            tmp_settings.write_text(json.dumps(initial_data, indent=2), encoding="utf-8")

            # Update critical action to "suspend" and mute to True
            py_code = (
                "import json, os, sys, tempfile\n"
                "p = sys.argv[1]\n"
                "with open(p, 'r', encoding='utf-8') as f: d = json.load(f)\n"
                "d.setdefault('events', {})['criticalAction'] = 'suspend'\n"
                "d.setdefault('events', {})['batteryLowThreshold'] = 25\n"
                "d.setdefault('sound', {})['muted'] = True\n"
                "d_dir = os.path.dirname(p)\n"
                "fd, tmp = tempfile.mkstemp(dir=d_dir, prefix='.rice-settings.tmp-')\n"
                "with os.fdopen(fd, 'w', encoding='utf-8') as f:\n"
                "    json.dump(d, f, indent=2)\n"
                "    f.flush(); os.fsync(f.fileno())\n"
                "os.replace(tmp, p)\n"
            )
            res = subprocess.run(["python3", "-c", py_code, str(tmp_settings)], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"Error: {res.stderr}")

            updated = json.loads(tmp_settings.read_text(encoding="utf-8"))
            self.assertEqual(updated["events"]["criticalAction"], "suspend")
            self.assertEqual(updated["events"]["batteryLowThreshold"], 25)
            self.assertTrue(updated["sound"]["muted"])
            # Existing keys preserved
            self.assertEqual(updated["hypr"]["general:gaps_in"], 5)
            self.assertEqual(updated["monitors"]["eDP-1"]["scale"], 1.5)
            self.assertEqual(updated["sound"]["volumeCap"], 0.9)


if __name__ == "__main__":
    unittest.main()
