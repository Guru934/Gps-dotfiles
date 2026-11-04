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
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
LOCK_INFO_SCRIPT = SCRIPTS_DIR / "lock-info.sh"
LOCK_BG_SCRIPT = SCRIPTS_DIR / "gps-lock-bg"
LOCK_EXTRA_SCRIPT = SCRIPTS_DIR / "lock-extra.sh"
LOCK_AVATAR_SCRIPT = SCRIPTS_DIR / "gps-lock-avatar"
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
        self.assertIn("source = ~/.config/gps/lock-avatar.conf", content)

    def test_fallback_lock_bg_file_exists_in_repo(self):
        self.assertTrue(LOCK_BG_FALLBACK.is_file())

    def test_telemetry_chips_have_non_overlapping_gaps(self):
        """Verify the 4 telemetry chips (bat, net, kb, caps) do not overlap."""
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        # Extract chip positions and sizes in redesigned layout (1920x1200 canvas):
        # bat: center -847, width 130 -> [-912, -782]
        # net: center -637, width 270 -> [-772, -502]
        # kb:  center -447, width 90  -> [-492, -402]
        # caps:center -327, width 130 -> [-392, -262]
        self.assertIn("position = -847, 496", content)
        self.assertIn("size = 130, 34", content)
        self.assertIn("position = -637, 496", content)
        self.assertIn("size = 270, 34", content)
        self.assertIn("position = -447, 496", content)
        self.assertIn("size = 90, 34", content)
        self.assertIn("position = -327, 496", content)
        self.assertIn("size = 130, 34", content)

        # Check gaps mathematically
        bat_r = -847 + 65  # -782
        net_l = -637 - 135 # -772
        self.assertGreater(net_l, bat_r, "Gap between Battery and Net must be positive")

        net_r = -637 + 135 # -502
        kb_l = -447 - 45   # -492
        self.assertGreater(kb_l, net_r, "Gap between Net and Keyboard must be positive")

        kb_r = -447 + 45   # -402
        caps_l = -327 - 65 # -392
        self.assertGreater(caps_l, kb_r, "Gap between Keyboard and Caps must be positive")

    def test_media_card_layout_bounds(self):
        """Verify media card layout: title and volume within card boundaries."""
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertIn("text = cmd[update:3000] $info media-title", content)
        self.assertNotIn("text = cmd[update:3000] $info media-title --always", content)
        self.assertIn("text = cmd[update:3000] $info media-vol", content)


class LockAvatarLifecycleTests(unittest.TestCase):
    """Test suite ensuring gps-lock-avatar correctly manages avatar config and assets."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.fake_home = self.tmp_path / "home"
        self.fake_home.mkdir(parents=True, exist_ok=True)
        self.fake_config = self.tmp_path / "config"
        self.fake_cache = self.tmp_path / "cache"
        self.fake_config.mkdir(parents=True, exist_ok=True)
        self.fake_cache.mkdir(parents=True, exist_ok=True)
        self.conf_path = self.fake_config / "gps" / "lock-avatar.conf"

        self.env = {
            **os.environ,
            "HOME": str(self.fake_home),
            "USER": "gps_test_isolated_user",
            "XDG_CONFIG_HOME": str(self.fake_config),
            "XDG_CACHE_HOME": str(self.fake_cache),
            "GPS_LOCK_AVATAR_CONF": str(self.conf_path),
        }

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _run_avatar_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(LOCK_AVATAR_SCRIPT), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_default_execution_generates_default_avatar_and_config(self):
        res = self._run_avatar_tool()
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.conf_path.is_file())
        content = self.conf_path.read_text(encoding="utf-8")
        self.assertIn("$avatar =", content)
        avatar_path = Path(content.split("=", 1)[1].strip())
        self.assertTrue(avatar_path.is_file())
        self.assertEqual(avatar_path.name, "avatar-default.png")

    def test_symlink_at_config_path_is_unlinked_before_write_preserving_target(self):
        repo_like_dir = self.tmp_path / "repo"
        repo_like_dir.mkdir(parents=True, exist_ok=True)
        protected_target = repo_like_dir / "placeholder.conf"
        protected_target.write_text("# protected repository content\n", encoding="utf-8")

        self.conf_path.parent.mkdir(parents=True, exist_ok=True)
        self.conf_path.symlink_to(protected_target)

        res = self._run_avatar_tool()
        self.assertEqual(res.returncode, 0)
        self.assertTrue(self.conf_path.is_file())
        self.assertFalse(self.conf_path.is_symlink())
        self.assertEqual(protected_target.read_text(encoding="utf-8"), "# protected repository content\n")

    def test_user_avatar_png_is_preserved_and_used(self):
        gps_dir = self.fake_config / "gps"
        gps_dir.mkdir(parents=True, exist_ok=True)
        user_avatar = gps_dir / "avatar.png"
        user_avatar.write_bytes(b"\x89PNG\r\n\x1a\nfake_user_avatar")

        res = self._run_avatar_tool()
        self.assertEqual(res.returncode, 0)
        content = self.conf_path.read_text(encoding="utf-8")
        self.assertIn(str(user_avatar), content)
        self.assertTrue(user_avatar.exists())

    def test_set_and_clear_lifecycle(self):
        from PIL import Image
        src_img = self.tmp_path / "custom.png"
        img = Image.new("RGBA", (200, 100), color="blue")
        img.save(src_img)

        # --set
        res_set = self._run_avatar_tool("--set", str(src_img))
        self.assertEqual(res_set.returncode, 0)
        content = self.conf_path.read_text(encoding="utf-8")
        user_avatar = self.fake_config / "gps" / "avatar.png"
        self.assertIn(str(user_avatar), content)
        self.assertTrue(user_avatar.is_file())

        # Check square crop
        with Image.open(user_avatar) as loaded:
            self.assertEqual(loaded.size, (512, 512))

        # --clear
        res_clear = self._run_avatar_tool("--clear")
        self.assertEqual(res_clear.returncode, 0)
        self.assertFalse(user_avatar.exists())
        content_after = self.conf_path.read_text(encoding="utf-8")
        self.assertIn("avatar-default.png", content_after)

    def test_removes_legacy_hypr_symlink(self):
        legacy_dir = self.fake_config / "hypr"
        legacy_dir.mkdir(parents=True, exist_ok=True)
        legacy_link = legacy_dir / "lock-avatar.conf"
        target = self.tmp_path / "some_target"
        target.write_text("dummy", encoding="utf-8")
        legacy_link.symlink_to(target)

        res = self._run_avatar_tool()
        self.assertEqual(res.returncode, 0)
        self.assertFalse(legacy_link.exists() or legacy_link.is_symlink())


class LockExtraArtworkHardeningTests(unittest.TestCase):
    """Test suite ensuring lock-extra.sh handles media art URLs securely and reliably."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.mock_bin_dir = self.tmp_path / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir = self.tmp_path / "cache" / "gps"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self.env = {
            **os.environ,
            "PATH": f"{self.mock_bin_dir}:{os.environ.get('PATH', '')}",
            "XDG_CACHE_HOME": str(self.tmp_path / "cache"),
        }

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _create_mock_playerctl(self, art_url: str):
        mock_pc = self.mock_bin_dir / "playerctl"
        content = (
            f"#!/bin/sh\n"
            f"if [ \"$1\" = \"metadata\" ] && [ \"$2\" = \"mpris:artUrl\" ]; then\n"
            f"    printf '%s\\n' '{art_url}'\n"
            f"    exit 0\n"
            f"fi\n"
            f"exit 0\n"
        )
        mock_pc.write_text(content, encoding="utf-8")
        mock_pc.chmod(mock_pc.stat().st_mode | stat.S_IEXEC)

    def _run_lock_extra(self, action: str = "media-art") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(LOCK_EXTRA_SCRIPT), action],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_local_file_url_resolved_directly(self):
        local_art = self.tmp_path / "local art cover.png"
        local_art.write_bytes(b"\x89PNG\r\n\x1a\nlocal_cover")

        # URL with encoded spaces
        self._create_mock_playerctl(f"file://{local_art.as_posix().replace(' ', '%20')}")
        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), str(local_art))

    def test_insecure_http_url_rejected_and_falls_back(self):
        self._create_mock_playerctl("http://example.com/insecure-art.jpg")
        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        # Should fallback to art-default.png
        self.assertTrue(res.stdout.strip().endswith("art-default.png"))

    def test_failed_download_leaves_no_temp_files(self):
        # Mock curl that exits with an error
        mock_curl = self.mock_bin_dir / "curl"
        mock_curl.write_text("#!/bin/sh\nexit 28\n")
        mock_curl.chmod(mock_curl.stat().st_mode | stat.S_IEXEC)

        self._create_mock_playerctl("https://example.com/artwork.jpg")
        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        self.assertTrue(res.stdout.strip().endswith("art-default.png"))

        # Confirm no temporary files left in cache
        temp_files = list(self.cache_dir.glob("art-*.tmp.*"))
        self.assertEqual(temp_files, [])

    def test_oversized_artwork_is_not_cached(self):
        # Mock curl that produces a file exceeding 5MB or returns error
        mock_curl = self.mock_bin_dir / "curl"
        # Simulate curl failing due to --max-filesize flag
        mock_curl.write_text("#!/bin/sh\nexit 63\n")
        mock_curl.chmod(mock_curl.stat().st_mode | stat.S_IEXEC)

        self._create_mock_playerctl("https://example.com/huge-art.jpg")
        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        self.assertTrue(res.stdout.strip().endswith("art-default.png"))

        # No cache images or temp files created
        cached_imgs = list(self.cache_dir.glob("art-*.img"))
        self.assertEqual(cached_imgs, [])
        temp_files = list(self.cache_dir.glob("art-*.tmp.*"))
        self.assertEqual(temp_files, [])

    def test_invalid_image_content_rejected_and_not_cached(self):
        """Downloaded content that is not a valid image (no recognized magic bytes) is rejected."""
        mock_curl = self.mock_bin_dir / "curl"
        # Mock curl that writes non-image content (HTML error page)
        html_content = b"<html><body>404 Not Found</body></html>"
        mock_curl.write_text(
            "#!/bin/sh\n"
            "# Only handle -o (output file) argument\n"
            "outfile=''\n"
            "for arg in \"$@\"; do\n"
            "    case \"$prev\" in\n"
            "        -o) outfile=\"$arg\" ;;\n"
            "    esac\n"
            "    prev=\"$arg\"\n"
            "done\n"
            f"printf '%s' '{html_content.decode()}' > \"$outfile\"\n"
            "exit 0\n"
        )
        mock_curl.chmod(mock_curl.stat().st_mode | stat.S_IEXEC)

        self._create_mock_playerctl("https://example.com/fake-art.jpg")
        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        self.assertTrue(res.stdout.strip().endswith("art-default.png"))

        # Verify no .img or .tmp files left
        cached_imgs = list(self.cache_dir.glob("art-*.img"))
        self.assertEqual(cached_imgs, [])
        temp_files = list(self.cache_dir.glob("art-*.tmp.*"))
        self.assertEqual(temp_files, [])

    def test_valid_png_image_is_cached_successfully(self):
        """Downloaded content with valid PNG magic bytes is accepted and cached."""
        # Minimal valid PNG (1x1 transparent pixel)
        import base64
        png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQABNjN9GQAAAAlwSFlzAAAWJQAAFiUBSVIk8AAAAA0lEQVQI12P4z8BQDwAEgAF/pOOxfwAAAABJRU5ErkJggg=="
        png_bytes = base64.b64decode(png_b64)
        png_hex = png_bytes.hex()

        mock_curl = self.mock_bin_dir / "curl"
        # Write a mock curl that produces a real PNG file
        png_file = self.tmp_path / "valid.png"
        png_file.write_bytes(png_bytes)
        mock_curl.write_text(
            "#!/bin/sh\n"
            "outfile=''\n"
            "for arg in \"$@\"; do\n"
            "    case \"$prev\" in\n"
            "        -o) outfile=\"$arg\" ;;\n"
            "    esac\n"
            "    prev=\"$arg\"\n"
            "done\n"
            f"cp '{png_file}' \"$outfile\"\n"
            "exit 0\n"
        )
        mock_curl.chmod(mock_curl.stat().st_mode | stat.S_IEXEC)

        self._create_mock_playerctl("https://example.com/real-cover.png")
        # Ensure lock subdir exists for cache
        lock_cache = self.tmp_path / "cache" / "gps" / "lock"
        lock_cache.mkdir(parents=True, exist_ok=True)

        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        output = res.stdout.strip()
        # Should NOT fall back to art-default.png
        self.assertFalse(output.endswith("art-default.png"), f"Expected cached image, got fallback: {output}")
        # The cached file should exist and be a valid PNG
        self.assertTrue(Path(output).is_file())
        self.assertGreater(Path(output).stat().st_size, 0)

    def test_valid_jpeg_image_is_cached_successfully(self):
        """Downloaded content with valid JPEG magic bytes is accepted and cached."""
        # Minimal JPEG-ish content (valid magic header + padding)
        jpeg_bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 64

        mock_curl = self.mock_bin_dir / "curl"
        jpeg_file = self.tmp_path / "valid.jpg"
        jpeg_file.write_bytes(jpeg_bytes)
        mock_curl.write_text(
            "#!/bin/sh\n"
            "outfile=''\n"
            "for arg in \"$@\"; do\n"
            "    case \"$prev\" in\n"
            "        -o) outfile=\"$arg\" ;;\n"
            "    esac\n"
            "    prev=\"$arg\"\n"
            "done\n"
            f"cp '{jpeg_file}' \"$outfile\"\n"
            "exit 0\n"
        )
        mock_curl.chmod(mock_curl.stat().st_mode | stat.S_IEXEC)

        self._create_mock_playerctl("https://example.com/cover.jpg")
        lock_cache = self.tmp_path / "cache" / "gps" / "lock"
        lock_cache.mkdir(parents=True, exist_ok=True)

        res = self._run_lock_extra("media-art")
        self.assertEqual(res.returncode, 0)
        output = res.stdout.strip()
        self.assertFalse(output.endswith("art-default.png"), f"Expected cached JPEG, got fallback: {output}")
        self.assertTrue(Path(output).is_file())


if __name__ == "__main__":
    unittest.main()
