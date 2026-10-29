import importlib.util
import json
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("media_hub_lyrics", SCRIPTS / "media-hub-lyrics.py")
lyrics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lyrics)


class FakeLyricsHandler(BaseHTTPRequestHandler):
    exact_status = 200
    exact_result = {}
    search_result = []
    requests = []

    def log_message(self, format_string, *args):
        return

    def do_GET(self):
        self.__class__.requests.append((self.path, self.headers.get("User-Agent")))
        if self.path.startswith("/api/get?"):
            status, value = self.__class__.exact_status, self.__class__.exact_result
        elif self.path.startswith("/api/search?"):
            status, value = 200, self.__class__.search_result
        else:
            status, value = 404, {}
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class MediaHubLyricsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeLyricsHandler)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}/api"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.server_thread.join(timeout=2)

    def setUp(self):
        FakeLyricsHandler.exact_status = 200
        FakeLyricsHandler.exact_result = {
            "syncedLyrics": "[00:02.00]First line\n[00:04.25]Second line",
            "plainLyrics": "First line\nSecond line",
        }
        FakeLyricsHandler.search_result = []
        FakeLyricsHandler.requests = []
        self.temp_dir = tempfile.TemporaryDirectory()
        self.cache = lyrics.hub_common.DiskCache(
            self.temp_dir.name,
            ttl_seconds=3600,
            max_bytes=1024 * 1024,
        )
        self.rate_limit_patch = patch.object(lyrics.hub_common, "RATE_LIMIT_INTERVAL", 0)
        self.rate_limit_patch.start()
        with lyrics.hub_common._host_lock:
            lyrics.hub_common._host_last_request.clear()

    def tearDown(self):
        self.rate_limit_patch.stop()
        self.temp_dir.cleanup()

    def lookup(self, title="Example Song"):
        return lyrics.lookup(
            "Example Artist",
            title,
            "Example Album",
            180,
            base_url=self.base_url,
            cache=self.cache,
        )

    def test_exact_lookup_normalizes_synced_lyrics_and_user_agent(self):
        result = self.lookup()
        self.assertEqual(result, {
            "status": "synced",
            "lines": [
                {"t": 2.0, "s": "First line"},
                {"t": 4.25, "s": "Second line"},
            ],
        })
        path, user_agent = FakeLyricsHandler.requests[0]
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
        self.assertEqual(query["track_name"], ["Example Song"])
        self.assertEqual(query["artist_name"], ["Example Artist"])
        self.assertEqual(query["album_name"], ["Example Album"])
        self.assertEqual(query["duration"], ["180"])
        self.assertEqual(user_agent, "GPS-Desktop/1.0")

    def test_no_exact_match_falls_back_to_search_and_selects_synced_candidate(self):
        FakeLyricsHandler.exact_status = 404
        FakeLyricsHandler.search_result = [
            {"trackName": "Unrelated", "artistName": "Other", "plainLyrics": "Wrong"},
            {
                "trackName": "Example Song",
                "artistName": "Example Artist",
                "syncedLyrics": "[00:01.50]Found it",
                "duration": 180,
            },
        ]
        result = self.lookup()
        self.assertEqual(result, {"status": "synced", "lines": [{"t": 1.5, "s": "Found it"}]})
        self.assertEqual(len(FakeLyricsHandler.requests), 2)
        self.assertTrue(FakeLyricsHandler.requests[1][0].startswith("/api/search?"))

    def test_search_falls_back_to_plain_lyrics(self):
        FakeLyricsHandler.exact_status = 404
        FakeLyricsHandler.search_result = [{
            "trackName": "Example Song",
            "artistName": "Example Artist",
            "plainLyrics": "Plain words",
            "duration": 180,
        }]
        self.assertEqual(self.lookup(), {"status": "plain", "plain": "Plain words"})

    def test_no_lyrics_is_cached(self):
        FakeLyricsHandler.exact_status = 404
        FakeLyricsHandler.search_result = []
        self.assertEqual(self.lookup(), {"status": "none"})
        self.assertEqual(self.lookup(), {"status": "none"})
        self.assertEqual(len(FakeLyricsHandler.requests), 2)

    def test_lookup_rejects_missing_title_without_network(self):
        with self.assertRaises(lyrics.hub_common.HubError) as raised:
            self.lookup(" ")
        self.assertEqual(raised.exception.kind, "invalid")
        self.assertEqual(FakeLyricsHandler.requests, [])

    def test_lrc_parser_expands_multiple_timestamps_and_sorts(self):
        self.assertEqual(
            lyrics.parse_lrc("[00:05.00][00:02.50]Shared line\n[ar:Artist]\n[00:03.00]Next"),
            [
                {"t": 2.5, "s": "Shared line"},
                {"t": 3.0, "s": "Next"},
                {"t": 5.0, "s": "Shared line"},
            ],
        )


if __name__ == "__main__":
    unittest.main()
