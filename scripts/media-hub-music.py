#!/usr/bin/env python3
"""Narrow music catalogue bridge for the Media Hub.

The helper exposes three validated operations: credential status, Jamendo
track search, and Radio Browser station search. It never downloads media and
does not accept arbitrary command arguments.
"""
from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


JAMENDO_API = "https://api.jamendo.com/v3.0/tracks/"
RADIO_API = "https://all.api.radio-browser.info/json/stations/search"
USER_AGENT = "GPS-MediaHub/1.0"
MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_CONFIG_BYTES = 256 * 1024
JAMENDO_HOSTS = {"jamendo.com", "www.jamendo.com"}
JAMENDO_ASSET_SUFFIX = ".jamendo.com"
JAMENDO_ORDERS = {
    "popularity_total",
    "popularity_month",
    "popularity_week",
    "releasedate_desc",
    "releasedate_asc",
    "name",
    "duration_desc",
    "duration_asc",
}
RADIO_ORDERS = {"clickcount", "clicktrend", "votes", "name", "bitrate", "random"}
CLIENT_ID_RE = re.compile(r"^[A-Za-z0-9:_-]{8,128}$")
JAMENDO_ID_RE = re.compile(r"^[0-9]{1,24}$")
RADIO_ID_RE = re.compile(r"^[0-9a-fA-F-]{32,40}$")
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
PALETTES = [
    ["#0b1030", "#2a1b5e", "#0e4a6b"],
    ["#071a1f", "#0e4a5b", "#a78bfa"],
    ["#2a1236", "#6b2c5f", "#f59e8b"],
    ["#1a1208", "#5a3a14", "#fbbf24"],
    ["#06150f", "#0f4a3a", "#7bd0ff"],
    ["#0b0f17", "#1f2937", "#475569"],
]
MOOD_TAGS = {
    "night drive": "synthwave",
    "dreamy": "ambient",
    "focus": "instrumental",
    "cosmic": "ambient",
    "energize": "electronic",
    "rainy day": "lofi",
}


class BridgeError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def emit(payload: dict, exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return exit_code


def fail(code: str, message: str) -> int:
    return emit({"ok": False, "code": code, "message": message}, 1)


def clean_text(value: object, limit: int = 200) -> str:
    if not isinstance(value, str):
        return ""
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", value)
    text = " ".join(text.split())
    return text[:limit]


def bounded_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return default


def clamp_int(value: object, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, bounded_int(value, minimum)))


def config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME", "")
    if base and "\0" not in base and Path(base).is_absolute():
        root = Path(base)
    else:
        root = Path.home() / ".config"
    return root / "quickshell" / "rice-settings.json"


def read_config_client_id() -> tuple[str, str]:
    path = config_path()
    try:
        if not path.is_file() or path.stat().st_size > MAX_CONFIG_BYTES:
            return "", ""
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return "", "Could not read music.jamendoClientId from the settings file."
    if not isinstance(payload, dict):
        return "", "The Quickshell settings file is not a JSON object."
    music = payload.get("music")
    value = music.get("jamendoClientId") if isinstance(music, dict) else None
    if not isinstance(value, str):
        return "", ""
    value = value.strip()
    if value == "":
        return "", ""
    if not CLIENT_ID_RE.fullmatch(value):
        return "", "music.jamendoClientId is not a valid Jamendo client ID."
    return value, ""


def jamendo_client_id() -> tuple[str, str, str]:
    value = os.environ.get("JAMENDO_CLIENT_ID", "").strip()
    if value:
        if not CLIENT_ID_RE.fullmatch(value):
            return "", "", "JAMENDO_CLIENT_ID is not a valid Jamendo client ID."
        return value, "environment", ""
    value, message = read_config_client_id()
    return value, ("config" if value else ""), message


def safe_url(value: object, schemes: set[str], host_suffix: str = "") -> str:
    if not isinstance(value, str) or not value or len(value) > 2048:
        return ""
    if re.search(r"[\x00-\x20\x7f]", value):
        return ""
    try:
        parsed = urllib.parse.urlsplit(value)
        host = (parsed.hostname or "").lower().rstrip(".")
        port = parsed.port
    except ValueError:
        return ""
    if parsed.scheme.lower() not in schemes or not host:
        return ""
    if parsed.username or parsed.password:
        return ""
    if port is not None and not 1 <= port <= 65535:
        return ""
    if host_suffix:
        suffix = host_suffix.lower().lstrip(".")
        if host != suffix and not host.endswith("." + suffix):
            return ""
    return value


def jamendo_asset(value: object) -> str:
    return safe_url(value, {"https"}, JAMENDO_ASSET_SUFFIX)


def jamendo_web(value: object) -> str:
    url = safe_url(value, {"https"})
    if not url:
        return ""
    host = (urllib.parse.urlsplit(url).hostname or "").lower().rstrip(".")
    return url if host in JAMENDO_HOSTS or host.endswith(".jamendo.com") else ""


def safe_web(value: object) -> str:
    return safe_url(value, {"https"})


def safe_stream(value: object) -> str:
    return safe_url(value, {"http", "https"})


def palette(seed: str) -> list[str]:
    total = sum(ord(char) for char in seed) if seed else 0
    return list(PALETTES[total % len(PALETTES)])


def license_label(value: object) -> str:
    raw = clean_text(value, 160)
    match = re.search(r"/licenses/([a-z-]+)/?", raw, re.IGNORECASE)
    code = match.group(1).upper().replace("-", "-") if match else ""
    if code:
        return "CC " + code
    if re.match(r"^CC\b", raw, re.IGNORECASE):
        return raw.upper()
    return "Creative Commons"


def string_list(raw: object, limit: int = 6, item_limit: int = 40) -> list[str]:
    values = raw if isinstance(raw, list) else []
    out: list[str] = []
    for item in values:
        text = clean_text(item, item_limit)
        if text and text not in out:
            out.append(text)
        if len(out) >= limit:
            break
    return out


def infer_moods(tags: list[str]) -> list[str]:
    haystack = " ".join(tags).lower()
    out = []
    for mood, tag in MOOD_TAGS.items():
        if tag in haystack or mood in haystack:
            out.append(mood.title())
    return out[:4]


def normalize_jamendo_track(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    track_id = str(raw.get("id", ""))
    if not JAMENDO_ID_RE.fullmatch(track_id):
        return None
    title = clean_text(raw.get("name"), 180)
    stream = jamendo_asset(raw.get("audio"))
    if not title or not stream:
        return None
    musicinfo = raw.get("musicinfo") if isinstance(raw.get("musicinfo"), dict) else {}
    tags = musicinfo.get("tags") if isinstance(musicinfo.get("tags"), dict) else {}
    genres = string_list(tags.get("genres"), 3)
    instruments = string_list(tags.get("instruments"), 3)
    vartags = string_list(tags.get("vartags"), 6)
    genre = genres[0].title() if genres else "Jamendo"
    source = jamendo_web(raw.get("shareurl")) or jamendo_web(raw.get("shorturl"))
    if not source:
        source = f"https://www.jamendo.com/track/{track_id}"
    art = jamendo_asset(raw.get("album_image")) or jamendo_asset(raw.get("image"))
    return {
        "kind": "track",
        "id": f"jamendo-{track_id}",
        "title": title,
        "artist": clean_text(raw.get("artist_name"), 120) or "Unknown artist",
        "album": clean_text(raw.get("album_name"), 120) or "Jamendo",
        "genre": genre,
        "dur": clamp_int(raw.get("duration"), 0, 24 * 60 * 60),
        "license": license_label(raw.get("license_ccurl")),
        "moods": infer_moods(genres + instruments + vartags),
        "streamUrl": stream,
        "art": art,
        "sourceUrl": source,
        "g": palette(genre),
        "plays": clamp_int(raw.get("listened"), 0, 2_000_000_000),
        "added": 0,
    }


def normalize_radio_station(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    station_id = clean_text(raw.get("stationuuid"), 40)
    if not RADIO_ID_RE.fullmatch(station_id):
        return None
    if bounded_int(raw.get("lastcheckok"), 1) != 1:
        return None
    title = clean_text(raw.get("name"), 180)
    stream = safe_stream(raw.get("url_resolved")) or safe_stream(raw.get("url"))
    if not title or not stream:
        return None
    tags = [tag.strip() for tag in clean_text(raw.get("tags"), 300).split(",") if tag.strip()][:8]
    genre = tags[0].title() if tags else (clean_text(raw.get("codec"), 20) or "Radio")
    country = clean_text(raw.get("country"), 80) or "Global"
    source = safe_web(raw.get("homepage")) or "https://www.radio-browser.info/"
    art = safe_web(raw.get("favicon"))
    votes = clamp_int(raw.get("votes"), 0, 2_000_000_000)
    clicks = clamp_int(raw.get("clickcount"), 0, 2_000_000_000)
    return {
        "kind": "station",
        "id": "radio-" + station_id,
        "title": title,
        "artist": "Live radio",
        "album": "",
        "genre": genre,
        "dur": 0,
        "license": "Radio",
        "moods": infer_moods(tags + [genre]),
        "streamUrl": stream,
        "art": art,
        "sourceUrl": source,
        "g": palette(genre),
        "votes": votes,
        "clicks": clicks,
        "listeners": votes,
        "bitrate": clamp_int(raw.get("bitrate"), 0, 10_000),
        "codec": clean_text(raw.get("codec"), 24) or "Unknown",
        "country": country,
        "hls": bool(raw.get("hls")),
        "tags": tags,
    }


def request_json(url: str, source_name: str, expect: type) -> object:
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status != 200:
                raise BridgeError("http_error", f"{source_name} returned HTTP {response.status}.")
            body = response.read(MAX_JSON_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise BridgeError("rate_limited", f"{source_name} rate limit reached. Wait a minute and retry.")
        if error.code in (401, 403):
            raise BridgeError("forbidden", f"{source_name} refused the request.")
        if error.code >= 500:
            raise BridgeError("server_error", f"{source_name} returned HTTP {error.code}.")
        raise BridgeError("http_error", f"{source_name} returned HTTP {error.code}.") from error
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
        reason = getattr(error, "reason", error)
        raise BridgeError("network_error", f"Could not reach {source_name}: {reason}") from error
    if len(body) > MAX_JSON_BYTES:
        raise BridgeError("invalid_response", f"{source_name} returned an oversized response.")
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BridgeError("invalid_response", f"{source_name} returned invalid JSON.") from error
    if not isinstance(payload, expect):
        raise BridgeError("invalid_response", f"{source_name} returned an invalid payload.")
    return payload


def validated_text(value: str, label: str, limit: int) -> str:
    if not isinstance(value, str):
        raise BridgeError("invalid_request", f"{label} must be text.")
    if re.search(r"[\x00-\x1f\x7f]", value):
        raise BridgeError("invalid_request", f"{label} contains invalid characters.")
    text = " ".join(value.split())
    if len(text) > limit:
        raise BridgeError("invalid_request", f"{label} is too long.")
    return text


def validated_limit(value: int) -> int:
    if not 1 <= value <= 50:
        raise BridgeError("invalid_request", "Limit must be between 1 and 50.")
    return value


def validated_offset(value: int) -> int:
    if not 0 <= value <= 10_000:
        raise BridgeError("invalid_request", "Offset must be between 0 and 10000.")
    return value


def jamendo_search(args: argparse.Namespace) -> dict:
    client_id, source, message = jamendo_client_id()
    if not client_id:
        raise BridgeError("jamendo_unconfigured",
                          message or "Set JAMENDO_CLIENT_ID or music.jamendoClientId to search Jamendo.")
    query = validated_text(args.query, "Query", 160)
    tag = validated_text(args.tag, "Tag", 80)
    if args.order not in JAMENDO_ORDERS:
        raise BridgeError("invalid_request", "Unsupported Jamendo order.")
    params = {
        "client_id": client_id,
        "format": "json",
        "limit": str(validated_limit(args.limit)),
        "offset": str(validated_offset(args.offset)),
        "order": args.order,
        "include": "musicinfo+licenses",
        "audioformat": "mp32",
        "imagesize": "300",
    }
    if query:
        params["search"] = query
    if tag:
        params["fuzzytags"] = tag
    payload = request_json(JAMENDO_API + "?" + urllib.parse.urlencode(params), "Jamendo", dict)
    headers = payload.get("headers")
    results = payload.get("results")
    if not isinstance(headers, dict) or not isinstance(results, list):
        raise BridgeError("invalid_response", "Jamendo returned an invalid search payload.")
    if headers.get("status") != "success":
        code = bounded_int(headers.get("code"), 0)
        if code == 5:
            raise BridgeError("jamendo_auth", "Jamendo rejected the client ID.")
        raise BridgeError("jamendo_error", "Jamendo could not complete the search.")
    tracks = []
    for raw in results:
        normalized = normalize_jamendo_track(raw)
        if normalized is not None:
            tracks.append(normalized)
    return {
        "ok": True,
        "source": "jamendo",
        "credentialSource": source,
        "results": tracks,
        "total": max(len(tracks), bounded_int(headers.get("results_fullcount"), len(tracks))),
    }


def radio_search(args: argparse.Namespace) -> dict:
    name = validated_text(args.name, "Station name", 120)
    tag = validated_text(args.tag, "Tag", 80)
    country = validated_text(args.country, "Country", 80)
    if args.order not in RADIO_ORDERS:
        raise BridgeError("invalid_request", "Unsupported Radio Browser order.")
    params = {
        "hidebroken": "true",
        "limit": str(validated_limit(args.limit)),
        "offset": str(validated_offset(args.offset)),
        "order": args.order,
        "reverse": "true" if args.order != "name" else "false",
    }
    if name:
        params["name"] = name
    if tag:
        params["tag"] = tag
    if country:
        params["country"] = country
    payload = request_json(RADIO_API + "?" + urllib.parse.urlencode(params), "Radio Browser", list)
    stations = []
    for raw in payload:
        normalized = normalize_radio_station(raw)
        if normalized is not None:
            stations.append(normalized)
    return {
        "ok": True,
        "source": "radio",
        "results": stations,
        "total": len(stations),
    }


def status() -> dict:
    client_id, source, message = jamendo_client_id()
    return {
        "ok": True,
        "configured": bool(client_id),
        "credentialSource": source,
        "configPath": str(config_path()),
        "message": message,
    }


def add_search_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--query", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--country", default="")
    parser.add_argument("--order", default="popularity_total")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--offset", type=int, default=0)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GPS Media Hub music catalogue helper.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    jamendo = sub.add_parser("jamendo")
    add_search_arguments(jamendo)
    jamendo.set_defaults(order="popularity_total")
    radio = sub.add_parser("radio")
    add_search_arguments(radio)
    radio.set_defaults(order="clickcount")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "status":
            return emit(status())
        if args.command == "jamendo":
            return emit(jamendo_search(args))
        if args.command == "radio":
            return emit(radio_search(args))
        raise BridgeError("invalid_request", "Unknown command.")
    except BridgeError as error:
        return fail(error.code, error.message)


if __name__ == "__main__":
    raise SystemExit(main())
