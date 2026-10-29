#!/usr/bin/env python3
"""Cached LRCLIB provider for Media Hub lyrics."""

from __future__ import annotations

import json
import math
import re
import sys
import urllib.parse
from typing import Any

import hub_common


API_BASE = "https://lrclib.net/api"
CACHE_TTL_SECONDS = 24 * 60 * 60
CACHE_MAX_BYTES = 5 * 1024 * 1024
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
_TIMESTAMP = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def parse_lrc(value: str) -> list[dict[str, Any]]:
    """Parse one or more LRC timestamps per line into ordered timed lines."""
    parsed: list[dict[str, Any]] = []
    for raw in value.splitlines():
        timestamps = list(_TIMESTAMP.finditer(raw))
        if not timestamps:
            continue
        text = raw[timestamps[-1].end():].strip()
        if not text:
            continue
        for timestamp in timestamps:
            seconds = int(timestamp.group(1)) * 60 + float(timestamp.group(2))
            parsed.append({"t": round(seconds, 2), "s": text})
    parsed.sort(key=lambda line: line["t"])
    return parsed


def _http_json(url: str) -> Any:
    data, _ = hub_common.request(url, max_bytes=MAX_RESPONSE_BYTES)
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise hub_common.HubError("invalid", "LRCLIB returned invalid JSON.") from None


def _is_not_found(error: hub_common.HubError) -> bool:
    return error.kind == "invalid" and error.message in {
        "The provider returned HTTP 400.",
        "The provider returned HTTP 404.",
    }


def _best_search_result(results: Any, title: str, artist: str, duration: float | None) -> dict[str, Any] | None:
    if not isinstance(results, list):
        raise hub_common.HubError("invalid", "LRCLIB returned an invalid search result.")

    normalized_title = title.casefold().strip()
    normalized_artist = artist.casefold().strip()
    candidates: list[tuple[float, dict[str, Any]]] = []
    for result in results:
        if not isinstance(result, dict):
            continue
        score = 0.0
        candidate_title = str(result.get("trackName") or "").casefold().strip()
        candidate_artist = str(result.get("artistName") or "").casefold().strip()
        candidate_duration = result.get("duration")
        if result.get("syncedLyrics"):
            score += 100
        elif result.get("plainLyrics"):
            score += 40
        if candidate_title == normalized_title:
            score += 30
        elif normalized_title and normalized_title in candidate_title:
            score += 10
        if normalized_artist and candidate_artist == normalized_artist:
            score += 20
        elif normalized_artist and normalized_artist in candidate_artist:
            score += 8
        if duration and isinstance(candidate_duration, (int, float)):
            difference = abs(float(candidate_duration) - duration)
            score -= min(60.0, difference) * 2
            if difference > 15:
                continue
        candidates.append((score, result))
    return max(candidates, key=lambda item: item[0])[1] if candidates else None


def _normalize_result(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        return {"status": "none"}
    synced = data.get("syncedLyrics")
    if isinstance(synced, str):
        lines = parse_lrc(synced)
        if lines:
            return {"status": "synced", "lines": lines}
    plain = data.get("plainLyrics")
    if isinstance(plain, str) and plain.strip():
        return {"status": "plain", "plain": plain.strip()}
    return {"status": "none"}


def lookup(
    artist: str,
    title: str,
    album: str = "",
    duration: float | None = None,
    *,
    base_url: str = API_BASE,
    cache: hub_common.DiskCache | None = None,
) -> dict[str, Any]:
    """Fetch exact LRCLIB metadata, search on no match, and cache normalized lyrics."""
    artist, title, album = artist.strip(), title.strip(), album.strip()
    if not title:
        raise hub_common.HubError("invalid", "A track title is required.")
    if duration is not None and (not math.isfinite(duration) or duration < 0):
        raise hub_common.HubError("invalid", "Track duration must be a non-negative number.")
    if duration is not None and not 1 <= duration <= 3600:
        duration = None

    api_base = base_url.rstrip("/")
    query_key = json.dumps(
        [api_base, artist.casefold(), title.casefold(), album.casefold(), int(duration) if duration else None],
        ensure_ascii=False,
        separators=(",", ":"),
    )
    cache = cache or hub_common.DiskCache(
        ttl_seconds=CACHE_TTL_SECONDS,
        max_bytes=CACHE_MAX_BYTES,
    )
    cached = cache.get(query_key)
    if cached is not None:
        try:
            result = json.loads(cached.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            result = None
        if isinstance(result, dict) and result.get("status") in {"synced", "plain", "none"}:
            try:
                hub_common.validate_contract("Lyrics", result)
            except ValueError:
                pass
            else:
                return result

    exact_query = {"track_name": title}
    if artist:
        exact_query["artist_name"] = artist
    if album:
        exact_query["album_name"] = album
    if duration is not None:
        exact_query["duration"] = str(int(duration))

    result_data: Any = None
    exact_url = f"{api_base}/get?{urllib.parse.urlencode(exact_query)}"
    try:
        result_data = _http_json(exact_url)
    except hub_common.HubError as error:
        if not _is_not_found(error):
            raise

    if not result_data:
        search_query = {"track_name": title}
        if artist:
            search_query["artist_name"] = artist
        search_url = f"{api_base}/search?{urllib.parse.urlencode(search_query)}"
        result_data = _best_search_result(
            _http_json(search_url),
            title,
            artist,
            duration,
        )

    result = _normalize_result(result_data)
    hub_common.validate_contract("Lyrics", result)
    cache.set(query_key, json.dumps(result, ensure_ascii=False).encode("utf-8"), "application/json")
    return result


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    artist = args[0].strip() if len(args) > 0 else ""
    title = args[1].strip() if len(args) > 1 else ""
    album = args[2].strip() if len(args) > 2 else ""
    try:
        duration = float(args[3]) if len(args) > 3 and args[3].strip() else None
        result = lookup(artist, title, album, duration)
        print(json.dumps({"ok": True, "lyrics": result}, ensure_ascii=False))
        return 0
    except ValueError:
        error = hub_common.error_payload("invalid", "Track duration must be a number.")
    except hub_common.HubError as exc:
        error = exc.as_json()
    print(json.dumps(error, ensure_ascii=False))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
