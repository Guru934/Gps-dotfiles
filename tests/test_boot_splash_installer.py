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

        # Mock Limine integration binary (limine-mkinitcpio)
        limine_mk = self.fake_bin / "limine-mkinitcpio"
        limine_mk.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        limine_mk.chmod(0o755)

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

        # Mock /boot/limine.conf with custom/unrelated entries
        self.initial_limine_conf = (
            "timeout: 5\n\n"
            "/Windows Boot Manager\n"
            "  protocol: efi_chainload\n"
            "  image_path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n\n"
            "/CachyOS Linux (Snapshot 12)\n"
            "  protocol: linux\n"
            "  kernel_path: boot():/d539a1316b0543e0b082edcf8cffe442/linux-cachyos/vmlinuz\n"
            "  initrd_path: boot():/d539a1316b0543e0b082edcf8cffe442/linux-cachyos/initramfs\n"
        )
        (self.fake_boot / "limine.conf").write_text(self.initial_limine_conf, encoding="utf-8")

        # Mock existing initramfs on separate /boot
        kdir = self.fake_boot / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos"
        kdir.mkdir(parents=True, exist_ok=True)
        self.initial_initramfs_data = "FAKE_INITRAMFS_BINARY_DATA_ORIGINAL"
        (kdir / "initramfs").write_text(self.initial_initramfs_data, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def run_installer(self, *args, env=None):
        cmd = [
            str(INSTALL_SCRIPT),
            "--root-dir", str(self.fake_root),
            "--no-initrd-rebuild",
        ] + list(args)
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=merged_env)

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

    def test_boot_partition_initramfs_and_limine_backup_and_restoration(self):
        """Installer backs up separate /boot files (limine.conf and initramfs) and restores them on rollback."""
        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)

        backups = list(self.fake_backups.glob("*_*"))
        self.assertEqual(len(backups), 1)
        bdir = backups[0]

        # Verify /boot/limine.conf was backed up
        backed_limine = bdir / "boot" / "limine.conf"
        self.assertTrue(backed_limine.exists())
        self.assertEqual(backed_limine.read_text(encoding="utf-8"), self.initial_limine_conf)

        # Verify initramfs was backed up
        backed_initramfs = bdir / "boot" / "initramfs" / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos" / "initramfs"
        self.assertTrue(backed_initramfs.exists())
        self.assertEqual(backed_initramfs.read_text(encoding="utf-8"), self.initial_initramfs_data)

        # Simulate mutation of /boot during bootloader updates
        (self.fake_boot / "limine.conf").write_text("MUTATED_LIMINE_CONF", encoding="utf-8")
        target_initramfs = self.fake_boot / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos" / "initramfs"
        target_initramfs.write_text("MUTATED_INITRAMFS_DATA", encoding="utf-8")

        # Rollback
        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)

        # Verify restoration of /boot files
        self.assertEqual((self.fake_boot / "limine.conf").read_text(encoding="utf-8"), self.initial_limine_conf)
        self.assertEqual(target_initramfs.read_text(encoding="utf-8"), self.initial_initramfs_data)

    def test_preservation_of_unrelated_boot_entries(self):
        """Unrelated bootloader entries (e.g. Windows Boot Manager) remain intact through apply and rollback."""
        self.run_installer("--apply")
        limine_text = (self.fake_boot / "limine.conf").read_text(encoding="utf-8")
        self.assertIn("/Windows Boot Manager", limine_text)
        self.assertIn("image_path: boot():/EFI/Microsoft/Boot/bootmgfw.efi", limine_text)

        self.run_installer("--rollback")
        limine_after = (self.fake_boot / "limine.conf").read_text(encoding="utf-8")
        self.assertEqual(limine_after, self.initial_limine_conf)

    def test_missing_limine_integration_refuses_to_apply(self):
        """Installer refuses to apply when Limine is detected but limine-mkinitcpio is missing."""
        (self.fake_bin / "limine-mkinitcpio").unlink()

        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("required command 'limine-mkinitcpio'", res.stderr)
        self.assertIn("limine-mkinitcpio-hook", res.stderr)

        # Verify no files installed
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_regeneration_command_limine_selection(self):
        """Dry-run explicitly displays the verified command 'sudo limine-mkinitcpio' for Limine."""
        cmd = [str(INSTALL_SCRIPT), "--root-dir", str(self.fake_root), "--dry-run"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Verified Command: sudo limine-mkinitcpio", res.stdout)

    def test_partial_failure_automatic_rollback(self):
        """If a failure occurs during apply, the error trap automatically reverts all changes."""
        res = self.run_installer("--apply", env={"GPS_TEST_FAIL_AFTER_COPY": "1"})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAILURE DETECTED", res.stderr)
        self.assertIn("Initiating automatic emergency rollback", res.stderr)

        # Verify theme files were safely rolled back / removed
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        # Verify plymouthd.conf was restored
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

    def test_idempotent_rollback(self):
        """Running rollback multiple times is completely idempotent and safe."""
        self.run_installer("--apply")

        res1 = self.run_installer("--rollback")
        self.assertEqual(res1.returncode, 0)
        self.assertIn("Rollback completed successfully", res1.stdout)

        # Second rollback
        res2 = self.run_installer("--rollback")
        self.assertEqual(res2.returncode, 0)

        # Files remain clean and original
        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_rollback_restores_previous_state(self):
        """--rollback completely restores original configuration and removes GPS theme."""
        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)

        res_rollback = self.run_installer("--rollback")
        self.assertEqual(res_rollback.returncode, 0, f"Rollback failed: {res_rollback.stderr}")
        self.assertIn("Rollback completed successfully", res_rollback.stdout)

        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

    def test_idempotent_repeated_apply(self):
        """Applying twice in succession succeeds cleanly and maintains valid state."""
        res1 = self.run_installer("--apply")
        self.assertEqual(res1.returncode, 0)

        res2 = self.run_installer("--apply")
        self.assertEqual(res2.returncode, 0)

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertEqual(conf_text.count("Theme=gps"), 1)

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

        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_missing_plymouth_package_fails_safely(self):
        """Installer fails with instructions if plymouth is not installed."""
        (self.fake_bin / "plymouth").unlink()

        res = self.run_installer("--apply")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Plymouth package is not installed", res.stderr)
        self.assertIn("sudo pacman -S plymouth", res.stderr)

    def test_grub_bootloader_variant(self):
        """Installer detects GRUB and appends splash to GRUB_CMDLINE_LINUX_DEFAULT if missing."""
        (self.fake_etc / "default" / "limine").unlink()
        (self.fake_boot / "limine.conf").unlink()

        grub_conf = self.fake_etc / "default" / "grub"
        grub_conf.write_text('GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"\n', encoding="utf-8")

        res_dry = self.run_installer("--dry-run")
        self.assertIn("Bootloader                : GRUB", res_dry.stdout)

        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)
        grub_after = grub_conf.read_text(encoding="utf-8")
        self.assertIn("splash", grub_after)

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
        (self.fake_etc / "default" / "limine").unlink()
        (self.fake_boot / "limine.conf").unlink()
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

    def test_rollback_never_invokes_limine_mkinitcpio(self):
        """Fix 1: Rollback is purely restorative and must NEVER invoke limine-mkinitcpio."""
        witness_file = self.fake_root / "limine_mkinitcpio_invoked"
        limine_spy = self.fake_bin / "limine-mkinitcpio"
        limine_spy.write_text(
            f"#!/bin/sh\ntouch \"{witness_file}\"\nexit 0\n",
            encoding="utf-8"
        )
        limine_spy.chmod(0o755)

        self.run_installer("--apply")
        self.assertFalse(witness_file.exists())

        cmd = [
            str(INSTALL_SCRIPT),
            "--root-dir", str(self.fake_root),
            "--rollback",
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0, f"Rollback failed: {res.stderr}")
        self.assertFalse(witness_file.exists(), "limine-mkinitcpio was invoked during rollback!")
        self.assertNotIn("Resynchronizing boot artifacts", res.stdout)
        self.assertNotIn("limine-mkinitcpio", res.stdout)

    def test_successful_restoration_preserves_exact_original_initramfs_bytes(self):
        """Fix 1 & 2: Rollback restores the exact original binary bytes of initramfs images."""
        target_img = self.fake_boot / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos" / "initramfs"
        binary_data = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\x03\xed\x9d\x07\x58\x14\x55\x19\xc7\xbf\x3b\xaa\xbb\xcc\xdd"
        target_img.write_bytes(binary_data)

        self.run_installer("--apply")

        # Mutate the initramfs in /boot
        target_img.write_bytes(b"\x00\x00\x00_MUTATED_CORRUPTED_INITRAMFS_DATA_123456")

        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)
        self.assertEqual(target_img.read_bytes(), binary_data)

    def test_successful_restoration_preserves_exact_original_limine_conf_bytes(self):
        """Fix 1 & 2: Rollback preserves exact original limine.conf bytes including comments and custom entries."""
        complex_limine = (
            "# Custom Limine Configuration with arbitrary formatting\n"
            "timeout: 10\n"
            "default_entry: 2\n\n"
            "/CachyOS Linux (Zen Kernel)\n"
            "  protocol: linux\n"
            "  kernel_path: boot():/vmlinuz-zen\n"
            "  kernel_cmdline: root=UUID=123 rw quiet splash\n\n"
            "//Custom Utilities\n"
            "/Memtest86+\n"
            "  protocol: efi_chainload\n"
            "  image_path: boot():/memtest.efi\n"
        )
        limine_file = self.fake_boot / "limine.conf"
        limine_file.write_text(complex_limine, encoding="utf-8")

        self.run_installer("--apply")

        # Mutate limine.conf
        limine_file.write_text("timeout: 0\n/Corrupted\n  protocol: none\n", encoding="utf-8")

        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)
        self.assertEqual(limine_file.read_text(encoding="utf-8"), complex_limine)

    def test_incomplete_boot_backup_aborts_before_any_system_modification(self):
        """Fix 2: Incomplete boot backup aborts in Phase B before modifying any system files."""
        res = self.run_installer("--apply", env={"GPS_TEST_FAIL_VERIFY_BACKUP": "1"})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Backup verification failed", res.stderr)
        self.assertIn("System configuration untouched", res.stderr)

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        self.assertFalse((self.fake_backups / "latest").exists())

    def test_backup_failure_does_not_leave_plymouthd_conf_modified(self):
        """Fix 2: Phase A backup failure aborts before modifying plymouthd.conf or installing theme."""
        res = self.run_installer("--apply", env={"GPS_TEST_FAIL_BACKUP": "1"})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Phase A backup", res.stderr)

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_existing_gps_theme_is_restored_exactly(self):
        """Fix 3: Existing GPS theme is backed up and restored exactly on rollback."""
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        dest_theme.mkdir(parents=True, exist_ok=True)
        marker_file = dest_theme / "custom_theme_file.txt"
        marker_file.write_text("PRE_EXISTING_THEME_CUSTOM_PAYLOAD_V1", encoding="utf-8")

        res_apply = self.run_installer("--apply")
        self.assertEqual(res_apply.returncode, 0)
        self.assertFalse(marker_file.exists())
        self.assertTrue((dest_theme / "gps.plymouth").exists())

        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)
        self.assertTrue(marker_file.exists())
        self.assertEqual(marker_file.read_text(encoding="utf-8"), "PRE_EXISTING_THEME_CUSTOM_PAYLOAD_V1")

    def test_newly_created_gps_theme_is_removed_on_rollback(self):
        """Fix 3: When no GPS theme existed before apply, rollback removes the installed theme directory."""
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        self.run_installer("--apply")
        self.assertTrue(dest_theme.exists())

        self.run_installer("--rollback")
        self.assertFalse(dest_theme.exists())

    def test_newly_generated_initramfs_files_are_cleaned_up_safely(self):
        """Fix 4: Newly generated initramfs artifacts created during apply are cleaned up on rollback."""
        self.run_installer("--apply")

        # Simulate newly generated boot artifacts created after/during apply
        new_img = self.fake_boot / "initramfs-linux-fallback.img"
        new_img.write_text("NEW_FALLBACK_INITRAMFS", encoding="utf-8")
        new_entry = self.fake_boot / "loader" / "entries" / "new-entry.conf"
        new_entry.parent.mkdir(parents=True, exist_ok=True)
        new_entry.write_text("title New Entry\n", encoding="utf-8")

        self.assertTrue(new_img.exists())
        self.assertTrue(new_entry.exists())

        res_rb = self.run_installer("--rollback")
        self.assertEqual(res_rb.returncode, 0)

        self.assertFalse(new_img.exists(), "Newly generated initramfs was not pruned on rollback")
        self.assertFalse(new_entry.exists(), "Newly generated bootloader entry was not pruned on rollback")

        target_initramfs = self.fake_boot / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos" / "initramfs"
        self.assertTrue(target_initramfs.exists())
        self.assertEqual(target_initramfs.read_text(encoding="utf-8"), self.initial_initramfs_data)

    def test_unrelated_boot_files_are_preserved(self):
        """Fix 4: Unrelated boot files are preserved through apply and rollback."""
        win_efi = self.fake_boot / "EFI" / "Microsoft" / "Boot" / "bootmgfw.efi"
        win_efi.parent.mkdir(parents=True, exist_ok=True)
        win_efi.write_bytes(b"MOCK_WINDOWS_BOOT_MANAGER_BINARY")

        memtest = self.fake_boot / "memtest86+" / "memtest.bin"
        memtest.parent.mkdir(parents=True, exist_ok=True)
        memtest.write_bytes(b"MOCK_MEMTEST_BINARY")

        self.run_installer("--apply")
        self.run_installer("--rollback")

        self.assertTrue(win_efi.exists())
        self.assertEqual(win_efi.read_bytes(), b"MOCK_WINDOWS_BOOT_MANAGER_BINARY")
        self.assertTrue(memtest.exists())
        self.assertEqual(memtest.read_bytes(), b"MOCK_MEMTEST_BINARY")

    def test_failed_rollback_never_prints_success_message(self):
        """Fix 5: Failed rollback reports failure clearly and never prints a success message."""
        nonexistent = self.fake_root / "var" / "backups" / "gps-boot" / "nonexistent_dir"
        res = self.run_installer("--rollback", str(nonexistent))
        self.assertNotEqual(res.returncode, 0)
        self.assertNotIn("[SUCCESS]", res.stdout)
        self.assertNotIn("[SUCCESS]", res.stderr)
        self.assertIn("Error:", res.stderr)

        corrupt_backup = self.fake_backups / "20261030_999999"
        corrupt_backup.mkdir(parents=True, exist_ok=True)
        res_corrupt = self.run_installer("--rollback", str(corrupt_backup))
        self.assertNotEqual(res_corrupt.returncode, 0)
        self.assertNotIn("[SUCCESS]", res_corrupt.stdout)
        self.assertNotIn("[SUCCESS]", res_corrupt.stderr)
        self.assertIn("Backup manifest not found", res_corrupt.stderr)

    def test_repeated_rollback_remains_safe(self):
        """Fix 5: Repeated rollback remains safe and idempotent without error."""
        self.run_installer("--apply")
        res1 = self.run_installer("--rollback")
        self.assertEqual(res1.returncode, 0)
        res2 = self.run_installer("--rollback")
        self.assertEqual(res2.returncode, 0)

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

    def test_failed_apply_restores_all_original_files_when_backup_is_valid(self):
        """Fix 5: Failed apply in Phase C restores all original files when backup is valid."""
        res = self.run_installer("--apply", env={"GPS_TEST_FAIL_AFTER_COPY": "1"})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAILURE DETECTED", res.stderr)
        self.assertIn("Initiating automatic emergency rollback", res.stderr)

        dest_theme = self.fake_share / "plymouth" / "themes" / "gps"
        self.assertFalse(dest_theme.exists())

        conf_text = (self.fake_etc / "plymouth" / "plymouthd.conf").read_text(encoding="utf-8")
        self.assertIn("Theme=cachyos-bootanimation", conf_text)
        self.assertNotIn("Theme=gps", conf_text)

        limine_text = (self.fake_boot / "limine.conf").read_text(encoding="utf-8")
        self.assertEqual(limine_text, self.initial_limine_conf)

        target_initramfs = self.fake_boot / "d539a1316b0543e0b082edcf8cffe442" / "linux-cachyos" / "initramfs"
        self.assertEqual(target_initramfs.read_text(encoding="utf-8"), self.initial_initramfs_data)


if __name__ == "__main__":
    unittest.main()
