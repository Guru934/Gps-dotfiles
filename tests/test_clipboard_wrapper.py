import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRAPPER_SCRIPT = ROOT / "scripts/gps-clip-store"


class GpsClipStoreWrapperTests(unittest.TestCase):
    """Verifies privacy filters, 1MB size limit, pause history, and graceful fallbacks in gps-clip-store."""

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.td.name)
        self.state_dir = self.temp_dir / ".local/state/gps"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.bin_dir = self.temp_dir / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)

        # Create mock cliphist recorder
        self.cliphist_log = self.temp_dir / "cliphist.log"
        self.mock_cliphist = self.bin_dir / "cliphist"
        self.mock_cliphist.write_text(
            f"""#!/bin/sh
cat >> "{self.cliphist_log}"
echo "STORED" >> "{self.cliphist_log}"
exit 0
""",
            encoding="utf-8"
        )
        self.mock_cliphist.chmod(0o755)

        # Create default mock wl-paste (normal mime types)
        self.mock_wl_paste = self.bin_dir / "wl-paste"
        self.mock_wl_paste.write_text(
            """#!/bin/sh
if [ "$1" = "--list-types" ]; then
    echo "text/plain"
    echo "UTF8_STRING"
    exit 0
fi
exit 0
""",
            encoding="utf-8"
        )
        self.mock_wl_paste.chmod(0o755)

        self.env = os.environ.copy()
        self.env["HOME"] = str(self.temp_dir)
        self.env["XDG_STATE_HOME"] = str(self.temp_dir / ".local/state")
        self.env["XDG_RUNTIME_DIR"] = str(self.temp_dir / "run")
        Path(self.env["XDG_RUNTIME_DIR"]).mkdir(parents=True, exist_ok=True)
        self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"

    def tearDown(self):
        self.td.cleanup()

    def test_normal_entry_is_stored(self):
        """Standard clipboard text under 1MB is forwarded to cliphist."""
        payload = b"Hello GPS Clipboard!"
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertTrue(self.cliphist_log.exists())
        self.assertIn("Hello GPS Clipboard!", self.cliphist_log.read_text(encoding="utf-8"))

    def test_paused_history_file_skips_storage(self):
        """When clipboard_paused flag file exists, nothing is stored."""
        (self.state_dir / "clipboard_paused").touch()
        payload = b"Should not be saved"
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertFalse(self.cliphist_log.exists())

    def test_paused_settings_json_skips_storage(self):
        """When clipboard_settings.json contains paused: true, nothing is stored."""
        settings_file = self.state_dir / "clipboard_settings.json"
        settings_file.write_text('{"version": 1, "paused": true}', encoding="utf-8")
        payload = b"Secret data"
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertFalse(self.cliphist_log.exists())

    def test_password_manager_mime_hint_skips_storage(self):
        """When clipboard carries x-kde-passwordManagerHint, entry is excluded from storage."""
        # Update mock wl-paste to advertise passwordManagerHint
        self.mock_wl_paste.write_text(
            """#!/bin/sh
if [ "$1" = "--list-types" ]; then
    echo "text/plain"
    echo "x-kde-passwordManagerHint"
    exit 0
fi
exit 0
""",
            encoding="utf-8"
        )
        payload = b"SuperSecretMasterPassword123"
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertFalse(self.cliphist_log.exists(), "Password manager data must never be saved to cliphist!")

    def test_entry_over_1mb_is_rejected(self):
        """Entries larger than 1 MB (1,048,576 bytes) are rejected."""
        large_payload = b"A" * (1024 * 1024 + 10)  # > 1 MB
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=large_payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertFalse(self.cliphist_log.exists(), "Payloads exceeding 1 MB must be dropped!")

    def test_entry_exactly_1mb_is_accepted(self):
        """Entries up to 1 MB (1,048,576 bytes) are accepted."""
        exact_payload = b"B" * (1024 * 1024)  # exactly 1 MB
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=exact_payload,
            env=self.env,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertTrue(self.cliphist_log.exists())
        self.assertEqual(len(self.cliphist_log.read_bytes()), 1024 * 1024 + len(b"STORED\n"))

    def test_missing_cliphist_graceful_exit(self):
        """If cliphist is not found in PATH, script exits cleanly with code 0."""
        env_no_cliphist = self.env.copy()
        # Remove bin_dir from PATH
        env_no_cliphist["PATH"] = "/usr/bin:/bin"
        # Temporarily mock cliphist as not executable or missing
        self.mock_cliphist.chmod(0o644)
        proc = subprocess.run(
            [str(WRAPPER_SCRIPT)],
            input=b"Some test text",
            env=env_no_cliphist,
            capture_output=True
        )
        self.assertEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
