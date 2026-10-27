import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
ISLAND = (ROOT / "island/Island.qml").read_text()
CONTROL = (ROOT / "island/states/Control.qml").read_text()


class ControlIntegrationContractTests(unittest.TestCase):
    """Regression checks for the QML-only control state seams.

    The project has no Qt Quick test harness for Quickshell types, so these
    checks protect the integration contract while live QML tests are run in a
    real Wayland session.
    """

    def test_control_is_registered_and_has_validated_ipc(self):
        self.assertIn('"Control"', re.search(r"stateFiles: \[(.*?)\]", ISLAND, re.S).group(1))
        self.assertIn("property bool controlOpen: false", ISLAND)
        self.assertIn("property bool controlExpanded: false", ISLAND)
        self.assertIsNotNone(re.search(
            r'function setControl\(action\).*?\["toggle", "open", "off", "close", "expand", "collapse"\]',
            ISLAND,
            re.S,
        ))
        self.assertIn('function control(action: string)', ISLAND)

    def test_priority_keeps_alert_privacy_and_launcher_ahead(self):
        auto_mode = re.search(r"readonly property string autoMode: (.+)", ISLAND).group(1)
        self.assertLess(auto_mode.index('"alert"'), auto_mode.index('"privacy"'))
        self.assertLess(auto_mode.index('"privacy"'), auto_mode.index('"launcher"'))
        self.assertLess(auto_mode.index('"launcher"'), auto_mode.index('"control"'))

    def test_probe_has_timeout_and_real_host_sources(self):
        self.assertIn('"timeout", "3s", "sh", "-c"', CONTROL)
        for marker in ("/proc/uptime", "uname -r", "powerprofilesctl get", "brightnessctl -m"):
            self.assertIn(marker, CONTROL)
        self.assertNotIn("127", CONTROL)

    def test_radio_and_text_safety_contracts(self):
        self.assertIn("nmcli radio wifi", CONTROL)
        self.assertIn("bluetoothctl power", CONTROL)
        self.assertIn("bluetoothctl devices Connected", CONTROL)
        self.assertIn("elide: Text.ElideRight", CONTROL)
        self.assertIn("core.setControl(\"close\")", CONTROL)

    def test_disruptive_actions_are_guarded(self):
        self.assertIn("if (!hasLocker) return", CONTROL)
        self.assertIn("if (!hasSystemctl) return", CONTROL)
        self.assertIn("confirmPower", CONTROL)


if __name__ == "__main__":
    unittest.main()
