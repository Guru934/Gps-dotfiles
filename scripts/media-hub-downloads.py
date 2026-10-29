#!/usr/bin/env python3
"""Narrow yt-dlp/FFmpeg bridge for the GPS Media Hub Downloads page.

Only dependency checks, URL inspection, destination checks, history file
verification and one download job per invocation are exposed. Commands are
built as argument arrays; this helper never invokes a shell, never accepts
arbitrary yt-dlp options and never handles cookies or credentials.
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import unicodedata
import urllib.parse
from collections import deque
from pathlib import Path

APP_VERSION = "1.0"
MAX_URL = 4096
MAX_PATH = 4096
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_ERROR_LINES = 40
MAX_ERROR_CHARS = 400
MAX_PLAYLIST_ITEMS = 100
INSPECT_PLAYLIST_ENTRIES = 51
INSPECT_TIMEOUT = 70
DOWNLOAD_TIMEOUT_GRACE = 5
FORMAT_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,63}\Z")
URL_CREDENTIAL_RE = re.compile(r"[\x00-\x20\x7f]")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
URL_IN_TEXT_RE = re.compile(r"https?://[^\s'\"<>]+")
PLAYLIST_PART_RE = re.compile(r"([0-9]{1,6})(?:-([0-9]{1,6})|:([0-9]{1,6})(?::([0-9]{1,6}))?)?\Z")
OUTPUT_TEMPLATE = "%(playlist_index&{} - |)s%(title).160s [%(id)s].%(ext)s"
PROGRESS_TEMPLATE = (
    "GPS_PROGRESS|%(progress.status)s|%(progress.downloaded_bytes|0)d|"
    "%(progress.total_bytes|0)d|%(progress.total_bytes_estimate|0)d|"
    "%(progress.speed|0)f|%(progress.eta|0)d|%(progress.fragment_index|0)d|"
    "%(progress.fragment_count|0)d"
)
POSTPROCESS_TEMPLATE = "GPS_POSTPROCESS|%(progress.status)s|%(progress.postprocessor|)s"
AUDIO_FORMATS = ("original", "mp3", "m4a", "flac", "opus")
AUDIO_QUALITIES = ("best", "320K", "256K", "192K", "128K")
INSTALL_GUIDANCE = {
    "yt-dlp": (
        "yt-dlp is not available. Install it with your normal package manager "
        "(Arch/CachyOS: sudo pacman -S yt-dlp) or pip, then press Recheck. "
        "GPS never installs or updates packages automatically."
    ),
    "ffmpeg": (
        "FFmpeg is not available. Video/audio merging and audio extraction are "
        "disabled; single-file video formats and original audio can still be "
        "downloaded. Install FFmpeg with your package manager, then press Recheck."
    ),
    "ffprobe": (
        "ffprobe is not available. Audio extraction and container remuxing may "
        "be limited. Install FFmpeg (which includes ffprobe) and press Recheck."
    ),
}


class BridgeError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def emit(payload: dict, exit_code: int = 0) -> int:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    return exit_code


def fail(code: str, message: str) -> int:
    return emit({"ok": False, "code": code, "message": message}, 1)


def executable(name: str) -> str:
    path = shutil.which(name)
    if not path:
        return ""
    try:
        resolved = str(Path(path).resolve())
    except OSError:
        resolved = path
    return resolved if os.path.isfile(resolved) and os.access(resolved, os.X_OK) else ""


def tool_state(name: str, version_args: list[str]) -> dict:
    path = executable(name)
    if not path:
        return {"path": "", "version": "", "ready": False}
    try:
        result = subprocess.run(
            [path] + version_args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=6,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {"path": path, "version": "", "ready": False}
    version = ""
    if result.returncode == 0:
        first = (result.stdout or result.stderr or "").strip().splitlines()
        if first:
            version = clean_text(first[0], 120)
    return {"path": path, "version": version, "ready": result.returncode == 0}


def clean_text(value: object, limit: int = 300) -> str:
    if not isinstance(value, str):
        return ""
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", value)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit]


def redact_text(value: object, limit: int = MAX_ERROR_CHARS) -> str:
    text = ANSI_RE.sub("", str(value or ""))
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", " ", text)

    def redact_url(match: re.Match[str]) -> str:
        raw = match.group(0)
        try:
            parsed = urllib.parse.urlsplit(raw)
        except ValueError:
            return "[url]"
        if parsed.query or parsed.fragment:
            return f"{parsed.scheme}://{parsed.netloc}{parsed.path}?[redacted]"
        return raw

    text = URL_IN_TEXT_RE.sub(redact_url, text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit]


def validate_url(value: object) -> str:
    if not isinstance(value, str):
        raise BridgeError("invalid_url", "A media URL is required.")
    raw = value.strip()
    if len(raw) < 8 or len(raw) > MAX_URL or URL_CREDENTIAL_RE.search(raw) or "\\" in raw:
        raise BridgeError("invalid_url", "That is not a valid HTTP or HTTPS URL.")
    try:
        parsed = urllib.parse.urlsplit(raw)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise BridgeError("invalid_url", "That URL is malformed.") from error
    if parsed.scheme.lower() not in ("http", "https"):
        raise BridgeError("invalid_url", "Only HTTP and HTTPS URLs are supported.")
    if not hostname or parsed.username or parsed.password:
        raise BridgeError("invalid_url", "URLs with credentials are not supported.")
    if port is not None and not 1 <= port <= 65535:
        raise BridgeError("invalid_url", "That URL has an invalid port.")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in hostname):
        raise BridgeError("invalid_url", "That URL has an invalid hostname.")
    return raw


def validate_format_id(value: object) -> str:
    if not isinstance(value, str) or not FORMAT_ID_RE.fullmatch(value):
        raise BridgeError("invalid_format", "The selected format id is invalid.")
    return value


def validate_height(value: object) -> int:
    try:
        height = int(value)
    except (TypeError, ValueError, OverflowError) as error:
        raise BridgeError("invalid_quality", "The selected quality is invalid.") from error
    if height < 1 or height > 10000:
        raise BridgeError("invalid_quality", "The selected quality is invalid.")
    return height


def validate_container(value: object) -> str:
    text = str(value or "Auto").lower()
    if text not in ("auto", "mp4", "mkv", "webm"):
        raise BridgeError("invalid_container", "That output container is not supported.")
    return "" if text == "auto" else text


def validate_audio_format(value: object) -> str:
    text = str(value or "original").lower()
    if text not in AUDIO_FORMATS:
        raise BridgeError("invalid_audio_format", "That audio format is not supported.")
    return text


def validate_audio_quality(value: object) -> str:
    text = str(value or "best")
    upper = text.upper()
    if upper == "BEST":
        return "best"
    if upper in AUDIO_QUALITIES:
        return upper
    raise BridgeError("invalid_audio_quality", "That audio quality is not supported.")


def validate_playlist_spec(value: object) -> tuple[str, int]:
    if not isinstance(value, str):
        raise BridgeError("invalid_playlist", "Enter valid playlist item numbers.")
    text = value.strip()
    if not text or len(text) > 200:
        raise BridgeError("invalid_playlist", "Enter valid playlist item numbers.")
    total = 0
    for part in text.split(","):
        match = PLAYLIST_PART_RE.fullmatch(part.strip())
        if not match:
            raise BridgeError("invalid_playlist", "Use playlist item numbers such as 1,3-5,7.")
        start = int(match.group(1))
        if start < 1:
            raise BridgeError("invalid_playlist", "Playlist item numbers start at 1.")
        if match.group(2) is not None:
            stop = int(match.group(2))
            if stop < start:
                raise BridgeError("invalid_playlist", "Check the playlist range.")
            count = stop - start + 1
        elif match.group(3) is not None:
            stop = int(match.group(3))
            step = int(match.group(4) or "1")
            if stop < start or step < 1:
                raise BridgeError("invalid_playlist", "Check the playlist range.")
            count = (stop - start) // step + 1
        else:
            count = 1
        total += count
        if total > MAX_PLAYLIST_ITEMS:
            raise BridgeError(
                "playlist_too_large",
                f"Select at most {MAX_PLAYLIST_ITEMS} playlist items.",
            )
    if total < 1:
        raise BridgeError("invalid_playlist", "Select at least one playlist item.")
    return text, total


def validate_playlist_count(value: object) -> int:
    try:
        count = int(value)
    except (TypeError, ValueError, OverflowError) as error:
        raise BridgeError("invalid_playlist", "The playlist item count is invalid.") from error
    if count < 1 or count > MAX_PLAYLIST_ITEMS:
        raise BridgeError(
            "playlist_too_large",
            f"Full playlist downloads are limited to {MAX_PLAYLIST_ITEMS} items.",
        )
    return count


def parse_user_dir_file(kind: str) -> str:
    config = os.environ.get("XDG_CONFIG_HOME", "")
    base = Path(config) if config and Path(config).is_absolute() else Path.home() / ".config"
    path = base / "user-dirs.dirs"
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    key = f"XDG_{kind}_DIR"
    for line in content.splitlines():
        line = line.strip()
        if not line.startswith(key + "="):
            continue
        value = line.split("=", 1)[1].strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        value = value.replace("$HOME", str(Path.home()))
        if os.path.isabs(value):
            return value
    return ""


def user_media_dir(kind: str) -> Path:
    if kind == "MUSIC":
        configured = os.environ.get("GPS_MUSIC_DIR", "")
        if configured and os.path.isabs(configured):
            return Path(configured)
        return Path.home() / "Music" / "GPS"
    configured = os.environ.get("XDG_VIDEOS_DIR", "")
    if configured and os.path.isabs(configured) and Path(configured) != Path.home():
        return Path(configured) / "GPS"
    from_file = parse_user_dir_file(kind)
    if from_file and Path(from_file) != Path.home():
        return Path(from_file) / "GPS"
    return Path.home() / "Videos" / "GPS"


def clean_destination(value: object) -> Path:
    if not isinstance(value, str):
        raise BridgeError("invalid_destination", "Choose an output folder.")
    raw = value.strip()
    if not raw or len(raw) > MAX_PATH or any(ord(ch) < 32 or ord(ch) == 127 for ch in raw):
        raise BridgeError("invalid_destination", "That output folder is not valid.")
    if raw.startswith("~"):
        raw = os.path.expanduser(raw)
    path = Path(raw)
    if not path.is_absolute():
        raise BridgeError("invalid_destination", "Choose an absolute output folder.")
    if path.is_symlink():
        raise BridgeError("destination_symlink", "Refusing a symlinked download folder.")
    try:
        resolved = path.resolve(strict=False)
    except OSError as error:
        raise BridgeError("invalid_destination", f"Could not resolve that folder: {error}") from error
    if resolved == Path("/"):
        raise BridgeError("invalid_destination", "Choose a dedicated download folder, not the filesystem root.")
    return resolved


def check_destination(value: object) -> dict:
    path = clean_destination(value)
    if path.is_symlink():
        raise BridgeError("destination_symlink", "Refusing a symlinked download folder.")
    if not path.exists():
        return {
            "ok": True,
            "path": str(path),
            "exists": False,
            "directory": False,
            "writable": False,
            "message": "That folder does not exist. Create it or choose another folder.",
        }
    if not path.is_dir():
        raise BridgeError("destination_not_directory", "That destination is not a folder.")
    writable = os.access(path, os.W_OK | os.X_OK)
    return {
        "ok": True,
        "path": str(path),
        "exists": True,
        "directory": True,
        "writable": writable,
        "message": "" if writable else "That folder is not writable.",
    }


def create_destination(value: object) -> dict:
    path = clean_destination(value)
    if path.is_symlink():
        raise BridgeError("destination_symlink", "Refusing a symlinked download folder.")
    try:
        path.mkdir(parents=True, exist_ok=True, mode=0o755)
    except OSError as error:
        raise BridgeError("destination_create_failed", f"Could not create that folder: {error}") from error
    if path.is_symlink() or not path.is_dir():
        raise BridgeError("destination_create_failed", "The download folder could not be created safely.")
    if not os.access(path, os.W_OK | os.X_OK):
        raise BridgeError("destination_not_writable", "The download folder is not writable.")
    return {"ok": True, "path": str(path), "created": True}


def require_destination(value: object) -> Path:
    path = clean_destination(value)
    if path.is_symlink():
        raise BridgeError("destination_symlink", "Refusing a symlinked download folder.")
    if not path.exists():
        raise BridgeError("destination_missing", "The output folder does not exist. Create it first.")
    if not path.is_dir():
        raise BridgeError("destination_not_directory", "The output destination is not a folder.")
    if not os.access(path, os.W_OK | os.X_OK):
        raise BridgeError("destination_not_writable", "The output folder is not writable.")
    return path


def verify_file(value: object, destination: Path | None = None) -> dict:
    if not isinstance(value, str):
        return {"path": "", "ok": False, "code": "invalid_path", "message": "Invalid output path."}
    raw = value.strip()
    if not raw or len(raw) > MAX_PATH or any(ord(ch) < 32 or ord(ch) == 127 for ch in raw):
        return {"path": raw[:MAX_PATH], "ok": False, "code": "invalid_path", "message": "Invalid output path."}
    path = Path(raw)
    if not path.is_absolute():
        return {"path": raw, "ok": False, "code": "invalid_path", "message": "Output path is not absolute."}
    if path.is_symlink():
        return {"path": raw, "ok": False, "code": "symlink", "message": "Output is a symlink."}
    try:
        resolved = path.resolve(strict=True)
    except OSError:
        return {"path": raw, "ok": False, "code": "missing", "message": "Output file is missing."}
    if not resolved.is_file():
        return {"path": raw, "ok": False, "code": "not_file", "message": "Output is not a regular file."}
    try:
        size = resolved.stat().st_size
    except OSError:
        return {"path": raw, "ok": False, "code": "unreadable", "message": "Output file could not be read."}
    if size <= 0:
        return {"path": raw, "ok": False, "code": "empty", "message": "Output file is empty."}
    if destination is not None:
        try:
            root = destination.resolve(strict=True)
        except OSError:
            return {"path": raw, "ok": False, "code": "missing_destination", "message": "Output folder is missing."}
        try:
            resolved.relative_to(root)
        except ValueError:
            return {"path": raw, "ok": False, "code": "outside_destination", "message": "Output escaped the chosen folder."}
        if resolved == root:
            return {"path": raw, "ok": False, "code": "not_file", "message": "Output is not a file."}
    return {"path": str(path), "ok": True, "code": "", "message": "", "size": size}


def parse_number(value: str, *, integer: bool = False) -> float | int | None:
    text = str(value or "").strip()
    if text in ("", "None", "NA", "N/A"):
        return None
    try:
        number = float(text)
    except (TypeError, ValueError):
        return None
    if not (number == number and abs(number) != float("inf")):
        return None
    if integer:
        return int(number)
    return number


def parse_progress_line(line: str) -> dict | None:
    if not isinstance(line, str) or not line.startswith("GPS_PROGRESS|"):
        return None
    parts = line.split("|")
    if len(parts) != 9:
        return None
    status = parts[1]
    if status not in ("downloading", "finished"):
        return None
    downloaded = parse_number(parts[2], integer=True)
    total = parse_number(parts[3], integer=True)
    estimate = parse_number(parts[4], integer=True)
    speed = parse_number(parts[5])
    eta = parse_number(parts[6], integer=True)
    fragment_index = parse_number(parts[7], integer=True)
    fragment_count = parse_number(parts[8], integer=True)
    return {
        "event": "progress",
        "status": status,
        "downloadedBytes": max(0, downloaded) if isinstance(downloaded, int) else None,
        "totalBytes": max(0, total) if isinstance(total, int) and total > 0 else None,
        "totalBytesEstimate": max(0, estimate) if isinstance(estimate, int) and estimate > 0 else None,
        "speed": max(0.0, speed) if isinstance(speed, float) and speed > 0 else None,
        "eta": max(0, eta) if isinstance(eta, int) else None,
        "fragmentIndex": max(0, fragment_index) if isinstance(fragment_index, int) else None,
        "fragmentCount": max(0, fragment_count) if isinstance(fragment_count, int) else None,
    }


def parse_postprocess_line(line: str) -> dict | None:
    if not isinstance(line, str) or not line.startswith("GPS_POSTPROCESS|"):
        return None
    parts = line.split("|", 2)
    if len(parts) != 3:
        return None
    status = parts[1]
    if status not in ("started", "processing", "finished"):
        return None
    name = clean_text(parts[2], 120)
    if name == "NA":
        name = ""
    return {"event": "postprocess", "status": status, "postprocessor": name}


def mark_path(line: str, marker: str) -> str:
    if not isinstance(line, str) or not line.startswith(marker):
        return ""
    return line[len(marker):].strip()


def normalize_format(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    format_id = raw.get("format_id")
    if not isinstance(format_id, str) or not FORMAT_ID_RE.fullmatch(format_id):
        return None
    ext = raw.get("ext")
    ext = ext.lower() if isinstance(ext, str) and re.fullmatch(r"[A-Za-z0-9]{1,8}", ext) else ""
    vcodec = clean_text(raw.get("vcodec"), 80)
    acodec = clean_text(raw.get("acodec"), 80)
    if vcodec == "none":
        vcodec = ""
    if acodec == "none":
        acodec = ""
    has_video = vcodec != ""
    has_audio = acodec != ""
    if not has_video and not has_audio:
        return None
    height = parse_number(str(raw.get("height") or ""), integer=True)
    fps = parse_number(str(raw.get("fps") or ""))
    size = parse_number(str(raw.get("filesize") or ""), integer=True)
    if not isinstance(size, int) or size <= 0:
        size = parse_number(str(raw.get("filesize_approx") or ""), integer=True)
    tbr = parse_number(str(raw.get("tbr") or ""))
    abr = parse_number(str(raw.get("abr") or ""))
    vbr = parse_number(str(raw.get("vbr") or ""))
    return {
        "format_id": format_id,
        "ext": ext,
        "vcodec": vcodec,
        "acodec": acodec,
        "hasVideo": has_video,
        "hasAudio": has_audio,
        "height": max(0, height) if isinstance(height, int) else 0,
        "fps": max(0.0, fps) if isinstance(fps, float) else 0,
        "sizeBytes": max(0, size) if isinstance(size, int) else 0,
        "tbr": max(0.0, tbr) if isinstance(tbr, float) else 0,
        "abr": max(0.0, abr) if isinstance(abr, float) else 0,
        "vbr": max(0.0, vbr) if isinstance(vbr, float) else 0,
        "format_note": clean_text(raw.get("format_note"), 120),
        "resolution": clean_text(raw.get("resolution"), 40),
    }


def normalize_formats(raw_formats: object) -> tuple[list[dict], list[dict], list[int]]:
    formats = []
    seen = set()
    if isinstance(raw_formats, list):
        for raw in raw_formats[:400]:
            normalized = normalize_format(raw)
            if normalized is None or normalized["format_id"] in seen:
                continue
            seen.add(normalized["format_id"])
            formats.append(normalized)
    video = [item for item in formats if item["hasVideo"]]
    audio = [item for item in formats if item["hasAudio"] and not item["hasVideo"]]
    video.sort(key=lambda item: (item["height"], item["fps"], item["tbr"]), reverse=True)
    audio.sort(key=lambda item: (item["abr"], item["tbr"]), reverse=True)
    heights = []
    for item in video:
        height = int(item["height"])
        if height > 0 and height not in heights:
            heights.append(height)
    return video[:80], audio[:80], heights[:16]


def normalize_thumbnail(raw: object) -> str:
    if isinstance(raw, str):
        try:
            parsed = urllib.parse.urlsplit(raw)
        except ValueError:
            return ""
        if parsed.scheme in ("http", "https") and parsed.hostname and not parsed.username and not parsed.password:
            return raw
    if isinstance(raw, list):
        for item in reversed(raw):
            if isinstance(item, dict):
                value = normalize_thumbnail(item.get("url"))
                if value:
                    return value
    return ""


def normalize_entry(raw: object, position: int) -> dict | None:
    if not isinstance(raw, dict):
        return None
    title = clean_text(raw.get("title"), 200)
    if not title:
        title = "Untitled item"
    index = parse_number(str(raw.get("playlist_index") or ""), integer=True)
    duration = parse_number(str(raw.get("duration") or ""))
    return {
        "index": index if isinstance(index, int) and index > 0 else position,
        "id": clean_text(raw.get("id"), 120),
        "title": title,
        "duration": max(0.0, duration) if isinstance(duration, float) else 0,
    }


def normalize_metadata(info: dict, url: str, *, is_playlist: bool, sample: dict | None = None) -> dict:
    entries_raw = info.get("entries") if isinstance(info.get("entries"), list) else []
    entries = []
    for index, raw in enumerate(entries_raw[:20]):
        entry = normalize_entry(raw, index + 1)
        if entry is not None:
            entries.append(entry)
    raw_count = parse_number(str(info.get("playlist_count") or ""), integer=True)
    if not isinstance(raw_count, int) or raw_count < 0:
        raw_count = parse_number(str(info.get("n_entries") or ""), integer=True)
    count_known = isinstance(raw_count, int) and raw_count > 0
    count = raw_count if count_known else max(0, len(entries_raw))
    truncated = len(entries_raw) >= INSPECT_PLAYLIST_ENTRIES and (not count_known or count > len(entries_raw))
    if not count_known and len(entries_raw) >= INSPECT_PLAYLIST_ENTRIES:
        truncated = True
    title = clean_text(info.get("playlist_title") or info.get("title"), 300)
    uploader = clean_text(info.get("uploader") or info.get("channel") or info.get("creator"), 160)
    extractor = clean_text(info.get("extractor_key") or info.get("extractor"), 120)
    duration = parse_number(str(info.get("duration") or ""))
    thumbnail = normalize_thumbnail(info.get("thumbnail") or info.get("thumbnails"))
    item = sample or {}
    sample_formats = item.get("formats") if isinstance(item, dict) else None
    formats = sample_formats if isinstance(sample_formats, list) else info.get("formats")
    video_formats, audio_formats, quality_heights = normalize_formats(formats)
    item_title = clean_text(item.get("title"), 300) if isinstance(item, dict) else ""
    if not item_title:
        item_title = title
    item_uploader = clean_text(item.get("uploader") or item.get("channel"), 160) if isinstance(item, dict) else ""
    item_duration = parse_number(str(item.get("duration") or "")) if isinstance(item, dict) else None
    item_thumbnail = normalize_thumbnail(item.get("thumbnail") or item.get("thumbnails")) if isinstance(item, dict) else ""
    item_id = clean_text(item.get("id"), 120) if isinstance(item, dict) else ""
    return {
        "ok": True,
        "url": url,
        "title": title or item_title or "Untitled media",
        "source": extractor,
        "uploader": uploader or item_uploader,
        "duration": max(0.0, duration) if isinstance(duration, float) else 0,
        "thumbnail": thumbnail or item_thumbnail,
        "item": {
            "id": item_id or clean_text(info.get("id"), 120),
            "title": item_title or title or "Untitled media",
            "uploader": item_uploader or uploader,
            "duration": max(0.0, item_duration) if isinstance(item_duration, float) else 0,
            "thumbnail": item_thumbnail or thumbnail,
            "formats": video_formats + audio_formats,
        },
        "videoFormats": video_formats,
        "audioFormats": audio_formats,
        "qualityHeights": quality_heights,
        "playlist": {
            "isPlaylist": is_playlist,
            "count": count,
            "countKnown": count_known,
            "truncated": truncated,
            "entries": entries,
            "maxItems": MAX_PLAYLIST_ITEMS,
        },
        "limits": {
            "maxPlaylistItems": MAX_PLAYLIST_ITEMS,
            "maxConcurrentJobs": 1,
        },
        "inspectedAt": int(time.time() * 1000),
    }


def looks_like_playlist(info: dict) -> bool:
    return info.get("_type") == "playlist" or (
        isinstance(info.get("entries"), list) and info.get("_type") not in (None, "video")
    )


def base_ytdlp_args(ytdlp: str) -> list[str]:
    return [
        ytdlp,
        "--ignore-config",
        "--no-warnings",
        "--no-color",
        "--socket-timeout", "20",
    ]


def inspect_command(ytdlp: str, url: str) -> list[str]:
    return base_ytdlp_args(ytdlp) + [
        "--dump-single-json",
        "--flat-playlist",
        "--playlist-end", str(INSPECT_PLAYLIST_ENTRIES),
        "--skip-download",
        "--", url,
    ]


def single_item_inspect_command(ytdlp: str, url: str) -> list[str]:
    return base_ytdlp_args(ytdlp) + [
        "--dump-single-json",
        "--skip-download",
        "--playlist-items", "1",
        "--", url,
    ]


_active_process: subprocess.Popen | None = None
_cancel_event = threading.Event()


def terminate_group(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            proc.terminate()
        except OSError:
            pass


def kill_group(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            proc.kill()
        except OSError:
            pass


def _signal_handler(signum, frame) -> None:
    _cancel_event.set()
    proc = _active_process
    if proc is not None:
        terminate_group(proc)


def run_capture(command: list[str], timeout: int) -> tuple[int, str, str]:
    global _active_process
    proc = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        start_new_session=True,
    )
    _active_process = proc
    try:
        if _cancel_event.is_set():
            terminate_group(proc)
        try:
            stdout, stderr = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            terminate_group(proc)
            try:
                stdout, stderr = proc.communicate(timeout=4)
            except subprocess.TimeoutExpired:
                kill_group(proc)
                stdout, stderr = proc.communicate(timeout=2)
            raise BridgeError("timeout", "The media service took too long to respond.") from None
    finally:
        _active_process = None
    if _cancel_event.is_set():
        raise BridgeError("cancelled", "Cancelled.")
    if len(stdout) > MAX_JSON_BYTES or len(stderr) > MAX_JSON_BYTES:
        raise BridgeError("invalid_response", "The media service returned an oversized response.")
    return proc.returncode, stdout, stderr


def classify_failure(text: str, exit_code: int) -> BridgeError:
    lower = text.lower()
    detail = redact_text(text.strip().splitlines()[-1] if text.strip() else "")
    if "unsupported url" in lower or "no suitable extractor" in lower:
        return BridgeError("unsupported_url", "yt-dlp does not support this URL or site.")
    if any(marker in lower for marker in (
        "private video", "sign in", "login", "log in", "members-only", "confirm your age",
        "cookies", "account", "subscriber", "paid", "purchase",
    )):
        return BridgeError(
            "access_restricted",
            "This content is not publicly accessible. GPS does not bypass logins or access controls.",
        )
    if any(marker in lower for marker in (
        "video unavailable", "does not exist", "has been removed", "not available", "no video formats",
    )):
        return BridgeError("unavailable", "The requested media is unavailable.")
    if "http error 429" in lower or "too many requests" in lower:
        return BridgeError("rate_limited", "The source rate limit was reached. Wait a moment and retry.")
    if "http error 401" in lower or "http error 403" in lower or "forbidden" in lower:
        return BridgeError("access_denied", "The source refused access to this media (HTTP 401/403).")
    if "requested format is not available" in lower or "no suitable format" in lower:
        return BridgeError("format_unavailable", "The selected format is not available for this media.")
    if "ffmpeg" in lower and ("not found" in lower or "not installed" in lower or "unable" in lower):
        return BridgeError("ffmpeg_missing", "FFmpeg is required for that operation but was not found.")
    if any(marker in lower for marker in (
        "timed out", "timeout", "temporary failure", "name or service not known",
        "network is unreachable", "connection refused", "connection reset", "ssl", "certificate",
    )):
        return BridgeError("network_error", "The source could not be reached. Check the network and retry.")
    if exit_code == 130:
        return BridgeError("cancelled", "Cancelled.")
    return BridgeError("download_failed", detail or f"yt-dlp exited with code {exit_code}.")


def parse_metadata(stdout: str) -> dict:
    text = stdout.strip()
    if not text:
        raise BridgeError("invalid_response", "yt-dlp returned no metadata.")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as error:
        raise BridgeError("invalid_response", "yt-dlp returned malformed metadata.") from error
    if isinstance(payload, list):
        if len(payload) != 1 or not isinstance(payload[0], dict):
            raise BridgeError("invalid_response", "yt-dlp returned an unexpected metadata shape.")
        payload = payload[0]
    if not isinstance(payload, dict):
        raise BridgeError("invalid_response", "yt-dlp returned an unexpected metadata shape.")
    return payload


def inspect_url(value: object) -> dict:
    url = validate_url(value)
    ytdlp = executable("yt-dlp")
    if not ytdlp:
        raise BridgeError("yt_dlp_missing", INSTALL_GUIDANCE["yt-dlp"])
    _cancel_event.clear()
    code, stdout, stderr = run_capture(inspect_command(ytdlp, url), INSPECT_TIMEOUT)
    if code != 0:
        raise classify_failure(stderr or stdout, code)
    info = parse_metadata(stdout)
    playlist = looks_like_playlist(info)
    sample = None
    warning = ""
    if playlist:
        try:
            sample_code, sample_out, sample_err = run_capture(
                single_item_inspect_command(ytdlp, url), INSPECT_TIMEOUT
            )
        except BridgeError as error:
            sample_code, sample_out, sample_err = 1, "", error.message
        if sample_code == 0:
            try:
                sample = parse_metadata(sample_out)
            except BridgeError as error:
                warning = error.message
        else:
            warning = classify_failure(sample_err or sample_out, sample_code).message
    result = normalize_metadata(info, url, is_playlist=playlist, sample=sample)
    if warning:
        result["warning"] = warning
    if playlist and sample is None:
        result["formatsUnavailable"] = True
    return result


def build_download_command(
    *,
    ytdlp: str,
    url: str,
    destination: Path,
    mode: str,
    format_id: str,
    format_has_audio: bool,
    quality_cap: int,
    container: str,
    audio_format: str,
    audio_quality: str,
    scope: str,
    playlist_items: str,
    playlist_count: int,
    ffmpeg_available: bool,
) -> list[str]:
    url = validate_url(url)
    mode = str(mode or "video")
    if mode not in ("video", "audio"):
        raise BridgeError("invalid_request", "Unsupported download mode.")
    if format_has_audio not in (True, False):
        raise BridgeError("invalid_request", "Invalid format audio flag.")
    if scope not in ("single", "selected", "full"):
        raise BridgeError("invalid_scope", "Unsupported playlist scope.")
    if not isinstance(quality_cap, int) or quality_cap < 0 or quality_cap > 10000:
        raise BridgeError("invalid_quality", "The selected quality is invalid.")
    container = validate_container(container)
    audio_format = validate_audio_format(audio_format)
    audio_quality = validate_audio_quality(audio_quality)

    command = base_ytdlp_args(ytdlp) + [
        "--newline",
        "--progress",
        "--progress-delta", "0.5",
        "--progress-template", "download:" + PROGRESS_TEMPLATE,
        "--progress-template", "postprocess:" + POSTPROCESS_TEMPLATE,
        "--print", "before_dl:GPS_PLAN|%(filename)s",
        "--print", "after_move:GPS_FILE|%(filepath)s",
        "--no-simulate",
        "--no-overwrites",
        "--continue",
        "--no-mtime",
        "--windows-filenames",
        "--trim-filenames", "200",
        "--retries", "5",
        "--fragment-retries", "5",
    ]

    if scope == "single":
        command += ["--no-playlist", "--playlist-items", "1"]
    elif scope == "selected":
        spec, _count = validate_playlist_spec(playlist_items)
        command += ["--yes-playlist", "--playlist-items", spec]
    else:
        count = validate_playlist_count(playlist_count)
        command += ["--yes-playlist", "--playlist-items", f"1:{count}"]

    if mode == "audio":
        if format_id:
            selected = validate_format_id(format_id)
            if container != "":
                raise BridgeError("invalid_container", "A container cannot be combined with a specific audio format.")
            command += ["--format", selected]
        elif audio_format == "original":
            command += ["--format", "ba/b"]
        else:
            if not ffmpeg_available:
                raise BridgeError(
                    "ffmpeg_missing",
                    "FFmpeg is required to extract or convert audio to that format.",
                )
            command += ["--format", "ba/b"]
        if audio_format != "original":
            if not ffmpeg_available:
                raise BridgeError(
                    "ffmpeg_missing",
                    "FFmpeg is required to extract or convert audio to that format.",
                )
            command += ["--extract-audio", "--audio-format", audio_format]
            if audio_quality != "best":
                command += ["--audio-quality", audio_quality]
    else:
        if format_id:
            selected = validate_format_id(format_id)
            if format_has_audio:
                command += ["--format", selected]
            else:
                if not ffmpeg_available:
                    raise BridgeError(
                        "ffmpeg_missing",
                        "FFmpeg is required to merge this video-only format with audio.",
                    )
                command += ["--format", f"{selected}+ba/{selected}"]
        elif quality_cap > 0:
            height = validate_height(quality_cap)
            if ffmpeg_available:
                command += ["--format", f"bv*[height<={height}]+ba/b[height<={height}]"]
            else:
                command += ["--format", f"b[height<={height}]"]
        elif ffmpeg_available:
            command += ["--format", "bv*+ba/b"]
        else:
            command += ["--format", "b"]
        if container:
            if not ffmpeg_available:
                raise BridgeError("ffmpeg_missing", "FFmpeg is required to merge into that container.")
            command += ["--merge-output-format", container]

    escaped_destination = str(destination).replace("%", "%%")
    command += ["--output", escaped_destination + "/" + OUTPUT_TEMPLATE, "--", url]
    return command


def verify_completed_files(paths: list[str], destination: Path) -> list[dict]:
    verified = []
    seen = set()
    for raw in paths:
        result = verify_file(raw, destination)
        if not result["ok"]:
            raise BridgeError(result["code"] or "file_invalid", result["message"])
        if result["path"] not in seen:
            seen.add(result["path"])
            verified.append(result)
    return verified


def _pump(stream, target: queue.Queue, kind: str) -> None:
    try:
        for line in iter(stream.readline, ""):
            target.put((kind, line.rstrip("\r\n")))
    finally:
        try:
            stream.close()
        except OSError:
            pass
        target.put((kind + "-eof", ""))


def run_download(args: argparse.Namespace) -> int:
    global _active_process
    url = validate_url(args.url)
    job_id = clean_text(args.job_id, 80)
    if not job_id:
        raise BridgeError("invalid_job", "A stable job id is required.")
    ytdlp = executable("yt-dlp")
    if not ytdlp:
        raise BridgeError("yt_dlp_missing", INSTALL_GUIDANCE["yt-dlp"])
    ffmpeg = executable("ffmpeg")
    destination = require_destination(args.output_dir)
    command = build_download_command(
        ytdlp=ytdlp,
        url=url,
        destination=destination,
        mode=args.mode,
        format_id=args.format_id or "",
        format_has_audio=args.format_has_audio == "true",
        quality_cap=args.quality_cap,
        container=args.container,
        audio_format=args.audio_format,
        audio_quality=args.audio_quality,
        scope=args.scope,
        playlist_items=args.playlist_items or "",
        playlist_count=args.playlist_count,
        ffmpeg_available=bool(ffmpeg),
    )
    _cancel_event.clear()
    emit({"event": "started", "jobId": job_id})
    proc = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        start_new_session=True,
    )
    _active_process = proc
    lines: queue.Queue = queue.Queue()
    errors: deque[str] = deque(maxlen=MAX_ERROR_LINES)
    stdout_thread = threading.Thread(target=_pump, args=(proc.stdout, lines, "out"), daemon=True)
    stderr_thread = threading.Thread(target=_pump, args=(proc.stderr, lines, "err"), daemon=True)
    stdout_thread.start()
    stderr_thread.start()
    reported_files: list[str] = []
    planned_files: list[str] = []
    out_done = False
    err_done = False
    cancel_deadline = 0.0
    try:
        if _cancel_event.is_set():
            terminate_group(proc)
        while not (out_done and err_done):
            if _cancel_event.is_set():
                if cancel_deadline == 0.0:
                    cancel_deadline = time.monotonic() + DOWNLOAD_TIMEOUT_GRACE
                    terminate_group(proc)
                elif time.monotonic() >= cancel_deadline and proc.poll() is None:
                    kill_group(proc)
            try:
                kind, line = lines.get(timeout=0.2)
            except queue.Empty:
                continue
            if kind == "out":
                progress = parse_progress_line(line)
                if progress is not None:
                    emit(progress)
                    continue
                postprocess = parse_postprocess_line(line)
                if postprocess is not None:
                    emit(postprocess)
                    continue
                path = mark_path(line, "GPS_FILE|")
                if path:
                    reported_files.append(path)
                    emit({"event": "file", "path": path})
                    continue
                path = mark_path(line, "GPS_PLAN|")
                if path:
                    planned_files.append(path)
                continue
            if kind == "err":
                if line.strip():
                    errors.append(redact_text(line))
                continue
            if kind == "out-eof":
                out_done = True
            elif kind == "err-eof":
                err_done = True
        try:
            code = proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            kill_group(proc)
            code = proc.wait(timeout=2)
    finally:
        _active_process = None
        stdout_thread.join(timeout=2)
        stderr_thread.join(timeout=2)

    if _cancel_event.is_set():
        emit({"event": "cancelled", "ok": False, "code": "cancelled", "message": "Download cancelled."})
        return 130
    if code != 0:
        error = classify_failure("\n".join(errors), code)
        try:
            partial = verify_completed_files(reported_files, destination)
        except BridgeError:
            partial = []
        emit({
            "event": "failed",
            "ok": False,
            "code": error.code,
            "message": error.message,
            "files": [item["path"] for item in partial],
        })
        return 1
    candidates = reported_files if reported_files else planned_files
    if not candidates:
        raise BridgeError(
            "file_unverified",
            "yt-dlp reported success but did not report a final file. Nothing was marked complete.",
        )
    verified = verify_completed_files(candidates, destination)
    if not verified:
        raise BridgeError("file_unverified", "The final file could not be verified.")
    emit({
        "event": "finished",
        "ok": True,
        "files": [item["path"] for item in verified],
        "file": verified[0]["path"],
        "size": sum(int(item.get("size", 0)) for item in verified),
    })
    return 0


def status_payload() -> dict:
    ytdlp = tool_state("yt-dlp", ["--version"])
    ffmpeg = tool_state("ffmpeg", ["-version"])
    ffprobe = tool_state("ffprobe", ["-version"])
    guidance = {
        "ytDlp": "" if ytdlp["ready"] else INSTALL_GUIDANCE["yt-dlp"],
        "ffmpeg": "" if ffmpeg["ready"] else INSTALL_GUIDANCE["ffmpeg"],
        "ffprobe": "" if ffprobe["ready"] else INSTALL_GUIDANCE["ffprobe"],
    }
    return {
        "ok": True,
        "ytDlpPath": ytdlp["path"],
        "ytDlpVersion": ytdlp["version"],
        "ytDlpReady": ytdlp["ready"],
        "ffmpegPath": ffmpeg["path"],
        "ffmpegVersion": ffmpeg["version"],
        "ffmpegReady": ffmpeg["ready"],
        "ffprobePath": ffprobe["path"],
        "ffprobeVersion": ffprobe["version"],
        "ffprobeReady": ffprobe["ready"],
        "ready": ytdlp["ready"],
        "mergeReady": ytdlp["ready"] and ffmpeg["ready"],
        "audioExtractReady": ytdlp["ready"] and ffmpeg["ready"],
        "videoDir": str(user_media_dir("VIDEOS")),
        "audioDir": str(user_media_dir("MUSIC")),
        "guidance": guidance,
        "limits": {
            "maxPlaylistItems": MAX_PLAYLIST_ITEMS,
            "maxConcurrentJobs": 1,
        },
        "appVersion": APP_VERSION,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GPS Media Hub downloads bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("--url", required=True)
    download_parser = subparsers.add_parser("download")
    download_parser.add_argument("--url", required=True)
    download_parser.add_argument("--job-id", required=True)
    download_parser.add_argument("--mode", choices=["video", "audio"], required=True)
    download_parser.add_argument("--output-dir", required=True)
    download_parser.add_argument("--scope", choices=["single", "selected", "full"], default="single")
    download_parser.add_argument("--format-id", default="")
    download_parser.add_argument("--format-has-audio", choices=["true", "false"], default="false")
    download_parser.add_argument("--quality-cap", type=int, default=0)
    download_parser.add_argument("--container", default="Auto")
    download_parser.add_argument("--audio-format", default="original")
    download_parser.add_argument("--audio-quality", default="best")
    download_parser.add_argument("--playlist-items", default="")
    download_parser.add_argument("--playlist-count", type=int, default=0)
    download_parser.add_argument("--resume", action="store_true")
    check_parser = subparsers.add_parser("check-destination")
    check_parser.add_argument("--path", required=True)
    create_parser = subparsers.add_parser("create-destination")
    create_parser.add_argument("--path", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--path", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)
    try:
        if args.command == "status":
            return emit(status_payload())
        if args.command == "inspect":
            return emit(inspect_url(args.url))
        if args.command == "download":
            return run_download(args)
        if args.command == "check-destination":
            return emit(check_destination(args.path))
        if args.command == "create-destination":
            return emit(create_destination(args.path))
        if args.command == "verify":
            results = []
            for raw in args.path:
                destination = None
                results.append(verify_file(raw, destination))
            return emit({"ok": True, "results": results})
        raise BridgeError("invalid_request", "Unknown command.")
    except BridgeError as error:
        if args.command == "download":
            return emit({"event": "failed", "ok": False, "code": error.code, "message": error.message}, 1)
        return fail(error.code, error.message)
    except KeyboardInterrupt:
        if args.command == "download":
            return emit({"event": "cancelled", "ok": False, "code": "cancelled", "message": "Cancelled."}, 130)
        return fail("cancelled", "Cancelled.")
    except Exception:
        message = "The download helper could not complete that request."
        if args.command == "download":
            return emit({"event": "failed", "ok": False, "code": "internal_error", "message": message}, 1)
        return fail("internal_error", message)


if __name__ == "__main__":
    raise SystemExit(main())
