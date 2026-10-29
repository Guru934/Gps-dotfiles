import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = REPO_ROOT / "login" / "install-login.sh"
PREVIEW_SCRIPT = REPO_ROOT / "login" / "preview.sh"
THEME_DIR = REPO_ROOT / "login" / "theme"


class LoginPackageInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="gps_login_test_")
        self.fake_root = Path(self.temp_dir)
        self.fake_etc = self.fake_root / "etc"
        self.fake_share = self.fake_root / "usr" / "share"
        self.fake_backups = self.fake_root / "var" / "backups" / "gps-login"

        self.fake_etc.mkdir(parents=True, exist_ok=True)
        self.fake_share.mkdir(parents=True, exist_ok=True)

        # Simulate pre-existing SDDM configs
        sddm_conf_d = self.fake_etc / "sddm.conf.d"
        sddm_conf_d.mkdir(parents=True, exist_ok=True)
        (sddm_conf_d / "caelestia.conf").write_text("[Theme]\nCurrent=caelestia\n", encoding="utf-8")
        (sddm_conf_d / "theme.conf").write_text("[Theme]\nCurrent=caelestia\n", encoding="utf-8")

        # Simulate pre-existing themes
        themes_dir = self.fake_share / "sddm" / "themes"
        caelestia_dir = themes_dir / "caelestia"
        caelestia_dir.mkdir(parents=True, exist_ok=True)
        (caelestia_dir / "metadata.desktop").write_text("[SddmGreeterTheme]\nName=caelestia\n", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def run_installer(self, *args):
        cmd = [str(INSTALL_SCRIPT), "--root-dir", str(self.fake_root)] + list(args)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_default_is_dry_run_and_modifies_no_files(self):
        """Default invocation without flags must perform dry-run and modify no files."""
        res = self.run_installer()
        self.assertEqual(res.returncode, 0, f"Dry-run failed: {res.stderr}")
        self.assertIn("DRY-RUN", res.stdout)
        self.assertIn("0 changes made", res.stdout)

        # Ensure no files were installed in fake_root
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "zz-gps-theme.conf"
        self.assertFalse(gps_theme.exists())
        self.assertFalse(gps_conf.exists())
        self.assertFalse(self.fake_backups.exists())

    def test_dry_run_reports_effective_configuration_and_precedence_conflict(self):
        """Dry-run must report the actual effective theme and warn if /etc/sddm.conf conflicts."""
        # Create an explicit /etc/sddm.conf with Current=caelestia
        sddm_conf = self.fake_etc / "sddm.conf"
        sddm_conf.write_text("[General]\nNumlock=on\n\n[Theme]\nCurrent=caelestia\n", encoding="utf-8")

        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Current Effective Theme  : caelestia", res.stdout)
        self.assertIn("PRECEDENCE CONFLICT DETECTED", res.stdout)
        self.assertIn("sddm.conf(5)", res.stdout)
        self.assertIn("HIGHEST PRECEDENCE", res.stdout)

    def test_apply_refuses_unresolved_sddm_conf_conflict(self):
        """--apply must refuse when /etc/sddm.conf explicitly sets a conflicting theme."""
        sddm_conf = self.fake_etc / "sddm.conf"
        sddm_conf.write_text("[General]\nNumlock=on\n\n[Theme]\nCurrent=caelestia\n", encoding="utf-8")

        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0, "Installer should refuse unresolved precedence conflict")
        self.assertIn("precedence conflict", res.stderr.lower())
        self.assertIn("sddm.conf", res.stderr)

        # Verify nothing was installed or modified
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "zz-gps-theme.conf"
        self.assertFalse(gps_theme.exists())
        self.assertFalse(gps_conf.exists())
        self.assertFalse(self.fake_backups.exists())

    def test_apply_refuses_conflicting_theme_dropin(self):
        """--apply must refuse when another drop-in sorts after GPS and overrides it."""
        # /etc/sddm.conf has no theme
        sddm_conf = self.fake_etc / "sddm.conf"
        sddm_conf.write_text("[General]\nNumlock=on\n", encoding="utf-8")

        # Create a conflicting drop-in sorting after zz-gps-theme.conf
        (self.fake_etc / "sddm.conf.d" / "zzz-override.conf").write_text("[Theme]\nCurrent=other\n", encoding="utf-8")

        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("precedence conflict", res.stderr.lower())
        self.assertIn("zzz-override.conf", res.stderr)

    def test_apply_with_update_sddm_conf_resolves_and_rolls_back(self):
        """--update-sddm-conf should safely comment out Current= in /etc/sddm.conf and restore on rollback."""
        sddm_conf = self.fake_etc / "sddm.conf"
        original_sddm_conf = "[General]\nNumlock=on\n\n[Theme]\nCurrent=caelestia\nCursorTheme=breeze\n"
        sddm_conf.write_text(original_sddm_conf, encoding="utf-8")

        # Apply with --update-sddm-conf
        res = self.run_installer("--apply", "--update-sddm-conf")
        self.assertEqual(res.returncode, 0, f"Apply failed: {res.stderr}")

        # Check theme installed
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "zz-gps-theme.conf"
        self.assertTrue(gps_theme.exists())
        self.assertTrue(gps_conf.exists())

        # Check /etc/sddm.conf: Numlock=on and CursorTheme=breeze preserved, Current=caelestia commented out
        mod_conf = sddm_conf.read_text(encoding="utf-8")
        self.assertIn("Numlock=on", mod_conf)
        self.assertIn("CursorTheme=breeze", mod_conf)
        self.assertIn("# Current=caelestia", mod_conf)

        # Check manifest
        latest_symlink = self.fake_backups / "latest"
        manifest = json.loads((latest_symlink / "manifest.json").read_text(encoding="utf-8"))
        self.assertTrue(manifest.get("modified_sddm_conf"))

        # Check status reports active
        res_status = self.run_installer("--status")
        self.assertIn("ACTIVE and EFFECTIVE", res_status.stdout)

        # Now test rollback
        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0, f"Rollback failed: {res_rb.stderr}")

        # Verify /etc/sddm.conf restored exactly to original
        self.assertEqual(sddm_conf.read_text(encoding="utf-8"), original_sddm_conf)
        self.assertFalse(gps_conf.exists())
        self.assertFalse(gps_theme.exists())

    def test_apply_succeeds_when_conflict_manually_resolved(self):
        """When /etc/sddm.conf has no conflicting Current=, --apply succeeds with drop-in."""
        sddm_conf = self.fake_etc / "sddm.conf"
        sddm_conf.write_text("[General]\nNumlock=on\n\n[Theme]\n# Current=caelestia\n", encoding="utf-8")

        res = self.run_installer("--apply")
        self.assertEqual(res.returncode, 0, f"Apply failed: {res.stderr}")

        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "zz-gps-theme.conf"
        self.assertTrue(gps_theme.exists())
        self.assertTrue(gps_conf.exists())

        # Status confirms GPS is active and effective because zz-gps-theme.conf sorts after caelestia.conf and theme.conf
        res_status = self.run_installer("--status")
        self.assertIn("ACTIVE and EFFECTIVE", res_status.stdout)

    def test_installer_is_idempotent(self):
        """Consecutive --apply runs should detect matching state and be idempotent."""
        sddm_conf = self.fake_etc / "sddm.conf"
        sddm_conf.write_text("[General]\nNumlock=on\n", encoding="utf-8")

        res1 = self.run_installer("--apply")
        self.assertEqual(res1.returncode, 0)

        backups_1 = list(self.fake_backups.glob("backup_*"))
        self.assertEqual(len(backups_1), 1)

        res2 = self.run_installer("--apply")
        self.assertEqual(res2.returncode, 0)
        self.assertIn("idempotent", res2.stdout.lower())

        backups_2 = list(self.fake_backups.glob("backup_*"))
        self.assertEqual(len(backups_2), 1)

    def test_system_apply_requires_root(self):
        """Running --apply against real system roots without root must fail safely."""
        if os.geteuid() != 0:
            res = subprocess.run([str(INSTALL_SCRIPT), "--apply"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("root", res.stderr.lower())

    def test_theme_package_structure(self):
        """Verify the package meets SDDM and GPS structural standards."""
        self.assertTrue(THEME_DIR.exists())
        metadata_file = THEME_DIR / "metadata.desktop"
        self.assertTrue(metadata_file.exists())
        metadata_txt = metadata_file.read_text(encoding="utf-8")
        self.assertIn("QtVersion=6", metadata_txt)
        self.assertIn("MainScript=Main.qml", metadata_txt)

        theme_conf = THEME_DIR / "theme.conf"
        self.assertTrue(theme_conf.exists())
        self.assertIn("background=assets/background.jpg", theme_conf.read_text(encoding="utf-8"))

        palette_file = THEME_DIR / "palette.json"
        self.assertTrue(palette_file.exists())
        palette_data = json.loads(palette_file.read_text(encoding="utf-8"))
        tokens = palette_data.get("tokens", {})
        self.assertEqual(tokens.get("brandAccent"), "#2DD4BF")
        self.assertEqual(tokens.get("surfaceDeep"), "#0F131C")
        self.assertEqual(tokens.get("card"), "#CC1C1F29")

        bg_asset = THEME_DIR / "assets" / "background.jpg"
        self.assertTrue(bg_asset.exists())
        self.assertGreater(bg_asset.stat().st_size, 10000)

        preview_img = REPO_ROOT / "login" / "preview.png"
        self.assertTrue(preview_img.exists())
        self.assertGreater(preview_img.stat().st_size, 10000)


if __name__ == "__main__":
    unittest.main()
