import contextlib
import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
import urllib.error
from argparse import Namespace
from email.message import Message
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts/media-hub-anilist.py"
SPEC = importlib.util.spec_from_file_location("media_hub_anilist", HELPER)
anilist = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(anilist)


class FakeResponse:
    def __init__(self, body, status=200, headers=None):
        self.body = body
        self.status = status
        self.headers = headers or {}

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


def http_error(status, body=b"", headers=None):
    return urllib.error.HTTPError(
        anilist.API_URL, status, "error", headers or Message(), io.BytesIO(body)
    )


def raw_anime(**overrides):
    media = {
        "id": 16498,
        "type": "ANIME",
        "title": {
            "romaji": "Shingeki no Kyojin",
            "english": "Attack on Titan",
            "native": "進撃の巨人",
        },
        "synonyms": ["AoT", "Attack on Titan", ""],
        "description": "<p>A grim <i>tale</i> of survival.</p><br><br>Second line.",
        "siteUrl": "https://anilist.co/anime/16498",
        "coverImage": {
            "extraLarge": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498.jpg",
            "large": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498-small.jpg",
            "color": "#e4a15d",
        },
        "bannerImage": "https://s4.anilist.co/file/anilistcdn/media/anime/banner/16498.jpg",
        "format": "TV",
        "status": "RELEASING",
        "season": "FALL",
        "seasonYear": 2026,
        "startDate": {"year": 2026},
        "episodes": 12,
        "chapters": None,
        "volumes": None,
        "duration": 24,
        "averageScore": 85,
        "meanScore": 84,
        "popularity": 500000,
        "trending": 1200,
        "favourites": 90000,
        "genres": ["Action", "Drama", "Ecchi", "Not A Genre"],
        "countryOfOrigin": "JP",
        "isAdult": False,
        "studios": {"nodes": [{"name": "MAPPA"}, {"name": "Wit Studio"}]},
        "staff": {
            "edges": [
                {"role": "Director", "node": {"name": {"full": "Tetsuro Araki"}}},
                {"role": "Original Creator", "node": {"name": {"full": "Hajime Isayama"}}},
            ]
        },
        "externalLinks": [
            {"id": 1, "url": "https://www.crunchyroll.com/series/GR751KNZY", "site": "Crunchyroll", "type": "STREAMING"},
            {"id": 2, "url": "https://en.wikipedia.org/wiki/Attack_on_Titan", "site": "Wikipedia", "type": "INFO"},
            {"id": 3, "url": "http://example.com/watch", "site": "Unsafe HTTP", "type": "STREAMING"},
            {"id": 4, "url": "https://www.crunchyroll.com/series/GR751KNZY", "site": "Crunchyroll duplicate", "type": "STREAMING"},
        ],
    }
    media.update(overrides)
    return media


def raw_manga(**overrides):
    media = {
        "id": 30002,
        "type": "MANGA",
        "title": {
            "romaji": "Solo Leveling",
            "english": "Solo Leveling",
            "native": "나 혼자만 레벨업",
        },
        "synonyms": ["Only I Level Up"],
        "description": "A hunter rises.",
        "siteUrl": "https://anilist.co/manga/30002",
        "coverImage": {
            "extraLarge": "https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/bx30002.jpg",
            "large": "",
            "color": "#2b2d42",
        },
        "bannerImage": None,
        "format": "MANGA",
        "status": "FINISHED",
        "season": None,
        "seasonYear": None,
        "startDate": {"year": 2018},
        "episodes": None,
        "chapters": 179,
        "volumes": 14,
        "duration": None,
        "averageScore": 81,
        "meanScore": 82,
        "popularity": 400000,
        "trending": 500,
        "favourites": 70000,
        "genres": ["Action", "Fantasy"],
        "countryOfOrigin": "KR",
        "isAdult": False,
        "studios": {"nodes": []},
        "staff": {
            "edges": [
                {"role": "Story", "node": {"name": {"full": "Chugong"}}},
                {"role": "Art", "node": {"name": {"full": "DUBU"}}},
            ]
        },
    }
    media.update(overrides)
    return media


def search_args(**overrides):
    values = {
        "type": "anime",
        "query": "",
        "genre": "",
        "status": "",
        "country": "",
        "sort": "POPULARITY_DESC",
        "page": 1,
        "per_page": 24,
        "seasonal": False,
    }
    values.update(overrides)
    return Namespace(**values)


def page_payload(*media, current=1, has_next=True, per_page=24):
    return {
        "Page": {
            "pageInfo": {
                "currentPage": current,
                "hasNextPage": has_next,
                "perPage": per_page,
            },
            "media": list(media),
        }
    }


class EnvironmentMixin:
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(
            os.environ,
            {
                "XDG_CACHE_HOME": self.temp.name,
                "HOME": self.temp.name,
            },
            clear=False,
        )
        self.env.start()
        self.addCleanup(self.env.stop)


class SeasonAndCacheTests(EnvironmentMixin, unittest.TestCase):
    def test_current_season_uses_anilist_boundaries(self):
        from datetime import date

        cases = [
            (date(2026, 1, 1), ("WINTER", 2026)),
            (date(2026, 3, 31), ("WINTER", 2026)),
            (date(2026, 4, 1), ("SPRING", 2026)),
            (date(2026, 7, 1), ("SUMMER", 2026)),
            (date(2026, 10, 1), ("FALL", 2026)),
            (date(2026, 12, 31), ("FALL", 2026)),
        ]
        for day, expected in cases:
            self.assertEqual(anilist.current_season(day), expected)

    def test_cache_paths_live_under_xdg_cache(self):
        path = anilist.cache_path({"page": 1})
        self.assertEqual(path.parent, Path(self.temp.name) / "gps-media-hub" / "anilist")
        self.assertRegex(path.name, r"^[0-9a-f]{64}\.json$")

    def test_cache_round_trip_and_expiry(self):
        request = {"kind": "anime", "page": 1}
        response = {"ok": True, "results": [{"id": "anime-1"}]}
        anilist.write_cache(request, response)
        self.assertEqual(anilist.read_cache(request), response)
        path = anilist.cache_path(request)
        old = time.time() - anilist.CACHE_TTL_SECONDS - 5
        os.utime(path, (old, old))
        self.assertIsNone(anilist.read_cache(request))

    def test_malformed_or_mismatched_cache_is_ignored(self):
        request = {"kind": "anime", "page": 1}
        path = anilist.cache_path(request)
        path.write_text("{not json", encoding="utf-8")
        self.assertIsNone(anilist.read_cache(request))
        path.write_text(json.dumps({"request": {"kind": "manga"}, "response": {"results": []}}))
        self.assertIsNone(anilist.read_cache(request))

    def test_cooldown_is_bounded_and_expires(self):
        now = time.time()
        self.assertEqual(anilist.cooldown_remaining(now), 0)
        self.assertEqual(anilist.write_cooldown(42, now), 42)
        self.assertEqual(anilist.cooldown_remaining(now), 42)
        self.assertEqual(anilist.cooldown_remaining(now + 43), 0)


class RequestValidationTests(unittest.TestCase):
    def test_cli_accepts_option_like_query_as_a_value(self):
        args = anilist.parse_args(["search", "--type", "anime", "--query=--help"])
        self.assertEqual(args.query, "--help")

    def test_default_request_is_normalized(self):
        request = anilist.validated_request(search_args(query="  Attack   on Titan  "))
        self.assertEqual(request["kind"], "anime")
        self.assertEqual(request["query"], "Attack on Titan")
        self.assertEqual(request["page"], 1)
        self.assertEqual(request["perPage"], 24)
        self.assertEqual(request["sort"], "POPULARITY_DESC")
        self.assertIsNone(request["season"])
        self.assertIsNone(request["seasonYear"])

    def test_seasonal_request_adds_current_season(self):
        with patch.object(anilist, "current_season", return_value=("FALL", 2026)):
            request = anilist.validated_request(search_args(seasonal=True))
        self.assertTrue(request["seasonal"])
        self.assertEqual(request["season"], "FALL")
        self.assertEqual(request["seasonYear"], 2026)

    def test_invalid_enum_and_pagination_values_are_rejected(self):
        invalid = [
            {"page": 0},
            {"page": 501},
            {"per_page": 0},
            {"per_page": 51},
            {"genre": "Hentai"},
            {"genre": "Not A Genre"},
            {"country": "US"},
            {"status": "WATCHING"},
            {"sort": "DROP TABLE"},
        ]
        for overrides in invalid:
            with self.subTest(overrides=overrides):
                with self.assertRaises(anilist.BridgeError) as caught:
                    anilist.validated_request(search_args(**overrides))
                self.assertEqual(caught.exception.code, "invalid_request")

    def test_seasonal_manga_is_rejected(self):
        with self.assertRaises(anilist.BridgeError) as caught:
            anilist.validated_request(search_args(type="manga", seasonal=True))
        self.assertEqual(caught.exception.code, "invalid_request")

    def test_query_and_country_are_bounded_and_normalized(self):
        request = anilist.validated_request(search_args(country="kr"))
        self.assertEqual(request["country"], "KR")
        with self.assertRaises(anilist.BridgeError):
            anilist.validated_request(search_args(query="x" * 101))
        with self.assertRaises(anilist.BridgeError):
            anilist.validated_request(search_args(country="KOR"))


class MediaNormalizationTests(unittest.TestCase):
    def test_anime_is_normalized_for_the_catalogue_ui(self):
        item = anilist.normalize_media("anime", raw_anime())
        self.assertEqual(item["kind"], "anime")
        self.assertEqual(item["id"], "anime-16498")
        self.assertEqual(item["title"], "Attack on Titan")
        self.assertEqual(item["type"], "Anime")
        self.assertEqual(item["total"], 12)
        self.assertEqual(item["chapters"], 0)
        self.assertEqual(item["volumes"], 0)
        self.assertEqual(item["statusLabel"], "Airing")
        self.assertEqual(item["catalogueStatus"], "RELEASING")
        self.assertEqual(item["formatLabel"], "TV")
        self.assertEqual(item["seasonLabel"], "Fall 2026")
        self.assertEqual(item["scoreLabel"], "8.5")
        self.assertEqual(item["countryLabel"], "Japan")
        self.assertEqual(item["studios"], ["MAPPA", "Wit Studio"])
        self.assertEqual(item["author"], "Tetsuro Araki · Hajime Isayama")
        self.assertIn("AoT", item["altTitles"])
        self.assertNotIn("Attack on Titan", item["altTitles"])
        self.assertIn("Action", item["genres"])
        self.assertNotIn("Ecchi", item["genres"])
        self.assertNotIn("Not A Genre", item["genres"])
        self.assertEqual(item["description"], "A grim tale of survival.\nSecond line.")
        self.assertEqual(item["siteUrl"], "https://anilist.co/anime/16498")
        self.assertEqual(item["officialLinks"], [{
            "site": "Crunchyroll",
            "url": "https://www.crunchyroll.com/series/GR751KNZY",
        }])
        self.assertTrue(item["cover"].startswith("https://s4.anilist.co/"))
        self.assertFalse(item["isAdult"])

    def test_manga_country_controls_manhwa_and_manhua_labels(self):
        manhwa = anilist.normalize_media("manga", raw_manga())
        self.assertEqual(manhwa["type"], "Manhwa")
        self.assertEqual(manhwa["total"], 179)
        self.assertEqual(manhwa["episodes"], 0)
        self.assertEqual(manhwa["statusLabel"], "Completed")
        self.assertEqual(manhwa["author"], "Chugong · DUBU")
        self.assertEqual(manhwa["countryLabel"], "Korea")

        manhua = anilist.normalize_media("manga", raw_manga(countryOfOrigin="CN"))
        self.assertEqual(manhua["type"], "Manhua")
        taiwan = anilist.normalize_media("manga", raw_manga(countryOfOrigin="TW"))
        self.assertEqual(taiwan["type"], "Manhua")

    def test_missing_year_falls_back_to_season_year(self):
        item = anilist.normalize_media("anime", raw_anime(startDate={}))
        self.assertEqual(item["year"], 2026)

    def test_untrusted_or_wrong_media_is_rejected(self):
        self.assertIsNone(anilist.normalize_media("anime", None))
        self.assertIsNone(anilist.normalize_media("anime", raw_manga()))
        self.assertIsNone(anilist.normalize_media("anime", raw_anime(isAdult=True)))
        self.assertIsNone(anilist.normalize_media("anime", raw_anime(id=0)))
        self.assertIsNone(anilist.normalize_media("anime", raw_anime(
            title={"romaji": "", "english": "", "native": ""})))

    def test_unsafe_image_urls_are_dropped(self):
        item = anilist.normalize_media("anime", raw_anime(
            coverImage={"extraLarge": "https://example.com/cover.jpg", "large": "", "color": "#fff"},
            bannerImage="javascript:alert(1)",
        ))
        self.assertEqual(item["cover"], "")
        self.assertEqual(item["banner"], "")
        self.assertEqual(item["coverColor"], "#fff")

        item = anilist.normalize_media("anime", raw_anime(
            coverImage={
                "extraLarge": "https://anilist.co:443/file/cover.jpg",
                "large": "https://user:pass@anilist.co/file/cover.jpg",
                "color": "",
            },
            bannerImage="https://evil-anilist.co/banner.jpg",
        ))
        self.assertEqual(item["cover"], "")
        self.assertEqual(item["banner"], "")

    def test_safe_image_hosts_accept_anilist_subdomains_only(self):
        self.assertTrue(anilist.safe_image_url("https://s4.anilist.co/a.jpg"))
        self.assertTrue(anilist.safe_image_url("https://anili.st/a.jpg"))
        self.assertFalse(anilist.safe_image_url("http://s4.anilist.co/a.jpg"))
        self.assertFalse(anilist.safe_image_url("https://anilist.co.evil.com/a.jpg"))
        self.assertFalse(anilist.safe_image_url("https://notanilist.co/a.jpg"))
        self.assertFalse(anilist.safe_image_url("https://s4.anilist.co/a b.jpg"))
        self.assertFalse(anilist.safe_image_url("https://s4.anilist.co:444/a.jpg"))

    def test_html_description_is_plain_text_and_bounded(self):
        description = "<div>Hello &amp; welcome</div><script>bad()</script><p>Next</p>"
        self.assertEqual(anilist.clean_description(description), "Hello & welcome\nNext")
        self.assertEqual(anilist.clean_description(None), "")
        self.assertLessEqual(len(anilist.clean_description("x" * 9000)), 5000)

    def test_page_deduplicates_media_and_preserves_page_info(self):
        page = anilist.normalize_page(
            "anime",
            page_payload(raw_anime(), raw_anime(title={"romaji": "Duplicate"}), current=2, has_next=False),
            requested_page=2,
            requested_per_page=24,
        )
        self.assertEqual(len(page["results"]), 1)
        self.assertEqual(page["page"], 2)
        self.assertFalse(page["hasNextPage"])
        self.assertFalse(page["cached"])

    def test_missing_page_shape_is_an_invalid_response(self):
        for data in (None, {}, {"Page": {}}, {"Page": {"pageInfo": {}, "media": None}}):
            with self.subTest(data=data):
                with self.assertRaises(anilist.BridgeError) as caught:
                    anilist.normalize_page("anime", data)
                self.assertEqual(caught.exception.code, "invalid_response")


class ApiAndSearchTests(EnvironmentMixin, unittest.TestCase):
    def test_search_builds_expected_variables_and_caches_results(self):
        captured = {}

        def fake_api(variables):
            captured.update(variables)
            return page_payload(raw_anime()), {"rateLimit": {"limit": 30, "remaining": 29}, "fetchedAt": 123}

        with patch.object(anilist, "api_request", side_effect=fake_api):
            first = anilist.search(search_args(
                type="anime", query="attack", genre="Action", status="RELEASING",
                country="JP", sort="TRENDING_DESC", page=2, per_page=12,
            ))
            second = anilist.search(search_args(
                type="anime", query="attack", genre="Action", status="RELEASING",
                country="JP", sort="TRENDING_DESC", page=2, per_page=12,
            ))

        self.assertEqual(captured["type"], "ANIME")
        self.assertEqual(captured["search"], "attack")
        self.assertEqual(captured["genres"], ["Action"])
        self.assertEqual(captured["status"], "RELEASING")
        self.assertEqual(captured["country"], "JP")
        self.assertEqual(captured["sort"], ["TRENDING_DESC"])
        self.assertEqual(captured["page"], 2)
        self.assertEqual(captured["perPage"], 12)
        self.assertNotIn("season", captured)
        self.assertTrue(first["ok"])
        self.assertFalse(first["cached"])
        self.assertEqual(first["rateLimit"], {"limit": 30, "remaining": 29})
        self.assertTrue(second["cached"])

    def test_different_queries_do_not_share_cache_entries(self):
        calls = []

        def fake_api(variables):
            calls.append(variables.get("search"))
            return page_payload(raw_anime()), {"rateLimit": {}, "fetchedAt": 1}

        with patch.object(anilist, "api_request", side_effect=fake_api):
            anilist.search(search_args(query="one"))
            anilist.search(search_args(query="two"))
        self.assertEqual(calls, ["one", "two"])

    def test_seasonal_search_sends_season_variables(self):
        captured = {}
        with patch.object(anilist, "current_season", return_value=("FALL", 2026)), \
             patch.object(anilist, "api_request") as request:
            request.side_effect = lambda variables: (
                captured.update(variables)
                or (page_payload(raw_anime()), {"rateLimit": {}, "fetchedAt": 1})
            )
            result = anilist.search(search_args(seasonal=True))
        self.assertEqual(captured["season"], "FALL")
        self.assertEqual(captured["seasonYear"], 2026)
        self.assertEqual(result["season"], "FALL")
        self.assertEqual(result["seasonYear"], 2026)

    def test_successful_http_response_is_normalized(self):
        body = json.dumps({
            "data": page_payload(raw_anime()),
            "errors": None,
        }).encode()
        headers = {"X-RateLimit-Limit": "30", "X-RateLimit-Remaining": "28"}
        with patch.object(anilist.urllib.request, "urlopen", return_value=FakeResponse(body, headers=headers)):
            data, meta = anilist.api_request({"type": "ANIME"})
        self.assertIn("Page", data)
        self.assertEqual(meta["rateLimit"], {"limit": 30, "remaining": 28})

    def test_http_429_writes_cooldown_and_reports_retry_after(self):
        headers = Message()
        headers["Retry-After"] = "45"
        headers["X-RateLimit-Limit"] = "30"
        headers["X-RateLimit-Remaining"] = "0"
        error = http_error(429, b'{"errors":[{"message":"Too Many Requests"}]}', headers)
        with patch.object(anilist.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(anilist.BridgeError) as caught:
                anilist.api_request({})
        self.assertEqual(caught.exception.code, "rate_limited")
        self.assertTrue(caught.exception.retryable)
        self.assertEqual(caught.exception.retry_after, 45)
        self.assertGreater(anilist.cooldown_remaining(), 40)

    def test_cooldown_prevents_network_requests(self):
        anilist.write_cooldown(30)
        with patch.object(anilist.urllib.request, "urlopen") as opened:
            with self.assertRaises(anilist.BridgeError) as caught:
                anilist.api_request({})
        opened.assert_not_called()
        self.assertEqual(caught.exception.code, "rate_limited")

    def test_graphql_and_http_errors_are_mapped(self):
        cases = [
            ("return", FakeResponse(json.dumps({"errors": [{"message": "Bad query", "status": 400}]}).encode()),
             "graphql_error", False),
            ("raise", http_error(500, b'{"errors":[{"message":"Backend down"}]}'),
             "server_error", True),
            ("raise", http_error(403), "forbidden", False),
            ("raise", http_error(404), "not_found", False),
        ]
        for mode, response, code, retryable in cases:
            with self.subTest(code=code):
                patched = patch.object(anilist.urllib.request, "urlopen",
                                       return_value=response if mode == "return" else None,
                                       side_effect=None if mode == "return" else response)
                with patched:
                    with self.assertRaises(anilist.BridgeError) as caught:
                        anilist.api_request({})
                self.assertEqual(caught.exception.code, code)
                self.assertEqual(caught.exception.retryable, retryable)

    def test_malformed_and_oversized_responses_are_rejected(self):
        with patch.object(anilist.urllib.request, "urlopen", return_value=FakeResponse(b"{not json")):
            with self.assertRaises(anilist.BridgeError) as caught:
                anilist.api_request({})
        self.assertEqual(caught.exception.code, "invalid_response")

        with patch.object(anilist, "MAX_RESPONSE_BYTES", 8), \
             patch.object(anilist.urllib.request, "urlopen", return_value=FakeResponse(b'{"data":{}}')):
            with self.assertRaises(anilist.BridgeError) as caught:
                anilist.api_request({})
        self.assertEqual(caught.exception.code, "invalid_response")

    def test_network_failure_is_retryable(self):
        with patch.object(anilist.urllib.request, "urlopen", side_effect=urllib.error.URLError("offline")):
            with self.assertRaises(anilist.BridgeError) as caught:
                anilist.api_request({})
        self.assertEqual(caught.exception.code, "network_error")
        self.assertTrue(caught.exception.retryable)

    def test_retry_after_parsing_supports_seconds_dates_and_reset(self):
        seconds = Message()
        seconds["Retry-After"] = "17"
        self.assertEqual(anilist.retry_after_seconds(seconds, now=1000), 17)

        reset = Message()
        reset["X-RateLimit-Reset"] = "1100"
        self.assertEqual(anilist.retry_after_seconds(reset, now=1000), 100)

        fallback = Message()
        self.assertEqual(anilist.retry_after_seconds(fallback, now=1000), 60)

    def test_cli_error_is_json_and_does_not_hit_network(self):
        output = io.StringIO()
        with patch.object(anilist.urllib.request, "urlopen") as opened, \
             contextlib.redirect_stdout(output):
            code = anilist.main(["search", "--type", "anime", "--genre", "Hentai"])
        opened.assert_not_called()
        payload = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_request")


if __name__ == "__main__":
    unittest.main()
