#!/usr/bin/env python3
"""Local audio index provider using ffprobe and the shared disk cache."""

from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import hub_common


AUDIO_EXTENSIONS = frozenset({".aac", ".aiff", ".alac", ".flac", ".m4a", ".mp3", ".oga", ".ogg", ".opus", ".wav", ".wma"})
MAX_TRACKS = 10_000
FFPROBE_TIMEOUT = 15
INDEX_TTL_SECONDS = 365 * 24 * 60 * 60


def _track_id(path: Path) -> str:
    digest = hashlib.sha256(os.fsencode(str(path))).hexdigest()
    return f"local:{digest}"


def _tag(tags: Any, *names: str) -> str:
    if not isinstance(tags, dict):
        return ""
    folded = {str(key).casefold(): value for key, value in tags.items()}
    for name in names:
        value = folded.get(name.casefold())
        if isinstance(value, str) and value.strip():
            return " ".join(value.split())[:240]
    return ""


def _probe(path: Path) -> dict[str, Any] | None:
    try:
        completed = subprocess.run(
            [
                "ffprobe",
                "-v", "error",
                "-show_entries", "format=duration:format_tags=title,artist,album,genre",
                "-of", "json",
                str(path),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=FFPROBE_TIMEOUT,
        )
    except FileNotFoundError:
        raise hub_common.HubError("unavailable", "ffprobe is required to scan local music.") from None
    except subprocess.TimeoutExpired:
        return None
    if completed.returncode != 0:
        return None
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or not isinstance(payload.get("format"), dict):
        return None

    media_format = payload["format"]
    tags = media_format.get("tags")
    title = _tag(tags, "title") or path.stem
    artist = _tag(tags, "artist", "album_artist", "albumartist")
    album = _tag(tags, "album")
    genre = _tag(tags, "genre")
    try:
        duration_value = float(media_format.get("duration", 0))
    except (TypeError, ValueError):
        duration_value = 0
    duration = int(round(duration_value)) if math.isfinite(duration_value) and duration_value > 0 else 0
    track = {
        "kind": "track",
        "id": _track_id(path),
        "title": title,
        "artist": artist,
        "album": album,
        "genre": genre,
        "dur": duration,
        "streamUrl": path.as_uri(),
        "art": "",
        "sourceUrl": "",
        "license": "Local file",
        "moods": [],
        "g": ["#0b1030", "#2a1b5e", "#0e4a6b"],
        "plays": 0,
        "added": 0,
    }
    hub_common.validate_contract("Track", track)
    return track


def _cached_index(cache: hub_common.DiskCache, key: str, root: Path) -> dict[str, dict[str, Any]]:
    data = cache.get(key)
    if data is None:
        return {}
    try:
        payload = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}
    if not isinstance(payload, dict) or payload.get("root") != str(root) or not isinstance(payload.get("entries"), list):
        return {}
    entries: dict[str, dict[str, Any]] = {}
    for entry in payload["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str) or not isinstance(entry.get("track"), dict):
            continue
        try:
            hub_common.validate_contract("Track", entry["track"])
            size = int(entry["size"])
            modified = int(entry["mtimeNs"])
        except (KeyError, TypeError, ValueError):
            continue
        entries[entry["path"]] = {"size": size, "mtimeNs": modified, "track": entry["track"]}
    return entries


def scan(
    directory: str | os.PathLike[str],
    *,
    cache: hub_common.DiskCache | None = None,
) -> dict[str, Any]:
    try:
        root = Path(directory).expanduser().resolve(strict=True)
    except (OSError, RuntimeError):
        raise hub_common.HubError("invalid", "The selected music folder is not available.") from None
    if not root.is_dir():
        raise hub_common.HubError("invalid", "The selected music folder is not a directory.")
    if shutil.which("ffprobe") is None:
        raise hub_common.HubError("unavailable", "ffprobe is required to scan local music.")

    cache = cache or hub_common.DiskCache(ttl_seconds=INDEX_TTL_SECONDS)
    cache_key = "local-library:" + str(root)
    previous = _cached_index(cache, cache_key, root)
    entries: list[dict[str, Any]] = []
    tracks: list[dict[str, Any]] = []
    skipped = 0
    walk_errors: list[OSError] = []
    for current, dirs, filenames in os.walk(root, followlinks=False, onerror=walk_errors.append):
        current_path = Path(current)
        dirs[:] = sorted(
            name for name in dirs
            if not (current_path / name).is_symlink()
        )
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix.casefold() not in AUDIO_EXTENSIONS or path.is_symlink():
                continue
            if len(tracks) >= MAX_TRACKS:
                skipped += 1
                continue
            try:
                resolved = path.resolve(strict=True)
                stat = resolved.stat()
            except (OSError, RuntimeError):
                skipped += 1
                continue
            old = previous.get(str(resolved))
            if old and old["size"] == stat.st_size and old["mtimeNs"] == stat.st_mtime_ns:
                track = old["track"]
            else:
                track = _probe(resolved)
                if track is None:
                    skipped += 1
                    continue
            entries.append({
                "path": str(resolved),
                "size": stat.st_size,
                "mtimeNs": stat.st_mtime_ns,
                "track": track,
            })
            tracks.append(track)
    skipped += len(walk_errors)

    cache.set(cache_key, json.dumps(
        {"root": str(root), "entries": entries},
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8"), "application/json")
    tracks.sort(key=lambda track: (
        track["artist"].casefold(),
        track["album"].casefold(),
        track["title"].casefold(),
    ))
    return {
        "ok": True,
        "root": str(root),
        "count": len(tracks),
        "skipped": skipped,
        "results": tracks,
    }


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) not in (1, 2) or args[0] != "scan":
        print(json.dumps(hub_common.error_payload("invalid", "Usage: media-hub-library.py scan [folder].")))
        return 2
    folder = args[1] if len(args) == 2 else os.environ.get(
        "GPS_MUSIC_DIR",
        str(Path.home() / "Music"),
    )
    try:
        result = scan(folder)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except hub_common.HubError as error:
        print(json.dumps(error.as_json(), ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
