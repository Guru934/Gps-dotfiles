import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WS_QML = ROOT / "components" / "WorkspaceIndicator.qml"


class WorkspaceIndicatorContractTests(unittest.TestCase):
    """Verifies that WorkspaceIndicator.qml adheres to the GPS Left Rail contract,

    design system, event-driven Hyprland integration, and safety rules.
    """

    def setUp(self):
        self.assertTrue(WS_QML.exists(), "WorkspaceIndicator.qml must exist")
        self.content = WS_QML.read_text(encoding="utf-8")

    def test_qmllint_clean(self):
        """Verifies qmllint passes on WorkspaceIndicator.qml with 0 errors."""
        res = subprocess.run(["qmllint", str(WS_QML)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"qmllint failed:\n{res.stderr}\n{res.stdout}")

    def test_required_imports(self):
        """Verifies necessary Quickshell and theme imports are present."""
        self.assertIn("import Quickshell", self.content)
        self.assertIn("import Quickshell.Hyprland", self.content)
        self.assertIn("import QtQuick", self.content)
        self.assertIn("import qs.config", self.content)

    def test_rail_geometry_preservation(self):
        """Must use Theme.railControlSize to fit the existing left rail layout."""
        self.assertIn("width: Theme.railControlSize", self.content)
        self.assertIn("readonly property int slotSize: Theme.railControlSize", self.content)
        self.assertIn("height: wsCol.implicitHeight + Theme.spacingMd", self.content)

    def test_preserved_behaviors_and_apis(self):
        """Must preserve existing public properties and control methods."""
        self.assertIn("property int workspaceCount: 5", self.content)
        self.assertIn("readonly property int currentWs:", self.content)
        self.assertIn("function isWorkspaceOccupied(wsId)", self.content)
        self.assertIn("function isWorkspaceUrgent(wsId)", self.content)
        self.assertIn("function workspaceName(wsId)", self.content)
        self.assertIn("function workspaceTooltipText(wsId)", self.content)
        self.assertIn("function switchTo(targetId)", self.content)
        self.assertIn("function handleWheel(deltaY)", self.content)

    def test_design_shapes(self):
        """Verifies empty/occupied diamond shapes, active pill, and urgent pulse."""
        # Diamond shape (rotated rectangle)
        self.assertIn("rotation: 45", self.content)
        # Empty hollow vs occupied filled
        self.assertIn("dotItem.isOccupied ? Theme.brandAccent : \"transparent\"", self.content)
        # Glowing active pill
        self.assertIn("id: activeIndicator", self.content)
        self.assertIn("id: activeGlow", self.content)
        self.assertIn("id: activePill", self.content)
        self.assertIn("easing.type: Easing.OutBack", self.content)
        self.assertIn("easing.overshoot:", self.content)
        # Urgent pulsing ring & animation
        self.assertIn("id: urgentRing", self.content)
        self.assertIn("dotItem.isUrgent", self.content)

    def test_no_forbidden_patterns(self):
        """No polling, no new timers, no shell commands."""
        self.assertNotIn("Timer {", self.content)
        self.assertNotIn("Process {", self.content)
        self.assertNotIn("sh -c", self.content)
        self.assertNotIn("hyprctl", self.content)  # Should use Quickshell Hyprland dispatch instead

    def test_no_hardcoded_colors(self):
        """Must use theme tokens rather than raw hardcoded hex colors."""
        # Find raw hex colors like #ffffff or #123456
        hex_matches = re.findall(r'#[0-9a-fA-F]{3,8}', self.content)
        self.assertEqual(hex_matches, [], f"Hardcoded hex colors found: {hex_matches}")


if __name__ == "__main__":
    unittest.main()
