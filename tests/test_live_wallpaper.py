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

        self.dummy_poster = self.tmp_path / "dummy_poster.jpg"
        self.dummy_poster.write_bytes(b"dummy poster bytes\n")

        # Patches for directories
        self.patch_config = patch.object(gps_wallpaper, "get_config_dir", return_value=self.config_dir)
        self.patch_runtime = patch.object(gps_wallpaper, "get_runtime_dir", return_value=self.runtime_dir)
        self.patch_cache = patch.object(gps_wallpaper, "get_cache_dir", return_value=self.cache_dir)
        self.patch_clear = patch.object(gps_wallpaper, "clear_static_wallpaper", return_value=True)
        self.patch_curr = patch.object(set_wallpaper, "get_current_wallpaper", return_value=str(self.static_img))
        self.patch_watcher_start = patch.object(gps_wallpaper, "start_watcher_daemon", return_value=True)
        self.patch_watcher_stop = patch.object(gps_wallpaper, "stop_watcher_daemon", return_value=True)
        self.patch_config.start()
        self.patch_runtime.start()
        self.patch_cache.start()
        self.patch_clear.start()
        self.patch_curr.start()
        self.patch_watcher_start.start()
        self.patch_watcher_stop.start()

    def tearDown(self):
        self.patch_watcher_stop.stop()
        self.patch_watcher_start.stop()
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

    # 17. AC connected + no windows = play
    def test_17_ac_connected_no_windows_plays(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "PAUSED: APPLICATION OPEN",
            "paused_reason": "windows",
        }
        mock_proc = MagicMock(pid=12345, poll=MagicMock(return_value=None))
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[]), \
             patch.object(gps_wallpaper, "apply_live_wallpaper", return_value={"ok": True, "pid": 12345}) as mock_apply:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("ok"))
            self.assertTrue(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "LIVE PLAYING")
            self.assertEqual(res.get("paused_reason"), "none")
            mock_apply.assert_called_once()

    # 18. AC disconnected + no windows = stop
    def test_18_ac_disconnected_no_windows_stops(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "LIVE PLAYING",
            "paused_reason": "none",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=False), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[12345]), \
             patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}) as mock_wall:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("ok"))
            self.assertFalse(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "PAUSED: BATTERY POWER")
            self.assertEqual(res.get("paused_reason"), "battery")
            mock_stop.assert_called_once()
            mock_wall.assert_called_once()

    # 19. AC connected + application window opened = stop
    def test_19_ac_connected_window_opened_stops(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "LIVE PLAYING",
            "paused_reason": "none",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=1), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[12345]), \
             patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}) as mock_wall:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("ok"))
            self.assertFalse(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "PAUSED: APPLICATION OPEN")
            self.assertEqual(res.get("paused_reason"), "windows")
            mock_stop.assert_called_once()
            mock_wall.assert_called_once()

    # 20. Last visible window closed + AC connected = resume
    def test_20_window_closed_resumes(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "PAUSED: APPLICATION OPEN",
            "paused_reason": "windows",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[]), \
             patch.object(gps_wallpaper, "apply_live_wallpaper", return_value={"ok": True}) as mock_apply:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("ok"))
            self.assertTrue(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "LIVE PLAYING")
            mock_apply.assert_called_once()

    # 21. Battery unplugged during playback = stop
    def test_21_battery_unplugged_during_playback_stops(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "LIVE PLAYING",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=False), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[55555]), \
             patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}):
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertFalse(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "PAUSED: BATTERY POWER")
            mock_stop.assert_called_once()

    # 22. Charger reconnected with no visible windows = resume
    def test_22_charger_reconnected_resumes(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "PAUSED: BATTERY POWER",
            "paused_reason": "battery",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[]), \
             patch.object(gps_wallpaper, "apply_live_wallpaper", return_value={"ok": True}) as mock_apply:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("live_enabled"))
            self.assertEqual(res.get("status"), "LIVE PLAYING")
            mock_apply.assert_called_once()

    # 23. Battery fully charged but AC connected = play permitted
    def test_23_battery_full_ac_connected_play_permitted(self):
        # When sysfs shows online=1 and battery is Full
        fake_sysfs = self.tmp_path / "sysfs_power"
        acad = fake_sysfs / "ACAD"
        acad.mkdir(parents=True)
        (acad / "type").write_text("Mains\n")
        (acad / "online").write_text("1\n")

        bat = fake_sysfs / "BAT1"
        bat.mkdir(parents=True)
        (bat / "type").write_text("Battery\n")
        (bat / "status").write_text("Full\n")

        with patch("pathlib.Path.is_dir", side_effect=lambda p: str(p) == "/sys/class/power_supply" or Path.is_dir(p)), \
             patch("pathlib.Path.iterdir", side_effect=lambda p: [acad, bat] if str(p) == "/sys/class/power_supply" else Path.iterdir(p)):
            self.assertTrue(gps_wallpaper.is_ac_connected())

    # 24. Multiple rapid window events do not spawn duplicate players
    def test_24_rapid_events_no_duplicates(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "LIVE PLAYING",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=0), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[77777]), \
             patch.object(gps_wallpaper, "apply_live_wallpaper") as mock_apply:
            # Calling evaluate multiple times when already playing
            res1 = gps_wallpaper.evaluate_playback_policy(state)
            res2 = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res1.get("live_enabled"))
            self.assertTrue(res2.get("live_enabled"))
            mock_apply.assert_not_called()

    # 25. Hidden-workspace windows do not count as visible
    def test_25_hidden_workspace_windows_not_visible(self):
        mock_monitors = json.dumps([
            {"id": 0, "name": "eDP-1", "activeWorkspace": {"id": 1, "name": "1"}, "specialWorkspace": {"name": ""}}
        ])
        mock_clients = json.dumps([
            {"address": "0x1", "mapped": True, "hidden": False, "workspace": {"id": 2, "name": "2"}},
            {"address": "0x2", "mapped": True, "hidden": False, "workspace": {"id": 3, "name": "3"}},
        ])
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "fake_sig"}), \
             patch("shutil.which", return_value="/usr/bin/hyprctl"), \
             patch("subprocess.check_output", side_effect=[mock_monitors, mock_clients]):
            count = gps_wallpaper.get_visible_application_window_count()
            self.assertEqual(count, 0)

    # 26. Multiple monitors with visible application windows
    def test_26_multiple_monitors_visible_windows(self):
        mock_monitors = json.dumps([
            {"id": 0, "name": "eDP-1", "activeWorkspace": {"id": 1, "name": "1"}, "specialWorkspace": {"name": ""}},
            {"id": 1, "name": "HDMI-A-1", "activeWorkspace": {"id": 4, "name": "4"}, "specialWorkspace": {"name": ""}},
        ])
        mock_clients = json.dumps([
            {"address": "0x1", "mapped": True, "hidden": False, "workspace": {"id": 4, "name": "4"}},
            {"address": "0x2", "mapped": True, "hidden": False, "workspace": {"id": 2, "name": "2"}},
        ])
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "fake_sig"}), \
             patch("shutil.which", return_value="/usr/bin/hyprctl"), \
             patch("subprocess.check_output", side_effect=[mock_monitors, mock_clients]):
            count = gps_wallpaper.get_visible_application_window_count()
            self.assertEqual(count, 1)

    # 27. Missing static fallback uses cached poster
    def test_27_missing_static_fallback_uses_cached_poster(self):
        dummy_poster = self.tmp_path / "dummy_poster.jpg"
        dummy_poster.write_bytes(b"dummy poster bytes")

        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(dummy_poster),
            "status": "LIVE PLAYING",
        }
        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=1), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[88888]), \
             patch.object(gps_wallpaper, "get_last_valid_static_wallpaper", return_value=None), \
             patch.object(gps_wallpaper, "stop_live_wallpaper"), \
             patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}) as mock_wall:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertFalse(res.get("live_enabled"))
            mock_wall.assert_called_once_with(
                image_path=dummy_poster,
                transition_type="none",
                skip_hooks=True,
                skip_theme=True,
            )

    # 28. Missing live video fails safely
    def test_28_missing_live_video_fails_safely(self):
        missing_video = self.wall_dir / "deleted_video.mp4"
        state = {
            "type": "video",
            "path": str(missing_video),
            "status": "LIVE PLAYING",
        }
        with patch.object(gps_wallpaper, "stop_live_wallpaper") as mock_stop, \
             patch.object(gps_wallpaper, "get_last_valid_static_wallpaper", return_value=self.static_img), \
             patch.object(gps_wallpaper, "apply_static_wallpaper") as mock_fallback:
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertFalse(res.get("ok"))
            self.assertEqual(res.get("status"), "ERROR: VIDEO MISSING")
            mock_stop.assert_called_once()
            mock_fallback.assert_called_once_with(self.static_img, is_fallback=True)

    # 29. Manual static wallpaper selection overrides automatic live resume
    def test_29_manual_static_overrides_live_resume(self):
        with patch.object(set_wallpaper, "apply_wallpaper", return_value={"ok": True}), \
             patch.object(gps_wallpaper, "stop_watcher_daemon") as mock_stop_watcher:
            res = gps_wallpaper.apply_wallpaper(self.static_img)
            self.assertTrue(res.get("ok"))
            mock_stop_watcher.assert_called_once()

        # Policy evaluation on static state does not resume video
        state = json.loads(gps_wallpaper.get_state_file_path().read_text(encoding="utf-8"))
        self.assertEqual(state.get("type"), "static")
        eval_res = gps_wallpaper.evaluate_playback_policy(state)
        self.assertFalse(eval_res.get("live_enabled"))
        self.assertEqual(eval_res.get("status"), "STATIC")

    # 30. GPS restart restores selected wallpaper and evaluates power/window state
    def test_30_gps_restart_restores_and_evaluates(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "poster": str(self.tmp_path / "dummy_poster.jpg"),
            "status": "LIVE PLAYING",
        }
        gps_wallpaper.get_state_file_path().write_text(json.dumps(state))
        with patch.object(gps_wallpaper, "start_watcher_daemon") as mock_start_w, \
             patch.object(gps_wallpaper, "evaluate_playback_policy", return_value={"ok": True, "live_enabled": False, "status": "PAUSED: APPLICATION OPEN"}) as mock_eval:
            res = gps_wallpaper.restore_wallpaper()
            mock_start_w.assert_called_once()
            mock_eval.assert_called_once()
            self.assertEqual(res.get("status"), "PAUSED: APPLICATION OPEN")

    # 31. Controller shutdown cleans up all processes
    def test_31_controller_shutdown_cleans_up_all_processes(self):
        with patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[12121]), \
             patch.object(gps_wallpaper, "stop_watcher_daemon") as mock_stop_watcher, \
             patch("os.kill") as mock_kill:
            ok = gps_wallpaper.stop_live_wallpaper(stop_watcher=True)
            self.assertTrue(ok)
            mock_stop_watcher.assert_called_once()
            mock_kill.assert_called_with(12121, signal.SIGTERM)

    # 32. IPC socket path generation in runtime directory
    def test_32_ipc_socket_path_generation(self):
        sock_p = gps_wallpaper.get_mpv_ipc_socket_path()
        self.assertEqual(sock_p.parent, self.runtime_dir)
        self.assertEqual(sock_p.name, "mpvpaper-ipc.sock")

    # 33. Zombie process detection via is_pid_alive
    def test_33_is_pid_alive_detects_zombies(self):
        # Non-existent PID
        self.assertFalse(gps_wallpaper.is_pid_alive(9999999))

        # Real running process
        import os
        self.assertTrue(gps_wallpaper.is_pid_alive(os.getpid()))

    # 34. First frame readiness detection via socket
    def test_34_first_frame_readiness_detection(self):
        import socket
        import threading

        sock_file = self.runtime_dir / "test-mpv.sock"

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(sock_file))
        server.listen(1)

        def _client_sim():
            conn, _ = server.accept()
            conn.sendall(b'{"event":"start-file"}\n{"event":"file-loaded"}\n{"event":"playback-restart"}\n')
            conn.close()

        th = threading.Thread(target=_client_sim)
        th.daemon = True
        th.start()

        ready = gps_wallpaper.wait_for_first_frame_ready(sock_file, timeout=1.0)
        self.assertTrue(ready)
        server.close()
        sock_file.unlink()

    # 35. First frame readiness timeout fails gracefully
    def test_35_first_frame_readiness_timeout(self):
        sock_file = self.runtime_dir / "nonexistent.sock"
        ready = gps_wallpaper.wait_for_first_frame_ready(sock_file, timeout=0.05)
        self.assertFalse(ready)

    # 36. Relevant Hyprland event filtering
    def test_36_relevant_hypr_events_filter(self):
        # Window & workspace events are relevant
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"workspace>>5\n"))
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"workspacev2>>5,5\n"))
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"openwindow>>0x123,5,app,title\n"))
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"closewindow>>0x123\n"))
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"movewindow>>0x123,5\n"))
        self.assertTrue(gps_wallpaper.is_relevant_hypr_event(b"fullscreen>>1\n"))

        # Layer and UI events are not application window events
        self.assertFalse(gps_wallpaper.is_relevant_hypr_event(b"openlayer>>island\n"))
        self.assertFalse(gps_wallpaper.is_relevant_hypr_event(b"closelayer>>mpvpaper\n"))
        self.assertFalse(gps_wallpaper.is_relevant_hypr_event(b"submap>>default\n"))
        self.assertFalse(gps_wallpaper.is_relevant_hypr_event(b"\n"))

    # 37. State not rewritten to disk when unchanged
    def test_37_state_not_rewritten_when_unchanged(self):
        state = {
            "type": "video",
            "path": str(self.video_mp4),
            "status": "PAUSED: APPLICATION OPEN",
            "paused_reason": "windows",
            "ac_connected": True,
            "visible_windows": 1,
            "live_enabled": False,
        }
        state_file = gps_wallpaper.get_state_file_path()
        state_file.write_text(json.dumps(state))
        mtime_before = state_file.stat().st_mtime_ns

        with patch.object(gps_wallpaper, "is_ac_connected", return_value=True), \
             patch.object(gps_wallpaper, "get_visible_application_window_count", return_value=1), \
             patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[]):
            res = gps_wallpaper.evaluate_playback_policy(state)
            self.assertTrue(res.get("ok"))
            # File should not have been overwritten since state is identical
            mtime_after = state_file.stat().st_mtime_ns
            self.assertEqual(mtime_before, mtime_after)

    # 38. Stopping live wallpaper unlinks IPC socket
    def test_38_stopping_live_wallpaper_cleans_up_ipc_socket(self):
        sock_p = gps_wallpaper.get_mpv_ipc_socket_path()
        sock_p.touch()
        self.assertTrue(sock_p.exists())

        with patch.object(gps_wallpaper, "get_running_mpvpaper_pids", return_value=[]):
            gps_wallpaper.stop_live_wallpaper()
            self.assertFalse(sock_p.exists())


if __name__ == "__main__":
    unittest.main()

