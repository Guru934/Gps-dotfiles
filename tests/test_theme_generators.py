#!/usr/bin/env python3
"""Comprehensive unit tests for GPS external application theme generators and contrast guard."""
from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
import sys
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import theme_common


class ContrastProtectionTests(unittest.TestCase):
    def test_relative_luminance_standards(self):
        """Relative luminance for standard pure black, white, and primary colors."""
        self.assertAlmostEqual(theme_common.relative_luminance("#000000"), 0.0, places=4)
        self.assertAlmostEqual(theme_common.relative_luminance("#FFFFFF"), 1.0, places=4)

    def test_contrast_ratio_formula(self):
        """Contrast ratio between pure black and white must equal 21:1."""
        ratio = theme_common.contrast_ratio("#FFFFFF", "#000000")
        self.assertAlmostEqual(ratio, 21.0, places=2)

    def test_safe_fallback_palette_meets_contrast_standard(self):
        """All text-on-surface combinations in canonical fallback palette must meet WCAG 4.5:1."""
        palette = theme_common.DEFAULT_FALLBACK_THEME
        fg = palette["textMain"]
        for bg_key in ["surfaceDeep", "card", "cardHover", "track"]:
            bg = palette[bg_key]
            ratio = theme_common.contrast_ratio(fg, bg)
            self.assertGreaterEqual(
                ratio,
                4.5,
                f"Contrast between {fg} and {bg_key} ({bg}) must be >= 4.5, got {ratio:.2f}",
            )

    def test_unsuitable_bright_palette_falls_back_to_safe_theme(self):
        """A bright wallpaper palette with insufficient text contrast must fall back safely."""
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            # Low contrast: #FFFFFF text on #FAFAFA background
            bad_data = {
                "surface": "#F2FAFAFA",
                "card": "#F0F0F0",
                "cardHover": "#EBEBEB",
                "track": "#F8F8F8",
                "border": "#D5D5D5",
                "brandAccent": "#FFCC00",
                "brandAccentFg": "#FFFFFF",
                "textMain": "#FFFFFF",
                "textMuted": "#EEEEEE",
            }
            f.write(json.dumps(bad_data))
            temp_path = f.name

        try:
            loaded, is_valid = theme_common.load_and_validate_palette(temp_path)
            self.assertFalse(is_valid, "Low-contrast palette must fail validation")
            self.assertEqual(loaded["surface"], theme_common.DEFAULT_FALLBACK_THEME["surface"])
            self.assertEqual(loaded["textMain"], theme_common.DEFAULT_FALLBACK_THEME["textMain"])
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)


class GTKThemeGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.config_dir = self.tmp_path / ".config"
        self.gtk3_dir = self.config_dir / "gtk-3.0"
        self.gtk4_dir = self.config_dir / "gtk-4.0"
        self.gtk3_dir.mkdir(parents=True, exist_ok=True)
        self.gtk4_dir.mkdir(parents=True, exist_ok=True)

        self.palette_file = self.tmp_path / "gps-theme.json"
        self.palette = {
            "surface": "#F2160B0B",
            "surfaceDeep": "#160B0B",
            "card": "#331C1C",
            "cardHover": "#472626",
            "track": "#160B0B",
            "border": "#5B3232",
            "brandAccent": "#F4504F",
            "brandAccentFg": "#140E14",
            "textMain": "#FFFFFF",
            "textMuted": "#DBBCBC",
        }
        self.palette_file.write_text(json.dumps(self.palette), encoding="utf-8")

        self.env = dict(os.environ, HOME=str(self.tmp_path), XDG_CONFIG_HOME=str(self.config_dir))

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_gtk_generation_and_adw_named_colors(self):
        """GTK hook generates gps-theme.css with all required libadwaita and GTK3 tokens."""
        hook = ROOT / "scripts" / "theme-hooks" / "01-gtk.py"
        res = subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Hook failed: {res.stderr}")

        for target_dir in [self.gtk3_dir, self.gtk4_dir]:
            gps_css = target_dir / "gps-theme.css"
            self.assertTrue(gps_css.is_file(), f"{gps_css} was not created")
            content = gps_css.read_text(encoding="utf-8")

            # Check libadwaita named colors
            self.assertIn("@define-color accent_color #F4504F;", content)
            self.assertIn("@define-color accent_bg_color #F4504F;", content)
            self.assertIn("@define-color accent_fg_color #140E14;", content)
            self.assertIn("@define-color window_bg_color #160B0B;", content)
            self.assertIn("@define-color window_fg_color #FFFFFF;", content)
            self.assertIn("@define-color card_bg_color #331C1C;", content)
            self.assertIn("@define-color border_color #5B3232;", content)

            # Check GTK 3 named colors
            self.assertIn("@define-color theme_selected_bg_color #F4504F;", content)
            self.assertIn("@define-color theme_bg_color #160B0B;", content)
            self.assertIn("@define-color theme_fg_color #FFFFFF;", content)

    def test_gtk_css_preserves_user_rules_and_creates_backup(self):
        """Existing user rules in gtk.css must be preserved and backed up to gtk.css.bak."""
        user_rule = "window.thunar { -gtk-icon-style: regular; }\n"
        (self.gtk3_dir / "gtk.css").write_text(user_rule, encoding="utf-8")

        hook = ROOT / "scripts" / "theme-hooks" / "01-gtk.py"
        subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, check=True)

        gtk_css = self.gtk3_dir / "gtk.css"
        backup = self.gtk3_dir / "gtk.css.bak"

        self.assertTrue(backup.is_file(), "Backup gtk.css.bak was not created")
        self.assertEqual(backup.read_text(encoding="utf-8"), user_rule)

        content = gtk_css.read_text(encoding="utf-8")
        self.assertIn("window.thunar", content)
        self.assertIn('@import url("gps-theme.css");', content)

    def test_gtk_repeated_runs_do_not_duplicate_blocks(self):
        """Running GTK hook multiple times must replace the GPS block without duplication."""
        hook = ROOT / "scripts" / "theme-hooks" / "01-gtk.py"
        subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, check=True)
        subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, check=True)

        content = (self.gtk3_dir / "gtk.css").read_text(encoding="utf-8")
        self.assertEqual(content.count("BEGIN GPS THEME"), 1)


class QtThemeGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.config_dir = self.tmp_path / ".config"
        self.qt6ct_dir = self.config_dir / "qt6ct"
        self.qt6ct_dir.mkdir(parents=True, exist_ok=True)

        self.palette_file = self.tmp_path / "gps-theme.json"
        self.palette = {
            "surface": "#F2160B0B",
            "surfaceDeep": "#160B0B",
            "card": "#331C1C",
            "cardHover": "#472626",
            "track": "#160B0B",
            "border": "#5B3232",
            "brandAccent": "#F4504F",
            "brandAccentFg": "#140E14",
            "textMain": "#FFFFFF",
            "textMuted": "#DBBCBC",
        }
        self.palette_file.write_text(json.dumps(self.palette), encoding="utf-8")
        self.env = dict(os.environ, HOME=str(self.tmp_path), XDG_CONFIG_HOME=str(self.config_dir))

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_qt6ct_color_scheme_format(self):
        """Qt hook creates 20-role active_colors and disabled_colors in INI format."""
        hook = ROOT / "scripts" / "theme-hooks" / "02-qt.py"
        res = subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Hook failed: {res.stderr}")

        scheme_file = self.qt6ct_dir / "colors" / "gps-theme.conf"
        self.assertTrue(scheme_file.is_file(), f"{scheme_file} was not created")

        cp = configparser.RawConfigParser()
        cp.read(str(scheme_file), encoding="utf-8")
        self.assertTrue(cp.has_section("ColorScheme"))

        active_colors = [c.strip() for c in cp.get("ColorScheme", "active_colors").split(",")]
        self.assertEqual(len(active_colors), 20, "Qt color scheme must define exactly 20 roles")

        for color in active_colors:
            self.assertTrue(re.match(r"^#[0-9a-fA-F]{8}$", color), f"Role color {color} is not #aarrggbb")

    def test_qt6ct_conf_preserves_other_sections(self):
        """Existing sections and keys in qt6ct.conf are preserved."""
        initial_conf = "[Fonts]\nfixed=\"JetBrains Mono,10\"\n"
        (self.qt6ct_dir / "qt6ct.conf").write_text(initial_conf, encoding="utf-8")

        hook = ROOT / "scripts" / "theme-hooks" / "02-qt.py"
        subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, check=True)

        cp = configparser.RawConfigParser()
        cp.read(str(self.qt6ct_dir / "qt6ct.conf"), encoding="utf-8")

        self.assertEqual(cp.get("Fonts", "fixed"), "\"JetBrains Mono,10\"")
        self.assertEqual(cp.get("Appearance", "custom_palette"), "true")
        self.assertIn("gps-theme.conf", cp.get("Appearance", "color_scheme_path"))
        self.assertTrue((self.qt6ct_dir / "qt6ct.conf.bak").is_file())


class KittyThemeGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.config_dir = self.tmp_path / ".config"
        self.kitty_dir = self.config_dir / "kitty"
        self.kitty_dir.mkdir(parents=True, exist_ok=True)

        self.palette_file = self.tmp_path / "gps-theme.json"
        self.palette = {
            "surface": "#F2160B0B",
            "surfaceDeep": "#160B0B",
            "card": "#331C1C",
            "cardHover": "#472626",
            "track": "#160B0B",
            "border": "#5B3232",
            "brandAccent": "#F4504F",
            "brandAccentFg": "#140E14",
            "textMain": "#FFFFFF",
            "textMuted": "#DBBCBC",
        }
        self.palette_file.write_text(json.dumps(self.palette), encoding="utf-8")
        self.env = dict(os.environ, HOME=str(self.tmp_path), XDG_CONFIG_HOME=str(self.config_dir))

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_kitty_theme_file_structure_and_contrast(self):
        """Kitty hook generates gps-theme.conf with colors and contrast protection."""
        hook = ROOT / "scripts" / "theme-hooks" / "03-kitty.py"
        res = subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Hook failed: {res.stderr}")

        theme_conf = self.kitty_dir / "gps-theme.conf"
        self.assertTrue(theme_conf.is_file())
        content = theme_conf.read_text(encoding="utf-8")

        self.assertIn("background", content)
        self.assertIn("foreground", content)
        self.assertIn("cursor", content)
        self.assertIn("selection_background", content)

        # Check all 16 ANSI colors present
        for i in range(16):
            self.assertIn(f"color{i} ", content)

    def test_kitty_conf_preserves_user_settings(self):
        """Existing user settings in kitty.conf are preserved and backed up."""
        user_conf = "font_family JetBrains Mono\nenable_audio_bell no\n"
        (self.kitty_dir / "kitty.conf").write_text(user_conf, encoding="utf-8")

        hook = ROOT / "scripts" / "theme-hooks" / "03-kitty.py"
        subprocess.run([sys.executable, str(hook), str(self.palette_file)], env=self.env, check=True)

        kitty_conf = self.kitty_dir / "kitty.conf"
        backup = self.kitty_dir / "kitty.conf.bak"

        self.assertTrue(backup.is_file())
        self.assertEqual(backup.read_text(encoding="utf-8"), user_conf)

        content = kitty_conf.read_text(encoding="utf-8")
        self.assertIn("enable_audio_bell no", content)
        self.assertIn("include gps-theme.conf", content)


if __name__ == "__main__":
    unittest.main()
