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

    def test_theme_exposes_and_animates_left_luminance(self):
        self.assertIn("property real leftLuminance:", THEME_QML)
        self.assertIn("Behavior on leftLuminance", THEME_QML)
        self.assertIn("NumberAnimation { duration: root.animDuration }", THEME_QML)
        self.assertIn("leftLuminance: pickNum(\"leftLuminance\"", THEME_QML)

    def test_island_theme_tokens_contract(self):
        """Verifies that every Theme token used by island/ exists in config/Theme.qml
        and that island files import the canonical qs.config module.
        """
        import os
        import re

        island_dir = ROOT / "island"
        self.assertTrue((island_dir / "config").exists(), "island/config must exist")
        if (island_dir / "config").is_symlink():
            self.assertEqual(
                os.readlink(island_dir / "config"),
                "../config",
                "island/config symlink must resolve to ../config",
            )

        control_qml = (island_dir / "states/Control.qml").read_text(encoding="utf-8")
        self.assertIn("import qs.config", control_qml, "Control.qml must import qs.config")
        self.assertNotIn('import "../../config"', control_qml, "Control.qml must not use relative config import")

        theme_props = set(
            re.findall(
                r"(?:property\s+[a-zA-Z0-9_<>]+\s+|readonly\s+property\s+[a-zA-Z0-9_<>]+\s+)([a-zA-Z0-9_]+)",
                THEME_QML,
            )
        )
        self.assertTrue(len(theme_props) > 0, "Failed to parse properties from Theme.qml")

        island_files = list(island_dir.rglob("*.qml"))
        for path in island_files:
            content = path.read_text(encoding="utf-8")
            used_tokens = set(re.findall(r"Theme\.([a-zA-Z0-9_]+)", content))
            if used_tokens:
                self.assertIn(
                    "import qs.config",
                    content,
                    f"{path.relative_to(ROOT)} uses Theme tokens but does not import qs.config",
                )
                missing = used_tokens - theme_props
                self.assertFalse(
                    missing,
                    f"{path.relative_to(ROOT)} uses Theme tokens not found in Theme.qml: {missing}",
                )

    def test_every_theme_token_used_in_qml_is_defined(self):
        """Scans every QML file for Theme.<name> and checks each name is declared
        in config/Theme.qml (and in island/config/Theme.qml), failing with file and line when not.
        """
        import re

        config_theme_path = ROOT / "config/Theme.qml"
        island_theme_path = ROOT / "island/config/Theme.qml"
        self.assertTrue(config_theme_path.exists(), "config/Theme.qml must exist")
        self.assertTrue(island_theme_path.exists(), "island/config/Theme.qml must exist")

        def extract_declared(theme_text):
            props = set(re.findall(
                r"(?:readonly\s+)?property\s+(?:alias|[a-zA-Z0-9_<>]+)\s+([a-zA-Z0-9_]+)",
                theme_text,
            ))
            funcs = set(re.findall(r"function\s+([a-zA-Z0-9_]+)", theme_text))
            return props | funcs

        declared_config = extract_declared(config_theme_path.read_text(encoding="utf-8"))
        declared_island = extract_declared(island_theme_path.read_text(encoding="utf-8"))

        violations = []
        for qml_path in sorted(ROOT.rglob("*.qml")):
            rel_path = qml_path.relative_to(ROOT)
            if "tests" in rel_path.parts:
                continue
            content = qml_path.read_text(encoding="utf-8")
            if re.search(r'import\s+["\'][^"\']*Theme\.js["\']\s+as\s+Theme', content):
                continue

            for line_no, line in enumerate(content.splitlines(), start=1):
                clean_line = re.sub(r"//.*$", "", line)
                for match in re.finditer(r"\bTheme\.([a-zA-Z0-9_]+)\b", clean_line):
                    token = match.group(1)
                    if token not in declared_config:
                        violations.append(f"{rel_path}:{line_no}: Theme.{token} not declared in config/Theme.qml")
                    if token not in declared_island:
                        violations.append(f"{rel_path}:{line_no}: Theme.{token} not declared in island/config/Theme.qml")

        if violations:
            self.fail(f"Found {len(violations)} undeclared Theme token usage(s):\n" + "\n".join(violations))


if __name__ == "__main__":
    unittest.main()
