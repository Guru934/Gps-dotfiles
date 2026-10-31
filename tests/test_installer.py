#!/usr/bin/env python3
"""Comprehensive hermetic tests for GPS Safe, Idempotent User-Space Installer (K3).

Tests all 25 safety, idempotency, backup, and recovery requirements:
 1. Default dry-run changes zero files.
 2. Dry-run reports all planned symlinks.
 3. Apply creates the expected symlinks.
 4. Apply creates missing templates only.
 5. Apply never overwrites existing rice-settings.json.
 6. Apply never overwrites user state.
 7. Second apply is idempotent.
 8. Conflicting files are backed up.
 9. Original symlinks are restored on uninstall.
10. Original regular files are restored on uninstall.
11. Original directories and their contents are restored.
12. Original permissions and attributes are preserved.
13. User changes after installation cause uninstall conflict detection.
14. Unrelated user files are preserved.
15. A conflicting UWSM environment is preserved.
16. GPS_ROOT works with arbitrary clone paths.
17. GPS_ROOT works with paths containing spaces.
18. Installation does not require sudo.
19. Installation never changes system directories.
20. Failed apply restores changes made by its own transaction.
21. Incomplete or corrupt backup refuses restoration.
22. Repeated uninstall is safe.
23. Existing backups are never overwritten.
24. XDG directory overrides work correctly.
25. Malicious paths and symlink traversal are rejected.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
INSTALL_SH = REPO_ROOT / "install.sh"
INSTALLER_PY = REPO_ROOT / "scripts" / "installer.py"


class InstallerTestBase(unittest.TestCase):
    """Hermetic test harness providing isolated temporary HOME and XDG trees."""

    def setUp(self):
        self.tmp_dir_obj = tempfile.TemporaryDirectory(prefix="gps_inst_test_")
        self.test_root = Path(self.tmp_dir_obj.name)
        self.fake_home = self.test_root / "fake_home"
        self.fake_home.mkdir(parents=True)

        self.fake_config = self.fake_home / ".config"
        self.fake_state = self.fake_home / ".local" / "state"
        self.fake_data = self.fake_home / ".local" / "share"
        self.fake_bin = self.fake_home / ".local" / "bin"

        self.env = os.environ.copy()
        self.env["HOME"] = str(self.fake_home)
        self.env["XDG_CONFIG_HOME"] = str(self.fake_config)
        self.env["XDG_STATE_HOME"] = str(self.fake_state)
        self.env["XDG_DATA_HOME"] = str(self.fake_data)
        self.env["GPS_ROOT"] = str(REPO_ROOT)
        self.env["GPS_SKIP_DEPS"] = "1"

    def tearDown(self):
        self.tmp_dir_obj.cleanup()

    def run_cmd(self, args: list[str], repo: Path = REPO_ROOT, env_override: dict | None = None) -> subprocess.CompletedProcess:
        """Run install.sh within hermetic environment."""
        env = self.env.copy()
        if env_override:
            env.update(env_override)

        cmd = [str(repo / "install.sh"), "--home", str(self.fake_home), "--no-color"] + args
        return subprocess.run(
            cmd,
            cwd=str(repo),
            capture_output=True,
            text=True,
            env=env,
        )


class TestGpsInstaller(InstallerTestBase):

    def test_01_default_dry_run_changes_zero_files(self):
        """1. Default dry-run changes zero files."""
        # Ensure home has no files initially
        initial_files = list(self.fake_home.rglob("*"))
        self.assertEqual(initial_files, [])

        res = self.run_cmd([])
        self.assertEqual(res.returncode, 0, f"Dry-run failed: {res.stderr}")
        self.assertIn("[DRY-RUN]", res.stdout)
        self.assertIn("ZERO changes made", res.stdout)

        # Confirm still 0 files in fake_home
        after_files = list(self.fake_home.rglob("*"))
        self.assertEqual(after_files, [])

    def test_02_dry_run_reports_all_planned_symlinks(self):
        """2. Dry-run reports all planned symlinks."""
        res = self.run_cmd(["--dry-run"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("dots/hypr/hyprland.lua", res.stdout)
        self.assertIn("dots/hypr/hypridle.conf", res.stdout)
        self.assertIn("dots/hypr/hyprlock.conf", res.stdout)
        self.assertIn("dots/hypr/lock-bg.conf", res.stdout)
        self.assertIn("dots/hypr/lock-colors.conf", res.stdout)
        self.assertIn("dots/rofi/config.rasi", res.stdout)
        self.assertIn("dots/awatcher/config.toml", res.stdout)
        self.assertIn("dots/awatcher/bundle-config.toml", res.stdout)
        self.assertIn("dots/fontconfig/fonts.conf", res.stdout)
        self.assertIn("dots/gtk-3.0/settings.ini", res.stdout)
        self.assertIn("dots/gtk-4.0/settings.ini", res.stdout)
        self.assertIn("dots/uwsm/env", res.stdout)
        self.assertIn("scripts/gps-ipc", res.stdout)
        self.assertIn("scripts/gps-lock", res.stdout)
        self.assertIn("scripts/gps-idle", res.stdout)
        self.assertIn("scripts/gps-sound", res.stdout)
        self.assertIn("scripts/pet-alert", res.stdout)
        self.assertIn("scripts/gps-gamemode", res.stdout)
        self.assertIn("templates/rice-settings.json", res.stdout)

    def test_03_apply_creates_the_expected_symlinks(self):
        """3. Apply creates the expected symlinks."""
        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0, f"Apply failed: {res.stderr}")

        # Check Hyprland symlinks
        hyprland_link = self.fake_config / "hypr" / "hyprland.lua"
        self.assertTrue(hyprland_link.is_symlink())
        self.assertEqual(hyprland_link.resolve(), (REPO_ROOT / "dots" / "hypr" / "hyprland.lua").resolve())

        hypridle_link = self.fake_config / "hypr" / "hypridle.conf"
        self.assertTrue(hypridle_link.is_symlink())

        hyprlock_link = self.fake_config / "hypr" / "hyprlock.conf"
        self.assertTrue(hyprlock_link.is_symlink())

        # Check binary symlinks
        gps_ipc = self.fake_bin / "gps-ipc"
        self.assertTrue(gps_ipc.is_symlink())
        self.assertEqual(gps_ipc.resolve(), (REPO_ROOT / "scripts" / "gps-ipc").resolve())

        gps_lock = self.fake_bin / "gps-lock"
        self.assertTrue(gps_lock.is_symlink())

        gps_idle = self.fake_bin / "gps-idle"
        self.assertTrue(gps_idle.is_symlink())

    def test_04_apply_creates_missing_templates_only(self):
        """4. Apply creates missing templates only."""
        settings_target = self.fake_config / "quickshell" / "rice-settings.json"
        self.assertFalse(settings_target.exists())

        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0)
        self.assertTrue(settings_target.is_file())
        self.assertFalse(settings_target.is_symlink())

        # Verify it matches template schema and contains neutral values
        data = json.loads(settings_target.read_text(encoding="utf-8"))
        self.assertIn("hypr", data)
        self.assertIn("ai", data)
        self.assertEqual(data["music"]["jamendoClientId"], "")

    def test_05_apply_never_overwrites_existing_rice_settings(self):
        """5. Apply never overwrites existing rice-settings.json."""
        settings_target = self.fake_config / "quickshell" / "rice-settings.json"
        settings_target.parent.mkdir(parents=True, exist_ok=True)
        custom_content = json.dumps({"custom_user_setting": "do_not_overwrite_12345"})
        settings_target.write_text(custom_content, encoding="utf-8")

        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(settings_target.read_text(encoding="utf-8"), custom_content)

    def test_06_apply_never_overwrites_user_state(self):
        """6. Apply never overwrites user state."""
        quickshell_dir = self.fake_config / "quickshell"
        quickshell_dir.mkdir(parents=True, exist_ok=True)

        pet_state = quickshell_dir / "pet.json"
        pet_state.write_text('{"hunger": 100, "affection": 80}', encoding="utf-8")

        wall_state = quickshell_dir / "gps-last-wall.txt"
        wall_state.write_text("/home/user/my_fav_wallpaper.png", encoding="utf-8")

        theme_state = quickshell_dir / "gps-theme.json"
        theme_state.write_text('{"surface": "#123456"}', encoding="utf-8")

        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0)

        # Verify all user state files remain completely untouched
        self.assertEqual(pet_state.read_text(encoding="utf-8"), '{"hunger": 100, "affection": 80}')
        self.assertEqual(wall_state.read_text(encoding="utf-8"), "/home/user/my_fav_wallpaper.png")
        self.assertEqual(theme_state.read_text(encoding="utf-8"), '{"surface": "#123456"}')

    def test_07_second_apply_is_idempotent(self):
        """7. Second apply is idempotent."""
        # First apply
        res1 = self.run_cmd(["--apply"])
        self.assertEqual(res1.returncode, 0)

        # Record timestamp/count of backups
        backup_dir = self.fake_state / "gps" / "backups"
        initial_backups = list(backup_dir.iterdir()) if backup_dir.exists() else []

        # Second apply
        res2 = self.run_cmd(["--apply"])
        self.assertEqual(res2.returncode, 0)
        self.assertIn("already fully up to date", res2.stdout)
        self.assertIn("0 backups created", res2.stdout)

        after_backups = list(backup_dir.iterdir()) if backup_dir.exists() else []
        self.assertEqual(len(initial_backups), len(after_backups))

    def test_08_conflicting_files_are_backed_up(self):
        """8. Conflicting files are backed up."""
        rofi_cfg = self.fake_config / "rofi" / "config.rasi"
        rofi_cfg.parent.mkdir(parents=True, exist_ok=True)
        original_content = "/* user custom rofi config */\n"
        rofi_cfg.write_text(original_content, encoding="utf-8")

        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0)

        # rofi_cfg must now be GPS symlink
        self.assertTrue(rofi_cfg.is_symlink())
        self.assertEqual(rofi_cfg.resolve(), (REPO_ROOT / "dots" / "rofi" / "config.rasi").resolve())

        # Backup archive must contain original
        backup_dir = self.fake_state / "gps" / "backups"
        self.assertTrue(backup_dir.is_dir())
        latest_backup = sorted(list(backup_dir.iterdir()))[-1]
        backed_up_file = latest_backup / "files" / "config" / "config.rasi"
        self.assertTrue(backed_up_file.is_file())
        self.assertEqual(backed_up_file.read_text(encoding="utf-8"), original_content)

    def test_09_original_symlinks_are_restored_on_uninstall(self):
        """9. Original symlinks are restored on uninstall."""
        hypr_cfg = self.fake_config / "hypr" / "hypridle.conf"
        hypr_cfg.parent.mkdir(parents=True, exist_ok=True)

        other_target = self.test_root / "other_hypridle.conf"
        other_target.write_text("# other idle config", encoding="utf-8")
        hypr_cfg.symlink_to(other_target)

        # Apply backs up existing symlink and replaces with GPS
        self.run_cmd(["--apply"])
        self.assertEqual(hypr_cfg.resolve(), (REPO_ROOT / "dots" / "hypr" / "hypridle.conf").resolve())

        # Uninstall restores original symlink
        res = self.run_cmd(["--uninstall"])
        self.assertEqual(res.returncode, 0)
        self.assertTrue(hypr_cfg.is_symlink())
        self.assertEqual(os.readlink(hypr_cfg), str(other_target))

    def test_10_original_regular_files_are_restored_on_uninstall(self):
        """10. Original regular files are restored on uninstall."""
        lock_cfg = self.fake_config / "hypr" / "hyprlock.conf"
        lock_cfg.parent.mkdir(parents=True, exist_ok=True)
        orig_text = "# Original hyprlock before GPS\n"
        lock_cfg.write_text(orig_text, encoding="utf-8")

        self.run_cmd(["--apply"])
        self.assertTrue(lock_cfg.is_symlink())

        self.run_cmd(["--uninstall"])
        self.assertFalse(lock_cfg.is_symlink())
        self.assertTrue(lock_cfg.is_file())
        self.assertEqual(lock_cfg.read_text(encoding="utf-8"), orig_text)

    def test_11_original_directories_and_their_contents_are_restored(self):
        """11. Original directories and their contents are restored."""
        # Pretend user had a directory where a binary was supposed to be
        dummy_dir = self.fake_bin / "gps-ipc"
        dummy_dir.mkdir(parents=True, exist_ok=True)
        (dummy_dir / "internal.txt").write_text("hello directory", encoding="utf-8")

        self.run_cmd(["--apply"])
        self.assertTrue(dummy_dir.is_symlink())

        self.run_cmd(["--uninstall"])
        self.assertFalse(dummy_dir.is_symlink())
        self.assertTrue(dummy_dir.is_dir())
        self.assertTrue((dummy_dir / "internal.txt").is_file())
        self.assertEqual((dummy_dir / "internal.txt").read_text(encoding="utf-8"), "hello directory")

    def test_12_original_permissions_and_attributes_are_preserved(self):
        """12. Original permissions and attributes are preserved."""
        gtk_cfg = self.fake_config / "gtk-3.0" / "settings.ini"
        gtk_cfg.parent.mkdir(parents=True, exist_ok=True)
        gtk_cfg.write_text("[Settings]\ncustom=1\n", encoding="utf-8")
        # Set distinct non-default permissions: read-only by user (0400)
        gtk_cfg.chmod(0o400)

        self.run_cmd(["--apply"])
        self.run_cmd(["--uninstall"])

        self.assertTrue(gtk_cfg.is_file())
        file_mode = stat.S_IMODE(gtk_cfg.stat().st_mode)
        self.assertEqual(file_mode, 0o400)

    def test_13_user_changes_after_installation_cause_uninstall_conflict_detection(self):
        """13. User changes after installation cause uninstall conflict detection."""
        self.run_cmd(["--apply"])

        # User modifies hyprland.lua after GPS installation (replaces symlink with file)
        hypr_lua = self.fake_config / "hypr" / "hyprland.lua"
        self.assertTrue(hypr_lua.is_symlink())
        hypr_lua.unlink()
        hypr_lua.write_text("-- user custom edit after GPS installed\n", encoding="utf-8")

        res = self.run_cmd(["--uninstall"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("conflict", res.stdout.lower())

        # Verify user edit was preserved and NOT deleted
        self.assertTrue(hypr_lua.is_file())
        self.assertIn("user custom edit after GPS installed", hypr_lua.read_text(encoding="utf-8"))

    def test_14_unrelated_user_files_are_preserved(self):
        """14. Unrelated user files are preserved."""
        hypr_dir = self.fake_config / "hypr"
        hypr_dir.mkdir(parents=True, exist_ok=True)
        caelestia_conf = hypr_dir / "caelestia.conf"
        caelestia_conf.write_text("# Caelestia config\n", encoding="utf-8")

        self.run_cmd(["--apply"])
        self.assertTrue(caelestia_conf.is_file())

        self.run_cmd(["--uninstall"])
        self.assertTrue(caelestia_conf.is_file())
        self.assertEqual(caelestia_conf.read_text(encoding="utf-8"), "# Caelestia config\n")

    def test_15_a_conflicting_uwsm_environment_is_preserved(self):
        """15. A conflicting UWSM environment is preserved."""
        uwsm_env = self.fake_config / "uwsm" / "env"
        uwsm_env.parent.mkdir(parents=True, exist_ok=True)
        custom_env = "export CUSTOM_UWSM_VAR=123\n"
        uwsm_env.write_text(custom_env, encoding="utf-8")

        res = self.run_cmd(["--apply"])
        self.assertEqual(res.returncode, 0)

        # UWSM must be preserved without overwriting
        self.assertFalse(uwsm_env.is_symlink())
        self.assertEqual(uwsm_env.read_text(encoding="utf-8"), custom_env)

    def test_16_gps_root_works_with_arbitrary_clone_paths(self):
        """16. GPS_ROOT works with arbitrary clone paths."""
        alt_repo = self.test_root / "arbitrary_clone"
        alt_repo.mkdir()
        shutil.copytree(REPO_ROOT / "dots", alt_repo / "dots", symlinks=True)
        shutil.copytree(REPO_ROOT / "scripts", alt_repo / "scripts", symlinks=True)
        shutil.copytree(REPO_ROOT / "templates", alt_repo / "templates", symlinks=True)
        shutil.copy2(REPO_ROOT / "install.sh", alt_repo / "install.sh")

        res = self.run_cmd(["--apply"], repo=alt_repo)
        self.assertEqual(res.returncode, 0)

        # Symlink must point to alt_repo
        hypr_link = self.fake_config / "hypr" / "hyprland.lua"
        self.assertEqual(hypr_link.resolve(), (alt_repo / "dots" / "hypr" / "hyprland.lua").resolve())

    def test_17_gps_root_works_with_paths_containing_spaces(self):
        """17. GPS_ROOT works with paths containing spaces."""
        space_repo = self.test_root / "repo with spaces in name"
        space_repo.mkdir()
        shutil.copytree(REPO_ROOT / "dots", space_repo / "dots", symlinks=True)
        shutil.copytree(REPO_ROOT / "scripts", space_repo / "scripts", symlinks=True)
        shutil.copytree(REPO_ROOT / "templates", space_repo / "templates", symlinks=True)
        shutil.copy2(REPO_ROOT / "install.sh", space_repo / "install.sh")

        space_home = self.test_root / "home with spaces"
        space_home.mkdir(parents=True)

        cmd = [str(space_repo / "install.sh"), "--home", str(space_home), "--apply", "--no-color"]
        res = subprocess.run(cmd, cwd=str(space_repo), capture_output=True, text=True, env=self.env)
        self.assertEqual(res.returncode, 0, f"Error: {res.stderr}")

        installed_link = space_home / ".config" / "hypr" / "hyprland.lua"
        self.assertTrue(installed_link.is_symlink())
        self.assertEqual(installed_link.resolve(), (space_repo / "dots" / "hypr" / "hyprland.lua").resolve())

    def test_18_installation_does_not_require_sudo(self):
        """18. Installation does not require sudo."""
        # Running normally succeeds without sudo
        res = self.run_cmd(["--dry-run"])
        self.assertEqual(res.returncode, 0)

        # Simulating execution as root (EUID=0) fails immediately with error
        env_root = self.env.copy()
        env_root["EUID"] = "0"
        res_root = subprocess.run(
            [str(REPO_ROOT / "install.sh"), "--home", str(self.fake_home)],
            capture_output=True,
            text=True,
            env=env_root,
        )
        self.assertNotEqual(res_root.returncode, 0)
        self.assertIn("must not be run as root", res_root.stderr)

    def test_19_installation_never_changes_system_directories(self):
        """19. Installation never changes system directories."""
        res = self.run_cmd(["--dry-run"])
        self.assertNotIn("/etc", res.stdout)
        self.assertNotIn("/usr", res.stdout)
        self.assertNotIn("/boot", res.stdout)
        self.assertNotIn("/var", res.stdout)

    def test_20_failed_apply_restores_changes_made_by_its_own_transaction(self):
        """20. Failed apply restores changes made by its own transaction."""
        from scripts.installer import GpsInstaller, TransactionError
        installer = GpsInstaller(
            repo_root=REPO_ROOT,
            home_dir=self.fake_home,
            config_dir=self.fake_config,
            state_dir=self.fake_state,
            bin_dir=self.fake_bin,
        )

        orig_file = self.fake_config / "hypr" / "hyprland.lua"
        orig_file.parent.mkdir(parents=True, exist_ok=True)
        orig_file.write_text("-- original lua\n", encoding="utf-8")

        # Mock an exception midway through apply
        entries = installer.manifest.get_entries()

        def faulty_inspect(e):
            return installer.inspect_destination(e)

        # Patch inspect_destination or trigger error during execution
        with mock.patch.object(os, "symlink", side_effect=[None, None, OSError("Simulated disk error")]):
            with self.assertRaises(TransactionError):
                installer.apply()

        # Check that original file was restored
        self.assertTrue(orig_file.is_file())
        self.assertEqual(orig_file.read_text(encoding="utf-8"), "-- original lua\n")

    def test_21_incomplete_or_corrupt_backup_refuses_restoration(self):
        """21. Incomplete or corrupt backup refuses restoration."""
        orig_file = self.fake_config / "rofi" / "config.rasi"
        orig_file.parent.mkdir(parents=True, exist_ok=True)
        orig_file.write_text("/* rofi */", encoding="utf-8")

        self.run_cmd(["--apply"])

        # Corrupt the backup by deleting the backed up file
        backup_dir = self.fake_state / "gps" / "backups"
        latest_backup = sorted(list(backup_dir.iterdir()))[-1]
        backed_up_file = latest_backup / "files" / "config" / "config.rasi"
        backed_up_file.unlink()

        res = self.run_cmd(["--uninstall"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Corrupt or incomplete backup archive", res.stderr)

    def test_22_repeated_uninstall_is_safe(self):
        """22. Repeated uninstall is safe."""
        self.run_cmd(["--apply"])

        # First uninstall
        res1 = self.run_cmd(["--uninstall"])
        self.assertEqual(res1.returncode, 0)

        # Second uninstall
        res2 = self.run_cmd(["--uninstall"])
        self.assertEqual(res2.returncode, 0)
        self.assertIn("uninstalled cleanly", res2.stdout)

    def test_23_existing_backups_are_never_overwritten(self):
        """23. Existing backups are never overwritten."""
        # Create a pre-existing dummy backup folder
        backup_root = self.fake_state / "gps" / "backups"
        backup_root.mkdir(parents=True, exist_ok=True)

        fixed_ts = "20261031_120000"
        dummy_backup = backup_root / fixed_ts
        dummy_backup.mkdir()
        canary = dummy_backup / "canary.txt"
        canary.write_text("do not overwrite me", encoding="utf-8")

        # Create conflicting file to trigger a backup
        rofi_cfg = self.fake_config / "rofi" / "config.rasi"
        rofi_cfg.parent.mkdir(parents=True, exist_ok=True)
        rofi_cfg.write_text("conflict", encoding="utf-8")

        # Run apply with mocked datetime matching fixed_ts using in-process installer
        from scripts.installer import GpsInstaller
        installer = GpsInstaller(
            repo_root=REPO_ROOT,
            home_dir=self.fake_home,
            config_dir=self.fake_config,
            state_dir=self.fake_state,
            bin_dir=self.fake_bin,
            skip_deps=True,
            no_color=True,
        )

        with mock.patch("scripts.installer.datetime") as mock_dt:
            mock_dt.now.return_value.strftime.return_value = fixed_ts
            mock_dt.now.return_value.isoformat.return_value = "2026-10-31T12:00:00"
            ret = installer.apply()
            self.assertEqual(ret, 0)

        # Canary must remain intact
        self.assertTrue(canary.is_file())
        self.assertEqual(canary.read_text(encoding="utf-8"), "do not overwrite me")

        # Colliding backup must have been created with suffix (e.g. 20261031_120000_1)
        numbered_backup = backup_root / f"{fixed_ts}_1"
        self.assertTrue(numbered_backup.is_dir())

    def test_24_xdg_directory_overrides_work_correctly(self):
        """24. XDG directory overrides work correctly."""
        custom_config = self.test_root / "my_custom_config"
        custom_state = self.test_root / "my_custom_state"
        custom_bin = self.test_root / "my_custom_bin"

        res = self.run_cmd([
            "--apply",
            "--config-dir", str(custom_config),
            "--state-dir", str(custom_state),
            "--bin-dir", str(custom_bin),
        ])
        self.assertEqual(res.returncode, 0)

        # Config files must be in custom_config
        self.assertTrue((custom_config / "hypr" / "hyprland.lua").is_symlink())

        # Binaries must be in custom_bin
        self.assertTrue((custom_bin / "gps-ipc").is_symlink())

        # State/backups must be in custom_state
        self.assertTrue((custom_state / "gps" / "install_manifest.json").is_file())

    def test_25_malicious_paths_and_symlink_traversal_are_rejected(self):
        """25. Malicious paths and symlink traversal are rejected."""
        from scripts.installer import validate_path_safety, SecurityError

        allowed = [self.fake_home]

        # 1. System path
        with self.assertRaises(SecurityError):
            validate_path_safety(Path("/etc/shadow"), allowed)

        # 2. Directory traversal outside allowed root
        with self.assertRaises(SecurityError):
            validate_path_safety(self.fake_home / ".." / "outside", allowed)

        # 3. Path in /usr/bin
        with self.assertRaises(SecurityError):
            validate_path_safety(Path("/usr/bin/gps-ipc"), allowed)

    def test_26_all_manifest_targets_verified_end_to_end(self):
        """Verify all declared installation targets in the manifest end-to-end."""
        from scripts.installer import InstallerManifest
        manifest = InstallerManifest(
            repo_root=REPO_ROOT,
            home_dir=self.fake_home,
            config_dir=self.fake_config,
            state_dir=self.fake_state,
            bin_dir=self.fake_bin,
        )
        entries = manifest.get_entries()
        self.assertEqual(len(entries), 19)  # 12 dots + 6 binaries + 1 template

        # Ensure all repo source files exist
        for e in entries:
            self.assertTrue(e["src"].is_file(), f"Source file must exist: {e['src']}")

        # Apply
        res_apply = self.run_cmd(["--apply"])
        self.assertEqual(res_apply.returncode, 0)

        # Verify every target exists
        for e in entries:
            dest = e["dest"]
            self.assertTrue(dest.exists(), f"Destination must exist after apply: {dest}")
            if e["type"] == "symlink":
                self.assertTrue(dest.is_symlink(), f"Must be symlink: {dest}")
                self.assertEqual(dest.resolve(), e["src"].resolve())
            elif e["type"] == "template":
                self.assertTrue(dest.is_file())
                self.assertFalse(dest.is_symlink())

        # Uninstall
        res_un = self.run_cmd(["--uninstall"])
        self.assertEqual(res_un.returncode, 0)

        # Verify symlinks are removed, but template is preserved
        for e in entries:
            dest = e["dest"]
            if e["type"] == "symlink":
                self.assertFalse(dest.exists(), f"GPS symlink must be removed on uninstall: {dest}")
            elif e["type"] == "template":
                self.assertTrue(dest.exists(), f"User template must be preserved on uninstall: {dest}")


if __name__ == "__main__":
    unittest.main()
