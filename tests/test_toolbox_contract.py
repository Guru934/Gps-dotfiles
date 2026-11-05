import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPR_LUA = (ROOT / "dots/hypr/hyprland.lua").read_text(encoding="utf-8")
TOOLBOX_QML = (ROOT / "components/Toolbox.qml").read_text(encoding="utf-8")
TOOLBOX_WIN = (ROOT / "components/ToolboxWindow.qml").read_text(encoding="utf-8")
TOOLBOX_BACKEND = (ROOT / "components/ToolboxBackend.qml").read_text(encoding="utf-8")


class ToolboxContractTests(unittest.TestCase):
    """Verifies GPS Toolbox keybinds, window wiring, and backend signal coverage."""

    def test_super_t_keybind_registered_in_hyprland(self):
        """Verifies Super+T is bound to 'scripts/gps-ipc toolbox toggle'."""
        self.assertIn('hl.bind(mainMod .. " + T"', HYPR_LUA)
        self.assertIn('scripts/gps-ipc toolbox toggle', HYPR_LUA)

    def test_toolbox_window_wires_backend_and_presentation(self):
        """Verifies ToolboxWindow embeds ToolboxBackend and binds live facts to Toolbox."""
        self.assertIn("ToolboxBackend", TOOLBOX_WIN)
        self.assertIn("toolbox: tb", TOOLBOX_WIN)
        self.assertIn("hostName: backend.hostName", TOOLBOX_WIN)
        self.assertIn("osName: backend.osName", TOOLBOX_WIN)
        self.assertIn("compositorName: backend.compositorName", TOOLBOX_WIN)
        self.assertIn("compositorState: backend.compositorState", TOOLBOX_WIN)
        self.assertIn("integrationAvailable: backend.integrationAvailable", TOOLBOX_WIN)

    def test_toolbox_backend_provides_live_facts(self):
        """Verifies ToolboxBackend has integrationAvailable true and Hyprland detection."""
        self.assertIn("readonly property bool integrationAvailable: true", TOOLBOX_BACKEND)
        self.assertIn('readonly property string compositorName: "Hyprland"', TOOLBOX_BACKEND)
        self.assertIn("Hyprland.monitors", TOOLBOX_BACKEND)

    def test_toolbox_backend_handles_all_toolbox_signals(self):
        """Verifies every root signal declared in Toolbox.qml has an explicit handler in ToolboxBackend."""
        signal_pattern = re.compile(r"^ {4}signal\s+([A-Za-z0-9_]+)\(", re.MULTILINE)
        signals = signal_pattern.findall(TOOLBOX_QML)
        self.assertGreaterEqual(len(signals), 14, "Expected at least 14 root signals in Toolbox.qml")

        for sig in signals:
            if sig == "closeRequested":
                continue  # Handled directly by ToolboxWindow to close the window
            handler_name = "on" + sig[0].upper() + sig[1:]
            self.assertIn(
                handler_name,
                TOOLBOX_BACKEND,
                f"Signal '{sig}' ({handler_name}) is missing an explicit handler in ToolboxBackend.qml",
            )


if __name__ == "__main__":
    unittest.main()
