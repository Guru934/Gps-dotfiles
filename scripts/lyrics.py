#!/usr/bin/env python3
"""One-shot LRCLIB lyrics lookup for the GPS dashboard.

User-initiated only: the dashboard calls this exactly when the user presses
the "look up" button in the Media tab. It sends the track's artist, title,
album and duration to https://lrclib.net (public API, no key, GET only) and
prints a single JSON line with the outcome:

    {"status": "ok", "synced": true, "lines": [{"t": 12.3, "s": "..."}]}
    {"status": "ok", "synced": false, "plain": "..."}
    {"status": "none"}
    {"status": "error", "message": "..."}

Read-only network behavior; nothing is uploaded beyond the track metadata
needed to identify the song.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://lrclib.net/api"
UA = "gps-dashboard/0.1 (local QuickShell; user-triggered lyric lookup)"
TIMEOUT = 8


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    last = None
    for _ in range(3):  # LRCLIB sometimes answers 503 ServerOverloaded
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            last = exc
            if not (500 <= exc.code < 600):
                raise
            time.sleep(0.8)
    raise last


def parse_lrc(text):
    """[mm:ss.xx] line -> {"t": seconds, "s": text}, sorted, empty dropped."""
    lines = []
    for raw in text.splitlines():
        raw = raw.strip()
        if not raw.startswith("[") or "]" not in raw:
            continue
        tag, rest = raw[1:].split("]", 1)
        if ":" not in tag:
            continue
        mm, ss = tag.split(":", 1)
        try:
            t = int(mm) * 60 + float(ss)
        except ValueError:
            continue
        body = rest.strip()
        if body:
            lines.append({"t": round(t, 2), "s": body})
    lines.sort(key=lambda x: x["t"])
    return lines


def main():
    argv = sys.argv[1:]
    artist = argv[0].strip() if len(argv) > 0 else ""
    title = argv[1].strip() if len(argv) > 1 else ""
    album = argv[2].strip() if len(argv) > 2 else ""
    duration = None
    if len(argv) > 3:
        try:
            duration = float(argv[3])
        except ValueError:
            duration = None

    if not title:
        print(json.dumps({"status": "error", "message": "no track title"}))
        return

    try:
        query = {"artist_name": artist, "track_name": title}
        if album:
            query["album_name"] = album
        # LRCLIB validates duration to 1..3600 s; anything outside (long
        # podcasts, unknown length) is omitted rather than rejected.
        if duration and 1 <= duration <= 3600:
            query["duration"] = int(duration)

        data = None
        try:
            data = get_json(BASE + "/get?" + urllib.parse.urlencode(query))
        except urllib.error.HTTPError as exc:
            if exc.code not in (400, 404):
                raise

        if data is None:
            search = {"track_name": title}
            if artist:
                search["artist_name"] = artist
            results = get_json(BASE + "/search?" + urllib.parse.urlencode(search))
            if isinstance(results, list):
                data = next((r for r in results if r.get("syncedLyrics")), None)
                if data is None and results:
                    data = results[0]

        if not data:
            print(json.dumps({"status": "none"}))
            return

        synced = (data.get("syncedLyrics") or "").strip()
        plain = (data.get("plainLyrics") or "").strip()
        if synced:
            lines = parse_lrc(synced)
            if lines:
                print(json.dumps({"status": "ok", "synced": True, "lines": lines, "source": "lrclib"}))
                return
        if plain:
            print(json.dumps({"status": "ok", "synced": False, "plain": plain, "source": "lrclib"}))
            return
        print(json.dumps({"status": "none"}))
    except Exception as exc:  # network down, timeout, bad JSON, ...
        print(json.dumps({"status": "error", "message": str(exc)}))


if __name__ == "__main__":
    main()
