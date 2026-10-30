import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL_QML = (ROOT / "shell.qml").read_text(encoding="utf-8")
PICKER_QML = (ROOT / "components/ClipboardPicker.qml").read_text(encoding="utf-8")
TOOLSTAB_QML = (ROOT / "components/dashboard/ToolsTab.qml").read_text(encoding="utf-8")
HYPRLAND_LUA = (ROOT / "dots/hypr/hyprland.lua").read_text(encoding="utf-8")
GPS_IPC = (ROOT / "scripts/gps-ipc").read_text(encoding="utf-8")


class ClipboardPickerContractTests(unittest.TestCase):
    """Verifies picker layer-shell contracts, unified IPC routes, and single entry points."""

    def test_picker_surface_layer_shell_contracts(self):
        """Picker must be a centered overlay layer-shell surface with on-demand keyboard focus."""
        self.assertIn('WlrLayershell.namespace: "gps-clipboard"', PICKER_QML)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", PICKER_QML)
        self.assertIn("WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None", PICKER_QML)
        self.assertIn("anchors {}", PICKER_QML, "Surface must be centered with empty anchors")

    def test_shell_exposes_clipboard_ipc_handler(self):
        """shell.qml must expose an IpcHandler for target 'clipboard'."""
        self.assertIn('target: "clipboard"', SHELL_QML)
        self.assertIn("function toggle() { root.toggleClipboard() }", SHELL_QML)
        self.assertIn("function open() { root.openClipboard() }", SHELL_QML)
        self.assertIn("function close() { root.closeClipboard() }", SHELL_QML)
        self.assertIn("function count(): int", SHELL_QML)

    def test_dashboard_tools_single_button_contract(self):
        """Dashboard Tools must have a single clipboard row opening the picker."""
        self.assertIn('scripts/gps-ipc", "shell", "clipboard", "toggle"', TOOLSTAB_QML)
        self.assertNotIn("CLEAR CLIPBOARD", TOOLSTAB_QML, "Duplicate clear row must be removed")
        self.assertNotIn("WIPE CLIP HISTORY", TOOLSTAB_QML, "Duplicate wipe row must be removed")

    def test_hyprland_super_v_binding(self):
        """Super+V must route through gps-ipc shell clipboard toggle."""
        self.assertIn('mainMod .. " + V", hl.dsp.exec_cmd(repo .. "/scripts/gps-ipc shell clipboard toggle")', HYPRLAND_LUA)

    def test_gps_ipc_routes_to_shell_clipboard(self):
        """gps-ipc shell clipboard routes to shell.qml."""
        self.assertIn('call_qs "$REPO_DIR/shell.qml" "$target" "$action"', GPS_IPC)

    def test_gps_clipboard_cli_list_and_status(self):
        """scripts/gps-clipboard status and list output valid JSON."""
        script = ROOT / "scripts/gps-clipboard"
        status_proc = subprocess.run([str(script), "status"], capture_output=True, text=True)
        self.assertEqual(status_proc.returncode, 0)
        status_data = json.loads(status_proc.stdout)
        self.assertTrue(status_data["ok"])
        self.assertIn("paused", status_data)

        list_proc = subprocess.run([str(script), "list"], capture_output=True, text=True)
        self.assertEqual(list_proc.returncode, 0)
        list_data = json.loads(list_proc.stdout)
        self.assertTrue(list_data["ok"])
        self.assertIn("items", list_data)
        self.assertIn("count", list_data)

    def test_picker_row_selection_and_contrast_contract(self):
        """Selected row uses an accent-tinted surface (0.2 alpha), visible accent border, and no undefined tokens."""
        self.assertNotIn("Theme.cardActive", PICKER_QML, "Undefined Theme.cardActive must not be used")
        self.assertIn("0.20", PICKER_QML, "Selected row must use accent tint at approx 0.2 alpha")
        self.assertIn("border.color: isSelected", PICKER_QML)
        self.assertIn("Theme.brandAccent", PICKER_QML)
        self.assertIn("Theme.textMain", PICKER_QML)


if __name__ == "__main__":
    unittest.main()
