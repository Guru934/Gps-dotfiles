import importlib.util
import io
import json
import os
import tempfile
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


def raw_jamendo_track(**overrides):
    track = {
        "id": 987654,
        "name": "Rain on Neon Glass",
        "artist_name": "Velvet Circuit",
        "album_name": "Midnight Transit",
        "duration": 214,
        "audio": "https://prod-1.storage.jamendo.com/?trackid=987654&format=mp32&from=app",
        "album_image": "https://usercontent.jamendo.com/?type=album&id=77",
        "shareurl": "https://www.jamendo.com/track/987654/rain-on-neon-glass",
        "license_ccurl": "https://creativecommons.org/licenses/by-sa/3.0/",
        "listened": 48210,
        "musicinfo": {
            "tags": {
                "genres": ["synthwave", "electronic"],
                "instruments": ["synthesizer"],
                "vartags": ["night", "rain"],
            }
        },
    }
    track.update(overrides)
    return track


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


def jamendo_args(**overrides):
    values = {
        "query": "",
        "tag": "",
        "order": "popularity_total",
        "limit": 40,
        "offset": 0,
    }
    values.update(overrides)
    return Namespace(**values)


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


def jamendo_payload(*tracks):
    return {
        "headers": {
            "status": "success",
            "code": 0,
            "results_count": len(tracks),
            "results_fullcount": 210,
        },
        "results": list(tracks),
    }


class MusicConfigTests(unittest.TestCase):
    def test_status_without_credentials_does_not_require_network(self):
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp}, clear=False), \
             patch.dict(os.environ, {"JAMENDO_CLIENT_ID": ""}, clear=False):
            result = music.status()
        self.assertTrue(result["ok"])
        self.assertFalse(result["configured"])
        self.assertEqual(Path(result["configPath"]), Path(tmp) / "quickshell" / "rice-settings.json")

    def test_nested_config_client_id_is_used_without_exposing_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "quickshell" / "rice-settings.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"music": {"jamendoClientId": "abcd1234efgh5678"}}))
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp, "JAMENDO_CLIENT_ID": ""}, clear=False):
                result = music.status()
                client_id, source, message = music.jamendo_client_id()
        self.assertTrue(result["configured"])
        self.assertEqual(result["credentialSource"], "config")
        self.assertEqual(client_id, "abcd1234efgh5678")
        self.assertEqual(source, "config")
        self.assertEqual(message, "")
        self.assertNotIn("abcd1234efgh5678", json.dumps(result))

    def test_invalid_client_id_is_reported_but_not_echoed(self):
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp, "JAMENDO_CLIENT_ID": "bad value!"}, clear=False):
            result = music.status()
        self.assertFalse(result["configured"])
        self.assertIn("JAMENDO_CLIENT_ID", result["message"])
        self.assertNotIn("bad value", result["message"])

    def test_malformed_settings_are_reported_as_unconfigured(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "quickshell" / "rice-settings.json"
            config.parent.mkdir(parents=True)
            config.write_text("{not json")
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp, "JAMENDO_CLIENT_ID": ""}, clear=False):
                result = music.status()
        self.assertFalse(result["configured"])
        self.assertIn("Could not read", result["message"])


class JamendoNormalizationTests(unittest.TestCase):
    def test_normalizes_track_and_derived_display_fields(self):
        result = music.normalize_jamendo_track(raw_jamendo_track())
        self.assertEqual(result["kind"], "track")
        self.assertEqual(result["id"], "jamendo-987654")
        self.assertEqual(result["title"], "Rain on Neon Glass")
        self.assertEqual(result["artist"], "Velvet Circuit")
        self.assertEqual(result["genre"], "Synthwave")
        self.assertEqual(result["dur"], 214)
        self.assertEqual(result["license"], "CC BY-SA")
        self.assertEqual(result["sourceUrl"], "https://www.jamendo.com/track/987654/rain-on-neon-glass")
        self.assertEqual(result["streamUrl"],
                         "https://prod-1.storage.jamendo.com/?trackid=987654&format=mp32&from=app")
        self.assertIn("Night Drive", result["moods"])
        self.assertEqual(len(result["g"]), 3)

    def test_rejects_untrusted_or_missing_audio_and_images(self):
        self.assertIsNone(music.normalize_jamendo_track(raw_jamendo_track(
            audio="https://example.com/stream.mp3")))
        self.assertIsNone(music.normalize_jamendo_track(raw_jamendo_track(audio="")))
        result = music.normalize_jamendo_track(raw_jamendo_track(
            shareurl="https://example.com/track/1"))
        self.assertEqual(result["sourceUrl"], "https://www.jamendo.com/track/987654")
        result = music.normalize_jamendo_track(raw_jamendo_track(
            album_image="http://usercontent.jamendo.com/covers/1.jpg"))
        self.assertEqual(result["art"], "")
        self.assertEqual(result["sourceUrl"], "https://www.jamendo.com/track/987654/rain-on-neon-glass")

    def test_missing_source_falls_back_to_jamendo_track_page(self):
        result = music.normalize_jamendo_track(raw_jamendo_track(shareurl=""))
        self.assertEqual(result["sourceUrl"], "https://www.jamendo.com/track/987654")

    def test_control_characters_are_removed_from_api_text(self):
        result = music.normalize_jamendo_track(raw_jamendo_track(
            name="Rain\x00 on\nNeon", artist_name="Velvet\tCircuit"))
        self.assertEqual(result["title"], "Rain on Neon")
        self.assertEqual(result["artist"], "Velvet Circuit")


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
            url_resolved="https://user:pass@stream.example.net/live")))
        self.assertIsNone(music.normalize_radio_station(raw_radio_station(stationuuid="not-a-uuid")))
        result = music.normalize_radio_station(raw_radio_station(
            favicon="http://neon.example.net/favicon.png", homepage="http://neon.example.net/"))
        self.assertEqual(result["art"], "")
        self.assertEqual(result["sourceUrl"], "https://www.radio-browser.info/")

    def test_http_streams_remain_playable(self):
        result = music.normalize_radio_station(raw_radio_station(
            url_resolved="http://stream.example.net/neon.mp3"))
        self.assertEqual(result["streamUrl"], "http://stream.example.net/neon.mp3")


class JamendoSearchTests(unittest.TestCase):
    def test_missing_client_id_fails_before_network(self):
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp, "JAMENDO_CLIENT_ID": ""}, clear=False), \
             patch.object(music, "request_json") as request:
            with self.assertRaises(music.BridgeError) as raised:
                music.jamendo_search(jamendo_args())
            request.assert_not_called()
        self.assertEqual(raised.exception.code, "jamendo_unconfigured")

    def test_search_builds_validated_request_and_never_echoes_the_secret(self):
        with patch.dict(os.environ, {"JAMENDO_CLIENT_ID": "abcd1234efgh5678"}, clear=False), \
             patch.object(music, "request_json", return_value=jamendo_payload(raw_jamendo_track())) as request:
            result = music.jamendo_search(jamendo_args(query="  neon   rain ", tag="synthwave",
                                                       order="popularity_week"))
        url = request.call_args.args[0]
        params = parse_qs(urlsplit(url).query)
        self.assertEqual(params["client_id"], ["abcd1234efgh5678"])
        self.assertEqual(params["search"], ["neon rain"])
        self.assertEqual(params["fuzzytags"], ["synthwave"])
        self.assertEqual(params["order"], ["popularity_week"])
        self.assertEqual(params["include"], ["musicinfo+licenses"])
        self.assertEqual(result["results"][0]["id"], "jamendo-987654")
        self.assertNotIn("abcd1234efgh5678", json.dumps(result))

    def test_invalid_filters_fail_before_network_access(self):
        cases = [
            {"order": "downloads"},
            {"limit": 0},
            {"limit": 51},
            {"offset": -1},
            {"query": "x" * 161},
            {"tag": "bad\x00tag"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                with patch.dict(os.environ, {"JAMENDO_CLIENT_ID": "abcd1234efgh5678"}, clear=False), \
                     patch.object(music, "request_json") as request:
                    with self.assertRaises(music.BridgeError):
                        music.jamendo_search(jamendo_args(**overrides))
                    request.assert_not_called()

    def test_api_auth_failure_is_classified(self):
        payload = {"headers": {"status": "failed", "code": 5}, "results": []}
        with patch.dict(os.environ, {"JAMENDO_CLIENT_ID": "abcd1234efgh5678"}, clear=False), \
             patch.object(music, "request_json", return_value=payload):
            with self.assertRaises(music.BridgeError) as raised:
                music.jamendo_search(jamendo_args())
        self.assertEqual(raised.exception.code, "jamendo_auth")

    def test_malformed_payload_is_rejected(self):
        with patch.dict(os.environ, {"JAMENDO_CLIENT_ID": "abcd1234efgh5678"}, clear=False), \
             patch.object(music, "request_json", return_value={"headers": {}, "results": "nope"}):
            with self.assertRaises(music.BridgeError) as raised:
                music.jamendo_search(jamendo_args())
        self.assertEqual(raised.exception.code, "invalid_response")


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
                        music.request_json("https://api.example", "Test", dict)
                self.assertEqual(raised.exception.code, code)

    def test_invalid_and_oversized_json_are_rejected(self):
        with patch.object(music.urllib.request, "urlopen", return_value=FakeResponse(b"not-json")):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Test", dict)
        self.assertEqual(raised.exception.code, "invalid_response")

        with patch.object(music, "MAX_JSON_BYTES", 16), \
             patch.object(music.urllib.request, "urlopen",
                          return_value=FakeResponse(b"{}" + b"x" * 32)):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Test", dict)
        self.assertEqual(raised.exception.code, "invalid_response")

    def test_wrong_payload_type_is_rejected(self):
        with patch.object(music.urllib.request, "urlopen", return_value=FakeResponse(b"[]")):
            with self.assertRaises(music.BridgeError) as raised:
                music.request_json("https://api.example", "Test", dict)
        self.assertEqual(raised.exception.code, "invalid_response")


class MusicCliTests(unittest.TestCase):
    def test_helper_is_executable_for_the_qml_bridge(self):
        self.assertTrue(HELPER.stat().st_mode & 0o111)

    def test_status_command_has_no_search_arguments(self):
        args = music.parse_args(["status"])
        self.assertEqual(args.command, "status")
        self.assertFalse(hasattr(args, "query"))

    def test_jamendo_and_radio_defaults_are_separate(self):
        jamendo = music.parse_args(["jamendo", "--query", "rain"])
        radio = music.parse_args(["radio", "--tag", "jazz"])
        self.assertEqual(jamendo.order, "popularity_total")
        self.assertEqual(radio.order, "clickcount")

    def test_main_emits_json_failure_for_unconfigured_jamendo(self):
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp, "JAMENDO_CLIENT_ID": ""}, clear=False), \
             patch("sys.stdout", new_callable=io.StringIO) as stdout:
            code = music.main(["jamendo", "--query", "rain"])
        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "jamendo_unconfigured")


if __name__ == "__main__":
    unittest.main()
