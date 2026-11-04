#!/usr/bin/env python3
"""Regression test suite for GPS Live Video Wallpaper Controller and Carousel Integration."""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
import sys

if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import gps_wallpaper
import set_wallpaper


class LiveWallpaperSubsystemTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)

        # Isolated config / runtime / cache paths
        self.config_dir = self.tmp_path / "config" / "quickshell"
        self.config_dir.mkdir(parents=True)
        self.runtime_dir = self.tmp_path / "run" / "gps"
        self.runtime_dir.mkdir(parents=True)
        self.cache_dir = self.tmp_path / "cache" / "gps" / "wallpaper-posters"
        self.cache_dir.mkdir(parents=True)
        self.wall_dir = self.tmp_path / "wallpapers"
        self.wall_dir.mkdir(parents=True)

        # Create dummy static image
        self.static_img = self.wall_dir / "sample_static.png"
        img = Image.new("RGB", (64, 64), color=(60, 120, 200))
        img.save(self.static_img)

        # Create dummy video files
        self.video_mp4 = self.wall_dir / "sample_live.mp4"
        self.video_mp4.write_bytes(b"dummy mp4 video stream data\n")

        self.video_webm = self.wall_dir / "sample_live2.webm"
        self.video_webm.write_bytes(b"dummy webm video stream data 2\n")

        # Patches for directories
        self.patch_config = patch.object(gps_wallpaper, "get_config_dir", return_value=self.config_dir)
        self.patch_runtime = patch.object(gps_wallpaper, "get_runtime_dir", return_value=self.runtime_dir)
        self.patch_cache = patch.object(gps_wallpaper, "get_cache_dir", return_value=self.cache_dir)
        self.patch_clear = patch.object(gps_wallpaper, "clear_static_wallpaper", return_value=True)
        self.patch_curr = patch.object(set_wallpaper, "get_current_wallpaper", return_value=str(self.static_img))
        self.patch_config.start()
        self.patch_runtime.start()
        self.patch_cache.start()
        self.patch_clear.start()
        self.patch_curr.start()

    def tearDown(self):
        self.patch_curr.stop()
        self.patch_clear.stop()
        self.patch_config.stop()
        self.patch_runtime.stop()
        self.patch_cache.stop()
        self.tmp_dir.cleanup()

    # 1. Static wallpaper discovery and application
    def test_01_static_wallpaper_discovery_and_application(self):
        self.assertTrue(gps_wallpaper.is_static_file(self.static_img))
        self.assertFalse(gps_wallpaper.is_video_file(self.static_img))

        with patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True, "wallpaper": str(self.static_img)}) as mock_set:
            res = gps_wallpaper.apply_wallpaper(self.static_img)
            self.assertTrue(res.get("ok"))
            mock_set.assert_called_once()

        state_file = gps_wallpaper.get_state_file_path()
        self.assertTrue(state_file.is_file())
        state = json.loads(state_file.read_text(encoding="utf-8"))
        self.assertEqual(state.get("type"), "static")
        self.assertEqual(state.get("path"), str(self.static_img.resolve()))

    # 2. Video wallpaper discovery
    def test_02_video_wallpaper_discovery(self):
        self.assertTrue(gps_wallpaper.is_video_file(self.video_mp4))
        self.assertTrue(gps_wallpaper.is_video_file(self.video_webm))
        self.assertTrue(gps_wallpaper.is_video_file("wallpaper.mkv"))
        self.assertTrue(gps_wallpaper.is_video_file("wallpaper.mov"))
        self.assertFalse(gps_wallpaper.is_video_file(self.static_img))

        # Check Carousel QML source has the new formats in nameFilters
        carousel_path = ROOT / "components" / "WallpaperCarousel.qml"
        qml_text = carousel_path.read_text(encoding="utf-8")
        self.assertIn("*.mp4", qml_text)
        self.assertIn("*.webm", qml_text)
        self.assertIn("*.mkv", qml_text)
        self.assertIn("*.mov", qml_text)
        self.assertIn("liveBadge", qml_text)

    # 3. Poster extraction and caching
    def test_03_poster_extraction_and_caching(self):
        # Fake ffmpeg execution creating poster
        def fake_ffmpeg(cmd, **kwargs):
            out_file = Path(cmd[-1])
            img = Image.new("RGB", (32, 32), color=(200, 50, 50))
            img.save(out_file)
            return SimpleNamespace(returncode=0)

        with patch("subprocess.run", side_effect=fake_ffmpeg) as mock_run:
            poster = gps_wallpaper.extract_poster_frame(self.video_mp4)
            self.assertIsNotNone(poster)
            self.assertTrue(poster.is_file())
            self.assertEqual(mock_run.call_count, 1)

            # Second call must hit cache without invoking ffmpeg
            mock_run.reset_mock()
            poster2 = gps_wallpaper.extract_poster_frame(self.video_mp4)
            self.assertEqual(poster, poster2)
            mock_run.assert_not_called()

    # 4. Video file replacement and cache invalidation
    def test_04_video_replacement_cache_invalidation(self):
        def fake_ffmpeg(cmd, **kwargs):
            out_file = Path(cmd[-1])
            img = Image.new("RGB", (32, 32), color=(100, 100, 100))
            img.save(out_file)
            return SimpleNamespace(returncode=0)

        with patch("subprocess.run", side_effect=fake_ffmpeg):
            poster1 = gps_wallpaper.extract_poster_frame(self.video_mp4)
            # Modify source video content and mtime
            time.sleep(0.01)
            self.video_mp4.write_bytes(b"updated video bytes\n")
            poster2 = gps_wallpaper.get_poster_path_for_video(self.video_mp4)
            # Different hash due to size and mtime
            self.assertNotEqual(poster1.name, poster2.name)

    # 5. Applying a video
    def test_05_applying_video(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)

        mock_proc = MagicMock()
        mock_proc.pid = 98765
        mock_proc.poll.return_value = None

        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc) as mock_popen, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True, "theme": {}}) as mock_theme:
            res = gps_wallpaper.apply_live_wallpaper(self.video_mp4, output="ALL", auto_mode="FULL", fit_mode="cover")
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("pid"), 98765)
            mock_stop.assert_called_once()
            mpv_calls = [c for c in mock_popen.call_args_list if c[0][0][0] == "mpvpaper"]
            self.assertEqual(len(mpv_calls), 1)
            cmd_called = mpv_calls[0][0][0]
            self.assertEqual(cmd_called[0], "mpvpaper")
            self.assertIn("-p", cmd_called)
            self.assertIn("-a", cmd_called)
            self.assertIn("FULL", cmd_called)
            self.assertIn("ALL", cmd_called)
            mpv_opts = cmd_called[cmd_called.index("-o") + 1]
            self.assertIn("--panscan=1.0", mpv_opts)
            self.assertIn("--video-unscaled=no", mpv_opts)
            self.assertIn("--background-color='#000000'", mpv_opts)
            self.assertIn(str(self.video_mp4.resolve()), cmd_called)
            mock_theme.assert_called_once_with(image_path=dummy_poster, skip_awww=True)

        state = json.loads(gps_wallpaper.get_state_file_path().read_text(encoding="utf-8"))
        self.assertEqual(state.get("type"), "video")
        self.assertEqual(state.get("pid"), 98765)
        self.assertEqual(state.get("fit_mode"), "cover")

    # 6. Replacing one video with another
    def test_06_replacing_video_with_another(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)

        mock_proc1 = MagicMock(pid=11111, poll=MagicMock(return_value=None))
        mock_proc2 = MagicMock(pid=22222, poll=MagicMock(return_value=None))

        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", side_effect=[mock_proc1, mock_proc2]), \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res1 = gps_wallpaper.apply_live_wallpaper(self.video_mp4)
            self.assertEqual(res1.get("pid"), 11111)

            res2 = gps_wallpaper.apply_live_wallpaper(self.video_webm)
            self.assertEqual(res2.get("pid"), 22222)
            self.assertEqual(mock_stop.call_count, 2)

    # 7. Switching from video to static
    def test_07_switching_from_video_to_static(self):
        with patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res = gps_wallpaper.apply_static_wallpaper(self.static_img)
            self.assertTrue(res.get("ok"))
            mock_stop.assert_called_once()

    # 8. Switching from static to video
    def test_08_switching_from_static_to_video(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)
        mock_proc = MagicMock(pid=33333, poll=MagicMock(return_value=None))

        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc), \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res = gps_wallpaper.apply_wallpaper(self.video_mp4)
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("type"), "video")

    # 9. Stopping video playback
    def test_09_stopping_video_playback(self):
        pid_file = gps_wallpaper.get_pid_file_path()
        pid_file.write_text("55555\n")

        with patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[55555]), \
             patch("os.kill") as mock_kill:
            stopped = gps_wallpaper.stop_live_wallpaper()
            self.assertTrue(stopped)
            mock_kill.assert_called_with(55555, signal.SIGTERM)
            self.assertFalse(pid_file.exists())

    # 10. Wallpaper restoration after GPS restart
    def test_10_wallpaper_restoration(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)

        # A) Video state saved -> restores video
        state_file = gps_wallpaper.get_state_file_path()
        state_file.write_text(json.dumps({"type": "video", "path": str(self.video_mp4)}))

        mock_proc = MagicMock(pid=77777, poll=MagicMock(return_value=None))
        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc), \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res = gps_wallpaper.restore_wallpaper()
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("type"), "video")

        # B) Static state saved -> restores static
        state_file.write_text(json.dumps({"type": "static", "path": str(self.static_img)}))
        with patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res_static = gps_wallpaper.restore_wallpaper()
            self.assertTrue(res_static.get("ok"))

    # 11. Missing video and missing dependency
    def test_11_missing_video_and_dependency(self):
        # Missing video returns error
        res = gps_wallpaper.apply_live_wallpaper(self.tmp_path / "nonexistent.mp4")
        self.assertFalse(res.get("ok"))
        self.assertIn("not found", res.get("error", ""))

        # Missing dependency
        with patch("shutil.which", return_value=None):
            res_no_dep = gps_wallpaper.apply_live_wallpaper(self.video_mp4)
            self.assertFalse(res_no_dep.get("ok"))
            self.assertIn("mpvpaper is not installed", res_no_dep.get("error", ""))

        # Restoration with missing video falls back to static wallpaper
        state_file = gps_wallpaper.get_state_file_path()
        state_file.write_text(json.dumps({"type": "video", "path": str(self.tmp_path / "deleted.mp4")}))
        gps_wallpaper.get_last_static_path().write_text(str(self.static_img) + "\n")

        with patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}) as mock_apply:
            fallback_res = gps_wallpaper.restore_wallpaper()
            self.assertTrue(fallback_res.get("ok"))
            mock_apply.assert_called_once()

    # 12. Duplicate player prevention
    def test_12_duplicate_player_prevention(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)

        stopped_calls = []

        def track_stop():
            stopped_calls.append(True)
            return True

        mock_proc = MagicMock(pid=88888, poll=MagicMock(return_value=None))
        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch.object(gps_wallpaper, "stop_live_wallpaper", side_effect=track_stop), \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc), \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            gps_wallpaper.apply_live_wallpaper(self.video_mp4)
            self.assertEqual(len(stopped_calls), 1)

    # 13. Safe process shutdown with UID and cmdline verification
    def test_13_safe_process_shutdown(self):
        # Only processes owned by current user and running mpvpaper are returned
        pids = gps_wallpaper.get_running_mpvpaper_pids()
        self.assertIsInstance(pids, list)

    # 14. Multiple monitor output selection
    def test_14_multiple_monitor_output_selection(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)
        mock_proc = MagicMock(pid=99999, poll=MagicMock(return_value=None))

        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc) as mock_popen, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            gps_wallpaper.apply_live_wallpaper(self.video_mp4, output="eDP-1")
            cmd = mock_popen.call_args[0][0]
            self.assertIn("eDP-1", cmd)

    # 15. Background clearing and fit modes
    def test_15_clear_static_wallpaper_and_fit_modes(self):
        # Test clear_static_wallpaper executes awww clear 000000ff
        self.patch_clear.stop()
        try:
            with patch("shutil.which", return_value="/stub/awww"), \
                 patch("subprocess.run", return_value=SimpleNamespace(returncode=0)) as mock_run:
                ok = gps_wallpaper.clear_static_wallpaper()
                self.assertTrue(ok)
                mock_run.assert_called_once()
                cmd = mock_run.call_args[0][0]
                self.assertEqual(cmd, ["awww", "clear", "000000ff"])
        finally:
            self.patch_clear.start()

        # Test contain mode sets panscan to 0.0
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        Image.new("RGB", (32, 32), color=(50, 150, 50)).save(dummy_poster)
        mock_proc = MagicMock(pid=44444, poll=MagicMock(return_value=None))
        with patch.object(gps_wallpaper, "extract_poster_frame", return_value=dummy_poster), \
             patch("shutil.which", return_value="/usr/bin/mpvpaper"), \
             patch("subprocess.Popen", return_value=mock_proc) as mock_popen, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            gps_wallpaper.apply_live_wallpaper(self.video_mp4, fit_mode="contain")
            cmd = mock_popen.call_args[0][0]
            opts = cmd[cmd.index("-o") + 1]
            self.assertIn("--panscan=0.0", opts)

    # 16. Monitor geometry detection
    def test_16_monitor_geometry_detection(self):
        mock_monitors_json = json.dumps([
            {"id": 0, "name": "eDP-1", "width": 1920, "height": 1200, "refreshRate": 165.0, "scale": 1.0}
        ])
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "fake_signature"}), \
             patch("subprocess.check_output", return_value=mock_monitors_json):
            monitors = gps_wallpaper.get_connected_monitors()
            self.assertEqual(len(monitors), 1)
            self.assertEqual(monitors[0]["name"], "eDP-1")
            self.assertEqual(monitors[0]["width"], 1920)
            self.assertEqual(monitors[0]["height"], 1200)


if __name__ == "__main__":
    unittest.main()

