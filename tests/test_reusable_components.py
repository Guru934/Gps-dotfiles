import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ROOT / "components"


class ReusableComponentsTests(unittest.TestCase):
    """Verifies that the canonical reusable visual primitives exist, import qs.config,

    and expose the required public contracts.
    """

    def test_primitives_exist_and_import_theme(self):
        primitives = [
            "GlassSurface.qml",
            "GlassCard.qml",
            "SectionHeader.qml",
            "IconButton.qml",
            "GpsButton.qml",
            "StatusIndicator.qml",
            "Separator.qml",
        ]
        for p in primitives:
            path = COMPONENTS / p
            self.assertTrue(path.exists(), f"Missing primitive component: {p}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("import qs.config", content, f"{p} must import qs.config")

    def test_glass_surface_contract(self):
        content = (COMPONENTS / "GlassSurface.qml").read_text(encoding="utf-8")
        self.assertIn("property bool elevated:", content)
        self.assertIn("property real cornerRadius:", content)
        self.assertIn("property real borderWidth:", content)
        self.assertIn("property color borderColor:", content)
        self.assertIn("property bool highlight:", content)

    def test_glass_card_contract(self):
        content = (COMPONENTS / "GlassCard.qml").read_text(encoding="utf-8")
        self.assertIn("property bool interactive:", content)
        self.assertIn("property bool selected:", content)
        self.assertIn("property bool accentBorder:", content)
        self.assertIn("signal clicked()", content)
        self.assertIn("readonly property bool hovered:", content)

    def test_section_header_contract(self):
        content = (COMPONENTS / "SectionHeader.qml").read_text(encoding="utf-8")
        self.assertIn("property string title:", content)
        self.assertIn("property string subtitle:", content)
        self.assertIn("property string icon:", content)
        self.assertIn("property string tag:", content)

    def test_icon_button_contract(self):
        content = (COMPONENTS / "IconButton.qml").read_text(encoding="utf-8")
        self.assertIn("property string icon:", content)
        self.assertIn("property real size:", content)
        self.assertIn("property color accentColor:", content)
        self.assertIn("signal clicked()", content)
        self.assertIn("signal scrolledUp()", content)
        self.assertIn("signal scrolledDown()", content)

    def test_gps_button_contract(self):
        content = (COMPONENTS / "GpsButton.qml").read_text(encoding="utf-8")
        self.assertIn("property string text:", content)
        self.assertIn("property string variant:", content)
        self.assertIn("property string size:", content)
        self.assertIn("signal clicked()", content)
        self.assertIn("variant === \"primary\"", content)
        self.assertIn("variant === \"danger\"", content)

    def test_status_indicator_contract(self):
        content = (COMPONENTS / "StatusIndicator.qml").read_text(encoding="utf-8")
        self.assertIn("property string status:", content)
        self.assertIn("property string label:", content)
        self.assertIn("property bool pulse:", content)
        self.assertIn("Theme.statusGood", content)
        self.assertIn("Theme.statusWarn", content)
        self.assertIn("Theme.statusDanger", content)

    def test_separator_contract(self):
        content = (COMPONENTS / "Separator.qml").read_text(encoding="utf-8")
        self.assertIn("property int orientation:", content)
        self.assertIn("property color strokeColor:", content)


if __name__ == "__main__":
    unittest.main()
