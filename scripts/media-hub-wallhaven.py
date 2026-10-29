#!/usr/bin/env python3
"""Narrow Wallhaven bridge for the Media Hub wallpapers page.

Only two operations are exposed: metadata search and downloading/applying a
selected Wallhaven image. Requests are built from validated arguments; this is
not a general-purpose command runner.
"""
from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


API_SEARCH = "https://wallhaven.cc/api/v1/search"
USER_AGENT = "GPS-MediaHub/1.0"
MAX_JSON_BYTES = 5 * 1024 * 1024
MAX_IMAGE_BYTES = 64 * 1024 * 1024
MIN_FREE_BYTES = 96 * 1024 * 1024
CATEGORIES = {
    "all": "111",
    "general": "100",
    "anime": "010",
    "people": "001",
}
SORTING = {"relevance", "random", "date_added", "favorites", "views", "toplist"}
RESOLUTIONS = {"1920x1080", "2560x1440", "3840x2160"}
RATIOS = {"16x10", "16x9", "21x9", "32x9"}
COLORS = {
    "663399",
    "0099cc",
    "ff9900",
    "669900",
    "cc3333",
    "ea4c88",
    "999999",
}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
FULL_HOSTS = {"w.wallhaven.cc"}
THUMB_HOSTS = {"th.wallhaven.cc"}
SOURCE_HOSTS = {"wallhaven.cc", "www.wallhaven.cc"}
CATEGORY_LABELS = {"general": "General", "anime": "Anime", "people": "People"}


class BridgeError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME", "")
    if base:
        if "\0" in base or not Path(base).is_absolute():
            raise BridgeError("invalid_cache", "XDG_CACHE_HOME must be an absolute path.")
        return Path(base) / "gps-media-hub" / "wallhaven"
    try:
        home = Path.home()
    except RuntimeError as error:
        raise BridgeError("invalid_cache", "Could not resolve the current home directory.") from error
    return home / ".cache" / "gps-media-hub" / "wallhaven"


def bounded_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return default


def meta_int(meta: dict, key: str, default: int) -> int:
    value = meta.get(key)
    if value is None:
        return default
    if isinstance(value, bool):
        raise BridgeError("invalid_response", "Wallhaven returned invalid search metadata.")
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError) as error:
        raise BridgeError("invalid_response", "Wallhaven returned invalid search metadata.") from error


def emit(payload: dict, exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return exit_code


def fail(code: str, message: str) -> int:
    return emit({"ok": False, "code": code, "message": message}, 1)


def https_url(value: object, hosts: set[str]) -> str:
    if not isinstance(value, str) or re.search(r"[\x00-\x20\x7f]", value):
        return ""
    try:
        parsed = urllib.parse.urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        return ""
    if parsed.scheme != "https" or hostname not in hosts:
        return ""
    if parsed.username or parsed.password or port not in (None, 443):
        return ""
    return value


def safe_id(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9]{6,12}", value):
        raise BridgeError("invalid_id", "Invalid Wallhaven wallpaper id.")
    return value


def human_size(size: object) -> str:
    try:
        value = float(size)
    except (TypeError, ValueError):
        return "unknown size"
    if value <= 0:
        return "unknown size"
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return "unknown size"


def ratio_label(width: int, height: int, raw: object) -> str:
    if width > 0 and height > 0:
        value = width / height
        for label, target in (
            ("32:9", 32 / 9),
            ("21:9", 21 / 9),
            ("16:9", 16 / 9),
            ("16:10", 16 / 10),
            ("3:2", 3 / 2),
            ("4:3", 4 / 3),
            ("1:1", 1.0),
        ):
            if abs(value - target) <= 0.025:
                return label
        return f"{value:.2f}:1"
    try:
        return f"{float(raw):.2f}:1"
    except (TypeError, ValueError):
        return "unknown"


def epoch(value: object) -> int:
    if not isinstance(value, str):
        return 0
    try:
        return int(datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return 0


def normalize_wallpaper(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    wallpaper_id = raw.get("id")
    if not isinstance(wallpaper_id, str) or not re.fullmatch(r"[A-Za-z0-9]{6,12}", wallpaper_id):
        return None
    width = max(0, bounded_int(raw.get("dimension_x"), 0))
    height = max(0, bounded_int(raw.get("dimension_y"), 0))
    full = https_url(raw.get("path"), FULL_HOSTS)
    if not full:
        return None
    thumbs = raw.get("thumbs") if isinstance(raw.get("thumbs"), dict) else {}
    thumb = ""
    for key in ("large", "original", "small"):
        thumb = https_url(thumbs.get(key), THUMB_HOSTS)
        if thumb:
            break
    source = https_url(raw.get("url"), SOURCE_HOSTS)
    if not source:
        source = f"https://wallhaven.cc/w/{wallpaper_id}"
    raw_category = raw.get("category")
    category = CATEGORY_LABELS.get(raw_category.lower(), "General") if isinstance(raw_category, str) else "General"
    colors = raw.get("colors")
    colors = [c for c in colors if isinstance(c, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", c)][:5] if isinstance(colors, list) else []
    if not colors:
        colors = ["#161c27", "#2a1b5e", "#0e4a6b"]
    favorites = max(0, bounded_int(raw.get("favorites"), 0))
    resolution = raw.get("resolution")
    if not isinstance(resolution, str) or not re.fullmatch(r"[0-9]{1,5}x[0-9]{1,5}", resolution):
        resolution = f"{width}×{height}" if width and height else "unknown"
    return {
        "id": wallpaper_id,
        "title": f"{category} wallpaper · {wallpaper_id.upper()}",
        "author": "Wallhaven community",
        "category": category,
        "w": width,
        "h": height,
        "res": resolution,
        "ratio": ratio_label(width, height, raw.get("ratio")),
        "size": human_size(raw.get("file_size")),
        "tags": [],
        "likes": favorites,
        "added": epoch(raw.get("created_at")),
        "thumb": thumb,
        "full": full,
        "source": source,
        "colors": colors,
        "desc": f"SFW {category.lower()} wallpaper from Wallhaven. Tags and uploader details are available on the source page.",
    }


def request_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            if response.status != 200:
                raise BridgeError("http_error", f"Wallhaven returned HTTP {response.status}.")
            body = response.read(MAX_JSON_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise BridgeError("rate_limited", "Wallhaven rate limit reached. Wait a minute and retry.")
        if error.code in (401, 403):
            raise BridgeError("forbidden", "Wallhaven refused the request.")
        if error.code == 500:
            raise BridgeError("server_error", "Wallhaven rejected the search (HTTP 500). Try fewer filters.")
        raise BridgeError("http_error", f"Wallhaven returned HTTP {error.code}.") from error
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
        reason = getattr(error, "reason", error)
        raise BridgeError("network_error", f"Could not reach Wallhaven: {reason}") from error
    if len(body) > MAX_JSON_BYTES:
        raise BridgeError("invalid_response", "Wallhaven returned an oversized response.")
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BridgeError("invalid_response", "Wallhaven returned an invalid response.") from error
    if not isinstance(payload, dict):
        raise BridgeError("invalid_response", "Wallhaven returned an invalid response.")
    return payload


def search(args: argparse.Namespace) -> dict:
    query = " ".join((args.query or "").split())[:160]
    category = args.category.lower()
    sorting = args.sorting.lower()
    if category not in CATEGORIES:
        raise BridgeError("invalid_request", "Unsupported Wallhaven category.")
    if sorting not in SORTING:
        raise BridgeError("invalid_request", "Unsupported Wallhaven sort order.")
    # Relevance needs a query on Wallhaven. Curated results are a better
    # default for an empty search than an empty response.
    if sorting == "relevance" and not query:
        sorting = "toplist"
    params = {
        "categories": CATEGORIES[category],
        "purity": "100",
        "sorting": sorting,
        "order": args.order,
        "page": str(max(1, args.page)),
    }
    if query:
        params["q"] = query
    if args.atleast:
        if args.atleast not in RESOLUTIONS:
            raise BridgeError("invalid_request", "Unsupported minimum resolution.")
        params["atleast"] = args.atleast
    if args.ratios:
        ratios = [value for value in args.ratios.split(",") if value]
        if not ratios or any(value not in RATIOS for value in ratios):
            raise BridgeError("invalid_request", "Unsupported aspect ratio.")
        params["ratios"] = ",".join(ratios)
    if args.color:
        if args.color not in COLORS:
            raise BridgeError("invalid_request", "Unsupported colour filter.")
        params["colors"] = args.color
    if args.seed and sorting == "random":
        if not re.fullmatch(r"[A-Za-z0-9]{6}", args.seed):
            raise BridgeError("invalid_request", "Invalid random seed.")
        params["seed"] = args.seed

    payload = request_json(API_SEARCH + "?" + urllib.parse.urlencode(params))
    data = payload.get("data")
    meta = payload.get("meta")
    if not isinstance(data, list) or not isinstance(meta, dict):
        raise BridgeError("invalid_response", "Wallhaven returned an invalid search payload.")
    current_page = meta_int(meta, "current_page", args.page)
    last_page = meta_int(meta, "last_page", 1)
    total = meta_int(meta, "total", 0)
    if current_page < 1 or last_page < 1 or total < 0:
        raise BridgeError("invalid_response", "Wallhaven returned invalid search metadata.")
    results = []
    for item in data:
        normalized = normalize_wallpaper(item)
        if normalized is not None:
            results.append(normalized)
    return {
        "ok": True,
        "results": results,
        "page": current_page,
        "lastPage": last_page,
        "total": total,
        "seed": meta.get("seed") if isinstance(meta.get("seed"), str) else "",
    }


def validate_image(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            head = handle.read(16)
    except OSError:
        return False
    if head.startswith(b"\xff\xd8\xff") or head.startswith(b"\x89PNG\r\n\x1a\n"):
        return True
    if head.startswith(b"GIF87a") or head.startswith(b"GIF89a"):
        return True
    return len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WEBP"


def ensure_image(wallpaper_id: str, full_url: str) -> tuple[Path, bool]:
    wallpaper_id = safe_id(wallpaper_id)
    full_url = https_url(full_url, FULL_HOSTS)
    if not full_url:
        raise BridgeError("invalid_url", "The image URL is not a Wallhaven full-size URL.")
    parsed = urllib.parse.urlsplit(full_url)
    filename = Path(parsed.path).name
    suffix = Path(filename).suffix.lower()
    if suffix == ".jpeg":
        suffix = ".jpg"
    if suffix not in IMAGE_EXTENSIONS:
        raise BridgeError("invalid_url", "Unsupported image type.")
    if Path(filename).stem.lower() != f"wallhaven-{wallpaper_id}".lower():
        raise BridgeError("invalid_url", "The image URL does not match the wallpaper id.")

    directory = cache_root()
    if directory.is_symlink():
        raise BridgeError("cache_error", "Refusing a symlinked wallpaper cache directory.")
    try:
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    except (OSError, ValueError) as error:
        raise BridgeError("cache_error", f"Could not create the wallpaper cache: {error}") from error
    target = directory / f"{wallpaper_id}{suffix}"
    if target.is_symlink():
        raise BridgeError("cache_error", "Refusing a symlinked wallpaper cache entry.")
    if target.is_file() and target.stat().st_size > 0 and validate_image(target):
        return target, True

    try:
        free = shutil.disk_usage(directory).free
    except OSError as error:
        raise BridgeError("cache_error", f"Could not inspect the wallpaper cache: {error}") from error
    if free < MIN_FREE_BYTES:
        raise BridgeError("disk_space", "Not enough free disk space to cache the wallpaper.")

    request = urllib.request.Request(full_url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "image/jpeg,image/png,image/webp,image/gif",
    })
    temp_path: Path | None = None
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            if https_url(response.geturl(), FULL_HOSTS) == "":
                raise BridgeError("invalid_url", "Wallhaven redirected the download to an untrusted host.")
            content_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
            if content_type and not content_type.startswith("image/"):
                raise BridgeError("invalid_image", "The download was not an image.")
            try:
                length = int(response.headers.get("Content-Length") or 0)
            except (TypeError, ValueError):
                length = 0
            if length < 0:
                length = 0
            if length > MAX_IMAGE_BYTES:
                raise BridgeError("too_large", "The wallpaper is larger than the 64 MB safety limit.")
            with tempfile.NamedTemporaryFile(prefix=f".{wallpaper_id}-", suffix=".part",
                                             dir=directory, delete=False) as handle:
                temp_path = Path(handle.name)
                total = 0
                while True:
                    chunk = response.read(256 * 1024)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_IMAGE_BYTES:
                        raise BridgeError("too_large", "The wallpaper exceeded the 64 MB safety limit.")
                    handle.write(chunk)
                handle.flush()
                os.fsync(handle.fileno())
        if temp_path is None or temp_path.stat().st_size == 0:
            raise BridgeError("invalid_image", "Wallhaven returned an empty image.")
        if length > 0 and temp_path.stat().st_size != length:
            raise BridgeError("incomplete_download", "Wallhaven returned an incomplete image.")
        if not validate_image(temp_path):
            raise BridgeError("invalid_image", "The downloaded file is not a supported image.")
        try:
            os.replace(temp_path, target)
        except OSError as error:
            raise BridgeError("cache_error", f"Could not store the wallpaper in the cache: {error}") from error
        temp_path = None
    except urllib.error.HTTPError as error:
        raise BridgeError("download_failed", f"Wallhaven download failed with HTTP {error.code}.") from error
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
        reason = getattr(error, "reason", error)
        raise BridgeError("network_error", f"Could not download the wallpaper: {reason}") from error
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink()
            except OSError:
                pass
    return target, False


def ensure_awww_daemon() -> None:
    if shutil.which("awww") is None:
        raise BridgeError("wallpaper_unavailable", "awww is not installed.")
    for attempt in range(12):
        try:
            result = subprocess.run(["awww", "query"], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=3)
            if result.returncode == 0:
                return
        except (OSError, subprocess.TimeoutExpired):
            pass
        if attempt == 0:
            try:
                subprocess.Popen(["awww-daemon"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            except OSError as error:
                raise BridgeError("wallpaper_unavailable", f"Could not start awww-daemon: {error}") from error
        time.sleep(0.25)
    raise BridgeError("wallpaper_unavailable", "awww-daemon did not become ready.")


def wallpaper_library_dir() -> Path:
    override = os.environ.get("GPS_WALLPAPER_DIR", "")
    if override:
        return Path(override)
    home = os.environ.get("HOME")
    if not home:
        home = os.path.expanduser("~")
    return Path(home) / "Pictures" / "Wallpapers"


def save_to_library(wallpaper_id: str, full_url: str) -> tuple[Path, bool]:
    wallpaper_id = safe_id(wallpaper_id)
    full_url = https_url(full_url, FULL_HOSTS)
    if not full_url:
        raise BridgeError("invalid_url", "The image URL is not a Wallhaven full-size URL.")
    parsed = urllib.parse.urlsplit(full_url)
    filename = Path(parsed.path).name
    suffix = Path(filename).suffix.lower()
    if suffix == ".jpeg":
        suffix = ".jpg"
    if suffix not in IMAGE_EXTENSIONS:
        raise BridgeError("invalid_url", "Unsupported image type.")
    if Path(filename).stem.lower() != f"wallhaven-{wallpaper_id}".lower():
        raise BridgeError("invalid_url", "The image URL does not match the wallpaper id.")

    lib_dir = wallpaper_library_dir()
    if lib_dir.is_symlink():
        raise BridgeError("library_error", "Refusing a symlinked wallpaper library directory.")
    try:
        lib_dir.mkdir(parents=True, exist_ok=True, mode=0o755)
    except (OSError, ValueError) as error:
        raise BridgeError("library_error", f"Could not create the wallpaper library: {error}") from error

    target = lib_dir / f"wallhaven-{wallpaper_id}{suffix}"
    if target.is_symlink():
        raise BridgeError("library_error", "Refusing a symlinked wallpaper library entry.")
    if target.is_file() and target.stat().st_size > 0 and validate_image(target):
        return target, True

    source_path, cached = ensure_image(wallpaper_id, full_url)
    if not source_path.is_file() or source_path.stat().st_size == 0 or not validate_image(source_path):
        raise BridgeError("invalid_image", "The source wallpaper is not a supported image.")

    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(prefix=f".wallhaven-{wallpaper_id}-", suffix=".part",
                                         dir=lib_dir, delete=False) as handle:
            temp_path = Path(handle.name)
            with source_path.open("rb") as src:
                shutil.copyfileobj(src, handle)
            handle.flush()
            os.fsync(handle.fileno())
        if temp_path.stat().st_size == 0 or not validate_image(temp_path):
            raise BridgeError("invalid_image", "The saved wallpaper is not a supported image.")
        os.replace(temp_path, target)
        temp_path = None
    except OSError as error:
        raise BridgeError("library_error", f"Could not store the wallpaper in the library: {error}") from error
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink()
            except OSError:
                pass
    return target, cached


def last_wall_path() -> Path:
    config_dir = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "quickshell"
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir / "gps-last-wall.txt"


def apply_wallpaper(args: argparse.Namespace) -> dict:
    path, cached = save_to_library(args.id, args.path)
    ensure_awww_daemon()
    try:
        result = subprocess.run([
            "awww", "img", str(path),
            "--transition-type", "outer",
            "--transition-pos", "0.92,0.06",
            "--transition-fps", "165",
            "--transition-duration", "1.1",
        ], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise BridgeError("wallpaper_failed", f"awww could not apply the wallpaper: {error}") from error
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "").strip().splitlines()
        detail = message[-1] if message else "unknown error"
        raise BridgeError("wallpaper_failed", f"awww rejected the wallpaper: {detail}")
    try:
        last_wall_path().write_text(str(path), encoding="utf-8")
    except OSError:
        pass
    try:
        scripts_dir = Path(__file__).resolve().parent
        if str(scripts_dir) not in sys.path:
            sys.path.insert(0, str(scripts_dir))
        import set_wallpaper
        set_wallpaper.apply_wallpaper(str(path), skip_awww=True)
    except Exception:
        pass
    return {"ok": True, "path": str(path), "cached": cached, "title": args.title}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Media Hub Wallhaven bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)

    search_parser = subparsers.add_parser("search")
    search_parser.add_argument("--query", default="")
    search_parser.add_argument("--category", default="all", choices=sorted(CATEGORIES))
    search_parser.add_argument("--sorting", default="relevance", choices=sorted(SORTING))
    search_parser.add_argument("--order", default="desc", choices=["asc", "desc"])
    search_parser.add_argument("--atleast", default="")
    search_parser.add_argument("--ratios", default="")
    search_parser.add_argument("--color", default="")
    search_parser.add_argument("--page", type=int, default=1)
    search_parser.add_argument("--seed", default="")

    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--id", required=True)
    apply_parser.add_argument("--path", required=True)
    apply_parser.add_argument("--title", default="Wallhaven wallpaper")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        if args.command == "search":
            return emit(search(args))
        if args.command == "apply":
            return emit(apply_wallpaper(args))
        raise BridgeError("invalid_request", "Unknown command.")
    except BridgeError as error:
        return fail(error.code, error.message)
    except KeyboardInterrupt:
        return fail("cancelled", "Cancelled.")


if __name__ == "__main__":
    raise SystemExit(main())
