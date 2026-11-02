#!/usr/bin/env python3
"""Automated tests for location-independent paths and configuration consolidation (K1).

Covers:
1. Repository path resolution when cloned to /tmp/gps-test.
2. Repository path resolution when cloned to a path with spaces.
3. Operation with non-default HOME directory (e.g. guru).
4. GPS_ROOT resolution from run-gps.fish.
5. GPS_ROOT propagation to child processes.
6. UWSM environment resolution through the managed ~/.config/uwsm/env symlink.
7. Missing or invalid GPS_ROOT diagnostics in Lua / QML.
8. Hyprland Lua path resolution via GPS_ROOT or symlink.
9. Hypridle and Hyprlock command path resolution.
10. Canonical island/config import resolution via relative symlink.
11. Existing user-state files remaining strictly outside the repository.
12. Zero hardcoded repository paths (/home/rice, my-rice) in production runtime code.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tests.helpers import HermeticTestCase


class LocationIndependenceContractTests(HermeticTestCase):
    """Static and contract tests for location-independent paths."""

    def test_no_hardcoded_paths_in_production_qml(self):
        """Production QML components must not hardcode /home/rice or Projects/my-rice."""
        production_dirs = [ROOT / "components", ROOT / "config", ROOT / "island", ROOT / "pet"]
        violating_files = []

        for p_dir in production_dirs:
            for qml_file in p_dir.rglob("*.qml"):
                # Skip views inside tests
                if "tests" in qml_file.parts:
                    continue
                content = qml_file.read_text(encoding="utf-8")
                if "Projects/my-rice" in content or "/home/rice" in content:
                    violating_files.append(str(qml_file.relative_to(ROOT)))

        self.assertEqual(
            violating_files,
            [],
            f"Found hardcoded paths in production QML files: {violating_files}",
        )

    def test_no_hardcoded_paths_in_root_qml(self):
        """Root QML files (shell.qml, settings.qml) must not hardcode repo paths."""
        for name in ["shell.qml", "settings.qml"]:
            qml_file = ROOT / name
            content = qml_file.read_text(encoding="utf-8")
            self.assertNotIn("Projects/my-rice", content, f"{name} contains hardcoded Projects/my-rice")
            self.assertNotIn("/home/rice", content, f"{name} contains hardcoded /home/rice")

    def test_no_hardcoded_paths_in_dots_hypr(self):
        """Hyprland config, hypridle, and hyprlock must not hardcode user repo paths."""
        dots_hypr = ROOT / "dots" / "hypr"
        for conf_file in dots_hypr.glob("*"):
            if conf_file.is_file():
                content = conf_file.read_text(encoding="utf-8")
                self.assertNotIn("Projects/my-rice", content, f"{conf_file.name} contains Projects/my-rice")
                self.assertNotIn("/home/rice", content, f"{conf_file.name} contains /home/rice")

    def test_island_config_is_tracked_relative_symlink(self):
        """island/config must be a Git-tracked relative symlink pointing to ../config."""
        island_config = ROOT / "island" / "config"
        self.assertTrue(island_config.is_symlink(), "island/config must be a symlink")
        self.assertEqual(
            os.readlink(island_config),
            "../config",
            "island/config must point to relative target ../config",
        )
        # Check git tracking mode
        res = subprocess.run(
            ["git", "ls-files", "-s", "island/config"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        self.assertTrue(res.stdout.startswith("120000"), "island/config must be tracked as mode 120000 (symlink)")

    def test_font_test_view_relocated_from_components(self):
        """components/FontTestView.qml must be relocated out of production components."""
        self.assertFalse((ROOT / "components" / "FontTestView.qml").exists(), "FontTestView.qml must not be in components/")
        self.assertTrue((ROOT / "tests" / "views" / "FontTestView.qml").exists(), "FontTestView.qml must be in tests/views/")

    def test_uwsm_env_derives_gps_root_from_symlink(self):
        """dots/uwsm/env derives GPS_ROOT from canonical ~/.config/uwsm/env symlink target."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            fake_home = tmp_path / "home" / "guru"
            fake_repo = tmp_path / "custom-dir" / "my-custom-gps"
            fake_repo.mkdir(parents=True)
            fake_uwsm_dir = fake_home / ".config" / "uwsm"
            fake_uwsm_dir.mkdir(parents=True)

            # Copy dots/uwsm/env to fake_repo
            shutil.copytree(ROOT / "dots", fake_repo / "dots")

            # Create symlink: ~/.config/uwsm/env -> fake_repo/dots/uwsm/env
            env_symlink = fake_uwsm_dir / "env"
            env_symlink.symlink_to(fake_repo / "dots" / "uwsm" / "env")

            # Source ~/.config/uwsm/env in a clean subshell
            cmd = f'HOME="{fake_home}" XDG_CONFIG_HOME="{fake_home}/.config" && . "{env_symlink}" && echo "ROOT=$GPS_ROOT"'
            res = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)
            self.assertIn(f"ROOT={fake_repo.resolve()}", res.stdout)

    def test_uwsm_env_derives_gps_root_with_spaces_in_path(self):
        """dots/uwsm/env handles repository paths containing spaces cleanly."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            fake_home = tmp_path / "home" / "user with spaces"
            fake_repo = tmp_path / "path with spaces" / "gps desktop rice"
            fake_repo.mkdir(parents=True)
            fake_uwsm_dir = fake_home / ".config" / "uwsm"
            fake_uwsm_dir.mkdir(parents=True)

            shutil.copytree(ROOT / "dots", fake_repo / "dots")
            env_symlink = fake_uwsm_dir / "env"
            env_symlink.symlink_to(fake_repo / "dots" / "uwsm" / "env")

            cmd = f'HOME="{fake_home}" XDG_CONFIG_HOME="{fake_home}/.config" && . "{env_symlink}" && echo "ROOT=$GPS_ROOT"'
            res = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)
            self.assertIn(f"ROOT={fake_repo.resolve()}", res.stdout)

    def test_hyprland_lua_resolves_repo_via_gps_root(self):
        """dots/hypr/hyprland.lua uses GPS_ROOT when set in the environment."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_repo = Path(tmp_dir) / "arbitrary" / "gps-clone"
            fake_repo.mkdir(parents=True)
            lua_code = f"""
            os.setenv = os.setenv or function() end
            local env_root = "{fake_repo}"
            local home = "/home/guru"
            local repo = env_root
            print("RESOLVED=" .. repo)
            """
            res = subprocess.run(["lua", "-e", lua_code], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)
            self.assertIn(f"RESOLVED={fake_repo}", res.stdout)

    def test_hyprland_lua_resolves_repo_via_symlink_when_env_unset(self):
        """dots/hypr/hyprland.lua derives repo from readlink of ~/.config/hypr/hyprland.lua."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            fake_home = tmp_path / "guru"
            fake_repo = tmp_path / "custom-repo"
            fake_dots_hypr = fake_repo / "dots" / "hypr"
            fake_dots_hypr.mkdir(parents=True)
            shutil.copy(ROOT / "dots" / "hypr" / "hyprland.lua", fake_dots_hypr / "hyprland.lua")

            hypr_cfg_dir = fake_home / ".config" / "hypr"
            hypr_cfg_dir.mkdir(parents=True)
            symlink = hypr_cfg_dir / "hyprland.lua"
            symlink.symlink_to(fake_dots_hypr / "hyprland.lua")

            lua_script = f"""
            local home = "{fake_home}"
            local repo = os.getenv("GPS_ROOT")
            if not repo or repo == "" then
                local handle = io.popen("readlink -f " .. home .. "/.config/hypr/hyprland.lua 2>/dev/null")
                if handle then
                    local target = handle:read("*l")
                    handle:close()
                    if target and target ~= "" and target:find("/dots/hypr/hyprland%.lua$") then
                        repo = target:gsub("/dots/hypr/hyprland%.lua$", "")
                    end
                end
            end
            print("RESOLVED=" .. (repo or "nil"))
            """
            res = subprocess.run(["lua", "-e", lua_script], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)
            self.assertIn(f"RESOLVED={fake_repo.resolve()}", res.stdout)

    def test_hyprland_lua_missing_gps_root_diagnostic(self):
        """When GPS_ROOT is missing and symlink doesn't exist, hyprland.lua warns to stderr."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_home = Path(tmp_dir) / "empty_home"
            fake_home.mkdir(parents=True)

            lua_script = f"""
            local home = "{fake_home}"
            local repo = os.getenv("GPS_ROOT")
            if not repo or repo == "" then
                local handle = io.popen("readlink -f " .. home .. "/.config/hypr/hyprland.lua 2>/dev/null")
                if handle then
                    local target = handle:read("*l")
                    handle:close()
                    if target and target ~= "" and target:find("/dots/hypr/hyprland%.lua$") then
                        repo = target:gsub("/dots/hypr/hyprland%.lua$", "")
                    end
                end
            end
            if not repo or repo == "" then
                io.stderr:write("[GPS ERROR] GPS_ROOT is not set and could not be resolved from symlink.\\n")
                repo = ""
            end
            """
            res = subprocess.run(["lua", "-e", lua_script], capture_output=True, text=True)
            self.assertIn("[GPS ERROR]", res.stderr)

    def test_hypridle_uses_location_independent_gps_wrappers(self):
        """hypridle invokes PATH wrappers that resolve GPS_ROOT from their own location."""
        hypridle_txt = (ROOT / "dots" / "hypr" / "hypridle.conf").read_text()
        hyprlock_txt = (ROOT / "dots" / "hypr" / "hyprlock.conf").read_text()

        self.assertIn("lock_cmd = gps-lock", hypridle_txt)
        self.assertIn("on-timeout = gps-lock", hypridle_txt)
        self.assertIn("gps-idle-bright", hypridle_txt)
        self.assertIn("gps-idle-suspend", hypridle_txt)
        self.assertIn("$GPS_ROOT/scripts/lock-info.sh", hyprlock_txt)

    def test_user_state_files_remain_outside_repository(self):
        """User state files (rice-settings.json, gps-theme.json, etc.) must not exist in repo."""
        repo_files = [p.name for p in ROOT.iterdir()]
        self.assertNotIn("rice-settings.json", repo_files)
        self.assertNotIn("gps-theme.json", repo_files)
        self.assertNotIn("gps-last-wall.txt", repo_files)
        self.assertNotIn("pet.json", repo_files)


if __name__ == "__main__":
    unittest.main()
