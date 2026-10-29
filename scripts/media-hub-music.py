#!/usr/bin/env python3
"""Narrow Radio Browser catalogue bridge for the Media Hub."""
from __future__ import annotations

import argparse
import http.client
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


RADIO_API = "https://all.api.radio-browser.info/json/stations/search"
USER_AGENT = "GPS-Desktop/1.0"
MAX_JSON_BYTES = 4 * 1024 * 1024
RADIO_ORDERS = {"clickcount", "clicktrend", "votes", "name", "bitrate", "random"}
RADIO_ID_RE = re.compile(r"^[0-9a-fA-F-]{32,40}$")
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


def safe_url(value: object, schemes: set[str]) -> str:
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
    return value


def safe_web(value: object) -> str:
    return safe_url(value, {"https"})


def safe_stream(value: object) -> str:
    return safe_url(value, {"http", "https"})


def palette(seed: str) -> list[str]:
    total = sum(ord(char) for char in seed) if seed else 0
    return list(PALETTES[total % len(PALETTES)])


def infer_moods(tags: list[str]) -> list[str]:
    haystack = " ".join(tags).lower()
    out = []
    for mood, tag in MOOD_TAGS.items():
        if tag in haystack or mood in haystack:
            out.append(mood.title())
    return out[:4]


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


def add_search_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--name", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--country", default="")
    parser.add_argument("--order", default="clickcount")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--offset", type=int, default=0)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GPS Media Hub Radio Browser helper.")
    sub = parser.add_subparsers(dest="command", required=True)
    radio = sub.add_parser("radio")
    add_search_arguments(radio)
    radio.set_defaults(order="clickcount")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "radio":
            return emit(radio_search(args))
        raise BridgeError("invalid_request", "Unknown command.")
    except BridgeError as error:
        return fail(error.code, error.message)


if __name__ == "__main__":
    raise SystemExit(main())
