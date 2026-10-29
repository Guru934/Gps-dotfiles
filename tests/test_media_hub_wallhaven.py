import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
import urllib.error
from argparse import Namespace
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts/media-hub-wallhaven.py"
SPEC = importlib.util.spec_from_file_location("media_hub_wallhaven", HELPER)
wallhaven = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wallhaven)


def raw_wallpaper(**overrides):
    wallpaper = {
        "id": "3q7mry",
        "url": "https://wallhaven.cc/w/3q7mry",
        "path": "https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg",
        "dimension_x": 2560,
        "dimension_y": 1600,
        "resolution": "2560x1600",
        "ratio": "1.6",
        "category": "anime",
        "file_size": 5242880,
        "created_at": "2026-10-01 12:30:00",
        "favorites": 321,
        "colors": ["#663399", "#0099cc"],
        "thumbs": {
            "large": "https://th.wallhaven.cc/lg/3q/3q7mry.jpg",
            "original": "https://th.wallhaven.cc/orig/3q/3q7mry.jpg",
        },
    }
    wallpaper.update(overrides)
    return wallpaper


def search_args(**overrides):
    values = {
        "query": "",
        "category": "all",
        "sorting": "relevance",
        "order": "desc",
        "atleast": "",
        "ratios": "",
        "color": "",
        "page": 1,
        "seed": "",
    }
    values.update(overrides)
    return Namespace(**values)


class FakeResponse:
    def __init__(self, body, headers=None, status=200, url="https://wallhaven.cc/"):
        self.body = body
        self.headers = headers or {}
        self.status = status
        self.url = url

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def geturl(self):
        return self.url

    def read(self, amount=-1):
        if amount < 0:
            body, self.body = self.body, b""
            return body
        body, self.body = self.body[:amount], self.body[amount:]
        return body


class WallhavenNormalizationTests(unittest.TestCase):
    def test_normalizes_only_trusted_https_assets(self):
        result = wallhaven.normalize_wallpaper(raw_wallpaper())
        self.assertEqual(result["id"], "3q7mry")
        self.assertEqual(result["title"], "Anime wallpaper · 3Q7MRY")
        self.assertEqual(result["source"], "https://wallhaven.cc/w/3q7mry")
        self.assertEqual(result["thumb"], "https://th.wallhaven.cc/lg/3q/3q7mry.jpg")
        self.assertEqual(result["ratio"], "16:10")
        self.assertEqual(result["size"], "5.0 MB")
        self.assertEqual(result["tags"], [])
        self.assertEqual(result["colors"], ["#663399", "#0099cc"])

    def test_rejects_untrusted_or_missing_full_image(self):
        self.assertIsNone(wallhaven.normalize_wallpaper(raw_wallpaper(path="https://example.com/a.jpg")))
        self.assertIsNone(wallhaven.normalize_wallpaper(raw_wallpaper(path="")))
        self.assertIsNone(wallhaven.normalize_wallpaper(None))

    def test_https_url_rejects_credentials_ports_and_wrong_scheme(self):
        allowed = {"w.wallhaven.cc"}
        self.assertEqual(wallhaven.https_url("https://w.wallhaven.cc/a.jpg", allowed),
                         "https://w.wallhaven.cc/a.jpg")
        self.assertEqual(wallhaven.https_url("http://w.wallhaven.cc/a.jpg", allowed), "")
        self.assertEqual(wallhaven.https_url("https://user:pass@w.wallhaven.cc/a.jpg", allowed), "")
        self.assertEqual(wallhaven.https_url("https://w.wallhaven.cc:8443/a.jpg", allowed), "")
        self.assertEqual(wallhaven.https_url("https://w.wallhaven.cc:bad/a.jpg", allowed), "")
        self.assertEqual(wallhaven.https_url("https://th.wallhaven.cc/a.jpg", allowed), "")
        self.assertEqual(wallhaven.https_url("https://w.wallhaven.cc/a.jpg\nX", allowed), "")

    def test_untrusted_metadata_text_is_sanitized(self):
        result = wallhaven.normalize_wallpaper(raw_wallpaper(
            category="<b>anime</b>", resolution="<script>alert(1)</script>"))
        self.assertEqual(result["category"], "General")
        self.assertEqual(result["title"], "General wallpaper · 3Q7MRY")
        self.assertEqual(result["res"], "2560×1600")


class WallhavenNetworkTests(unittest.TestCase):
    def test_http_errors_and_timeouts_are_classified(self):
        cases = [
            (urllib.error.HTTPError("https://wallhaven.cc", 429, "rate limited", {}, None),
             "rate_limited"),
            (urllib.error.HTTPError("https://wallhaven.cc", 503, "unavailable", {}, None),
             "http_error"),
            (TimeoutError("slow"), "network_error"),
        ]
        for error, code in cases:
            with self.subTest(code=code):
                with patch.object(wallhaven.urllib.request, "urlopen", side_effect=error):
                    with self.assertRaises(wallhaven.BridgeError) as raised:
                        wallhaven.request_json("https://wallhaven.cc/api/v1/search")
                self.assertEqual(raised.exception.code, code)

    def test_malformed_and_oversized_json_are_rejected(self):
        malformed = FakeResponse(b"not-json")
        with patch.object(wallhaven.urllib.request, "urlopen", return_value=malformed):
            with self.assertRaises(wallhaven.BridgeError) as raised:
                wallhaven.request_json("https://wallhaven.cc/api/v1/search")
        self.assertEqual(raised.exception.code, "invalid_response")

        oversized = FakeResponse(b"{}" + b"x" * 32)
        with patch.object(wallhaven, "MAX_JSON_BYTES", 16), \
             patch.object(wallhaven.urllib.request, "urlopen", return_value=oversized):
            with self.assertRaises(wallhaven.BridgeError) as raised:
                wallhaven.request_json("https://wallhaven.cc/api/v1/search")
        self.assertEqual(raised.exception.code, "invalid_response")

    def test_invalid_search_metadata_does_not_escape_as_traceback(self):
        payload = {"data": [], "meta": {"current_page": 1, "last_page": "many", "total": 0}}
        with patch.object(wallhaven, "request_json", return_value=payload):
            with self.assertRaises(wallhaven.BridgeError) as raised:
                wallhaven.search(search_args())
        self.assertEqual(raised.exception.code, "invalid_response")


class WallhavenSearchTests(unittest.TestCase):
    def test_empty_relevance_becomes_toplist_and_forces_sfw_purity(self):
        payload = {
            "data": [raw_wallpaper()],
            "meta": {"current_page": 1, "last_page": 2, "total": 25, "seed": None},
        }
        with patch.object(wallhaven, "request_json", return_value=payload) as request:
            result = wallhaven.search(search_args(query="  cyberpunk   neon  "))
        url = request.call_args.args[0]
        params = parse_qs(urlsplit(url).query)
        self.assertEqual(params["purity"], ["100"])
        self.assertEqual(params["sorting"], ["relevance"])
        self.assertEqual(params["q"], ["cyberpunk neon"])
        self.assertEqual(result["results"][0]["id"], "3q7mry")
        self.assertEqual(result["lastPage"], 2)

        with patch.object(wallhaven, "request_json", return_value=payload) as request:
            wallhaven.search(search_args())
        params = parse_qs(urlsplit(request.call_args.args[0]).query)
        self.assertEqual(params["sorting"], ["toplist"])
        self.assertNotIn("q", params)

    def test_search_forwards_validated_filters(self):
        payload = {"data": [], "meta": {"current_page": 2, "last_page": 4, "total": 80}}
        args = search_args(atleast="2560x1440", ratios="16x10,16x9", color="663399",
                           page=2, sorting="random", seed="a1b2c3")
        with patch.object(wallhaven, "request_json", return_value=payload) as request:
            wallhaven.search(args)
        params = parse_qs(urlsplit(request.call_args.args[0]).query)
        self.assertEqual(params["atleast"], ["2560x1440"])
        self.assertEqual(params["ratios"], ["16x10,16x9"])
        self.assertEqual(params["colors"], ["663399"])
        self.assertEqual(params["page"], ["2"])
        self.assertEqual(params["seed"], ["a1b2c3"])

    def test_unsupported_filters_fail_before_network_access(self):
        cases = [
            {"atleast": "1920"},
            {"ratios": "4x3"},
            {"color": "000000"},
            {"category": "unknown"},
            {"sorting": "unknown"},
            {"seed": "../bad", "sorting": "random"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                with patch.object(wallhaven, "request_json") as request:
                    with self.assertRaises(wallhaven.BridgeError):
                        wallhaven.search(search_args(**overrides))
                    request.assert_not_called()


class WallhavenDownloadTests(unittest.TestCase):
    URL = "https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg"

    def image_response(self, body, declared_length=None):
        return FakeResponse(body, headers={
            "Content-Type": "image/jpeg",
            "Content-Length": str(len(body) if declared_length is None else declared_length),
        }, url=self.URL)

    def test_incomplete_download_never_becomes_a_cached_image(self):
        body = b"\xff\xd8\xff\xe0" + b"valid-jpeg-body" * 4
        response = self.image_response(body, declared_length=len(body) + 50)
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CACHE_HOME": tmp}), \
             patch.object(wallhaven.urllib.request, "urlopen", return_value=response):
            with self.assertRaises(wallhaven.BridgeError) as raised:
                wallhaven.ensure_image("3q7mry", self.URL)
            cache = Path(tmp) / "gps-media-hub" / "wallhaven"
            self.assertEqual(raised.exception.code, "incomplete_download")
            self.assertEqual(list(cache.glob("*.jpg")), [])
            self.assertEqual(list(cache.glob("*.part")), [])

    def test_complete_download_is_cached_and_reused_without_duplicate_request(self):
        body = b"\xff\xd8\xff\xe0" + b"valid-jpeg-body" * 4
        response = self.image_response(body)
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CACHE_HOME": tmp}), \
             patch.object(wallhaven.urllib.request, "urlopen", return_value=response) as urlopen:
            first, first_cached = wallhaven.ensure_image("3q7mry", self.URL)
            second, second_cached = wallhaven.ensure_image("3q7mry", self.URL)
            self.assertFalse(first_cached)
            self.assertTrue(second_cached)
            self.assertEqual(first, second)
            self.assertEqual(first.read_bytes(), body)
            self.assertEqual(urlopen.call_count, 1)

    def test_untrusted_filenames_and_relative_cache_roots_are_rejected(self):
        with self.assertRaises(wallhaven.BridgeError) as raised:
            wallhaven.ensure_image("3q7mry", "https://w.wallhaven.cc/full/3q/wallhaven-other.jpg")
        self.assertEqual(raised.exception.code, "invalid_url")
        with patch.dict(os.environ, {"XDG_CACHE_HOME": "relative/cache"}):
            with self.assertRaises(wallhaven.BridgeError) as raised:
                wallhaven.cache_root()
        self.assertEqual(raised.exception.code, "invalid_cache")


class WallhavenLibraryTests(unittest.TestCase):
    URL = "https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg"
    VALID_JPG = b"\xff\xd8\xff\xe0" + b"valid-jpeg-body" * 4

    def image_response(self, body, declared_length=None):
        return FakeResponse(body, headers={
            "Content-Type": "image/jpeg",
            "Content-Length": str(len(body) if declared_length is None else declared_length),
        }, url=self.URL)

    def test_new_save_creates_permanent_copy_in_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            lib_dir = Path(tmp) / "library"
            cache_dir = Path(tmp) / "cache"
            response = self.image_response(self.VALID_JPG)
            with patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir), "XDG_CACHE_HOME": str(cache_dir)}), \
                 patch.object(wallhaven.urllib.request, "urlopen", return_value=response):
                path, cached = wallhaven.save_to_library("3q7mry", self.URL)
            self.assertEqual(path, lib_dir / "wallhaven-3q7mry.jpg")
            self.assertTrue(path.is_file())
            self.assertEqual(path.read_bytes(), self.VALID_JPG)
            self.assertFalse(cached)

    def test_duplicate_save_reuses_existing_library_file_without_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            lib_dir = Path(tmp) / "library"
            lib_dir.mkdir(parents=True)
            existing = lib_dir / "wallhaven-3q7mry.jpg"
            existing.write_bytes(self.VALID_JPG)
            with patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir)}), \
                 patch.object(wallhaven.urllib.request, "urlopen") as mock_url:
                path, cached = wallhaven.save_to_library("3q7mry", self.URL)
            self.assertEqual(path, existing)
            self.assertTrue(cached)
            self.assertEqual(mock_url.call_count, 0)

    def test_invalid_file_is_rejected_and_never_leaves_partial_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            lib_dir = Path(tmp) / "library"
            cache_dir = Path(tmp) / "cache"
            response = self.image_response(b"<html>error</html>")
            with patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir), "XDG_CACHE_HOME": str(cache_dir)}), \
                 patch.object(wallhaven.urllib.request, "urlopen", return_value=response):
                with self.assertRaises(wallhaven.BridgeError) as raised:
                    wallhaven.save_to_library("3q7mry", self.URL)
            self.assertEqual(raised.exception.code, "invalid_image")
            self.assertFalse((lib_dir / "wallhaven-3q7mry.jpg").exists())
            self.assertEqual(list(lib_dir.glob("*.part")), [])

    def test_missing_directory_is_created_automatically(self):
        with tempfile.TemporaryDirectory() as tmp:
            lib_dir = Path(tmp) / "nested" / "Pictures" / "Wallpapers"
            cache_dir = Path(tmp) / "cache"
            self.assertFalse(lib_dir.exists())
            response = self.image_response(self.VALID_JPG)
            with patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir), "XDG_CACHE_HOME": str(cache_dir)}), \
                 patch.object(wallhaven.urllib.request, "urlopen", return_value=response):
                path, _ = wallhaven.save_to_library("3q7mry", self.URL)
            self.assertTrue(lib_dir.is_dir())
            self.assertTrue(path.is_file())
            self.assertEqual(path, lib_dir / "wallhaven-3q7mry.jpg")
            self.assertEqual(path.read_bytes(), self.VALID_JPG)


class WallhavenApplyTests(unittest.TestCase):
    def test_apply_uses_fixed_awww_command_and_records_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "3q7mry.jpg"
            image.write_bytes(b"\xff\xd8\xfftest")
            lib_dir = Path(tmp) / "Wallpapers"
            args = Namespace(id="3q7mry", path="https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg",
                             title="Example")
            run = unittest.mock.MagicMock(return_value=SimpleNamespace(returncode=0, stdout="", stderr=""))
            with patch.object(wallhaven, "ensure_image", return_value=(image, True)), \
                 patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir)}), \
                 patch.object(wallhaven, "ensure_awww_daemon"), \
                 patch.object(wallhaven.subprocess, "run", run), \
                 patch.object(wallhaven, "last_wall_path", return_value=Path(tmp) / "gps-last-wall.txt"):
                result = wallhaven.apply_wallpaper(args)
            command = run.call_args.args[0]
            self.assertEqual(command[:2], ["awww", "img"])
            self.assertIn("--transition-type", command)
            expected_target = str(lib_dir / "wallhaven-3q7mry.jpg")
            self.assertEqual(result["path"], expected_target)
            self.assertTrue(result["cached"])
            self.assertEqual((Path(tmp) / "gps-last-wall.txt").read_text(), expected_target)

    def test_apply_failure_does_not_record_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "3q7mry.jpg"
            image.write_bytes(b"\xff\xd8\xfftest")
            lib_dir = Path(tmp) / "Wallpapers"
            args = Namespace(id="3q7mry", path="https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg",
                             title="Example")
            run = unittest.mock.MagicMock(return_value=SimpleNamespace(returncode=1, stdout="", stderr="rejected"))
            with patch.object(wallhaven, "ensure_image", return_value=(image, True)), \
                 patch.dict(os.environ, {"GPS_WALLPAPER_DIR": str(lib_dir)}), \
                 patch.object(wallhaven, "ensure_awww_daemon"), \
                 patch.object(wallhaven.subprocess, "run", run), \
                 patch.object(wallhaven, "last_wall_path", return_value=Path(tmp) / "gps-last-wall.txt"):
                with self.assertRaises(wallhaven.BridgeError):
                    wallhaven.apply_wallpaper(args)
            self.assertFalse((Path(tmp) / "gps-last-wall.txt").exists())


class MediaHubContractTests(unittest.TestCase):
    def test_window_is_a_normal_single_toplevel(self):
        window = (ROOT / "components/MediaHubWindow.qml").read_text()
        self.assertIn("FloatingWindow {", window)
        self.assertNotIn("WlrLayershell", window)
        self.assertNotIn("PanelWindow", window)
        self.assertIn('title: "GPS Media Hub"', window)
        self.assertIn("function open()", window)
        self.assertIn("function close()", window)
        self.assertIn("function toggle()", window)
        self.assertNotIn("hl.dsp.window.float", window)

    def test_wallpaper_browser_keeps_sfw_locked(self):
        hub = (ROOT / "components/MediaHub.qml").read_text()
        self.assertIn("readonly property bool sfwOnly: true", hub)
        self.assertNotIn("root.sfwOnly = !root.sfwOnly", hub)
        self.assertIn('case "People": return { code: "people", term: "" }', hub)
        window = (ROOT / "components/MediaHubWindow.qml").read_text()
        self.assertIn(r"https:\/\/wallhaven\.cc\/w\/", window)
        self.assertIn("wallhavenUsingRemote", hub)

    def test_bridge_requires_zero_exit_before_success(self):
        bridge = (ROOT / "components/MediaHubWallhaven.qml").read_text()
        self.assertEqual(bridge.count("exitCode === 0 && payload && payload.ok === true"), 2)


class WallhavenCliTests(unittest.TestCase):
    def test_search_cli_has_no_purity_override(self):
        args = wallhaven.parse_args([
            "search", "--query", "space", "--category", "general",
            "--sorting", "favorites", "--atleast", "1920x1080",
        ])
        self.assertEqual(args.query, "space")
        self.assertFalse(hasattr(args, "purity"))

    def test_apply_cli_requires_id_and_path(self):
        args = wallhaven.parse_args([
            "apply", "--id", "3q7mry",
            "--path", "https://w.wallhaven.cc/full/3q/wallhaven-3q7mry.jpg",
            "--title", "Example",
        ])
        self.assertEqual(args.id, "3q7mry")
        self.assertEqual(args.title, "Example")
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                wallhaven.parse_args(["apply", "--id", "3q7mry"])


if __name__ == "__main__":
    unittest.main()
