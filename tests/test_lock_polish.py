#!/usr/bin/env python3
"""Automated unit and integration tests for GPS lock visual polish, accurate volume,

and rotating backgrounds.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
LOCK_INFO_SCRIPT = SCRIPTS_DIR / "lock-info.sh"
LOCK_BG_SCRIPT = SCRIPTS_DIR / "gps-lock-bg"
HYPRLOCK_CONF = ROOT / "dots" / "hypr" / "hyprlock.conf"
LOCK_BG_FALLBACK = ROOT / "dots" / "hypr" / "lock-bg.conf"


class LockInfoVolumeTests(unittest.TestCase):
    """Test suite for accurate system volume extraction via lock-info.sh."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.mock_bin_dir = self.tmp_path / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _create_mock_wpctl(self, stdout: str, exit_code: int = 0):
        mock_wpctl = self.mock_bin_dir / "wpctl"
        content = f"#!/bin/sh\ncat << 'EOF'\n{stdout}\nEOF\nexit {exit_code}\n"
        mock_wpctl.write_text(content, encoding="utf-8")
        mock_wpctl.chmod(mock_wpctl.stat().st_mode | stat.S_IEXEC)

    def _run_lock_info(self, mode: str = "media-vol") -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "PATH": f"{self.mock_bin_dir}:{os.environ.get('PATH', '')}",
        }
        return subprocess.run(
            [str(LOCK_INFO_SCRIPT), mode],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_normal_output_volume(self):
        self._create_mock_wpctl("Volume: 0.26")
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "26% Volume")

    def test_vol_alias_behaves_identically(self):
        self._create_mock_wpctl("Volume: 0.75")
        res = self._run_lock_info("vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "75% Volume")

    def test_full_volume_100(self):
        self._create_mock_wpctl("Volume: 1.00")
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "100% Volume")

    def test_amplified_volume(self):
        self._create_mock_wpctl("Volume: 1.25")
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "125% Volume")

    def test_muted_volume_shows_muted(self):
        self._create_mock_wpctl("Volume: 0.45 [MUTED]")
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "45% (muted)")

    def test_muted_zero_volume(self):
        self._create_mock_wpctl("Volume: 0.00 [MUTED]")
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "0% (muted)")

    def test_wpctl_failure_exits_cleanly_without_crashing(self):
        self._create_mock_wpctl("Error: Connection refused", exit_code=1)
        res = self._run_lock_info("media-vol")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "")


class LockInfoMediaMetadataTests(unittest.TestCase):
    """Test suite for media metadata layout, truncation, and state handling in lock-info.sh."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.mock_bin_dir = self.tmp_path / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _create_mock_playerctl(self, status: str, title: str = "", artist: str = ""):
        mock_playerctl = self.mock_bin_dir / "playerctl"
        script = f"""#!/bin/sh
if [ "$1" = "status" ]; then
    echo "{status}"
    exit 0
fi
if [ "$1" = "metadata" ]; then
    if [ "$3" = "{{{{title}}}}" ]; then
        printf "%s\\n" "{title}"
        exit 0
    elif [ "$3" = "{{{{artist}}}}" ]; then
        printf "%s\\n" "{artist}"
        exit 0
    fi
fi
exit 0
"""
        mock_playerctl.write_text(script, encoding="utf-8")
        mock_playerctl.chmod(mock_playerctl.stat().st_mode | stat.S_IEXEC)

    def _run_lock_info(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "PATH": f"{self.mock_bin_dir}:{os.environ.get('PATH', '')}",
        }
        return subprocess.run(
            [str(LOCK_INFO_SCRIPT), *args],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_short_title_and_artist(self):
        self._create_mock_playerctl("Playing", title="Moonlight", artist="Beethoven")
        res_t = self._run_lock_info("media-title")
        self.assertEqual(res_t.returncode, 0)
        self.assertEqual(res_t.stdout.strip(), "Moonlight")

        res_a = self._run_lock_info("media-artist")
        self.assertEqual(res_a.returncode, 0)
        self.assertEqual(res_a.stdout.strip(), "Beethoven")

    def test_long_title_truncated_with_ellipsis(self):
        long_title = "This is a very long song title that should be truncated safely"
        self._create_mock_playerctl("Playing", title=long_title, artist="Someone")
        res = self._run_lock_info("media-title")
        self.assertEqual(res.returncode, 0)
        out = res.stdout.strip()
        self.assertTrue(out.endswith("…"), f"Expected ellipsis at end, got: {out}")
        self.assertLessEqual(len(out), 22, f"Length {len(out)} exceeds 22 characters: {out}")
        self.assertEqual(out, "This is a very long s…")

    def test_unicode_title_truncated_safely(self):
        unicode_title = "夜に駆ける - YOASOBI - 日本語タイトルテスト"
        self._create_mock_playerctl("Playing", title=unicode_title, artist="YOASOBI")
        res = self._run_lock_info("media-title")
        self.assertEqual(res.returncode, 0)
        out = res.stdout.strip()
        self.assertTrue(out.endswith("…"))
        self.assertLessEqual(len(out), 22)
        self.assertEqual(out, "夜に駆ける - YOASOBI - 日本語…")

    def test_paused_playback_shows_pause_indicator(self):
        self._create_mock_playerctl("Paused", title="Yesterday", artist="The Beatles")
        res_t = self._run_lock_info("media-title")
        self.assertEqual(res_t.returncode, 0)
        self.assertEqual(res_t.stdout.strip(), "⏸ Yesterday")

        res_a = self._run_lock_info("media-artist")
        self.assertEqual(res_a.returncode, 0)
        self.assertEqual(res_a.stdout.strip(), "The Beatles")

    def test_missing_metadata_handled_gracefully(self):
        self._create_mock_playerctl("Playing", title="", artist="")
        res_t = self._run_lock_info("media-title")
        self.assertEqual(res_t.returncode, 0)
        self.assertEqual(res_t.stdout.strip(), "Unknown Title")

        res_a = self._run_lock_info("media-artist")
        self.assertEqual(res_a.returncode, 0)
        self.assertEqual(res_a.stdout.strip(), "")

    def test_stopped_playback_optional_display(self):
        self._create_mock_playerctl("Stopped")
        res_t = self._run_lock_info("media-title")
        self.assertEqual(res_t.returncode, 0)
        self.assertEqual(res_t.stdout.strip(), "")

        res_a = self._run_lock_info("media-artist")
        self.assertEqual(res_a.returncode, 0)
        self.assertEqual(res_a.stdout.strip(), "")

    def test_stopped_playback_with_always_flag(self):
        self._create_mock_playerctl("Stopped")
        res_t = self._run_lock_info("media-title", "--always")
        self.assertEqual(res_t.returncode, 0)
        self.assertEqual(res_t.stdout.strip(), "Nothing playing")


class LockBackgroundRotationTests(unittest.TestCase):
    """Test suite for scripts/gps-lock-bg background rotation logic."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.collection_dir = self.tmp_path / "Lockscreen-Background"
        self.conf_path = self.tmp_path / "lock-bg.conf"
        self.state_path = self.tmp_path / "last-lock-bg.txt"

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _create_dummy_image(self, name: str) -> Path:
        self.collection_dir.mkdir(parents=True, exist_ok=True)
        img_path = self.collection_dir / name
        img_path.write_bytes(b"\x89PNG\r\n\x1a\nfakeimagecontent")
        return img_path

    def _run_bg_rotator(self, *args: str) -> subprocess.CompletedProcess[str]:
        cmd = [
            str(LOCK_BG_SCRIPT),
            "--dir", str(self.collection_dir),
            "--conf", str(self.conf_path),
            "--state", str(self.state_path),
            *args,
        ]
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_auto_creates_collection_directory(self):
        self.assertFalse(self.collection_dir.exists())
        res = self._run_bg_rotator()
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.collection_dir.is_dir())

    def test_supported_extensions_case_insensitive(self):
        img_png = self._create_dummy_image("wall1.PNG")
        img_jpg = self._create_dummy_image("wall2.jpg")
        img_jpeg = self._create_dummy_image("wall3.JPEG")
        img_webp = self._create_dummy_image("wall4.WebP")
        self._create_dummy_image("not_an_image.txt")
        self._create_dummy_image("script.sh")

        res = self._run_bg_rotator("--status")
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertEqual(data["total_images"], 4)

    def test_rotates_without_immediate_repeat(self):
        img1 = self._create_dummy_image("a.png")
        img2 = self._create_dummy_image("b.png")

        # Run 1: with seed 42
        res1 = self._run_bg_rotator("--seed", "42")
        self.assertEqual(res1.returncode, 0)
        first_selected = res1.stdout.strip()
        self.assertIn(first_selected, [str(img1), str(img2)])

        # Run 2: without repeat
        res2 = self._run_bg_rotator("--seed", "42")
        self.assertEqual(res2.returncode, 0)
        second_selected = res2.stdout.strip()
        self.assertNotEqual(first_selected, second_selected, "Consecutive run should pick a different image")

    def test_deterministic_mode(self):
        img1 = self._create_dummy_image("alpha.png")
        img2 = self._create_dummy_image("beta.png")

        res = self._run_bg_rotator("--deterministic")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), str(img1))

    def test_force_image_mode(self):
        img1 = self._create_dummy_image("alpha.png")
        img2 = self._create_dummy_image("beta.png")

        res = self._run_bg_rotator("--force", str(img2))
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), str(img2))
        self.assertIn(f"$wallpaper = {img2}", self.conf_path.read_text())

    def test_fallback_when_directory_is_empty(self):
        self.collection_dir.mkdir(parents=True, exist_ok=True)
        res = self._run_bg_rotator()
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.conf_path.exists())
        conf_content = self.conf_path.read_text()
        self.assertNotIn("$wallpaper = ", conf_content)
        self.assertIn("Retaining wallpaper from lock-colors.conf", conf_content)

    def test_paths_with_spaces_handled_safely(self):
        img_spaces = self._create_dummy_image("My Cool Wallpaper (1920x1080).png")
        res = self._run_bg_rotator()
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), str(img_spaces))
        conf_content = self.conf_path.read_text()
        self.assertIn(f"$wallpaper = {img_spaces}", conf_content)


class LockConfigurationLayoutTests(unittest.TestCase):
    """Test suite ensuring hyprlock.conf layout, chip alignment, and file inclusions."""

    def test_hyprlock_conf_exists_and_includes_sources(self):
        self.assertTrue(HYPRLOCK_CONF.is_file())
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertIn("source = ~/.config/hypr/lock-colors.conf", content)
        self.assertIn("source = ~/.config/hypr/lock-bg.conf", content)

    def test_fallback_lock_bg_file_exists_in_repo(self):
        self.assertTrue(LOCK_BG_FALLBACK.is_file())

    def test_telemetry_chips_have_non_overlapping_gaps(self):
        """Verify the 4 telemetry chips (bat, net, kb, caps) do not overlap."""
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        # Extract chip positions and sizes
        # In our refined config:
        # bat: center -509, width 110 -> [-564, -454]
        # net: center -366, width 160 -> [-446, -286]
        # kb:  center -242, width 72  -> [-278, -206]
        # caps:center -156, width 84  -> [-198, -114]
        self.assertIn("position = -509, 285", content)
        self.assertIn("size = 110, 22", content)
        self.assertIn("position = -366, 285", content)
        self.assertIn("size = 160, 22", content)
        self.assertIn("position = -242, 285", content)
        self.assertIn("size = 72, 22", content)
        self.assertIn("position = -156, 285", content)
        self.assertIn("size = 84, 22", content)

        # Check gaps mathematically
        bat_r = -509 + 55  # -454
        net_l = -366 - 80  # -446
        self.assertGreater(net_l, bat_r, "Gap between Battery and Net must be positive")

        net_r = -366 + 80  # -286
        kb_l = -242 - 36   # -278
        self.assertGreater(kb_l, net_r, "Gap between Net and Keyboard must be positive")

        kb_r = -242 + 36   # -206
        caps_l = -156 - 42 # -198
        self.assertGreater(caps_l, kb_r, "Gap between Keyboard and Caps must be positive")

    def test_media_card_layout_bounds(self):
        """Verify media card layout: title at left (max 22 chars), volume positioned at left 315."""
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertIn("text = cmd[update:3000] $info media-title", content)
        self.assertNotIn("text = cmd[update:3000] $info media-title --always", content)
        self.assertIn("position = 315, -358", content)


if __name__ == "__main__":
    unittest.main()
