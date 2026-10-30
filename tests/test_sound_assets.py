#!/usr/bin/env python3
"""Unit tests for sound assets: theme.json validation, duration < 700ms, peak amplitude & no clipping."""

import json
import subprocess
import tempfile
import unittest
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.sound_engine import get_repo_root, resolve_sound_file


class SoundAssetTests(unittest.TestCase):
    def setUp(self):
        self.repo_root = get_repo_root()
        self.default_theme_dir = self.repo_root / "assets" / "sounds" / "default"
        self.theme_json_path = self.default_theme_dir / "theme.json"
        self.licenses_path = self.repo_root / "assets" / "sounds" / "LICENSES.md"

    def test_licenses_file_exists(self):
        self.assertTrue(self.licenses_path.is_file(), "LICENSES.md must exist in assets/sounds/")
        text = self.licenses_path.read_text(encoding="utf-8")
        self.assertIn("CC0", text)
        self.assertIn("Third-Party", text)

    def test_theme_json_exists_and_valid(self):
        self.assertTrue(self.theme_json_path.is_file(), "theme.json must exist in assets/sounds/default/")
        with open(self.theme_json_path, "r", encoding="utf-8") as f:
            mapping = json.load(f)
        self.assertIsInstance(mapping, dict)

        required_events = [
            "notification",
            "critical",
            "notification-critical",
            "agent-permission",
            "agent-permission-reminder",
            "agent-done",
            "agent-error",
            "reminder",
            "download-done",
            "download-failed",
            "error",
            "tick",
            "shutter",
            "record-start",
            "record-stop",
            "lock",
            "unlock",
            "battery-low",
            "plug",
            "unplug",
            "device-connect",
            "device-disconnect",
            "dnd-on",
            "dnd-off",
        ]
        for ev in required_events:
            self.assertIn(ev, mapping, f"Event '{ev}' must be mapped in theme.json")
            target_file = self.default_theme_dir / mapping[ev]
            self.assertTrue(target_file.is_file(), f"Sound file '{mapping[ev]}' for '{ev}' must exist on disk")

    def test_sound_files_duration_and_no_clipping(self):
        """Measure every file via ffprobe/ffmpeg to verify duration < 700ms and peak <= 0 dBFS."""
        with open(self.theme_json_path, "r", encoding="utf-8") as f:
            mapping = json.load(f)

        unique_files = set(mapping.values())
        for fname in unique_files:
            fpath = self.default_theme_dir / fname
            self.assertTrue(fpath.is_file(), f"File {fpath} must exist")

            # Check duration via ffprobe
            probe_cmd = [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(fpath),
            ]
            res = subprocess.run(probe_cmd, capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL)
            duration_s = float(res.stdout.strip())
            self.assertLess(
                duration_s,
                0.700,
                f"File '{fname}' duration {duration_s*1000:.1f}ms exceeds 700ms limit!",
            )

            # Check peak volume via ffmpeg volumedetect filter
            vol_cmd = [
                "ffmpeg",
                "-nostdin",
                "-i",
                str(fpath),
                "-af",
                "volumedetect",
                "-f",
                "null",
                "-",
            ]
            vol_res = subprocess.run(vol_cmd, capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL)
            # Find max_volume: -X.X dB
            max_vol = None
            for line in vol_res.stderr.splitlines():
                if "max_volume:" in line:
                    # max_volume: -1.0 dB
                    parts = line.split("max_volume:")
                    val_str = parts[1].replace("dB", "").strip()
                    max_vol = float(val_str)
                    break

            self.assertIsNotNone(max_vol, f"Could not determine max_volume for '{fname}'")
            self.assertLessEqual(
                max_vol,
                0.0,
                f"File '{fname}' peak {max_vol} dBFS exceeds 0 dBFS (clipping)!",
            )

    def test_custom_theme_resolution_and_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            themes_root = Path(temp_dir)
            custom_theme = themes_root / "retro"
            custom_theme.mkdir(parents=True)
            (custom_theme / "retro_beep.ogg").write_bytes(b"dummy")
            (custom_theme / "theme.json").write_text(
                json.dumps({"notification": "retro_beep.ogg"}), encoding="utf-8"
            )

            # Copy default theme into themes_root
            default_dir = themes_root / "default"
            default_dir.mkdir(parents=True)
            (default_dir / "chime.ogg").write_bytes(b"dummy_default")
            (default_dir / "theme.json").write_text(
                json.dumps({"notification": "chime.ogg", "critical": "crit.ogg"}),
                encoding="utf-8",
            )
            (default_dir / "crit.ogg").write_bytes(b"dummy_crit")

            # Resolving 'notification' in retro should return retro_beep.ogg
            res_notif = resolve_sound_file("notification", theme_name="retro", themes_root=themes_root)
            self.assertIsNotNone(res_notif)
            self.assertEqual(res_notif.name, "retro_beep.ogg")

            # Resolving 'critical' in retro should fall back to default theme
            res_crit = resolve_sound_file("critical", theme_name="retro", themes_root=themes_root)
            self.assertIsNotNone(res_crit)
            self.assertEqual(res_crit.name, "crit.ogg")


if __name__ == "__main__":
    unittest.main()
