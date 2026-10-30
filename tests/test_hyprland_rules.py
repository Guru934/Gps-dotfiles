import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPR_LUA = (ROOT / "dots/hypr/hyprland.lua").read_text(encoding="utf-8")


class HyprlandVisualRulesTests(unittest.TestCase):
    """Verifies that Hyprland window and layer rules adhere to the GPS Unified Visual Design System."""

    def test_border_colors_match_gps_palette(self):
        self.assertIn("2dd4bf", HYPR_LUA)
        self.assertIn("57f1db", HYPR_LUA)
        self.assertIn("3c4a46", HYPR_LUA)

    def test_layer_rules_for_gps_surfaces(self):
        self.assertIn("gps-rail-blur", HYPR_LUA)
        self.assertIn("gps-island-blur", HYPR_LUA)
        self.assertIn("gps-rofi-blur", HYPR_LUA)

    def test_text_crispness_and_terminal_exception(self):
        self.assertIn("gps-terminal-opaque", HYPR_LUA)
        self.assertIn("opaque = true", HYPR_LUA)

    def test_media_playback_and_pip_exceptions(self):
        self.assertIn("gps-media-opaque", HYPR_LUA)
        self.assertIn("idle_inhibit", HYPR_LUA)
        self.assertIn("gps-pip-float", HYPR_LUA)

    def test_floating_utility_and_hub_rules(self):
        self.assertIn("gps-floating-dialogs", HYPR_LUA)
        self.assertIn("gps-hubs-float", HYPR_LUA)
        self.assertIn("gps-pet-companion-float", HYPR_LUA)


if __name__ == "__main__":
    unittest.main()
