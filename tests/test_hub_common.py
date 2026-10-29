import importlib.util
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location("hub_common", ROOT / "scripts" / "hub_common.py")
hub_common = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hub_common)


class FakeProviderHandler(BaseHTTPRequestHandler):
    counts = {}
    user_agents = []

    def log_message(self, format_string, *args):
        return

    def do_GET(self):
        self.__class__.counts[self.path] = self.__class__.counts.get(self.path, 0) + 1
        self.__class__.user_agents.append(self.headers.get("User-Agent"))
        attempt = self.__class__.counts[self.path]
        if self.path == "/retry" and attempt < 3:
            self.send_response(503)
            self.end_headers()
            return
        if self.path == "/limited" and attempt == 1:
            self.send_response(429)
            self.send_header("Retry-After", "2")
            self.end_headers()
            return
        if self.path == "/long-limited":
            self.send_response(429)
            self.send_header("Retry-After", "120")
            self.end_headers()
            return
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class HubCommonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        FakeProviderHandler.counts = {}
        FakeProviderHandler.user_agents = []
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeProviderHandler)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.server_thread.join(timeout=2)

    def setUp(self):
        with hub_common._host_lock:
            hub_common._host_last_request.clear()
        self.rate_limit_patch = patch.object(hub_common, "RATE_LIMIT_INTERVAL", 0)
        self.rate_limit_patch.start()
        self.addCleanup(self.rate_limit_patch.stop)

    def test_request_retries_with_exponential_backoff(self):
        delays = []
        body, headers = hub_common.request(
            self.base_url + "/retry",
            sleep=delays.append,
            retries=3,
        )
        self.assertEqual(body, b'{"ok":true}')
        self.assertEqual(FakeProviderHandler.counts["/retry"], 3)
        self.assertEqual(delays, [0.5, 1.0])

    def test_request_identifies_the_desktop_client_without_browser_spoofing(self):
        body, _ = hub_common.request(self.base_url + "/agent", retries=0)
        self.assertEqual(body, b'{"ok":true}')
        self.assertEqual(FakeProviderHandler.user_agents[-1], "GPS-Desktop/1.0")

    def test_429_honors_retry_after(self):
        delays = []
        body, _ = hub_common.request(
            self.base_url + "/limited",
            sleep=delays.append,
            retries=2,
        )
        self.assertEqual(body, b'{"ok":true}')
        self.assertEqual(FakeProviderHandler.counts["/limited"], 2)
        self.assertEqual(delays, [2.0])

    def test_long_429_retry_after_is_reported_without_blocking_the_provider(self):
        delays = []
        with self.assertRaises(hub_common.HubError) as raised:
            hub_common.request(
                self.base_url + "/long-limited",
                sleep=delays.append,
                retries=3,
            )
        self.assertEqual(raised.exception.kind, "rate_limited")
        self.assertEqual(raised.exception.retry_after, 120)
        self.assertEqual(delays, [])
        self.assertEqual(FakeProviderHandler.counts["/long-limited"], 1)

    def test_cache_ttl_expires_entries(self):
        now = [100.0]
        with tempfile.TemporaryDirectory() as directory:
            cache = hub_common.DiskCache(directory, ttl_seconds=10, max_bytes=100, now=lambda: now[0])
            cache.set("key", b"payload", "image/png")
            self.assertEqual(cache.get("key"), b"payload")
            now[0] = 110.0
            self.assertIsNone(cache.get("key"))

    def test_cache_size_limit_removes_least_recently_used_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = hub_common.DiskCache(directory, ttl_seconds=100, max_bytes=7)
            cache.set("old", b"1234")
            cache.get("old")
            cache.set("new", b"5678")
            total = sum(path.stat().st_size for path in Path(directory).glob("*.bin"))
            self.assertLessEqual(total, 7)
            self.assertIsNone(cache.get("old"))
            self.assertEqual(cache.get("new"), b"5678")

    def test_file_fetch_validates_content_type_and_size_and_caches_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = hub_common.DiskCache(directory, max_bytes=100)
            with patch.object(
                hub_common, "request",
                return_value=(b"image-bytes", {"Content-Type": "image/png", "Content-Length": "11"}),
            ) as request:
                cached_path = hub_common.fetch_and_cache(
                    "https://images.example/test.png", cache=cache, max_bytes=20,
                )
            self.assertEqual(cached_path.read_bytes(), b"image-bytes")
            request.assert_called_once()
            with patch.object(
                hub_common, "request",
                return_value=(b"image-bytes", {"Content-Type": "text/html"}),
            ):
                with self.assertRaises(hub_common.HubError) as raised:
                    hub_common.fetch_and_cache("https://images.example/unsafe", cache=cache)
            self.assertEqual(raised.exception.kind, "invalid")
            with patch.object(
                hub_common, "request",
                return_value=(b"x" * 21, {"Content-Type": "image/png"}),
            ):
                with self.assertRaises(hub_common.HubError):
                    hub_common.fetch_and_cache(
                        "https://images.example/large", cache=cache, max_bytes=20,
                    )

    def test_persistent_state_writes_atomically_and_loads_json(self):
        with tempfile.TemporaryDirectory() as directory:
            state = hub_common.PersistentState("music", root=directory)
            real_replace = os.replace
            observed = []

            def replace(source, target):
                observed.append((Path(source), Path(target)))
                real_replace(source, target)

            with patch.object(hub_common.os, "replace", side_effect=replace):
                state.save({"queue": [1, 2]})
            self.assertEqual(state.load({}), {"queue": [1, 2]})
            self.assertEqual(list(Path(directory).glob("*.tmp")), [])
            self.assertEqual(observed[0][1], state.path)
            self.assertEqual(observed[0][0].parent, state.path.parent)
            self.assertEqual(state.path.parent, Path(directory))
            self.assertEqual(os.stat(state.path).st_mode & 0o777, 0o600)

    def test_corrupt_state_is_backed_up_and_defaulted(self):
        with tempfile.TemporaryDirectory() as directory:
            state = hub_common.PersistentState("library", root=directory)
            state.path.parent.mkdir(parents=True, exist_ok=True)
            state.path.write_text("{bad json", encoding="utf-8")
            self.assertEqual(state.load({"entries": []}), {"entries": []})
            self.assertTrue(state.last_error)
            backups = list(Path(directory).glob("library.corrupt-*.json"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(encoding="utf-8"), "{bad json")

    def test_contract_validation_accepts_normalized_shapes_and_rejects_bad_data(self):
        valid = {
            "kind": "track",
            "id": "provider-1",
            "title": "Example",
            "artist": "",
            "album": "",
            "dur": 0,
            "streamUrl": "https://media.example/stream",
        }
        hub_common.validate_contract("Track", valid)
        hub_common.validate_contract("Anime", {
            "kind": "anime", "id": "anime-1", "title": "Title",
            "siteUrl": "https://catalogue.example/anime/1",
        })
        hub_common.validate_contract("Manga", {
            "kind": "manga", "id": "manga-1", "title": "Title",
            "siteUrl": "https://catalogue.example/manga/1",
        })
        hub_common.validate_contract("Chapter", {
            "title": "Chapter", "pageCount": 1, "pages": ["file:///tmp/page.png"],
        })
        hub_common.validate_contract("PageList", {
            "title": "Chapter", "pageCount": 1, "pages": ["https://images.example/1.png"],
        })
        hub_common.validate_contract("Lyrics", {
            "status": "synced", "lines": [{"t": 1.25, "s": "Line"}],
        })
        hub_common.validate_contract("Lyrics", {"status": "plain", "plain": "Words"})
        hub_common.validate_contract("Lyrics", {"status": "none"})
        hub_common.validate_contract("Error", hub_common.error_payload("network", "Offline"))
        with self.assertRaises(ValueError):
            hub_common.validate_contract("Track", {**valid, "dur": True})
        with self.assertRaises(ValueError):
            hub_common.validate_contract("Chapter", {
                "title": "Chapter", "pageCount": 2, "pages": ["file:///tmp/page.png"],
            })
        with self.assertRaises(ValueError):
            hub_common.validate_contract("Error", {
                "ok": False, "error": {"kind": "other", "message": "bad"},
            })
        with self.assertRaises(ValueError):
            hub_common.validate_contract("Lyrics", {
                "status": "synced", "lines": [{"t": -1, "s": "Line"}],
            })


if __name__ == "__main__":
    unittest.main()
