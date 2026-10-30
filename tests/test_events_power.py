#!/usr/bin/env python3
"""Hermetic tests for GPS Events Service - Power Events (E1).

Verifies:
- Battery low threshold defaults to 20%
- Battery critical threshold defaults to 8% with critical urgency
- Charger plugged and unplugged events
- Fully charged event triggers once
- Hysteresis prevents flapping repeats
- Critical action executes only when configured (e.g. suspend)
- DND suppression respects critical bypass rules
- IPC contract for events handler
"""

import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


class EventsPowerTests(unittest.TestCase):
    def test_node_events_logic_suite(self):
        """Run Node.js pure-logic test suite for EventsLogic."""
        script = ROOT / "tests" / "test_events_logic.js"
        res = subprocess.run(["node", str(script)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node tests failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("All EventsLogic Power Tests Passed Successfully!", res.stdout)

    def test_events_service_qml_exists_and_parses(self):
        """Verify EventsService.qml exists and passes qmllint."""
        qml_path = ROOT / "components" / "EventsService.qml"
        self.assertTrue(qml_path.is_file(), "EventsService.qml must exist")
        res = subprocess.run(["qmllint", str(qml_path)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"qmllint failed:\n{res.stderr}")

    def test_shell_qml_instantiates_events_service(self):
        """shell.qml must instantiate EventsService."""
        shell_content = (ROOT / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("EventsService", shell_content)

    def test_events_defaults(self):
        """Verify EventsLogic default thresholds and values."""
        cmd = [
            "node", "-e",
            'const { DEFAULT_EVENTS_SETTINGS } = require("./components/EventsLogic.js");'
            + 'console.log(JSON.stringify(DEFAULT_EVENTS_SETTINGS));'
        ]
        res = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        defaults = json.loads(res.stdout)
        self.assertEqual(defaults["batteryLowThreshold"], 20)
        self.assertEqual(defaults["batteryCriticalThreshold"], 8)
        self.assertEqual(defaults["criticalAction"], "none")
        self.assertEqual(defaults["hysteresisMargin"], 3)
        self.assertTrue(defaults["notifyBatteryLow"])
        self.assertTrue(defaults["notifyBatteryCritical"])
        self.assertTrue(defaults["soundBatteryLow"])
        self.assertTrue(defaults["soundBatteryCritical"])


if __name__ == "__main__":
    unittest.main()
