import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_QML = (ROOT / "config/Theme.qml").read_text(encoding="utf-8")


class ThemeContractTests(unittest.TestCase):
    def test_theme_watches_gps_theme_file(self):
        self.assertIn("watchChanges: true", THEME_QML)
        self.assertIn("gps-theme.json", THEME_QML)
        self.assertIn("onLoaded: root.applyLive", THEME_QML)
        self.assertIn("onFileChanged: themeFile.reload()", THEME_QML)

    def test_theme_respects_animation_and_reduced_motion(self):
        self.assertIn("GPS_REDUCED_MOTION", THEME_QML)
        self.assertIn("animDuration:", THEME_QML)
        self.assertIn("rice-settings.json", THEME_QML)
        self.assertIn("ColorAnimation { duration: root.animDuration }", THEME_QML)

    def test_theme_animates_core_colors(self):
        for prop in ["surface", "card", "cardHover", "border", "brandAccent", "brandAccentFg", "textMain", "textMuted", "surfaceBase", "accentPrimary"]:
            self.assertIn(f"Behavior on {prop}", THEME_QML)

    def test_theme_preserves_safe_fallbacks(self):
        self.assertIn("#B30F131C", THEME_QML)
        self.assertIn("#CC1C1F29", THEME_QML)
        self.assertIn("#2DD4BF", THEME_QML)
        self.assertIn("#003731", THEME_QML)


if __name__ == "__main__":
    unittest.main()
