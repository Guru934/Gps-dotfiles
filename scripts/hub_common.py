#!/usr/bin/env python3
"""Shared HTTP, cache, state, and JSON contract helpers for Media Hub providers."""

from __future__ import annotations

import hashlib
import ipaddress
import json
import math
import os
import re
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any, Callable, Mapping


APP_VERSION = "1.0"
USER_AGENT = f"GPS-Desktop/{APP_VERSION}"
DEFAULT_TIMEOUT = 12.0
DEFAULT_RETRIES = 3
DEFAULT_CACHE_TTL = 600
DEFAULT_CACHE_SIZE = 50 * 1024 * 1024
MAX_RETRY_AFTER = 24 * 60 * 60
MAX_RETRY_SLEEP = 30
RATE_LIMIT_INTERVAL = 0.25
ERROR_KINDS = frozenset({"network", "rate_limited", "unavailable", "invalid"})
_host_lock = threading.Lock()
_host_last_request: dict[str, float] = {}


class HubError(Exception):
    """A provider-facing error with a stable JSON representation."""

    def __init__(self, kind: str, message: str, retry_after: int | None = None):
        if kind not in ERROR_KINDS:
            raise ValueError(f"Unsupported Hub error kind: {kind}")
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.retry_after = retry_after

    def as_json(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "ok": False,
            "error": {"kind": self.kind, "message": self.message},
        }
        if self.retry_after is not None:
            result["retryAfter"] = self.retry_after
        return result


def cache_root() -> Path:
    configured = os.environ.get("XDG_CACHE_HOME")
    base = Path(configured) if configured and Path(configured).is_absolute() else Path.home() / ".cache"
    return base / "gps" / "media"


def state_root() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    base = Path(configured) if configured and Path(configured).is_absolute() else Path.home() / ".local" / "state"
    return base / "gps"


def _atomic_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
        try:
            directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError:
            pass
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def atomic_json_write(path: str | os.PathLike[str], payload: Any) -> None:
    target = Path(path)
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    _atomic_bytes(target, data)


def _retry_after(headers: Mapping[str, str] | Any, now: float) -> int | None:
    raw = headers.get("Retry-After") if headers else None
    if raw is None:
        return None
    value = str(raw).strip()
    try:
        seconds = float(value)
        if not math.isfinite(seconds):
            return None
    except ValueError:
        try:
            parsed = parsedate_to_datetime(value)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            seconds = parsed.timestamp() - now
        except (TypeError, ValueError, OverflowError):
            return None
    if seconds < 0:
        return 0
    return min(MAX_RETRY_AFTER, int(seconds + 0.999))


def _rate_limit(host: str, sleep: Callable[[float], None], now: Callable[[], float]) -> None:
    with _host_lock:
        current = now()
        delay = max(0.0, _host_last_request.get(host, 0.0) + RATE_LIMIT_INTERVAL - current)
        _host_last_request[host] = current + delay
    if delay:
        sleep(delay)


def _validated_request_url(url: str) -> urllib.parse.SplitResult:
    try:
        parsed = urllib.parse.urlsplit(url)
        host = parsed.hostname
        port = parsed.port
    except (TypeError, ValueError):
        raise HubError("invalid", "The provider URL is invalid.") from None
    if parsed.scheme not in ("http", "https") or not host or parsed.username or parsed.password:
        raise HubError("invalid", "The provider URL must use HTTP or HTTPS without credentials.")
    if port is not None and not 1 <= port <= 65535:
        raise HubError("invalid", "The provider URL has an invalid port.")
    return parsed


class _SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, new_url):
        parsed = _validated_request_url(new_url)
        if req.full_url.startswith("https:") and parsed.scheme != "https":
            raise HubError("invalid", "HTTPS provider requests cannot redirect to HTTP.")
        if parsed.scheme == "https":
            _validated_public_url(new_url)
        return super().redirect_request(req, fp, code, msg, headers, new_url)


def _open_url(request: urllib.request.Request, timeout: float):
    opener = urllib.request.build_opener(_SafeRedirectHandler)
    return opener.open(request, timeout=timeout)


def request(
    url: str,
    *,
    data: bytes | None = None,
    method: str | None = None,
    headers: Mapping[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT,
    retries: int = DEFAULT_RETRIES,
    max_bytes: int = 10 * 1024 * 1024,
    opener: Callable[[urllib.request.Request, float], Any] | None = None,
    sleep: Callable[[float], None] = time.sleep,
    now: Callable[[], float] = time.time,
) -> tuple[bytes, Mapping[str, str]]:
    """Fetch one HTTP response with host pacing, bounded retries, and clear errors."""
    parsed = _validated_request_url(url)
    if timeout <= 0 or retries < 0 or max_bytes <= 0:
        raise ValueError("timeout and max_bytes must be positive; retries cannot be negative")
    request_headers = {str(key): str(value) for key, value in (headers or {}).items()}
    if any(key.lower() == "user-agent" for key in request_headers):
        raise ValueError("Provider User-Agent is managed by hub_common")
    request_headers["User-Agent"] = USER_AGENT
    request_headers.setdefault("Accept", "application/json, image/*;q=0.8, */*;q=0.1")
    http_request = urllib.request.Request(url, data=data, headers=request_headers, method=method)
    opener = opener or _open_url
    retry_delay = 0.5

    for attempt in range(retries + 1):
        _rate_limit(parsed.hostname.lower(), sleep, now)
        try:
            with opener(http_request, timeout) as response:
                status = int(getattr(response, "status", 200))
                response_headers = getattr(response, "headers", {})
                if status == 429:
                    delay = _retry_after(response_headers, now())
                    if delay is not None and delay > MAX_RETRY_SLEEP:
                        raise HubError("rate_limited", "The provider rate limit was reached.", delay)
                    if attempt < retries:
                        sleep(float(delay if delay is not None else retry_delay))
                        retry_delay = min(30.0, retry_delay * 2)
                        continue
                    raise HubError("rate_limited", "The provider rate limit was reached.", delay)
                if status >= 500:
                    if attempt < retries:
                        sleep(retry_delay)
                        retry_delay = min(30.0, retry_delay * 2)
                        continue
                    raise HubError("unavailable", f"The provider returned HTTP {status}.")
                if status < 200 or status >= 300:
                    raise HubError("unavailable", f"The provider returned HTTP {status}.")
                length = response_headers.get("Content-Length")
                if length is not None:
                    try:
                        if int(length) > max_bytes:
                            raise HubError("invalid", "The provider response exceeds the configured size limit.")
                    except ValueError:
                        raise HubError("invalid", "The provider returned an invalid content length.") from None
                body = response.read(max_bytes + 1)
            if len(body) > max_bytes:
                raise HubError("invalid", "The provider response exceeds the configured size limit.")
            return body, response_headers
        except urllib.error.HTTPError as error:
            error.close()
            if error.code == 429:
                delay = _retry_after(error.headers, now())
                if delay is not None and delay > MAX_RETRY_SLEEP:
                    raise HubError("rate_limited", "The provider rate limit was reached.", delay) from None
                if attempt < retries:
                    sleep(float(delay if delay is not None else retry_delay))
                    retry_delay = min(30.0, retry_delay * 2)
                    continue
                raise HubError("rate_limited", "The provider rate limit was reached.", delay) from None
            if error.code >= 500 and attempt < retries:
                sleep(retry_delay)
                retry_delay = min(30.0, retry_delay * 2)
                continue
            kind = "unavailable" if error.code >= 500 else "invalid"
            raise HubError(kind, f"The provider returned HTTP {error.code}.") from None
        except HubError:
            raise
        except (TimeoutError, urllib.error.URLError, OSError) as error:
            if attempt < retries:
                sleep(retry_delay)
                retry_delay = min(30.0, retry_delay * 2)
                continue
            reason = getattr(error, "reason", error)
            raise HubError("network", f"The provider could not be reached: {reason}") from None
    raise HubError("unavailable", "The provider request could not be completed.")


class DiskCache:
    """Small TTL byte cache with an on-disk size bound and LRU cleanup."""

    def __init__(
        self,
        root: str | os.PathLike[str] | None = None,
        *,
        ttl_seconds: int = DEFAULT_CACHE_TTL,
        max_bytes: int = DEFAULT_CACHE_SIZE,
        now: Callable[[], float] = time.time,
    ):
        if ttl_seconds < 0 or max_bytes < 0:
            raise ValueError("cache limits cannot be negative")
        self.root = Path(root) if root is not None else cache_root()
        self.ttl_seconds = ttl_seconds
        self.max_bytes = max_bytes
        self.now = now

    def _paths(self, key: str) -> tuple[Path, Path]:
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        return self.root / f"{digest}.bin", self.root / f"{digest}.json"

    def get_entry(self, key: str) -> tuple[bytes, str | None] | None:
        data_path, meta_path = self._paths(key)
        try:
            metadata = json.loads(meta_path.read_text(encoding="utf-8"))
            if not isinstance(metadata, dict) or self.now() - float(metadata["created"]) >= self.ttl_seconds:
                self._remove(data_path, meta_path)
                return None
            data = data_path.read_bytes()
            if len(data) != metadata.get("size"):
                self._remove(data_path, meta_path)
                return None
            os.utime(data_path, None)
            return data, metadata.get("contentType") if isinstance(metadata.get("contentType"), str) else None
        except (OSError, ValueError, TypeError, KeyError):
            return None

    def get(self, key: str) -> bytes | None:
        entry = self.get_entry(key)
        return entry[0] if entry else None

    def set(self, key: str, data: bytes, content_type: str | None = None) -> Path:
        if len(data) > self.max_bytes:
            raise ValueError("cache entry exceeds the configured cache size")
        data_path, meta_path = self._paths(key)
        _atomic_bytes(data_path, data)
        atomic_json_write(meta_path, {
            "created": self.now(),
            "size": len(data),
            "contentType": content_type,
        })
        self.cleanup()
        return data_path

    @staticmethod
    def _remove(data_path: Path, meta_path: Path) -> None:
        for path in (data_path, meta_path):
            try:
                path.unlink()
            except FileNotFoundError:
                pass

    def cleanup(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        entries: list[tuple[float, Path, Path, int]] = []
        total = 0
        for meta_path in self.root.glob("*.json"):
            data_path = meta_path.with_suffix(".bin")
            try:
                metadata = json.loads(meta_path.read_text(encoding="utf-8"))
                created = float(metadata["created"])
                size = data_path.stat().st_size
                if self.now() - created >= self.ttl_seconds:
                    self._remove(data_path, meta_path)
                    continue
                entries.append((data_path.stat().st_mtime, data_path, meta_path, size))
                total += size
            except (OSError, ValueError, TypeError, KeyError):
                self._remove(data_path, meta_path)
        for _, data_path, meta_path, size in sorted(entries):
            if total <= self.max_bytes:
                break
            self._remove(data_path, meta_path)
            total -= size


def _validated_public_url(url: str) -> urllib.parse.SplitResult:
    parsed = _validated_request_url(url)
    if parsed.scheme != "https" or parsed.port not in (None, 443):
        raise HubError("invalid", "Cached files must be fetched from HTTPS URLs.")
    host = parsed.hostname.lower()
    if host == "localhost" or host.endswith(".localhost"):
        raise HubError("invalid", "Local hosts cannot be used for remote file fetches.")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise HubError("invalid", "Private or reserved addresses cannot be used for remote file fetches.")
    return parsed


def fetch_and_cache(
    url: str,
    *,
    allowed_content_types: tuple[str, ...] = ("image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"),
    max_bytes: int = 10 * 1024 * 1024,
    cache: DiskCache | None = None,
    timeout: float = DEFAULT_TIMEOUT,
    retries: int = DEFAULT_RETRIES,
) -> Path:
    """Fetch a validated remote image/file and return its atomically cached path."""
    _validated_public_url(url)
    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    cache = cache or DiskCache()
    key = f"file:{url}"
    cached = cache.get_entry(key)
    if cached:
        data, content_type = cached
        if len(data) <= max_bytes and content_type in allowed_content_types:
            return cache._paths(key)[0]
    data, headers = request(url, timeout=timeout, retries=retries, max_bytes=max_bytes)
    content_type = str(headers.get("Content-Type", "")).split(";", 1)[0].strip().lower()
    allowed = {value.lower() for value in allowed_content_types}
    if content_type not in allowed:
        raise HubError("invalid", "The fetched file has an unsupported content type.")
    if len(data) > max_bytes:
        raise HubError("invalid", "The fetched file exceeds the configured size limit.")
    length = headers.get("Content-Length")
    if length is not None:
        try:
            if int(length) > max_bytes:
                raise HubError("invalid", "The fetched file exceeds the configured size limit.")
        except ValueError:
            raise HubError("invalid", "The fetched file has an invalid content length.") from None
    return cache.set(key, data, content_type)


class PersistentState:
    """Atomic JSON state under ~/.local/state/gps; corrupt files are backed up."""

    def __init__(self, name: str, *, root: str | os.PathLike[str] | None = None):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,79}", name):
            raise ValueError("state name must be a simple filename stem")
        self.path = (Path(root) if root is not None else state_root()) / f"{name}.json"
        self.last_error = ""

    def load(self, default: Any) -> Any:
        self.last_error = ""
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return default
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.last_error = str(error)
            if isinstance(error, json.JSONDecodeError):
                backup = self.path.with_name(f"{self.path.stem}.corrupt-{time.time_ns()}.json")
                try:
                    os.replace(self.path, backup)
                except OSError as backup_error:
                    self.last_error += f"; could not preserve corrupt state: {backup_error}"
            return default

    def save(self, payload: Any) -> None:
        atomic_json_write(self.path, payload)


def error_payload(kind: str, message: str) -> dict[str, Any]:
    validate_contract("Error", {"ok": False, "error": {"kind": kind, "message": message}})
    return {"ok": False, "error": {"kind": kind, "message": message}}


def validate_contract(shape: str, value: Any) -> None:
    """Raise ValueError unless a normalized provider value matches its contract."""
    if not isinstance(value, dict):
        raise ValueError(f"{shape} must be a JSON object")

    def text(field: str, required: bool = True) -> str:
        item = value.get(field)
        if required and (not isinstance(item, str) or not item.strip()):
            raise ValueError(f"{shape}.{field} must be a non-empty string")
        if not required and item is not None and not isinstance(item, str):
            raise ValueError(f"{shape}.{field} must be a string or null")
        return item if isinstance(item, str) else ""

    def positive_int(field: str, *, allow_zero: bool = False) -> int:
        item = value.get(field)
        if isinstance(item, bool) or not isinstance(item, int) or item < (0 if allow_zero else 1):
            raise ValueError(f"{shape}.{field} must be an integer")
        return item

    def url(field: str, allow_file: bool = False) -> None:
        raw = text(field)
        parsed = urllib.parse.urlsplit(raw)
        permitted = {"https", "http"} | ({"file"} if allow_file else set())
        if parsed.scheme not in permitted or (parsed.scheme != "file" and not parsed.hostname):
            raise ValueError(f"{shape}.{field} must be an absolute URL")

    if shape == "Error":
        if value.get("ok") is not False:
            raise ValueError("Error.ok must be false")
        error = value.get("error")
        if not isinstance(error, dict) or error.get("kind") not in ERROR_KINDS:
            raise ValueError("Error.error.kind is unsupported")
        if not isinstance(error.get("message"), str) or not error["message"].strip():
            raise ValueError("Error.error.message must be non-empty text")
        retry_after = value.get("retryAfter")
        if retry_after is not None and (
            isinstance(retry_after, bool)
            or not isinstance(retry_after, (int, float))
            or retry_after < 0
        ):
            raise ValueError("Error.retryAfter must be a non-negative number")
        return
    if shape == "Track":
        if value.get("kind") != "track":
            raise ValueError("Track.kind must be 'track'")
        for field in ("id", "title", "artist", "album"):
            text(field, required=field in ("id", "title"))
        positive_int("dur", allow_zero=True)
        url("streamUrl")
        for field in ("art", "sourceUrl"):
            if value.get(field):
                url(field)
        return
    if shape in ("Anime", "Manga"):
        expected = shape.lower()
        if value.get("kind") != expected:
            raise ValueError(f"{shape}.kind must be {expected!r}")
        text("id")
        text("title")
        url("siteUrl")
        if value.get("cover"):
            url("cover")
        return
    if shape == "Chapter":
        text("title")
        count = positive_int("pageCount")
        pages = value.get("pages")
        if not isinstance(pages, list) or len(pages) != count:
            raise ValueError("Chapter.pages length must equal pageCount")
        for item in pages:
            if not isinstance(item, str):
                raise ValueError("Chapter page URLs must be strings")
            parsed = urllib.parse.urlsplit(item)
            if parsed.scheme not in ("https", "http", "file"):
                raise ValueError("Chapter pages must use HTTP, HTTPS, or file URLs")
        return
    if shape == "PageList":
        text("title")
        positive_int("pageCount")
        pages = value.get("pages")
        if not isinstance(pages, list) or len(pages) != value["pageCount"]:
            raise ValueError("PageList.pages length must equal pageCount")
        for page in pages:
            if not isinstance(page, str):
                raise ValueError("PageList pages must be URL strings")
            parsed = urllib.parse.urlsplit(page)
            if parsed.scheme not in ("https", "http", "file"):
                raise ValueError("PageList pages must use HTTP, HTTPS, or file URLs")
        return
    raise ValueError(f"Unknown normalized shape: {shape}")
