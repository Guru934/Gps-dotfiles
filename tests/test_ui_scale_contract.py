"""Central UI scale token contracts for the shared GPS surfaces."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME = (ROOT / "config/Theme.qml").read_text(encoding="utf-8")


class UiScaleContractTests(unittest.TestCase):
    def test_ui_scale_has_adjustable_default_and_shared_rounding_helper(self):
        self.assertRegex(THEME, r"readonly property real uiScale:\s*1\.15\b")
        self.assertRegex(
            THEME,
            r"function scaled\(value\)\s*\{\s*return Math\.round\(value \* root\.uiScale\)\s*\}",
        )

    def test_typography_and_geometry_tokens_scale_once_from_base_values(self):
        expected = {
            "fontSizeDisplay": 22,
            "fontSizeHeading": 16,
            "fontSizeSubheading": 14,
            "fontSizeBody": 13,
            "fontSizeSecondary": 12,
            "fontSizeCaption": 10,
            "fontSizeSmall": 9,
            "spacingXs": 4,
            "spacingSm": 8,
            "spacingMd": 12,
            "spacingLg": 16,
            "spacingXl": 24,
            "paddingSm": 8,
            "paddingMd": 12,
            "paddingLg": 16,
            "paddingXl": 20,
            "controlHeightSm": 24,
            "controlHeightMd": 32,
            "controlHeightLg": 40,
            "controlHeightXl": 48,
            "iconXs": 12,
            "iconSm": 16,
            "iconMd": 20,
            "iconLg": 24,
            "iconXl": 32,
            "sidebarWindowWidth": 54,
            "sidebarBarWidth": 54,
            "sideButtonSize": 38,
            "sidebarRailWidth": 50,
            "railControlSize": 36,
            "railIconSize": 19,
            "dashboardWidth": 480,
        }
        for token, base in expected.items():
            with self.subTest(token=token):
                pattern = rf"readonly property (?:real|int) {token}:\s*root\.scaled\({base}\)"
                self.assertIsNotNone(re.search(pattern, THEME), f"{token} must scale from {base}")

    def test_scaled_surface_tokens_cover_primary_layouts(self):
        expected = {
            "notificationCenterWidth": 380,
            "notificationCenterMaxHeight": 640,
            "systemPopupWidth": 330,
            "trayPopupWidth": 280,
            "powerPopupWidth": 240,
            "islandPanelWidth": 560,
            "islandPanelHeight": 580,
            "islandControlWidthExpanded": 460,
            "islandControlWidthCompact": 180,
            "islandControlHeightCompact": 36,
            "islandControlMaxHeight": 560,
            "islandLauncherWidth": 520,
            "islandLauncherSearchHeight": 44,
        }
        for token, base in expected.items():
            with self.subTest(token=token):
                pattern = rf"readonly property int {token}:\s*root\.scaled\({base}\)"
                self.assertIsNotNone(re.search(pattern, THEME), f"{token} must scale from {base}")

    def test_major_surfaces_consume_shared_tokens_and_keep_responsive_bounds(self):
        checks = {
            "components/LeftRail.qml": ["Theme.sidebarRailWidth", "Theme.powerPopupWidth"],
            "components/DashboardHost.qml": ["Theme.dashboardWidth", "root.screen.width - 24"],
            "components/NotifCenter.qml": [
                "Theme.notificationCenterWidth",
                "Theme.notificationCenterMaxHeight",
            ],
            "components/WifiPopup.qml": ["Theme.systemPopupWidth"],
            "components/BluetoothPopup.qml": ["Theme.systemPopupWidth"],
            "components/BatteryPopup.qml": ["Theme.systemPopupWidth"],
            "components/TrayPopup.qml": ["Theme.trayPopupWidth"],
            "island/Island.qml": ["Theme.islandPanelWidth", "Theme.islandPanelHeight"],
            "island/states/Control.qml": [
                "Theme.islandControlWidthExpanded",
                "Theme.islandControlWidthCompact",
                "Theme.islandControlMaxHeight",
            ],
            "island/states/Launcher.qml": [
                "Theme.islandLauncherWidth",
                "Theme.islandLauncherSearchHeight",
            ],
        }
        for relative_path, tokens in checks.items():
            source = (ROOT / relative_path).read_text(encoding="utf-8")
            with self.subTest(component=relative_path):
                for token in tokens:
                    self.assertIn(token, source)

    def test_phase_two_surfaces_use_dedicated_readability_and_hit_area_tokens(self):
        for token, base in {
            "dashboardFramePadding": 18,
            "dashboardCardPadding": 14,
            "dashboardSectionGap": 14,
            "dashboardControlHeight": 40,
            "dashboardTextCaption": 9,
            "dashboardTextHeading": 15,
        }.items():
            with self.subTest(token=token):
                self.assertRegex(
                    THEME,
                    rf"readonly property int {token}:\s*root\.scaled\({base}\)",
                )
        self.assertIn("function dashboardText(baseSize)", THEME)
        self.assertIn("Theme.railControlSize", (ROOT / "components/LeftRail.qml").read_text())
        self.assertIn("Theme.dashboardWidth", (ROOT / "components/DashboardHost.qml").read_text())
        self.assertIn("Theme.dashboardCardPadding", (ROOT / "components/dashboard/HomeTab.qml").read_text())
        self.assertIn("Theme.dashboardControlHeight", (ROOT / "components/dashboard/DashTabBar.qml").read_text())
        rail = (ROOT / "components/LeftRail.qml").read_text()
        self.assertIn("function showRailTooltip(text, item)", rail)
        self.assertIn('WlrLayershell.namespace: "gps-rail-tooltip"', rail)

    def test_existing_token_consumers_are_not_scaled_a_second_time(self):
        button = (ROOT / "components/GpsButton.qml").read_text(encoding="utf-8")
        icon_button = (ROOT / "components/IconButton.qml").read_text(encoding="utf-8")
        self.assertIn("Theme.controlHeightSm", button)
        self.assertIn("Theme.fontSizeBody", button)
        self.assertIn("Theme.iconSm", icon_button)
        self.assertNotRegex(button, r"Theme\.scaled\(\s*Theme\.")
        self.assertNotRegex(icon_button, r"Theme\.scaled\(\s*Theme\.")


if __name__ == "__main__":
    unittest.main()
