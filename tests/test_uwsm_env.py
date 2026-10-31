#!/usr/bin/env python3
"""Automated unit and contract tests for GPS UWSM environment setup."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
UWSM_ENV = ROOT / "dots" / "uwsm" / "env"
SETUP_SCRIPT = ROOT / "scripts" / "setup-uwsm.sh"


class UwsmEnvContractTests(unittest.TestCase):
    """Verifies that dots/uwsm/env exists and declares the expected environment variables."""

    def test_uwsm_env_file_exists(self):
        self.assertTrue(UWSM_ENV.is_file(), f"{UWSM_ENV} must exist")

    def test_uwsm_env_declares_qt6ct(self):
        content = UWSM_ENV.read_text(encoding="utf-8")
        self.assertIn("export QT_QPA_PLATFORMTHEME=qt6ct", content)


class UwsmInstallerTests(unittest.TestCase):
    """Tests for scripts/setup-uwsm.sh installer safety, idempotency, and conflict preservation."""

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp(prefix="gps_uwsm_installer_")
        self.dest_dir = Path(self.tmp_dir) / "uwsm"

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def run_installer(self, *args):
        cmd = [str(SETUP_SCRIPT), "--dest-dir", str(self.dest_dir)] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_dry_run_modifies_no_files(self):
        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("[DRY-RUN]", res.stdout)
        self.assertFalse(self.dest_dir.exists())

    def test_install_creates_symlink(self):
        res = self.run_installer()
        self.assertEqual(res.returncode, 0, f"Installer failed: {res.stderr}")
        dest_file = self.dest_dir / "env"
        self.assertTrue(dest_file.is_symlink())
        self.assertEqual(dest_file.resolve(), UWSM_ENV.resolve())

    def test_re_run_is_idempotent(self):
        res1 = self.run_installer()
        self.assertEqual(res1.returncode, 0)
        res2 = self.run_installer()
        self.assertEqual(res2.returncode, 0)
        self.assertIn("already linked", res2.stdout)

    def test_existing_conflicting_file_is_preserved_and_reported(self):
        self.dest_dir.mkdir(parents=True)
        conflicting_file = self.dest_dir / "env"
        conflicting_content = "export CUSTOM_VAR=preserved\n"
        conflicting_file.write_text(conflicting_content, encoding="utf-8")

        res = self.run_installer()
        self.assertNotEqual(res.returncode, 0, "Installer should return non-zero on conflict")
        self.assertIn("Conflict", res.stderr)
        # Ensure file was not overwritten or removed
        self.assertFalse(conflicting_file.is_symlink())
        self.assertEqual(conflicting_file.read_text(encoding="utf-8"), conflicting_content)

    def test_existing_different_symlink_is_preserved_and_reported(self):
        self.dest_dir.mkdir(parents=True)
        dummy_target = Path(self.tmp_dir) / "other_env"
        dummy_target.write_text("export OTHER=1\n", encoding="utf-8")
        conflicting_symlink = self.dest_dir / "env"
        conflicting_symlink.symlink_to(dummy_target)

        res = self.run_installer()
        self.assertNotEqual(res.returncode, 0, "Installer should return non-zero on conflicting symlink")
        self.assertIn("Conflict", res.stderr)
        self.assertEqual(conflicting_symlink.resolve(), dummy_target.resolve())


if __name__ == "__main__":
    unittest.main()
