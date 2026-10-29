import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_QML = (ROOT / "config/Theme.qml").read_text(encoding="utf-8")
TOOLBOX_QML = (ROOT / "components/Toolbox.qml").read_text(encoding="utf-8")
MEDIAHUB_QML = (ROOT / "components/MediaHub.qml").read_text(encoding="utf-8")
CAROUSEL_QML = (ROOT / "components/WallpaperCarousel.qml").read_text(encoding="utf-8")


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

    def test_toolbox_maps_structural_tokens_to_theme(self):
        self.assertIn("import qs.config", TOOLBOX_QML)
        self.assertIn("bg: Theme.surfaceDeep", TOOLBOX_QML)
        self.assertIn("panel: Theme.surfaceBase", TOOLBOX_QML)
        self.assertIn("raised: Theme.card", TOOLBOX_QML)
        self.assertIn("line: Theme.outlineSoft", TOOLBOX_QML)
        self.assertIn("text: Theme.textMain", TOOLBOX_QML)
        self.assertIn("violet: Theme.brandAccent", TOOLBOX_QML)

    def test_mediahub_maps_structural_tokens_to_theme(self):
        self.assertIn("import qs.config", MEDIAHUB_QML)
        self.assertIn("bg: Theme.surfaceDeep", MEDIAHUB_QML)
        self.assertIn("low: Theme.surfaceBase", MEDIAHUB_QML)
        self.assertIn("cont: Theme.card", MEDIAHUB_QML)
        self.assertIn("line: Theme.outlineSoft", MEDIAHUB_QML)
        self.assertIn("text: Theme.textMain", MEDIAHUB_QML)
        self.assertIn('id: "system"', MEDIAHUB_QML)
        self.assertIn("accent: Theme.brandAccent", MEDIAHUB_QML)

    def test_carousel_uses_theme_tokens(self):
        self.assertIn("Theme.surfaceDeep", CAROUSEL_QML)


if __name__ == "__main__":
    unittest.main()
