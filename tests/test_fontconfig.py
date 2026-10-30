#!/usr/bin/env python3
"""Automated unit and contract tests for GPS fontconfig configuration and setup."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FONTS_CONF = ROOT / "dots" / "fontconfig" / "fonts.conf"
SETUP_SCRIPT = ROOT / "scripts" / "setup-fonts.sh"


class FontconfigXmlTests(unittest.TestCase):
    """Verifies that dots/fontconfig/fonts.conf exists and is valid XML conforming to requirements."""

    def test_fonts_conf_exists_and_is_valid_xml(self):
        self.assertTrue(FONTS_CONF.is_file(), f"{FONTS_CONF} must exist")
        tree = ET.parse(FONTS_CONF)
        root = tree.getroot()
        self.assertEqual(root.tag, "fontconfig")

    def test_rendering_rules_configured(self):
        text = FONTS_CONF.read_text(encoding="utf-8")
        self.assertIn("<const>hintslight</const>", text)
        self.assertIn("<const>none</const>", text)
        self.assertIn("<bool>true</bool>", text)

    def test_fallback_chains_include_all_target_scripts(self):
        text = FONTS_CONF.read_text(encoding="utf-8")
        # English preferred
        self.assertIn("Plus Jakarta Sans", text)
        self.assertIn("JetBrains Mono", text)
        # Nerd Font bridge
        self.assertIn("JetBrainsMono Nerd Font", text)
        # Devanagari / Hindi
        self.assertIn("Noto Sans Devanagari", text)
        # Japanese CJK
        self.assertIn("Noto Sans CJK JP", text)
        # Korean CJK
        self.assertIn("Noto Sans CJK KR", text)
        # Emoji
        self.assertIn("Noto Color Emoji", text)


class FontconfigInstallerTests(unittest.TestCase):
    """Tests for scripts/setup-fonts.sh installer safety and idempotency."""

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp(prefix="gps_font_installer_")
        self.dest_dir = Path(self.tmp_dir) / "fontconfig"

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def run_installer(self, *args):
        cmd = [str(SETUP_SCRIPT), "--dest-dir", str(self.dest_dir), "--no-cache"] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_dry_run_modifies_no_files(self):
        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[DRY-RUN]", res.stdout)
        self.assertFalse(self.dest_dir.exists())

    def test_install_creates_symlink(self):
        res = self.run_installer()
        self.assertEqual(res.returncode, 0)
        dest_conf = self.dest_dir / "fonts.conf"
        self.assertTrue(dest_conf.is_symlink())
        self.assertEqual(dest_conf.resolve(), FONTS_CONF.resolve())

    def test_re_run_is_idempotent(self):
        res1 = self.run_installer()
        self.assertEqual(res1.returncode, 0)
        res2 = self.run_installer()
        self.assertEqual(res2.returncode, 0)
        self.assertIn("already linked", res2.stdout)

    def test_existing_config_is_backed_up(self):
        self.dest_dir.mkdir(parents=True)
        orig_file = self.dest_dir / "fonts.conf"
        orig_file.write_text("<!-- preexisting user config -->\n", encoding="utf-8")

        res = self.run_installer()
        self.assertEqual(res.returncode, 0)

        # Confirm new symlink is in place
        self.assertTrue(orig_file.is_symlink())
        self.assertEqual(orig_file.resolve(), FONTS_CONF.resolve())

        # Confirm backup was made
        backups = list(self.dest_dir.glob("fonts.conf.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), "<!-- preexisting user config -->\n")


class FontResolutionTests(unittest.TestCase):
    """Asserts fontconfig matching with fc-match, gracefully skipping missing optional fonts."""

    def fc_match(self, query, fmt="%{family}"):
        cmd = ["fc-match", "-f", fmt, query]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"fc-match failed on {query}: {res.stderr}")
        return res.stdout.strip()

    def is_font_installed(self, family_name):
        cmd = ["fc-list", f":family={family_name}", "family"]
        res = subprocess.run(cmd, capture_output=True, text=True)
        return bool(res.stdout.strip())

    def test_rendering_properties(self):
        out = self.fc_match("sans-serif", "%{antialias}:%{hinting}:%{hintstyle}:%{rgba}")
        parts = out.split(":")
        self.assertEqual(parts[0], "True", "Antialiasing must be enabled")
        self.assertEqual(parts[1], "True", "Hinting must be enabled")
        self.assertEqual(parts[2], "1", "Hintstyle must be 1 (hintslight)")
        self.assertEqual(parts[3], "5", "RGBA must be 5 (none for OLED agnostic output)")

    def test_sans_resolution_with_fallback(self):
        matched = self.fc_match("sans-serif")
        if self.is_font_installed("Plus Jakarta Sans"):
            self.assertIn("Plus Jakarta Sans", matched)
        else:
            self.assertIn("Noto Sans", matched)

    def test_mono_resolution_with_fallback(self):
        matched = self.fc_match("monospace")
        # JetBrainsMono Nerd Font is installed in this environment
        self.assertTrue(
            "JetBrains" in matched or "Noto Sans Mono" in matched,
            f"Expected JetBrains or Noto Sans Mono, got: {matched}"
        )

    def test_emoji_resolution(self):
        if self.is_font_installed("Noto Color Emoji"):
            matched = self.fc_match("emoji")
            self.assertIn("Noto Color Emoji", matched)

    def test_devanagari_resolution(self):
        if self.is_font_installed("Noto Sans Devanagari"):
            matched = self.fc_match("sans-serif:lang=hi")
            self.assertIn("Noto Sans Devanagari", matched)

    def test_japanese_resolution_prefers_jp_over_kr(self):
        if self.is_font_installed("Noto Sans CJK JP"):
            matched = self.fc_match("sans-serif:lang=ja")
            self.assertIn("Noto Sans CJK JP", matched)
            self.assertNotIn("KR", matched)

    def test_korean_resolution_prefers_kr_over_jp(self):
        if self.is_font_installed("Noto Sans CJK KR"):
            matched = self.fc_match("sans-serif:lang=ko")
            self.assertIn("Noto Sans CJK KR", matched)
            self.assertNotIn("JP", matched)

    def test_material_symbols_resolution(self):
        if self.is_font_installed("Material Symbols Rounded"):
            matched = self.fc_match("Material Symbols Rounded")
            self.assertIn("Material Symbols Rounded", matched)


if __name__ == "__main__":
    unittest.main()
