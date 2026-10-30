import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_QML_PATH = ROOT / "config" / "Theme.qml"
THEME_QML = THEME_QML_PATH.read_text(encoding="utf-8")


class FontContractTests(unittest.TestCase):
    """Contract tests ensuring unified font system adherence across production QML."""

    def test_theme_exposes_central_font_tokens(self):
        """Theme.qml must define fontSans, fontMono, fontIcon and backwards-compatible fontUi."""
        self.assertIn("readonly property string fontSans:", THEME_QML)
        self.assertIn("readonly property string fontMono:", THEME_QML)
        self.assertIn("readonly property string fontIcon:", THEME_QML)
        self.assertIn("readonly property string fontUi:", THEME_QML)

    def test_theme_exposes_preferred_and_fallback_font_tokens(self):
        """Theme.qml must expose explicit preferred families and installed fallback properties."""
        self.assertIn("readonly property string fontSansPreferred:", THEME_QML)
        self.assertIn("readonly property string fontMonoPreferred:", THEME_QML)
        self.assertIn("readonly property string fontIconPreferred:", THEME_QML)
        self.assertIn("readonly property string fontSansFallback:", THEME_QML)
        self.assertIn("readonly property string fontMonoFallback:", THEME_QML)
        self.assertIn("readonly property string fontIconFallback:", THEME_QML)

        # Ensure preferred targets match GPS visual identity
        self.assertIn('"Plus Jakarta Sans"', THEME_QML)
        self.assertIn('"JetBrains Mono"', THEME_QML)
        self.assertIn('"Material Symbols Rounded"', THEME_QML)

    def test_theme_defines_resolve_font_function(self):
        """Theme.qml must provide a resolution function that inspects installed fonts."""
        self.assertIn("function resolveFont(preferred, fallbacks)", THEME_QML)

    def test_no_hardcoded_font_families_in_production_qml(self):
        """Production QML components must never hard-code font family strings outside Theme.qml."""
        family_pattern = re.compile(r"""(?:font\.family|family)\s*:\s*["']([^"']+)["']""")
        violations = []

        # Directories containing production QML
        scan_dirs = ["components", "island", "pet", "login"]
        target_files = [ROOT / "shell.qml", ROOT / "settings.qml"]
        for d in scan_dirs:
            target_files.extend((ROOT / d).rglob("*.qml"))

        for path in target_files:
            if not path.is_file():
                continue
            # Allow Theme.qml itself to define fallback strings
            if path.resolve() == THEME_QML_PATH.resolve():
                continue
            content = path.read_text(encoding="utf-8")
            for idx, line in enumerate(content.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("/*"):
                    continue
                match = family_pattern.search(line)
                if match:
                    font_name = match.group(1)
                    violations.append(f"{path.relative_to(ROOT)}:L{idx} -> '{font_name}' in: {stripped}")

        self.assertEqual(violations, [], f"Found hard-coded font families in production QML:\n" + "\n".join(violations))


if __name__ == "__main__":
    unittest.main()
