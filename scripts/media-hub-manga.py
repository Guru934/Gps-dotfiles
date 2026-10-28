#!/usr/bin/env python3
"""Local manga collection helper for the GPS Media Hub.

The helper accepts one explicitly selected CBZ, CBR or image folder, validates
it and returns page file URLs. Archives are extracted into a dedicated cache
directory. It never scans a home directory, follows no archive links and never
starts a reader or shell command.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
from pathlib import Path, PurePosixPath


MAX_PATH = 4096
MAX_ENTRIES = 5000
MAX_PAGES = 5000
MAX_CHAPTERS = 500
MAX_TOTAL_BYTES = 2 * 1024 * 1024 * 1024
MAX_ENTRY_BYTES = 256 * 1024 * 1024
MAX_LIST_BYTES = 8 * 1024 * 1024
LIST_TIMEOUT_SECONDS = 30
EXTRACT_TIMEOUT_SECONDS = 120
CACHE_VERSION = 1
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ARCHIVE_EXTENSIONS = {".cbz": "CBZ", ".cbr": "CBR"}


class MangaError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def executable(name):
    path = shutil.which(name)
    if not path:
        return ""
    try:
        resolved = str(Path(path).resolve())
    except OSError:
        resolved = path
    return resolved if os.path.isfile(resolved) and os.access(resolved, os.X_OK) else ""


def clean_text(value, limit=200):
    if not isinstance(value, str):
        return ""
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", value).strip()
    return re.sub(r"\s+", " ", text)[:limit]


def natural_key(value):
    parts = re.split(r"(\d+)", value.casefold())
    return tuple((0, int(part)) if part.isdigit() else (1, part) for part in parts)


def cache_root(create=False):
    root = os.environ.get("XDG_CACHE_HOME")
    if not root:
        root = str(Path.home() / ".cache")
    path = Path(root) / "gps-media-hub" / "manga"
    if create:
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            path.chmod(0o700)
        except OSError:
            pass
    return path


def safe_input_path(value):
    if not isinstance(value, str):
        raise MangaError("invalid_path", "Choose a local manga file or folder.")
    raw = value.strip()
    if not raw or len(raw) > MAX_PATH:
        raise MangaError("invalid_path", "That manga path is not valid.")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in raw):
        raise MangaError("invalid_path", "That manga path contains control characters.")
    if raw.lower().startswith("file://"):
        parsed = urllib.parse.urlsplit(raw)
        if parsed.scheme.lower() != "file" or parsed.netloc not in ("", "localhost"):
            raise MangaError("invalid_path", "Only local file URLs are supported.")
        if parsed.query or parsed.fragment:
            raise MangaError("invalid_path", "That local file URL is not valid.")
        raw = urllib.parse.unquote(parsed.path)
    path = Path(raw)
    if not path.is_absolute():
        raise MangaError("invalid_path", "Choose an absolute local path.")
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError):
        raise MangaError("not_found", "That manga path does not exist.") from None
    if resolved.is_file():
        if resolved.suffix.lower() not in ARCHIVE_EXTENSIONS:
            raise MangaError("unsupported_file", "Choose a CBZ or CBR archive.")
    elif resolved.is_dir():
        if resolved == Path("/") or resolved == Path.home():
            raise MangaError("unsafe_path", "Choose a manga folder, not your home directory or the filesystem root.")
    else:
        raise MangaError("not_file", "That path is not a regular file or folder.")
    return resolved


def safe_archive_name(value):
    if not isinstance(value, str):
        raise MangaError("unsafe_archive", "The archive contains an invalid entry name.")
    name = value.strip()
    if not name or len(name) > MAX_PATH:
        raise MangaError("unsafe_archive", "The archive contains an invalid entry name.")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in name):
        raise MangaError("unsafe_archive", "The archive contains a control character in an entry name.")
    if "\\" in name:
        raise MangaError("unsafe_archive", "The archive contains an unsafe backslash path.")
    pure = PurePosixPath(name)
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        raise MangaError("unsafe_archive", "The archive contains an unsafe path.")
    return str(pure)


def safe_join(root, name):
    target = (root / PurePosixPath(name)).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError:
        raise MangaError("unsafe_archive", "The archive contains a path outside its cache.") from None
    return target


def image_name(value):
    return Path(value).suffix.lower() in IMAGE_EXTENSIONS


def file_url(path):
    return path.resolve().as_uri()


def image_files(directory):
    try:
        children = list(directory.iterdir())
    except OSError:
        raise MangaError("inaccessible", "That manga folder cannot be read.") from None
    files = []
    for child in children:
        if child.name.startswith(".") or child.is_symlink():
            continue
        try:
            if child.is_file() and child.suffix.lower() in IMAGE_EXTENSIONS:
                files.append(child)
        except OSError:
            continue
    return sorted(files, key=lambda item: natural_key(item.name))


def chapter_from_pages(title, pages):
    return {
        "title": clean_text(title, 160) or "Pages",
        "pageCount": len(pages),
        "pages": [file_url(page) for page in pages],
    }


def archive_key(path):
    try:
        info = path.stat()
    except OSError:
        raise MangaError("not_found", "That archive is no longer available.") from None
    raw = f"{path}\0{info.st_mtime_ns}\0{info.st_size}\0{CACHE_VERSION}".encode()
    return hashlib.sha256(raw).hexdigest()[:24]


def manifest_pages(target):
    manifest = target / "manifest.json"
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("version") != CACHE_VERSION:
        return None
    names = data.get("pages")
    if not isinstance(names, list) or not names or len(names) > MAX_PAGES:
        return None
    pages = []
    for name in names:
        try:
            safe_name = safe_archive_name(name)
        except MangaError:
            return None
        page = safe_join(target, safe_name)
        if page.is_symlink() or not page.is_file():
            return None
        pages.append(page)
    return pages


def remove_cache_dir(target):
    root = cache_root(create=False).resolve()
    try:
        target.resolve().relative_to(root)
    except ValueError:
        return
    if target.name.startswith(".tmp-") or target.parent.resolve() == root:
        try:
            if target.is_symlink() or target.is_file():
                target.unlink()
            elif target.is_dir():
                shutil.rmtree(target)
        except OSError:
            pass


def validate_zip_entries(archive):
    try:
        with zipfile.ZipFile(archive) as bundle:
            infos = bundle.infolist()
            if len(infos) > MAX_ENTRIES:
                raise MangaError("too_many_entries", "That archive contains too many files.")
            total = 0
            pages = []
            seen = set()
            for info in infos:
                name = safe_archive_name(info.filename)
                if info.flag_bits & 0x1:
                    raise MangaError("encrypted_archive", "Encrypted archives are not supported.")
                mode = (info.external_attr >> 16) & 0xFFFF
                file_type = stat.S_IFMT(mode)
                if file_type == stat.S_IFLNK:
                    raise MangaError("unsafe_archive", "The archive contains a symbolic link.")
                if file_type and file_type not in (stat.S_IFREG, stat.S_IFDIR):
                    raise MangaError("unsafe_archive", "The archive contains a special file.")
                if info.is_dir():
                    continue
                total += info.file_size
                if info.file_size > MAX_ENTRY_BYTES or total > MAX_TOTAL_BYTES:
                    raise MangaError("archive_too_large", "That archive is too large to open safely.")
                if image_name(name):
                    if name in seen:
                        raise MangaError("unsafe_archive", "The archive contains duplicate page names.")
                    seen.add(name)
                    pages.append(info)
            if not pages:
                raise MangaError("no_pages", "That archive contains no supported images.")
            pages.sort(key=lambda info: natural_key(info.filename))
            return pages
    except zipfile.BadZipFile:
        raise MangaError("corrupt_archive", "That CBZ archive is damaged.") from None
    except OSError:
        raise MangaError("inaccessible", "That CBZ archive cannot be read.") from None


def extract_zip(archive, target):
    infos = validate_zip_entries(archive)
    pages = []
    try:
        with zipfile.ZipFile(archive) as bundle:
            for info in infos:
                name = safe_archive_name(info.filename)
                destination = safe_join(target, name)
                destination.parent.mkdir(parents=True, exist_ok=True)
                written = 0
                with bundle.open(info) as source, destination.open("wb") as output:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        written += len(chunk)
                        if written > MAX_ENTRY_BYTES:
                            raise MangaError("archive_too_large", "That archive is too large to open safely.")
                        output.write(chunk)
                pages.append(destination)
    except zipfile.BadZipFile:
        raise MangaError("corrupt_archive", "That CBZ archive is damaged.") from None
    except OSError:
        raise MangaError("extract_failed", "That CBZ archive could not be extracted.") from None
    return pages


def seven_zip():
    return executable("7z")


def parse_7z_entries(text):
    lines = text.splitlines()
    try:
        start = lines.index("----------") + 1
    except ValueError:
        raise MangaError("unsupported_archive", "That CBR archive could not be listed.") from None
    blocks = []
    current = {}
    for line in lines[start:]:
        if line.strip() == "":
            if current:
                blocks.append(current)
                current = {}
            continue
        if " = " in line:
            key, value = line.split(" = ", 1)
            current[key.strip()] = value
    if current:
        blocks.append(current)
    return blocks


def validate_cbr_entries(archive, extractor):
    try:
        result = subprocess.run(
            [extractor, "l", "-slt", "--", str(archive)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=LIST_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise MangaError("extractor_timeout", "That CBR archive took too long to inspect.") from None
    except OSError:
        raise MangaError("extractor_failed", "The CBR extractor could not be started.") from None
    if result.returncode != 0:
        raise MangaError("unsupported_archive", "That CBR archive could not be read.")
    if len(result.stdout) > MAX_LIST_BYTES:
        raise MangaError("too_many_entries", "That archive contains too many files.")
    try:
        text = result.stdout.decode("utf-8", errors="replace")
    except Exception:
        raise MangaError("unsupported_archive", "That CBR archive could not be listed.") from None
    entries = parse_7z_entries(text)
    if len(entries) > MAX_ENTRIES:
        raise MangaError("too_many_entries", "That archive contains too many files.")
    total = 0
    pages = []
    seen = set()
    for entry in entries:
        name = safe_archive_name(entry.get("Path", ""))
        if entry.get("Folder") == "+":
            continue
        if entry.get("Encrypted") == "+":
            raise MangaError("encrypted_archive", "Encrypted archives are not supported.")
        attributes = str(entry.get("Attributes", "")).strip().lower()
        mode = attributes.split()[-1] if attributes else ""
        if mode.startswith(("l", "h", "c", "b", "p", "s")):
            raise MangaError("unsafe_archive", "The archive contains a link or special file.")
        if entry.get("Symbolic Link", "") or entry.get("Hard Link", ""):
            raise MangaError("unsafe_archive", "The archive contains a link.")
        try:
            size = int(entry.get("Size", "0"))
        except ValueError:
            raise MangaError("unsupported_archive", "That CBR archive has an invalid entry.") from None
        total += size
        if size < 0 or size > MAX_ENTRY_BYTES or total > MAX_TOTAL_BYTES:
            raise MangaError("archive_too_large", "That archive is too large to open safely.")
        if image_name(name):
            if name in seen:
                raise MangaError("unsafe_archive", "The archive contains duplicate page names.")
            seen.add(name)
            pages.append(name)
    if not pages:
        raise MangaError("no_pages", "That archive contains no supported images.")
    pages.sort(key=natural_key)
    return pages


def extract_cbr(archive, target):
    extractor = seven_zip()
    if not extractor:
        raise MangaError("cbr_unsupported", "CBR support needs 7z; install it separately to open this archive.")
    names = validate_cbr_entries(archive, extractor)
    try:
        result = subprocess.run(
            [extractor, "x", str(archive), "-y", "-bd", "-bso0", "-bsp0", f"-o{target}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=EXTRACT_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise MangaError("extractor_timeout", "That CBR archive took too long to extract.") from None
    except OSError:
        raise MangaError("extractor_failed", "The CBR extractor could not be started.") from None
    if result.returncode != 0:
        raise MangaError("extract_failed", "That CBR archive could not be extracted.")
    pages = []
    for name in names:
        page = safe_join(target, name)
        if page.is_symlink() or not page.is_file():
            raise MangaError("unsafe_archive", "The archive extraction produced an unsafe page.")
        pages.append(page)
    return pages


def extract_archive(archive):
    suffix = archive.suffix.lower()
    target = cache_root(create=True) / archive_key(archive)
    existing = manifest_pages(target)
    if existing is not None:
        return existing
    temp = Path(tempfile.mkdtemp(prefix=".tmp-", dir=str(cache_root(create=True))))
    try:
        if suffix == ".cbz":
            pages = extract_zip(archive, temp)
        elif suffix == ".cbr":
            pages = extract_cbr(archive, temp)
        else:
            raise MangaError("unsupported_file", "Choose a CBZ or CBR archive.")
        if not pages:
            raise MangaError("no_pages", "That archive contains no supported images.")
        names = [str(page.relative_to(temp)) for page in pages]
        (temp / "manifest.json").write_text(
            json.dumps({"version": CACHE_VERSION, "pages": names}, ensure_ascii=False),
            encoding="utf-8",
        )
        remove_cache_dir(target)
        os.replace(temp, target)
        temp = None
        return [target / name for name in names]
    finally:
        if temp is not None:
            remove_cache_dir(temp)


def folder_chapters(folder):
    chapters = []
    warnings = []
    direct = image_files(folder)
    if direct:
        chapters.append(chapter_from_pages(folder.name, direct))
    try:
        children = sorted(folder.iterdir(), key=lambda item: natural_key(item.name))
    except OSError:
        raise MangaError("inaccessible", "That manga folder cannot be read.") from None
    for child in children:
        if len(chapters) >= MAX_CHAPTERS:
            break
        if child.name.startswith(".") or child.is_symlink():
            continue
        if child.is_dir():
            pages = image_files(child)
            if pages:
                chapters.append(chapter_from_pages(child.name, pages))
        elif child.is_file() and child.suffix.lower() in ARCHIVE_EXTENSIONS:
            try:
                pages = extract_archive(child)
            except MangaError as error:
                warnings.append(child.name + ": " + error.message)
                continue
            chapters.append(chapter_from_pages(child.stem, pages))
    if not chapters:
        raise MangaError("no_pages", "That folder contains no supported images or manga archives.")
    total = sum(chapter["pageCount"] for chapter in chapters)
    if total > MAX_PAGES:
        raise MangaError("too_many_pages", "That collection contains too many pages.")
    return chapters, warnings


def collection_payload(path):
    path = safe_input_path(path)
    if path.is_dir():
        chapters, warnings = folder_chapters(path)
        title = path.name
        fmt = "Folder"
    else:
        pages = extract_archive(path)
        chapters = [chapter_from_pages(path.stem, pages)]
        title = path.stem
        fmt = ARCHIVE_EXTENSIONS[path.suffix.lower()]
        warnings = []
    total = sum(chapter["pageCount"] for chapter in chapters)
    if total > MAX_PAGES:
        raise MangaError("too_many_pages", "That collection contains too many pages.")
    collection = {
        "id": "local-" + hashlib.sha256(str(path).encode()).hexdigest()[:16],
        "title": clean_text(title, 160) or "Local collection",
        "path": str(path),
        "format": fmt,
        "chapters": chapters,
        "chapterCount": len(chapters),
        "pageCount": total,
        "warnings": warnings,
    }
    return collection


def status_payload():
    extractor = seven_zip()
    return {
        "ok": True,
        "cbrSupported": bool(extractor),
        "cbrExtractor": extractor,
        "cbzSupported": True,
        "folderSupported": True,
        "guidance": "" if extractor else "CBR support needs 7z; install it separately. CBZ and image folders still work.",
    }


def cleanup_payload(value):
    path = safe_input_path(value)
    removed = False
    if path.is_file() and path.suffix.lower() in ARCHIVE_EXTENSIONS:
        target = cache_root(create=False) / archive_key(path)
        if target.exists():
            remove_cache_dir(target)
            removed = True
    elif path.is_dir():
        try:
            children = list(path.iterdir())
        except OSError:
            children = []
        for child in children:
            if child.is_file() and child.suffix.lower() in ARCHIVE_EXTENSIONS:
                target = cache_root(create=False) / archive_key(child)
                if target.exists():
                    remove_cache_dir(target)
                    removed = True
    return {"ok": True, "removed": removed}


def emit(payload, code=0):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return code


def main(argv=None):
    parser = argparse.ArgumentParser(description="GPS Media Hub local manga collections")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    opened = sub.add_parser("open")
    opened.add_argument("--path", required=True)
    cleaned = sub.add_parser("cleanup")
    cleaned.add_argument("--path", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "status":
            return emit(status_payload())
        if args.command == "open":
            return emit({"ok": True, "collection": collection_payload(args.path)})
        if args.command == "cleanup":
            return emit(cleanup_payload(args.path))
    except MangaError as error:
        return emit({"ok": False, "code": error.code, "message": error.message}, 1)
    except Exception:
        return emit({
            "ok": False,
            "code": "internal_error",
            "message": "The manga helper could not complete that request.",
        }, 1)
    return emit({"ok": False, "code": "invalid_request", "message": "Unknown command."}, 1)


if __name__ == "__main__":
    raise SystemExit(main())
