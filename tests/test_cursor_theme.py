#!/usr/bin/env python3
"""Automated unit and contract tests for GPS cursor configuration."""
import configparser
import os
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HYPRLAND_LUA = ROOT / "dots" / "hypr" / "hyprland.lua"
GTK3_SETTINGS = ROOT / "dots" / "gtk-3.0" / "settings.ini"
GTK4_SETTINGS = ROOT / "dots" / "gtk-4.0" / "settings.ini"

import sys
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import cursor_setup


class HyprlandCursorContractTests(unittest.TestCase):
    """Verifies that Hyprland configuration sets required cursor environment variables."""

    def test_hyprland_lua_has_cursor_variables(self):
        self.assertTrue(HYPRLAND_LUA.is_file(), f"{HYPRLAND_LUA} must exist")
        content = HYPRLAND_LUA.read_text(encoding="utf-8")
        self.assertIn('hl.env("XCURSOR_THEME", "Adwaita")', content)
        self.assertIn('hl.env("XCURSOR_SIZE", "24")', content)
        self.assertIn('hl.env("HYPRCURSOR_THEME", "Adwaita")', content)
        self.assertIn('hl.env("HYPRCURSOR_SIZE", "24")', content)


class GtkSettingsDotfileContractTests(unittest.TestCase):
    """Verifies that repository dotfiles for GTK include cursor and dark theme settings."""

    def test_gtk3_dotfile_exists_and_valid(self):
        self.assertTrue(GTK3_SETTINGS.is_file(), f"{GTK3_SETTINGS} must exist")
        cp = configparser.RawConfigParser()
        cp.read(str(GTK3_SETTINGS), encoding="utf-8")
        self.assertTrue(cp.has_section("Settings"))
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-name"), "Adwaita")
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-size"), "24")
        self.assertEqual(cp.get("Settings", "gtk-application-prefer-dark-theme"), "1")

    def test_gtk4_dotfile_exists_and_valid(self):
        self.assertTrue(GTK4_SETTINGS.is_file(), f"{GTK4_SETTINGS} must exist")
        cp = configparser.RawConfigParser()
        cp.read(str(GTK4_SETTINGS), encoding="utf-8")
        self.assertTrue(cp.has_section("Settings"))
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-name"), "Adwaita")
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-size"), "24")


class CursorSetupUnitTests(unittest.TestCase):
    """Unit tests for cursor resolution, settings preservation, and atomic generation."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.config_dir = self.tmp_path / "config"
        self.icons_dir = self.tmp_path / "icons"
        self.config_dir.mkdir(parents=True)
        self.icons_dir.mkdir(parents=True)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_resolve_cursor_theme_with_available_theme(self):
        # Create a mock cursor theme
        mock_root = self.tmp_path / "share_icons"
        mock_theme = mock_root / "MyCursor" / "cursors"
        mock_theme.mkdir(parents=True)

        res = cursor_setup.resolve_cursor_theme("MyCursor", custom_roots=[mock_root])
        self.assertEqual(res, "MyCursor")

    def test_resolve_cursor_theme_fallback_on_missing(self):
        mock_root = self.tmp_path / "share_icons"
        mock_adwaita = mock_root / "Adwaita" / "cursors"
        mock_adwaita.mkdir(parents=True)

        # Nonexistent theme requested -> falls back to Adwaita
        res = cursor_setup.resolve_cursor_theme("NonExistentTheme", custom_roots=[mock_root])
        self.assertEqual(res, "Adwaita")

    def test_update_gtk_settings_preserves_existing_keys(self):
        gtk3_file = self.config_dir / "gtk-3.0" / "settings.ini"
        gtk3_file.parent.mkdir(parents=True)
        gtk3_file.write_text(
            "[Settings]\n"
            "gtk-font-name = Plus Jakarta Sans 11\n"
            "gtk-icon-theme-name = CustomIcons\n"
            "custom-user-key = user_value\n",
            encoding="utf-8",
        )

        changed = cursor_setup.update_gtk_settings_ini(
            gtk3_file,
            theme_name="Adwaita",
            size=24,
            dry_run=False,
        )
        self.assertTrue(changed)

        cp = configparser.RawConfigParser()
        cp.read(str(gtk3_file), encoding="utf-8")
        # Existing custom keys preserved
        self.assertEqual(cp.get("Settings", "gtk-font-name"), "Plus Jakarta Sans 11")
        self.assertEqual(cp.get("Settings", "gtk-icon-theme-name"), "CustomIcons")
        self.assertEqual(cp.get("Settings", "custom-user-key"), "user_value")
        # Cursor settings applied
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-name"), "Adwaita")
        self.assertEqual(cp.get("Settings", "gtk-cursor-theme-size"), "24")

    def test_update_gtk_settings_idempotent(self):
        gtk3_file = self.config_dir / "gtk-3.0" / "settings.ini"
        cursor_setup.update_gtk_settings_ini(gtk3_file, theme_name="Adwaita", size=24, dry_run=False)
        # Second call with same parameters should return False (no change)
        changed = cursor_setup.update_gtk_settings_ini(gtk3_file, theme_name="Adwaita", size=24, dry_run=False)
        self.assertFalse(changed)

    def test_update_xwayland_default_theme_creates_valid_index(self):
        default_dir = self.icons_dir / "default"
        changed = cursor_setup.update_xwayland_default_theme(default_dir, "Adwaita", dry_run=False)
        self.assertTrue(changed)

        index_file = default_dir / "index.theme"
        self.assertTrue(index_file.is_file())
        content = index_file.read_text(encoding="utf-8")
        self.assertIn("[Icon Theme]", content)
        self.assertIn("Inherits=Adwaita", content)

    def test_setup_cursor_dry_run_does_not_modify_disk(self):
        res = cursor_setup.setup_cursor(
            theme="Adwaita",
            size=24,
            config_dir=self.config_dir,
            icons_dir=self.icons_dir,
            dry_run=True,
            apply_live=False,
        )
        self.assertTrue(res["ok"])
        # No files should have been created
        self.assertFalse((self.config_dir / "gtk-3.0" / "settings.ini").exists())
        self.assertFalse((self.icons_dir / "default" / "index.theme").exists())

    def test_setup_cursor_end_to_end(self):
        res = cursor_setup.setup_cursor(
            theme="Adwaita",
            size=24,
            config_dir=self.config_dir,
            icons_dir=self.icons_dir,
            dry_run=False,
            apply_live=False,
        )
        self.assertTrue(res["ok"])
        self.assertEqual(res["resolved_theme"], "Adwaita")
        self.assertEqual(res["size"], 24)
        self.assertTrue((self.config_dir / "gtk-3.0" / "settings.ini").is_file())
        self.assertTrue((self.config_dir / "gtk-4.0" / "settings.ini").is_file())
        self.assertTrue((self.icons_dir / "default" / "index.theme").is_file())


if __name__ == "__main__":
    unittest.main()
