#!/usr/bin/env python3
"""Contracts for the opt-in Caelestia-compatible Hyprland integration."""

from __future__ import annotations

import os
from contextlib import redirect_stdout
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys_path = str(ROOT)
import sys

if sys_path not in sys.path:
    sys.path.insert(0, sys_path)

from scripts.installer import GpsInstaller


class CaelestiaIntegrationTests(unittest.TestCase):
    def test_active_hyprland_roots_are_not_installer_targets_or_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="gps-caelestia-test-") as temp:
            home = Path(temp) / "home"
            home.mkdir()
            config = home / ".config"
            hypr = config / "hypr"
            hypr.mkdir(parents=True)
            root_config = hypr / "hyprland.lua"
            idle_config = hypr / "hypridle.conf"
            root_config.write_text("-- Caelestia active root\n", encoding="utf-8")
            idle_config.write_text("# Caelestia idle policy\n", encoding="utf-8")

            installer = GpsInstaller(
                repo_root=ROOT,
                home_dir=home,
                config_dir=config,
                state_dir=home / ".local/state",
                data_dir=home / ".local/share",
                bin_dir=home / ".local/bin",
                skip_deps=True,
                no_color=True,
            )
            managed_destinations = {entry["dest"] for entry in installer.manifest.get_entries()}
            self.assertNotIn(root_config, managed_destinations)
            self.assertNotIn(idle_config, managed_destinations)

            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/installer.py"), "--apply", "--home", str(home), "--no-color", "--skip-deps"],
                cwd=ROOT,
                env={**os.environ, "HOME": str(home), "GPS_ROOT": str(ROOT)},
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(root_config.is_symlink())
            self.assertFalse(idle_config.is_symlink())
            self.assertEqual(root_config.read_text(encoding="utf-8"), "-- Caelestia active root\n")
            self.assertEqual(idle_config.read_text(encoding="utf-8"), "# Caelestia idle policy\n")

    def test_hypr_namespace_conflicts_are_reported_and_preserved(self):
        with tempfile.TemporaryDirectory(prefix="gps-hypr-conflict-test-") as temp:
            home = Path(temp) / "home"
            home.mkdir()
            config = home / ".config"
            target = config / "hypr/gps/integration.lua"
            target.parent.mkdir(parents=True)
            target.write_text("-- user-owned integration\n", encoding="utf-8")
            installer = GpsInstaller(
                repo_root=ROOT,
                home_dir=home,
                config_dir=config,
                state_dir=home / ".local/state",
                data_dir=home / ".local/share",
                bin_dir=home / ".local/bin",
                skip_deps=True,
                no_color=True,
            )

            dry_run_output = io.StringIO()
            with redirect_stdout(dry_run_output):
                result = installer.dry_run()
            self.assertEqual(result, 0)
            self.assertIn("[CONFLICT: PRESERVED]", dry_run_output.getvalue())
            inspection = next(row for row in (installer.inspect_destination(e) for e in installer.manifest.get_entries()) if row["entry"]["id"] == "gps_hypr_integration")
            self.assertEqual(inspection["action"], "preserve")
            self.assertTrue(inspection["is_conflict"])
            self.assertEqual(target.read_text(encoding="utf-8"), "-- user-owned integration\n")

            first_apply_output = io.StringIO()
            with redirect_stdout(first_apply_output):
                self.assertEqual(installer.apply(), 0)
            self.assertIn("Conflict detected; preserved:", first_apply_output.getvalue())

            repeat_output = io.StringIO()
            with redirect_stdout(repeat_output):
                self.assertEqual(installer.apply(), 0)
            self.assertIn("Conflict detected; preserved without overwriting:", repeat_output.getvalue())
            self.assertEqual(target.read_text(encoding="utf-8"), "-- user-owned integration\n")

    def test_integration_replaces_conflicting_keys_with_gps_shortcuts(self):
        module = (ROOT / "dots/hypr/gps/integration.lua").read_text(encoding="utf-8")
        self.assertEqual(module.count("hl.bind("), 1)
        self.assertIn('"SUPER + SPACE"', module)
        self.assertIn('"SUPER + R"', module)
        self.assertIn('"SUPER + SHIFT + V"', module)
        self.assertIn('"SUPER + D"', module)
        self.assertIn('"SUPER + N"', module)
        self.assertIn('"SUPER + L"', module)  # unbind Caelestia's unverified lock binding
        self.assertIn('"SUPER + L", hl.dsp.exec_cmd', module)  # rebind to verified GPS lock wrapper
        self.assertIn("hl.unbind(key)", module)
        self.assertIn('"SUPER + W"', module)
        self.assertIn('"SUPER + Q"', module)
        self.assertIn('"SUPER + V"', module)
        self.assertIn('"SUPER + comma"', module)
        self.assertIn('"SUPER + Z"', module)
        self.assertIn('"SUPER + ALT + C"', module)
        for conflicting_key in (
            "SUPER + M",
            "SUPER + S", "SUPER + SHIFT + S", "XF86MonBrightnessUp",
            "XF86MonBrightnessDown", "XF86AudioNext", "XF86AudioPause",
        ):
            self.assertNotIn(f'"{conflicting_key}"', module)
        self.assertNotIn('hl.on(', module)
        self.assertIn('"shell dashboard toggle"', module)
        self.assertIn('"shell notifcenter toggle"', module)

        active_root = (ROOT / "dots/hypr/hyprland.lua").read_text(encoding="utf-8")
        self.assertNotIn('require("gps.integration")', active_root)
        self.assertNotIn('require("gps.startup")', active_root)

    def test_startup_hook_requires_explicit_enable_and_guards_notification_owner(self):
        startup = (ROOT / "dots/hypr/gps/startup.lua").read_text(encoding="utf-8")
        self.assertIn("function M.enable()", startup)
        executable_lines = "\n".join(line for line in startup.splitlines() if not line.lstrip().startswith("--"))
        self.assertNotRegex(executable_lines, r"(?m)^\s*M\.enable\(\)\s*$")
        self.assertIn("gps-start-safe", startup)
        guard = (ROOT / "scripts/gps-start-safe").read_text(encoding="utf-8")
        self.assertIn("GetNameOwner", guard)
        self.assertIn("IslandProduction.qml", guard)


if __name__ == "__main__":
    unittest.main()
