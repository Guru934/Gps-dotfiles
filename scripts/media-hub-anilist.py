#!/usr/bin/env python3
"""Narrow AniList GraphQL bridge for the Media Hub anime and manga pages.

Only validated public catalogue searches are supported. The helper owns HTTP
errors, GraphQL errors, rate-limit cooldowns, a small on-disk response cache and
response normalization; presentation state stays in QML.
"""

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from pathlib import Path


API_URL = "https://graphql.anilist.co"
USER_AGENT = "GPS-Media-Hub/1.0"
TIMEOUT_SECONDS = 12
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
CACHE_VERSION = 3
CACHE_TTL_SECONDS = 600
MAX_CACHE_AGE_SECONDS = 7 * 24 * 60 * 60
MAX_PAGE = 500
MAX_PER_PAGE = 50
MAX_TEXT = 240
MAX_DESCRIPTION = 5000

GENRES = {
    "Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror",
    "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological",
    "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller",
}
STATUSES = {
    "anime": {"RELEASING", "FINISHED", "NOT_YET_RELEASED", "HIATUS", "CANCELLED"},
    "manga": {"RELEASING", "FINISHED", "NOT_YET_RELEASED", "HIATUS", "CANCELLED"},
}
COUNTRIES = {"JP", "KR", "CN", "TW"}
SORTS = {
    "TRENDING_DESC", "POPULARITY_DESC", "SCORE_DESC", "START_DATE_DESC",
    "TITLE_ROMAJI", "FAVOURITES_DESC", "UPDATED_AT_DESC",
}

QUERY = """
query (
  $type: MediaType!
  $page: Int!
  $perPage: Int!
  $search: String
  $genres: [String]
  $status: MediaStatus
  $country: CountryCode
  $season: MediaSeason
  $seasonYear: Int
  $sort: [MediaSort]!
) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { currentPage hasNextPage perPage }
    media(
      type: $type
      search: $search
      genre_in: $genres
      status: $status
      countryOfOrigin: $country
      season: $season
      seasonYear: $seasonYear
      sort: $sort
      isAdult: false
    ) {
      id
      type
      title { romaji english native }
      synonyms
      description(asHtml: false)
      siteUrl
      coverImage { extraLarge large color }
      bannerImage
      format
      status
      season
      seasonYear
      startDate { year }
      episodes
      chapters
      volumes
      duration
      averageScore
      meanScore
      popularity
      trending
      favourites
      genres
      countryOfOrigin
      isAdult
      studios(isMain: true) { nodes { name } }
      staff(perPage: 6) { edges { role node { name { full } } } }
      externalLinks { id url site type }
    }
  }
}
"""


class BridgeError(Exception):
    def __init__(self, code, message, retry_after=None, retryable=False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retry_after = retry_after
        self.retryable = retryable


class PlainTextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
        elif tag in ("br", "p", "div", "li"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.skip:
            self.skip -= 1
        elif tag in ("p", "div", "li"):
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def clean_text(value, limit=MAX_TEXT):
    if not isinstance(value, str):
        return ""
    text = "".join(ch for ch in value if ch >= " " and ch != "\x7f")
    text = " ".join(text.split())
    return text[:limit].strip()


def clean_description(value):
    if not isinstance(value, str):
        return ""
    parser = PlainTextParser()
    try:
        parser.feed(value)
        parser.close()
    except Exception:
        return ""
    text = "".join(parser.parts).replace("\r", "")
    lines = [" ".join(line.split()) for line in text.split("\n")]
    text = "\n".join(line for line in lines if line)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text[:MAX_DESCRIPTION].strip()


def bounded_int(value, fallback=0, minimum=0, maximum=100_000_000):
    if isinstance(value, bool) or not isinstance(value, int):
        return fallback
    return max(minimum, min(maximum, value))


def safe_image_url(value):
    if not isinstance(value, str):
        return ""
    raw = value.strip()
    if not raw or len(raw) > 2048 or any(ord(ch) <= 32 or ord(ch) == 127 for ch in raw):
        return ""
    try:
        parsed = urllib.parse.urlsplit(raw)
        port = parsed.port
        host = (parsed.hostname or "").lower()
    except ValueError:
        return ""
    if parsed.scheme != "https" or parsed.username or parsed.password or port is not None:
        return ""
    trusted = host == "anilist.co" or host.endswith(".anilist.co")
    trusted = trusted or host == "anili.st" or host.endswith(".anili.st")
    if not trusted:
        return ""
    return raw


def safe_external_url(value):
    if not isinstance(value, str):
        return ""
    raw = value.strip()
    if not raw or len(raw) > 2048 or any(ord(ch) <= 32 or ord(ch) == 127 for ch in raw):
        return ""
    try:
        parsed = urllib.parse.urlsplit(raw)
        port = parsed.port
    except ValueError:
        return ""
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        return ""
    if parsed.username or parsed.password:
        return ""
    if port is not None and port != 443:
        return ""
    return raw


def validated_text(value, label, limit, required=False):
    text = clean_text(value, limit + 1)
    if len(text) > limit:
        raise BridgeError("invalid_request", f"{label} is too long.")
    if required and not text:
        raise BridgeError("invalid_request", f"{label} is required.")
    return text


def current_season(today=None):
    day = today or date.today()
    if day.month <= 3:
        season = "WINTER"
    elif day.month <= 6:
        season = "SPRING"
    elif day.month <= 9:
        season = "SUMMER"
    else:
        season = "FALL"
    return season, day.year


def header_value(headers, name):
    if not headers:
        return ""
    try:
        for key, value in headers.items():
            if str(key).lower() == name.lower():
                return str(value)
    except Exception:
        return ""
    return ""


def retry_after_seconds(headers, now=None):
    now = now if now is not None else time.time()
    raw = header_value(headers, "Retry-After").strip()
    if raw:
        try:
            seconds = int(raw)
            return max(1, min(86400, seconds))
        except ValueError:
            try:
                parsed = parsedate_to_datetime(raw)
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                return max(1, min(86400, int(parsed.timestamp() - now)))
            except Exception:
                pass
    reset = header_value(headers, "X-RateLimit-Reset").strip()
    if reset:
        try:
            return max(1, min(86400, int(float(reset) - now)))
        except ValueError:
            pass
    return 60


def cache_root():
    configured = os.environ.get("XDG_CACHE_HOME", "")
    if configured and os.path.isabs(configured):
        root = Path(configured)
    else:
        home = os.environ.get("HOME", "")
        if not home or not os.path.isabs(home):
            raise OSError("HOME is not an absolute path")
        root = Path(home) / ".cache"
    path = root / "gps-media-hub" / "anilist"
    path.mkdir(parents=True, exist_ok=True)
    return path


def cache_key(request):
    raw = json.dumps({"version": CACHE_VERSION, "request": request}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def cache_path(request):
    return cache_root() / (cache_key(request) + ".json")


def atomic_json_write(path, payload):
    temp = path.with_name(path.name + ".tmp-" + str(os.getpid()))
    temp.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    os.replace(temp, path)


def prune_cache(root, now=None):
    now = now if now is not None else time.time()
    try:
        for path in root.glob("*.json"):
            if path.stat().st_mtime < now - MAX_CACHE_AGE_SECONDS:
                path.unlink()
    except OSError:
        return


def read_cache(request):
    try:
        path = cache_path(request)
        if not path.is_file():
            return None
        if path.stat().st_mtime < time.time() - CACHE_TTL_SECONDS:
            return None
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict) or payload.get("request") != request:
            return None
        response = payload.get("response")
        if not isinstance(response, dict) or not isinstance(response.get("results"), list):
            return None
        return response
    except (OSError, ValueError, TypeError):
        return None


def write_cache(request, response):
    try:
        root = cache_root()
        atomic_json_write(cache_path(request), {
            "request": request,
            "response": response,
            "cachedAt": int(time.time()),
        })
        prune_cache(root)
    except OSError:
        pass


def cooldown_path():
    return cache_root() / "rate-limit.json"


def cooldown_remaining(now=None):
    now = now if now is not None else time.time()
    try:
        payload = json.loads(cooldown_path().read_text(encoding="utf-8"))
        until = float(payload.get("until", 0))
    except (OSError, ValueError, TypeError):
        return 0
    return max(0, min(86400, int(until - now + 0.999)))


def write_cooldown(seconds, now=None):
    now = now if now is not None else time.time()
    seconds = max(1, min(86400, int(seconds)))
    try:
        atomic_json_write(cooldown_path(), {"until": now + seconds})
    except OSError:
        pass
    return seconds


def rate_limit_meta(headers):
    limit = header_value(headers, "X-RateLimit-Limit")
    remaining = header_value(headers, "X-RateLimit-Remaining")
    return {
        "limit": bounded_int(int(limit), 0, 0, 1_000_000) if limit.isdigit() else 0,
        "remaining": bounded_int(int(remaining), 0, 0, 1_000_000) if remaining.isdigit() else 0,
    }


def error_message_from_body(raw):
    try:
        payload = json.loads(raw.decode("utf-8", errors="replace"))
        errors = payload.get("errors") if isinstance(payload, dict) else None
        if isinstance(errors, list) and errors and isinstance(errors[0], dict):
            message = clean_text(errors[0].get("message"), 240)
            if message:
                return message
    except Exception:
        pass
    return ""


def api_request(variables):
    remaining = cooldown_remaining()
    if remaining > 0:
        raise BridgeError(
            "rate_limited",
            f"AniList asked us to wait {remaining} seconds before another request.",
            retry_after=remaining,
            retryable=True,
        )
    body = json.dumps({"query": QUERY, "variables": variables}, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=body,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    headers = {}
    status = 200
    raw = b""
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            status = bounded_int(getattr(response, "status", 200), 200, 100, 599)
            headers = getattr(response, "headers", {}) or {}
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        status = bounded_int(error.code, 500, 100, 599)
        headers = error.headers or {}
        try:
            raw = error.read(MAX_RESPONSE_BYTES + 1)
        except Exception:
            raw = b""
        message = error_message_from_body(raw) or f"AniList returned HTTP {status}."
        if status == 429:
            seconds = write_cooldown(retry_after_seconds(headers))
            raise BridgeError("rate_limited", message, retry_after=seconds, retryable=True)
        if status in (401, 403):
            raise BridgeError("forbidden", "AniList refused this request.", retryable=False)
        if status == 404:
            raise BridgeError("not_found", "AniList could not find that catalogue entry.", retryable=False)
        if status >= 500:
            raise BridgeError("server_error", message, retryable=True)
        raise BridgeError("graphql_error", message, retryable=False)
    except (TimeoutError, urllib.error.URLError, OSError) as error:
        reason = getattr(error, "reason", error)
        if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
            raise BridgeError("network_error", "AniList timed out. Check your connection and retry.", retryable=True)
        raise BridgeError("network_error", "AniList is unreachable. Check your connection and retry.", retryable=True)

    if len(raw) > MAX_RESPONSE_BYTES:
        raise BridgeError("invalid_response", "AniList returned an oversized response.", retryable=False)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise BridgeError("invalid_response", "AniList returned malformed JSON.", retryable=True)
    if not isinstance(payload, dict):
        raise BridgeError("invalid_response", "AniList returned an invalid response.", retryable=True)

    errors = payload.get("errors")
    if isinstance(errors, list) and errors:
        first = errors[0] if isinstance(errors[0], dict) else {}
        message = clean_text(first.get("message"), 240) or "AniList rejected the GraphQL request."
        error_status = bounded_int(first.get("status"), status, 100, 599)
        if error_status == 429 or status == 429:
            seconds = write_cooldown(retry_after_seconds(headers))
            raise BridgeError("rate_limited", message, retry_after=seconds, retryable=True)
        if error_status >= 500:
            raise BridgeError("server_error", message, retryable=True)
        raise BridgeError("graphql_error", message, retryable=False)

    data = payload.get("data")
    if not isinstance(data, dict):
        raise BridgeError("invalid_response", "AniList returned no catalogue data.", retryable=True)
    meta = {"rateLimit": rate_limit_meta(headers), "fetchedAt": int(time.time())}
    return data, meta


def normalized_alt_titles(raw, display):
    values = []
    for value in raw.get("synonyms") if isinstance(raw.get("synonyms"), list) else []:
        text = clean_text(value, 160)
        if text and text != display and text not in values:
            values.append(text)
    titles = raw.get("title") if isinstance(raw.get("title"), dict) else {}
    for key in ("romaji", "english", "native"):
        text = clean_text(titles.get(key), 160)
        if text and text != display and text not in values:
            values.append(text)
    return values[:8]


def format_label(value):
    labels = {
        "TV": "TV", "TV_SHORT": "TV Short", "MOVIE": "Movie", "SPECIAL": "Special",
        "OVA": "OVA", "ONA": "ONA", "MUSIC": "Music",
        "MANGA": "Manga", "NOVEL": "Light Novel", "ONE_SHOT": "One-shot",
    }
    return labels.get(value, clean_text(value, 24).replace("_", " ").title() if isinstance(value, str) else "")


def catalogue_status_label(kind, value):
    labels = {
        "RELEASING": "Airing" if kind == "anime" else "Ongoing",
        "FINISHED": "Finished" if kind == "anime" else "Completed",
        "NOT_YET_RELEASED": "Upcoming",
        "HIATUS": "Hiatus",
        "CANCELLED": "Cancelled",
    }
    return labels.get(value, clean_text(value, 32).replace("_", " ").title() if isinstance(value, str) else "Unknown")


def manga_type(country):
    if country == "KR":
        return "Manhwa"
    if country in ("CN", "TW"):
        return "Manhua"
    return "Manga"


def normalize_media(kind, raw):
    if not isinstance(raw, dict):
        return None
    expected_type = "ANIME" if kind == "anime" else "MANGA"
    if raw.get("type") != expected_type:
        return None
    raw_id = raw.get("id")
    if isinstance(raw_id, bool) or not isinstance(raw_id, int) or raw_id <= 0:
        return None
    catalogue_id = bounded_int(raw_id, 0, 1, 2_000_000_000)
    if catalogue_id <= 0 or raw.get("isAdult") is True:
        return None
    titles = raw.get("title") if isinstance(raw.get("title"), dict) else {}
    romaji = clean_text(titles.get("romaji"), 200)
    english = clean_text(titles.get("english"), 200)
    native = clean_text(titles.get("native"), 200)
    title = english or romaji or native
    if not title:
        return None

    cover = raw.get("coverImage") if isinstance(raw.get("coverImage"), dict) else {}
    cover_url = safe_image_url(cover.get("extraLarge")) or safe_image_url(cover.get("large"))
    banner_url = safe_image_url(raw.get("bannerImage"))
    country = raw.get("countryOfOrigin") if raw.get("countryOfOrigin") in COUNTRIES else ""
    score = bounded_int(raw.get("averageScore"), 0, 0, 100)
    year = 0
    start = raw.get("startDate") if isinstance(raw.get("startDate"), dict) else {}
    if isinstance(start.get("year"), int):
        year = bounded_int(start.get("year"), 0, 0, 3000)
    season_year = bounded_int(raw.get("seasonYear"), 0, 0, 3000)
    if year == 0:
        year = season_year

    genres = []
    for value in raw.get("genres") if isinstance(raw.get("genres"), list) else []:
        text = clean_text(value, 40)
        if text in GENRES and text not in genres:
            genres.append(text)

    official_links = []
    for link in raw.get("externalLinks") if isinstance(raw.get("externalLinks"), list) else []:
        if not isinstance(link, dict) or link.get("type") != "STREAMING":
            continue
        url = safe_external_url(link.get("url"))
        site = clean_text(link.get("site"), 80)
        if not url or not site:
            continue
        if any(existing["url"] == url for existing in official_links):
            continue
        official_links.append({"site": site, "url": url})
        if len(official_links) >= 6:
            break

    studios = []
    studio_obj = raw.get("studios") if isinstance(raw.get("studios"), dict) else {}
    for node in studio_obj.get("nodes") if isinstance(studio_obj.get("nodes"), list) else []:
        name = clean_text(node.get("name"), 100) if isinstance(node, dict) else ""
        if name and name not in studios:
            studios.append(name)

    staff = []
    staff_obj = raw.get("staff") if isinstance(raw.get("staff"), dict) else {}
    for edge in staff_obj.get("edges") if isinstance(staff_obj.get("edges"), list) else []:
        if not isinstance(edge, dict):
            continue
        role = clean_text(edge.get("role"), 80) or "Staff"
        node = edge.get("node") if isinstance(edge.get("node"), dict) else {}
        name_obj = node.get("name") if isinstance(node.get("name"), dict) else {}
        name = clean_text(name_obj.get("full"), 100)
        if name:
            staff.append({"role": role, "name": name})
        if len(staff) >= 6:
            break
    author_names = []
    for member in staff:
        if member["name"] not in author_names:
            author_names.append(member["name"])
    author = " · ".join(author_names[:3])

    total = bounded_int(raw.get("episodes") if kind == "anime" else raw.get("chapters"), 0, 0, 100_000)
    volumes = bounded_int(raw.get("volumes"), 0, 0, 100_000)
    catalogue_status = raw.get("status") if raw.get("status") in STATUSES[kind] else ""
    season = raw.get("season") if raw.get("season") in ("WINTER", "SPRING", "SUMMER", "FALL") else ""
    season_label = ""
    if season:
        season_label = season.title() + (f" {season_year}" if season_year else "")
    elif year:
        season_label = str(year)

    return {
        "kind": kind,
        "id": f"{kind}-{catalogue_id}",
        "catalogueId": catalogue_id,
        "title": title,
        "titleRomaji": romaji,
        "titleEnglish": english,
        "titleNative": native,
        "altTitles": normalized_alt_titles(raw, title),
        "description": clean_description(raw.get("description")),
        "genres": genres,
        "year": year,
        "season": season,
        "seasonYear": season_year,
        "seasonLabel": season_label,
        "catalogueStatus": catalogue_status,
        "statusLabel": catalogue_status_label(kind, catalogue_status),
        "format": clean_text(raw.get("format"), 24),
        "formatLabel": format_label(raw.get("format")),
        "type": "Anime" if kind == "anime" else manga_type(country),
        "country": country,
        "countryLabel": {"JP": "Japan", "KR": "Korea", "CN": "China", "TW": "Taiwan"}.get(country, ""),
        "episodes": bounded_int(raw.get("episodes"), 0, 0, 100_000) if kind == "anime" else 0,
        "chapters": bounded_int(raw.get("chapters"), 0, 0, 100_000) if kind == "manga" else 0,
        "volumes": volumes if kind == "manga" else 0,
        "total": total,
        "duration": bounded_int(raw.get("duration"), 0, 0, 10_000) if kind == "anime" else 0,
        "score": score,
        "scoreLabel": f"{score / 10:.1f}" if score > 0 else "—",
        "popularity": bounded_int(raw.get("popularity"), 0, 0, 2_000_000_000),
        "trending": bounded_int(raw.get("trending"), 0, 0, 2_000_000_000),
        "favourites": bounded_int(raw.get("favourites"), 0, 0, 2_000_000_000),
        "cover": cover_url,
        "coverColor": clean_text(cover.get("color"), 16),
        "banner": banner_url,
        "siteUrl": f"https://anilist.co/{kind}/{catalogue_id}",
        "officialLinks": official_links,
        "studios": studios[:4],
        "staff": staff,
        "author": author,
        "isAdult": False,
    }


def normalize_page(kind, data, requested_page=1, requested_per_page=24):
    page = data.get("Page") if isinstance(data, dict) else None
    if not isinstance(page, dict):
        raise BridgeError("invalid_response", "AniList returned no Page object.", retryable=True)
    info = page.get("pageInfo") if isinstance(page.get("pageInfo"), dict) else {}
    media = page.get("media")
    if not isinstance(media, list):
        raise BridgeError("invalid_response", "AniList returned no media list.", retryable=True)
    results = []
    seen = set()
    for raw in media:
        item = normalize_media(kind, raw)
        if item is not None and item["id"] not in seen:
            seen.add(item["id"])
            results.append(item)
    current_page = bounded_int(info.get("currentPage"), requested_page, 1, MAX_PAGE)
    per_page = bounded_int(info.get("perPage"), requested_per_page, 1, MAX_PER_PAGE)
    return {
        "ok": True,
        "source": "anilist",
        "kind": kind,
        "page": current_page,
        "perPage": per_page,
        "hasNextPage": info.get("hasNextPage") is True,
        "results": results,
        "cached": False,
    }


def validated_request(args):
    kind = args.type
    if kind not in ("anime", "manga"):
        raise BridgeError("invalid_request", "Unsupported catalogue type.")
    query = validated_text(args.query, "Search query", 100)
    genre = validated_text(args.genre, "Genre", 40)
    if genre:
        if genre not in GENRES:
            raise BridgeError("invalid_request", "Unsupported AniList genre.")
    status = validated_text(args.status, "Status", 32)
    if status:
        if status not in STATUSES[kind]:
            raise BridgeError("invalid_request", "Unsupported AniList status for this catalogue.")
    country = validated_text(args.country, "Country", 2).upper()
    if country and country not in COUNTRIES:
        raise BridgeError("invalid_request", "Unsupported country of origin.")
    sort = validated_text(args.sort, "Sort", 32).upper()
    if sort not in SORTS:
        raise BridgeError("invalid_request", "Unsupported AniList sort.")
    page = bounded_int(args.page, 1, 1, MAX_PAGE)
    if page != args.page:
        raise BridgeError("invalid_request", "Page must be between 1 and 500.")
    per_page = bounded_int(args.per_page, 24, 1, MAX_PER_PAGE)
    if per_page != args.per_page:
        raise BridgeError("invalid_request", "Page size must be between 1 and 50.")
    seasonal = bool(args.seasonal)
    if seasonal and kind != "anime":
        raise BridgeError("invalid_request", "Seasonal browsing is only available for anime.")
    season = season_year = None
    if seasonal:
        season, season_year = current_season()
    request = {
        "kind": kind,
        "query": query,
        "genre": genre,
        "status": status,
        "country": country,
        "sort": sort,
        "page": page,
        "perPage": per_page,
        "seasonal": seasonal,
        "season": season,
        "seasonYear": season_year,
    }
    return request


def search(args):
    request = validated_request(args)
    cached = read_cache(request)
    if cached is not None:
        cached = dict(cached)
        cached["cached"] = True
        return cached

    variables = {
        "type": "ANIME" if request["kind"] == "anime" else "MANGA",
        "page": request["page"],
        "perPage": request["perPage"],
        "sort": [request["sort"]],
    }
    if request["query"]:
        variables["search"] = request["query"]
    if request["genre"]:
        variables["genres"] = [request["genre"]]
    if request["status"]:
        variables["status"] = request["status"]
    if request["country"]:
        variables["country"] = request["country"]
    if request["seasonal"]:
        variables["season"] = request["season"]
        variables["seasonYear"] = request["seasonYear"]

    data, meta = api_request(variables)
    response = normalize_page(request["kind"], data, request["page"], request["perPage"])
    response["season"] = request["season"]
    response["seasonYear"] = request["seasonYear"]
    response["sort"] = request["sort"]
    response["request"] = request
    response["rateLimit"] = meta.get("rateLimit", {})
    response["fetchedAt"] = meta.get("fetchedAt", int(time.time()))
    write_cache(request, {k: v for k, v in response.items() if k not in ("request",)})
    return response


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="GPS Media Hub AniList bridge")
    sub = parser.add_subparsers(dest="command", required=True)
    search_parser = sub.add_parser("search")
    search_parser.add_argument("--type", required=True, choices=("anime", "manga"))
    search_parser.add_argument("--query", default="")
    search_parser.add_argument("--genre", default="")
    search_parser.add_argument("--status", default="")
    search_parser.add_argument("--country", default="")
    search_parser.add_argument("--sort", default="POPULARITY_DESC")
    search_parser.add_argument("--page", type=int, default=1)
    search_parser.add_argument("--per-page", type=int, default=24)
    search_parser.add_argument("--seasonal", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        if args.command == "search":
            result = search(args)
        else:
            raise BridgeError("invalid_request", "Unsupported command.")
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
        return 0
    except BridgeError as error:
        payload = {
            "ok": False,
            "code": error.code,
            "message": error.message,
            "retryable": bool(error.retryable),
        }
        if error.retry_after is not None:
            payload["retryAfter"] = int(error.retry_after)
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        return 1
    except Exception:
        print(json.dumps({
            "ok": False,
            "code": "internal_error",
            "message": "The AniList helper hit an unexpected internal error.",
            "retryable": False,
        }, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    sys.exit(main())
