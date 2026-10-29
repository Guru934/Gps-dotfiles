import importlib.util
import io
import json
import unittest
import urllib.error
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts/media-hub-music.py"
SPEC = importlib.util.spec_from_file_location("media_hub_music", HELPER)
music = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(music)


class FakeResponse:
    def __init__(self, body, status=200):
        self.body = body
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self, amount=-1):
        if amount < 0:
            body, self.body = self.body, b""
            return body
        body, self.body = self.body[:amount], self.body[amount:]
        return body


def raw_radio_station(**overrides):
    station = {
        "stationuuid": "3d5a6c9e-12b4-4f51-9a8c-7e2f0d1b6c33",
        "name": "Neon Static FM",
        "url_resolved": "https://stream.example.net/neon.mp3",
        "homepage": "https://neon.example.net/",
        "favicon": "https://neon.example.net/favicon.png",
        "tags": "synthwave, electronic",
        "country": "Germany",
        "codec": "MP3",
        "bitrate": 128,
        "votes": 140,
        "clickcount": 912,
        "lastcheckok": 1,
        "hls": 0,
    }
    station.update(overrides)
    return station


def radio_args(**overrides):
    values = {
        "name": "",
        "tag": "",
        "country": "",
        "order": "clickcount",
        "limit": 40,
        "offset": 0,
    }
    values.update(overrides)
    return Namespace(**values)


class RadioNormalizationTests(unittest.TestCase):
    def test_normalizes_station_and_keeps_stream_metadata(self):
        result = music.normalize_radio_station(raw_radio_station())
        self.assertEqual(result["kind"], "station")
        self.assertEqual(result["id"], "radio-3d5a6c9e-12b4-4f51-9a8c-7e2f0d1b6c33")
        self.assertEqual(result["streamUrl"], "https://stream.example.net/neon.mp3")
        self.assertEqual(result["genre"], "Synthwave")
        self.assertEqual(result["country"], "Germany")
        self.assertEqual(result["codec"], "MP3")
        self.assertEqual(result["bitrate"], 128)
        self.assertEqual(result["votes"], 140)
        self.assertEqual(result["sourceUrl"], "https://neon.example.net/")
        self.assertEqual(len(result["g"]), 3)

    def test_rejects_broken_untrusted_or_non_http_stations(self):
        self.assertIsNone(music.normalize_radio_station(raw_radio_station(lastcheckok=0)))
        self.assertIsNone(music.normalize_radio_station(raw_radio_station(
            url_resolved="javascript:alert(1)")))
        self.assertIsNone(music.normalize_radio_station(raw_radio_station(
            url_resolved="******stream.example.net/live")))
        self.assertIsNone(music.normalize_radio_station(raw_radio_station(stationuuid="not-a-uuid")))
        result = music.normalize_radio_station(raw_radio_station(
            favicon="http://neon.example.net/favicon.png", homepage="http://neon.example.net/"))
        self.assertEqual(result["art"], "")
        self.assertEqual(result["sourceUrl"], "https://www.radio-browser.info/")

    def test_http_streams_remain_playable(self):
        result = music.normalize_radio_station(raw_radio_station(
            url_resolved="http://stream.example.net/neon.mp3"))
        self.assertEqual(result["streamUrl"], "http://stream.example.net/neon.mp3")


class RadioSearchTests(unittest.TestCase):
    def test_search_forwards_only_validated_filters(self):
        with patch.object(music, "request_json", return_value=[raw_radio_station()]) as request:
            result = music.radio_search(radio_args(name=" Neon ", tag="synthwave",
                                                   country="Germany", order="votes"))
        params = parse_qs(urlsplit(request.call_args.args[0]).query)
        self.assertEqual(params["hidebroken"], ["true"])
        self.assertEqual(params["name"], ["Neon"])
        self.assertEqual(params["tag"], ["synthwave"])
        self.assertEqual(params["country"], ["Germany"])
        self.assertEqual(params["order"], ["votes"])
        self.assertEqual(params["reverse"], ["true"])
        self.assertEqual(result["results"][0]["id"],
                         "radio-3d5a6c9e-12b4-4f51-9a8c-7e2f0d1b6c33")

    def test_invalid_filters_fail_before_network(self):
        cases = [
            {"order": "listeners"},
            {"limit": 100},
            {"offset": 10001},
            {"country": "x" * 81},
            {"name": "bad\nname"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                with patch.object(music, "request_json") as request:
                    with self.assertRaises(music.BridgeError):
                        music.radio_search(radio_args(**overrides))
                    request.assert_not_called()

    def test_invalid_entries_are_skipped(self):
        with patch.object(music, "request_json",
                          return_value=[raw_radio_station(), raw_radio_station(lastcheckok=0)]):
            result = music.radio_search(radio_args())
        self.assertEqual(len(result["results"]), 1)

    def test_name_ordering_does_not_reverse(self):
        with patch.object(music, "request_json", return_value=[]) as request:
            music.radio_search(radio_args(order="name"))
        params = parse_qs(urlsplit(request.call_args.args[0]).query)
        self.assertEqual(params["reverse"], ["false"])


class RequestTests(unittest.TestCase):
    def test_http_and_network_errors_are_classified(self):
        cases = [
            (urllib.error.HTTPError("https://api.example", 429, "rate limited", {}, None),
             "rate_limited"),
            (urllib.error.HTTPError("https://api.example", 403, "forbidden", {}, None),
             "forbidden"),
            (urllib.error.HTTPError("https://api.example", 503, "down", {}, None),
             "server_error"),
            (TimeoutError("slow"), "network_error"),
        ]
        for error, code in cases:
            with self.subTest(code=code):
                with patch.object(music.urllib.request, "urlopen", side_effect=error):
                    with self.assertRaises(music.BridgeError) as raised:
                        music.request_json("https://api.example", "Radio Browser", list)
                self.assertEqual(raised.exception.code, code)

    def test_invalid_and_oversized_json_are_rejected(self):
        with patch.object(music.urllib.request, "urlopen",
                          return_value=FakeResponse(b"not-json")):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Radio Browser", list)
        self.assertEqual(raised.exception.code, "invalid_response")

        with patch.object(music, "MAX_JSON_BYTES", 16), \
             patch.object(music.urllib.request, "urlopen",
                          return_value=FakeResponse(b"[]" + b"x" * 32)):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Radio Browser", list)
        self.assertEqual(raised.exception.code, "invalid_response")

    def test_wrong_payload_type_is_rejected(self):
        with patch.object(music.urllib.request, "urlopen",
                          return_value=FakeResponse(b"{}")):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Radio Browser", list)
        self.assertEqual(raised.exception.code, "invalid_response")


class RadioCliTests(unittest.TestCase):
    def test_helper_is_executable_for_the_qml_bridge(self):
        self.assertTrue(HELPER.stat().st_mode & 0o111)

    def test_radio_command_defaults(self):
        args = music.parse_args(["radio", "--tag", "jazz"])
        self.assertEqual(args.command, "radio")
        self.assertEqual(args.order, "clickcount")
        self.assertEqual(args.limit, 40)
        self.assertEqual(args.tag, "jazz")

    def test_main_emits_one_json_document(self):
        with patch.object(music, "request_json", return_value=[]), \
             patch("sys.stdout", new_callable=io.StringIO) as stdout:
            code = music.main(["radio"])
        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["source"], "radio")
        self.assertEqual(payload["results"], [])

    def test_main_emits_json_failure_for_invalid_request(self):
        with patch("sys.stdout", new_callable=io.StringIO) as stdout:
            code = music.main(["radio", "--order", "listeners"])
        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_request")


if __name__ == "__main__":
    unittest.main()
