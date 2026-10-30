#!/usr/bin/env python3
"""Automated unit and contract tests for GPS user-space icon theme generation."""
import configparser
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
import sys
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import gps_icons
import theme_common


class SvgRecoloringUnitTests(unittest.TestCase):
    """Verifies SVG recoloring algorithm, shade computations, and XML preservation."""

    def test_compute_folder_shades_produces_valid_hex(self):
        acc = "#2DD4BF"
        front, back, glyph = gps_icons.compute_folder_shades(acc)
        self.assertEqual(front.lower(), "#2dd4bf")
        self.assertTrue(back.startswith("#") and len(back) == 7)
        self.assertTrue(glyph.startswith("#") and len(glyph) == 7)

        # Back flap should have lower luminance than front flap
        l_front = theme_common.relative_luminance(front)
        l_back = theme_common.relative_luminance(back)
        self.assertLess(l_back, l_front)

    def test_recolor_svg_content_replaces_expected_colors(self):
        sample_svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">\n'
            ' <path style="fill:#4877b1" d="M 4,34 Z"/>\n'
            ' <rect style="fill:#5294e2" width="40" height="26"/>\n'
            ' <path style="fill:#1d344f" d="M 19 22 Z"/>\n'
            '</svg>'
        )
        recolored = gps_icons.recolor_svg_content(sample_svg, "#112233", "#445566", "#778899")
        self.assertNotIn("#4877b1", recolored)
        self.assertNotIn("#5294e2", recolored)
        self.assertNotIn("#1d344f", recolored)
        self.assertIn("#112233", recolored)
        self.assertIn("#445566", recolored)
        self.assertIn("#778899", recolored)
        # XML tags and attributes preserved
        self.assertIn('width="48"', recolored)
        self.assertIn('height="48"', recolored)
        self.assertIn('<rect style="fill:#112233" width="40" height="26"/>', recolored)

    def test_recolor_16x16_symbolic_svg(self):
        sample_16 = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">\n'
            ' <path style="fill:currentColor" class="ColorScheme-Text" d="M 1,2 Z"/>\n'
            '</svg>'
        )
        recolored = gps_icons.recolor_svg_content(sample_16, "#ff0077", "#880033", "#330011")
        self.assertIn('style="fill:#ff0077"', recolored)


class IndexThemeGenerationTests(unittest.TestCase):
    """Verifies standard Freedesktop index.theme generation and inheritance."""

    def test_valid_index_theme_structure(self):
        dirs = [("16x16/places", 16), ("48x48/places", 48)]
        content = gps_icons.generate_index_theme("Papirus-Dark", dirs)

        self.assertIn("[Icon Theme]", content)
        self.assertIn("Name=GPS-Icons", content)
        self.assertIn("Inherits=Papirus-Dark,hicolor", content)
        self.assertIn("Directories=16x16/places,48x48/places", content)

        self.assertIn("[16x16/places]", content)
        self.assertIn("Context=Places", content)
        self.assertIn("Size=16", content)
        self.assertIn("Type=Fixed", content)

        self.assertIn("[48x48/places]", content)
        self.assertIn("Size=48", content)


class ThemeGenerationPipelineTests(unittest.TestCase):
    """Tests the full generation pipeline using isolated temporary directories."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.icons_root = self.tmp_path / "share" / "icons"
        self.state_dir = self.tmp_path / "state" / "gps"
        self.config_dir = self.tmp_path / "config"
        self.icons_root.mkdir(parents=True)
        self.state_dir.mkdir(parents=True)
        self.config_dir.mkdir(parents=True)

        # Create a mock palette JSON
        self.palette_file = self.tmp_path / "theme.json"
        self.palette_data = dict(theme_common.DEFAULT_FALLBACK_THEME)
        self.palette_data["brandAccent"] = "#F46EAE"
        self.palette_file.write_text(json.dumps(self.palette_data), encoding="utf-8")

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _setup_mock_base_theme(self, name: str = "Papirus-Dark") -> Path:
        base_dir = self.icons_root / name
        base_dir.mkdir(parents=True)
        (base_dir / "index.theme").write_text("[Icon Theme]\nName=" + name + "\n", encoding="utf-8")

        places_48 = base_dir / "48x48" / "places"
        places_48.mkdir(parents=True)
        sample_svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">\n'
            ' <path style="fill:#4877b1" d="M 4,34 Z"/>\n'
            ' <rect style="fill:#5294e2" width="40" height="26"/>\n'
            '</svg>'
        )
        (places_48 / "folder-blue.svg").write_text(sample_svg, encoding="utf-8")
        (places_48 / "folder.svg").symlink_to("folder-blue.svg")
        return base_dir

    def test_generation_with_base_theme(self):
        self._setup_mock_base_theme("Papirus-Dark")

        res = gps_icons.generate_gps_icon_theme(
            palette_path=self.palette_file,
            target_icons_root=self.icons_root,
            custom_icon_roots=[self.icons_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
            force=True,
        )
        self.assertTrue(res["ok"])
        self.assertTrue(res["recolored"])
        self.assertEqual(res["base_theme"], "Papirus-Dark")
        self.assertEqual(res["accent"].lower(), "#f46eae")

        target_theme = self.icons_root / "GPS-Icons"
        self.assertTrue(target_theme.is_dir())
        self.assertTrue((target_theme / "index.theme").is_file())

        index_txt = (target_theme / "index.theme").read_text(encoding="utf-8")
        self.assertIn("Inherits=Papirus-Dark,hicolor", index_txt)

        recolored_svg = (target_theme / "48x48" / "places" / "folder-blue.svg").read_text(encoding="utf-8")
        self.assertIn("#f46eae", recolored_svg)
        self.assertNotIn("#5294e2", recolored_svg)

        # Relative symlink preserved
        folder_symlink = target_theme / "48x48" / "places" / "folder.svg"
        self.assertTrue(folder_symlink.is_symlink())
        self.assertEqual(os.readlink(folder_symlink), "folder-blue.svg")

    def test_noop_when_accent_unchanged(self):
        self._setup_mock_base_theme("Papirus-Dark")

        # Initial generation
        res1 = gps_icons.generate_gps_icon_theme(
            palette_path=self.palette_file,
            target_icons_root=self.icons_root,
            custom_icon_roots=[self.icons_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
        )
        self.assertTrue(res1["recolored"])

        # Second run with same palette -> no-op
        res2 = gps_icons.generate_gps_icon_theme(
            palette_path=self.palette_file,
            target_icons_root=self.icons_root,
            custom_icon_roots=[self.icons_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
        )
        self.assertTrue(res2["ok"])
        self.assertFalse(res2["recolored"])
        self.assertIn("no-op", res2["reason"].lower())

    def test_fallback_when_base_theme_missing(self):
        # Empty icon root (no base theme present)
        empty_root = self.tmp_path / "empty_icons"
        empty_root.mkdir()

        res = gps_icons.generate_gps_icon_theme(
            palette_path=self.palette_file,
            target_icons_root=self.icons_root,
            custom_icon_roots=[empty_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
            force=True,
        )
        self.assertTrue(res["ok"])
        self.assertTrue(res["recolored"])
        self.assertEqual(res["base_theme"], "hicolor")

        target_theme = self.icons_root / "GPS-Icons"
        self.assertTrue(target_theme.is_dir())
        self.assertTrue((target_theme / "index.theme").is_file())
        self.assertTrue((target_theme / "48x48" / "places" / "folder.svg").is_file())

    def test_invalid_palette_falls_back_safely(self):
        bad_palette = self.tmp_path / "corrupt.json"
        bad_palette.write_text("invalid json content {{{", encoding="utf-8")

        res = gps_icons.generate_gps_icon_theme(
            palette_path=bad_palette,
            target_icons_root=self.icons_root,
            custom_icon_roots=[self.icons_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
            force=True,
        )
        self.assertTrue(res["ok"])
        # Falls back to canonical default accent (#2DD4BF)
        self.assertEqual(res["accent"].upper(), "#2DD4BF")

    def test_preserves_existing_user_gtk_and_qt_settings(self):
        # Pre-populate gtk-3.0/settings.ini with custom options
        gtk3_file = self.config_dir / "gtk-3.0" / "settings.ini"
        gtk3_file.parent.mkdir(parents=True)
        gtk3_file.write_text(
            "[Settings]\n"
            "gtk-cursor-theme-name = Adwaita\n"
            "custom-user-font = JetBrains Mono 10\n",
            encoding="utf-8",
        )

        # Pre-populate qt6ct.conf
        qt6ct_file = self.config_dir / "qt6ct" / "qt6ct.conf"
        qt6ct_file.parent.mkdir(parents=True)
        qt6ct_file.write_text(
            "[Appearance]\n"
            "style = Fusion\n"
            "custom_palette = true\n",
            encoding="utf-8",
        )

        self._setup_mock_base_theme("Papirus-Dark")

        gps_icons.generate_gps_icon_theme(
            palette_path=self.palette_file,
            target_icons_root=self.icons_root,
            custom_icon_roots=[self.icons_root],
            state_dir=self.state_dir,
            config_dir=self.config_dir,
            force=True,
        )

        # Check GTK preserved
        cp = configparser.RawConfigParser()
        cp.read(str(gtk3_file), encoding="utf-8")
        self.assertEqual(cp.get("Settings", "custom-user-font"), "JetBrains Mono 10")
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-name"), "Adwaita")
        self.assertEqual(cp.get("Settings", "gtk-icon-theme-name"), "GPS-Icons")

        # Check Qt preserved
        qcp = configparser.RawConfigParser()
        qcp.read(str(qt6ct_file), encoding="utf-8")
        self.assertEqual(qcp.get("Appearance", "style"), "Fusion")
        self.assertEqual(qcp.get("Appearance", "icon_theme"), "GPS-Icons")


if __name__ == "__main__":
    unittest.main()
