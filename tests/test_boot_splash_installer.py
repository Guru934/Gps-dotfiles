import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = REPO_ROOT / "boot" / "install-splash.sh"
THEME_DIR = REPO_ROOT / "boot" / "theme"


class BootSplashInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="gps_boot_test_")
        self.fake_root = Path(self.temp_dir)
        self.fake_etc = self.fake_root / "etc"
        self.fake_share = self.fake_root / "usr" / "share"
        self.fake_bin = self.fake_root / "usr" / "bin"
        self.fake_lib = self.fake_root / "usr" / "lib" / "plymouth"
        self.fake_boot = self.fake_root / "boot"
        self.fake_backups = self.fake_root / "var" / "backups" / "gps-boot"

        self.fake_etc.mkdir(parents=True, exist_ok=True)
        self.fake_share.mkdir(parents=True, exist_ok=True)
        self.fake_bin.mkdir(parents=True, exist_ok=True)
        self.fake_lib.mkdir(parents=True, exist_ok=True)
        self.fake_boot.mkdir(parents=True, exist_ok=True)
        self.fake_backups.mkdir(parents=True, exist_ok=True)

        # Mock plymouth binary and two-step plugin
        plymouth_bin = self.fake_bin / "plymouth"
        plymouth_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        plymouth_bin.chmod(0o755)
        (self.fake_lib / "two-step.so").write_bytes(b"\x7fELFfake")

        # Mock existing plymouthd.conf
        plymouth_dir = self.fake_etc / "plymouth"
        plymouth_dir.mkdir(parents=True, exist_ok=True)
        (plymouth_dir / "plymouthd.conf").write_text(
            "[Daemon]\nTheme=cachyos-bootanimation\n",
            encoding="utf-8"
        )

        # Mock Limine config in /etc/default/limine
        default_dir = self.fake_etc / "default"
        default_dir.mkdir(parents=True, exist_ok=True)
        (default_dir / "limine").write_text(
            'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@"\n',
            encoding="utf-8"
        )

        # Mock mkinitcpio.conf
        (self.fake_etc / "mkinitcpio.conf").write_text(
            "HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)\n",
            encoding="utf-8"
        )

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def run_installer(self, *args):
        cmd = [
            str(INSTALL_SCRIPT),
            "--root-dir", str(self.fake_root),
            "--no-initrd-rebuild",
        ] + list(args)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_default_is_dry_run_and_modifies_no_files(self):
        """Default invocation without flags must perform dry-run and modify 0 files."""
        res = self.run_installer()
        self.assertEqual(res.returncode, 0, f"Dry-run failed: {res.stderr}")
        self.assertIn("DRY-RUN", res.stdout)
        self.assertIn("0 modifications made", res.stdout)

        # Ensure theme was NOT installed
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        # Ensure plymouthd.conf was NOT modified
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

        # Ensure no backups created
        backups = list(self.fake_backups.glob("*_*"))
        self.assertEqual(len(backups), 0)

    def test_explicit_dry_run_flag(self):
        """--dry-run flag behaves identically to default mode."""
        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("DRY-RUN", res.stdout)
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_apply_installs_theme_and_creates_backup(self):
        """--apply installs GPS theme, updates plymouthd.conf, and creates manifest backup."""
        res = self.run_installer("--apply")
        self.assertEqual(res.returncode, 0, f"Apply failed: {res.stderr}")
        self.assertIn("GPS Plymouth Boot Splash Theme applied successfully", res.stdout)

        # Verify theme files installed
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertTrue(dest_theme.exists())
        self.assertTrue((dest_theme / "gps.plymouth").exists())
        self.assertTrue((dest_theme / "watermark.png").exists())
        self.assertTrue((dest_theme / "bullet.png").exists())
        self.assertTrue((dest_theme / "entry.png").exists())
        self.assertTrue((dest_theme / "throbber-0001.png").exists())

        # Verify plymouthd.conf updated
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=gps", conf_text)

        # Verify backup manifest created
        backups = list(self.fake_backups.glob("*_*"))
        self.assertEqual(len(backups), 1)
        backup_dir = backups[0]
        manifest_file = backup_dir / "manifest.json"
        self.assertTrue(manifest_file.exists())

        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        self.assertEqual(manifest["previous_theme"], "cachyos-bootanimation")
        self.assertEqual(manifest["installed_theme"], "gps")
        self.assertTrue((backup_dir / "plymouthd.conf.orig").exists())

    def test_rollback_restores_previous_state(self):
        """--rollback completely restores original configuration and removes GPS theme."""
        # First apply
        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)

        # Then rollback
        res_rollback = self.run_installer("--rollback")
        self.assertEqual(res_rollback.returncode, 0, f"Rollback failed: {res_rollback.stderr}")
        self.assertIn("Rollback completed successfully", res_rollback.stdout)

        # Theme folder must be removed
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        # plymouthd.conf must be restored
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

    def test_idempotent_repeated_apply(self):
        """Applying twice in succession succeeds cleanly and maintains valid state."""
        res1 = self.run_installer("--apply")
        self.assertEqual(res1.returncode, 0)

        res2 = self.run_installer("--apply")
        self.assertEqual(res2.returncode, 0)

        # Check theme still set once
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertEqual(conf_text.count("Theme=gps"), 1)

        # Check hook not duplicated
        mk_text = (self.fake_etc / "mkinitcpio.conf").read_text(encoding="utf-8")
        self.assertEqual(mk_text.count("plymouth"), 1)

    def test_mkinitcpio_hook_injection_when_missing(self):
        """Installer injects 'plymouth' hook after sd-vconsole if missing from mkinitcpio.conf."""
        (self.fake_etc / "mkinitcpio.conf").write_text(
            "HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole filesystems)\n",
            encoding="utf-8"
        )
        res = self.run_installer("--apply")
        self.assertEqual(res.returncode, 0)

        mk_text = (self.fake_etc / "mkinitcpio.conf").read_text(encoding="utf-8")
        self.assertIn("sd-vconsole plymouth filesystems", mk_text)

        # Rollback restores original
        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)
        restored_text = (self.fake_etc / "mkinitcpio.conf").read_text(encoding="utf-8")
        self.assertNotIn("plymouth", restored_text)

    def test_encryption_detected_with_valid_order_succeeds(self):
        """Encryption with valid hook order (plymouth BEFORE sd-encrypt) passes safety check."""
        (self.fake_etc / "mkinitcpio.conf").write_text(
            "HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth sd-encrypt filesystems)\n",
            encoding="utf-8"
        )
        (self.fake_etc / "crypttab").write_text(
            "cryptroot UUID=1234-5678 none luks\n",
            encoding="utf-8"
        )
        res = self.run_installer("--apply")
        self.assertEqual(res.returncode, 0)
        self.assertIn("GPS Plymouth Boot Splash Theme applied successfully", res.stdout)

    def test_encryption_detected_with_invalid_order_refuses_to_apply(self):
        """Encryption with invalid hook order (sd-encrypt BEFORE plymouth) refuses to apply."""
        (self.fake_etc / "mkinitcpio.conf").write_text(
            "HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole sd-encrypt plymouth filesystems)\n",
            encoding="utf-8"
        )
        (self.fake_etc / "crypttab").write_text(
            "cryptroot UUID=1234-5678 none luks\n",
            encoding="utf-8"
        )
        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("SAFETY ERROR", res.stderr)
        self.assertIn("appears BEFORE 'plymouth'", res.stderr)

        # Ensure no modifications occurred
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_missing_plymouth_package_fails_safely(self):
        """Installer fails with instructions if plymouth is not installed."""
        # Remove fake plymouth binary from fake root
        (self.fake_bin / "plymouth").unlink()

        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Plymouth package is not installed", res.stderr)
        self.assertIn("sudo pacman -S plymouth", res.stderr)

    def test_grub_bootloader_variant(self):
        """Installer detects GRUB and appends splash to GRUB_CMDLINE_LINUX_DEFAULT if missing."""
        # Remove Limine config
        (self.fake_etc / "default" / "limine").unlink()

        # Create GRUB config without splash
        grub_conf = self.fake_etc / "default" / "grub"
        grub_conf.write_text('GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"\n', encoding="utf-8")

        res_dry = self.run_installer("--dry-run")
        self.assertIn("Bootloader                : GRUB", res_dry.stdout)

        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)
        grub_after = grub_conf.read_text(encoding="utf-8")
        self.assertIn("splash", grub_after)

        # Rollback restores GRUB
        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)
        grub_restored = grub_conf.read_text(encoding="utf-8")
        self.assertEqual(grub_restored, 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"\n')

    def test_status_command(self):
        """--status accurately reports installation state."""
        res_before = self.run_installer("--status")
        self.assertEqual(res_before.returncode, 0)
        self.assertIn("Theme Files Installed: NO", res_before.stdout)

        self.run_installer("--apply")
        res_after = self.run_installer("--status")
        self.assertEqual(res_after.returncode, 0)
        self.assertIn("Theme Files Installed: YES", res_after.stdout)
        self.assertIn("Is GPS Theme Active  : YES", res_after.stdout)

    def test_systemd_boot_variant(self):
        """Installer detects systemd-boot when loader.conf is present."""
        # Remove Limine config
        (self.fake_etc / "default" / "limine").unlink()
        loader_dir = self.fake_boot / "loader"
        loader_dir.mkdir(parents=True, exist_ok=True)
        (loader_dir / "loader.conf").write_text("timeout 3\ndefault arch\n", encoding="utf-8")

        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Bootloader                : systemd-boot", res.stdout)

    def test_dracut_variant(self):
        """Installer detects dracut when dracut.conf is present and mkinitcpio is absent."""
        (self.fake_etc / "mkinitcpio.conf").unlink()
        (self.fake_etc / "dracut.conf").write_text("# dracut config\n", encoding="utf-8")

        res = self.run_installer("--dry-run")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Initramfs Generator       : dracut", res.stdout)

    def test_permission_guard_on_system_paths(self):
        """Running --apply on system paths without root privileges must fail safely."""
        # Non-root user running without --root-dir
        cmd = [str(INSTALL_SCRIPT), "--apply"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 1)
        self.assertIn("requires root privileges", res.stderr)

    def test_rollback_to_explicit_backup_path(self):
        """--rollback [PATH] restores from specified backup directory."""
        self.run_installer("--apply")
        backups = list(self.fake_backups.glob("*_*"))
        self.assertEqual(len(backups), 1)
        target_backup = backups[0]

        res = self.run_installer("--rollback", str(target_backup))
        self.assertEqual(res.returncode, 0)
        self.assertIn(f"Restoring from backup archive: {target_backup}", res.stdout)
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())


if __name__ == "__main__":
    unittest.main()
