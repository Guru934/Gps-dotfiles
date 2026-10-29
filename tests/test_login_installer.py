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

    def test_default_is_dry_run(self):
        """Default invocation without flags must perform dry-run and modify no files."""
        res = self.run_installer()
        self.assertEqual(res.returncode, 0, f"Dry-run failed: {res.stderr}")
        self.assertIn("DRY-RUN", res.stdout)
        self.assertIn("0 changes made", res.stdout)

        # Ensure no files were installed in fake_root
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "99-gps-theme.conf"
        self.assertFalse(gps_theme.exists())
        self.assertFalse(gps_conf.exists())
        self.assertFalse(self.fake_backups.exists())

    def test_explicit_dry_run_flag(self):
        """Explicit --dry-run must report plan and make no changes."""
        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("DRY-RUN", res.stdout)
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        self.assertFalse(gps_theme.exists())

    def test_apply_installs_theme_and_dropin(self):
        """--apply should install the theme directory and drop-in config non-destructively."""
        res = self.run_installer("--apply")
        self.assertEqual(res.returncode, 0, f"Apply failed: {res.stderr}")

        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "99-gps-theme.conf"

        self.assertTrue(gps_theme.exists())
        self.assertTrue((gps_theme / "metadata.desktop").exists())
        self.assertTrue((gps_theme / "Main.qml").exists())
        self.assertTrue((gps_theme / "theme.conf").exists())
        self.assertTrue(gps_conf.exists())

        conf_content = gps_conf.read_text(encoding="utf-8")
        self.assertIn("Current=gps", conf_content)

        # Ensure pre-existing themes and configs are untouched
        caelestia_conf = self.fake_etc / "sddm.conf.d" / "caelestia.conf"
        self.assertTrue(caelestia_conf.exists())
        self.assertIn("Current=caelestia", caelestia_conf.read_text(encoding="utf-8"))

        caelestia_theme = self.fake_share / "sddm" / "themes" / "caelestia"
        self.assertTrue(caelestia_theme.exists())

        # Verify backup manifest was created
        self.assertTrue(self.fake_backups.exists())
        latest_symlink = self.fake_backups / "latest"
        self.assertTrue(latest_symlink.is_symlink() or latest_symlink.exists())
        manifest_file = latest_symlink / "manifest.json"
        self.assertTrue(manifest_file.exists())
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        self.assertEqual(manifest.get("theme_name"), "gps")

    def test_installer_is_idempotent(self):
        """Consecutive --apply runs should detect matching state and be idempotent."""
        res1 = self.run_installer("--apply")
        self.assertEqual(res1.returncode, 0)

        # Count backup directories created
        backups_1 = list(self.fake_backups.glob("backup_*"))
        self.assertEqual(len(backups_1), 1)

        res2 = self.run_installer("--apply")
        self.assertEqual(res2.returncode, 0)
        self.assertIn("idempotent", res2.stdout.lower())

        # No duplicate backup created on redundant run
        backups_2 = list(self.fake_backups.glob("backup_*"))
        self.assertEqual(len(backups_2), 1)

    def test_rollback_reverts_cleanly(self):
        """--rollback should remove the GPS drop-in and theme, leaving existing system intact."""
        # First apply
        self.run_installer("--apply")
        gps_theme = self.fake_share / "sddm" / "themes" / "gps"
        gps_conf = self.fake_etc / "sddm.conf.d" / "99-gps-theme.conf"
        self.assertTrue(gps_theme.exists())
        self.assertTrue(gps_conf.exists())

        # Now rollback
        res = self.run_installer("--rollback")
        self.assertEqual(res.returncode, 0, f"Rollback failed: {res.stderr}")
        self.assertIn("Rollback completed successfully", res.stdout)

        # GPS files removed
        self.assertFalse(gps_theme.exists())
        self.assertFalse(gps_conf.exists())

        # Pre-existing configuration intact
        caelestia_conf = self.fake_etc / "sddm.conf.d" / "caelestia.conf"
        self.assertTrue(caelestia_conf.exists())
        self.assertIn("Current=caelestia", caelestia_conf.read_text(encoding="utf-8"))

    def test_status_reports_correct_state(self):
        """--status accurately reflects unapplied vs applied state."""
        res_before = self.run_installer("--status")
        self.assertIn("NOT INSTALLED", res_before.stdout)

        self.run_installer("--apply")
        res_after = self.run_installer("--status")
        self.assertIn("ACTIVE", res_after.stdout)

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
