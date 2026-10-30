import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_QML = (ROOT / "config/Theme.qml").read_text(encoding="utf-8")


class DesignTokensContractTests(unittest.TestCase):
    """Verifies that the canonical design tokens are defined and exported in Theme.qml."""

    def test_color_tokens_exist(self):
        colors = [
            "accentPrimary",
            "brandAccent",
            "brandAccentFg",
            "onAccent",
            "accentSecondary",
            "accentSecondaryDim",
            "accentTertiary",
            "surfaceDeep",
            "surfaceBase",
            "surfaceHigh",
            "surfaceVariant",
            "surface",
            "card",
            "cardHover",
            "surfaceActive",
            "track",
            "border",
            "outlineSoft",
            "glassBorder",
            "textMain",
            "textDim",
            "textMuted",
            "textSecondary",
            "statusGood",
            "statusWarn",
            "statusDanger",
            "statusDangerBg",
            "statusDangerBorder",
            "statusDangerFg",
            "statusSuccessBg",
            "statusSuccessFg",
            "statusWarnBg",
            "statusWarnFg",
        ]
        for c in colors:
            self.assertTrue(
                f"property color {c}" in THEME_QML or f"property alias {c}" in THEME_QML or f"readonly property color {c}" in THEME_QML,
                f"Missing color token: {c}",
            )

    def test_geometry_tokens_exist(self):
        geometry = [
            # Spacing scale
            "spacingXs", "spacingSm", "spacingMd", "spacingLg", "spacingXl",
            # Corner radius scale
            "radiusXs", "radiusSm", "radiusMd", "radiusCard", "radiusDrawer", "radiusPanel", "radiusPill", "radiusLg", "radiusXl",
            # Border widths
            "borderWidth", "borderWidthThick",
            # Component heights
            "controlHeightSm", "controlHeightMd", "controlHeightLg", "controlHeightXl",
            # Padding scale
            "paddingSm", "paddingMd", "paddingLg", "paddingXl",
            # Icon sizes
            "iconXs", "iconSm", "iconMd", "iconLg", "iconXl",
        ]
        for g in geometry:
            self.assertIn(f"readonly property int {g}:", THEME_QML, f"Missing geometry token: {g}")

    def test_typography_tokens_exist(self):
        self.assertIn("readonly property string fontUi:", THEME_QML)
        self.assertIn("readonly property string fontMono:", THEME_QML)
        type_scales = [
            "fontSizeDisplay", "fontSizeHeading", "fontSizeSubheading",
            "fontSizeBody", "fontSizeSecondary", "fontSizeCaption", "fontSizeSmall"
        ]
        for t in type_scales:
            self.assertIn(f"readonly property int {t}:", THEME_QML, f"Missing typography token: {t}")

    def test_effects_tokens_exist(self):
        effects = [
            ("glassAlpha", "real"),
            ("glassAlphaElevated", "real"),
            ("glassAlphaSolid", "real"),
            ("borderAlpha", "real"),
            ("highlightAlpha", "real"),
            ("hoverAlpha", "real"),
            ("shadowColor", "color"),
            ("shadowRadius", "int"),
            ("blurRadius", "int"),
            ("blurPasses", "int"),
        ]
        for name, typ in effects:
            self.assertIn(f"readonly property {typ} {name}:", THEME_QML, f"Missing effect token: {name}")

    def test_motion_tokens_exist(self):
        durations = ["animFast", "animNormal", "animSlow", "animDuration"]
        for d in durations:
            self.assertIn(f"readonly property int {d}:", THEME_QML, f"Missing motion duration: {d}")
        self.assertIn("readonly property int easingStandard:", THEME_QML)
        self.assertIn("readonly property int easingEmphasized:", THEME_QML)


if __name__ == "__main__":
    unittest.main()
