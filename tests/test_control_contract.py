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

    def test_lock_and_idle_wrapper_contract(self):
        """Control Center uses unified gps-lock and gps-idle wrappers."""
        self.assertIn("gps-lock", CONTROL)
        self.assertIn("gps-idle", CONTROL)
        self.assertIn("function toggleIdleLock()", CONTROL)
        self.assertIn("function lockScreen()", CONTROL)

    def test_control_view_launcher_buttons(self):
        self.assertIn('tooltipText: "Media Hub"', CONTROL)
        self.assertIn('tooltipText: "Toolbox"', CONTROL)
        self.assertIn('tooltipText: "Settings"', CONTROL)
        self.assertIn('function openMediaHub()', CONTROL)
        self.assertIn('function openToolbox()', CONTROL)
        self.assertIn('function openSettings(', CONTROL)

    def test_shell_and_ipc_contracts(self):
        shell = (ROOT / "shell.qml").read_text()
        gps_ipc = (ROOT / "scripts/gps-ipc").read_text()
        toolbox_win = (ROOT / "components/ToolboxWindow.qml").read_text()
        toolbox_qml = (ROOT / "components/Toolbox.qml").read_text()

        self.assertIn('target: "mediahub"', shell)
        self.assertIn('target: "toolbox"', shell)
        self.assertIn('ToolboxWindow', shell)
        self.assertIn('mediahub)', gps_ipc)
        self.assertIn('toolbox)', gps_ipc)
        self.assertIn('title: "GPS Toolbox"', toolbox_win)
        self.assertIn('FloatingWindow', toolbox_win)
        self.assertIn('property bool showCloseButton:', toolbox_qml)
        self.assertIn('signal closeRequested()', toolbox_qml)


if __name__ == "__main__":
    unittest.main()
