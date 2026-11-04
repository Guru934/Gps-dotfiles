#!/usr/bin/env python3
"""Unified GPS Wallpaper Controller (Static awww + Live mpvpaper)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any

# Import sibling set_wallpaper module
SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import set_wallpaper

VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
STATIC_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".gif"}


def get_config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "quickshell"


def get_state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state")) / "gps"


def get_runtime_dir() -> Path:
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime and os.path.isdir(xdg_runtime):
        return Path(xdg_runtime) / "gps"
    return Path(f"/tmp/gps-{os.getuid()}")


def get_cache_dir() -> Path:
    xdg_cache = os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")
    return Path(xdg_cache) / "gps" / "wallpaper-posters"


def get_state_file_path() -> Path:
    return get_config_dir() / "gps-wallpaper-state.json"


def get_last_wall_path() -> Path:
    return get_config_dir() / "gps-last-wall.txt"


def get_last_video_path() -> Path:
    return get_config_dir() / "gps-last-video.txt"


def get_last_static_path() -> Path:
    return get_config_dir() / "gps-last-wall-static.txt"


def get_pid_file_path() -> Path:
    return get_runtime_dir() / "mpvpaper.pid"


def is_video_file(path: Path | str) -> bool:
    return Path(path).suffix.lower() in VIDEO_EXTENSIONS


def is_static_file(path: Path | str) -> bool:
    return Path(path).suffix.lower() in STATIC_EXTENSIONS


def atomic_write(target_path: Path | str, content: str) -> None:
    set_wallpaper.atomic_write(target_path, content)


def get_poster_path_for_video(video_path: Path | str, cache_dir: Path | None = None) -> Path:
    """Derive deterministic cached poster path keyed by source path, mtime, and size."""
    p = Path(video_path).expanduser().resolve()
    target_cache = cache_dir or get_cache_dir()
    target_cache.mkdir(parents=True, exist_ok=True)

    stat = p.stat()
    key_str = f"{p}:{stat.st_mtime_ns}:{stat.st_size}"
    h = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:20]
    safe_stem = "".join(c if c.isalnum() or c in "-_" else "_" for c in p.stem)[:32]
    return target_cache / f"{safe_stem}_{h}.jpg"


def extract_poster_frame(
    video_path: Path | str,
    output_path: Path | str | None = None,
    cache_dir: Path | None = None,
) -> Path | None:
    """Extract a poster frame from a video using ffmpeg, with mtime/size caching."""
    v_path = Path(video_path).expanduser().resolve()
    if not v_path.is_file():
        return None

    if output_path:
        out_p = Path(output_path).expanduser().resolve()
    else:
        out_p = get_poster_path_for_video(v_path, cache_dir=cache_dir)

    # Cache hit check: if exists and non-empty
    if out_p.is_file() and out_p.stat().st_size > 0:
        return out_p

    out_p.parent.mkdir(parents=True, exist_ok=True)
    temp_target = out_p.parent / f".tmp_{out_p.name}"

    # Try extraction at 1.0 second, fallback to 0.0s for short clips
    for seek_time in ["00:00:01", "00:00:00"]:
        cmd = [
            "ffmpeg",
            "-y",
            "-ss",
            seek_time,
            "-i",
            str(v_path),
            "-frames:v",
            "1",
            "-update",
            "1",
            "-q:v",
            "2",
            str(temp_target),
        ]
        try:
            res = subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            if res.returncode == 0 and temp_target.is_file() and temp_target.stat().st_size > 0:
                os.replace(temp_target, out_p)
                return out_p
        except (subprocess.TimeoutExpired, OSError):
            pass
        finally:
            if temp_target.is_file():
                try:
                    temp_target.unlink()
                except OSError:
                    pass

    return None


def get_running_mpvpaper_pids() -> list[int]:
    """Find all mpvpaper PIDs strictly owned by the current UID."""
    my_uid = os.getuid()
    my_pid = os.getpid()
    pids: list[int] = []

    # 1. Check PID file
    pid_file = get_pid_file_path()
    if pid_file.is_file():
        try:
            val = int(pid_file.read_text(encoding="utf-8").strip())
            if val > 0 and val != my_pid:
                pids.append(val)
        except (ValueError, OSError):
            pass

    # 2. Check /proc for user processes whose executable is mpvpaper
    proc_dir = Path("/proc")
    if proc_dir.is_dir():
        for entry in proc_dir.iterdir():
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            if pid == my_pid:
                continue
            try:
                stat = entry.stat()
                if stat.st_uid != my_uid:
                    continue
                comm_path = entry / "comm"
                if comm_path.is_file() and comm_path.read_text(encoding="utf-8", errors="ignore").strip() == "mpvpaper":
                    if pid not in pids:
                        pids.append(pid)
            except (OSError, PermissionError):
                continue

    # Filter only actually verified PIDs
    confirmed: list[int] = []
    for pid in pids:
        try:
            proc_p = Path(f"/proc/{pid}")
            if proc_p.is_dir() and proc_p.stat().st_uid == my_uid:
                comm_path = proc_p / "comm"
                if comm_path.is_file() and comm_path.read_text(encoding="utf-8", errors="ignore").strip() == "mpvpaper":
                    confirmed.append(pid)
        except (OSError, PermissionError):
            continue

    return confirmed


def stop_live_wallpaper(timeout: float = 1.5) -> bool:
    """Safely terminate any running mpvpaper processes owned by current user."""
    pid_file = get_pid_file_path()
    pids = get_running_mpvpaper_pids()

    if not pids:
        if pid_file.is_file():
            try:
                pid_file.unlink()
            except OSError:
                pass
        return True

    # Send SIGTERM
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass

    # Wait gracefully
    deadline = time.time() + timeout
    while time.time() < deadline:
        alive = [p for p in pids if Path(f"/proc/{p}").is_dir()]
        if not alive:
            break
        time.sleep(0.05)

    # Fallback to SIGKILL for any stubborn process
    for pid in pids:
        try:
            proc_p = Path(f"/proc/{pid}")
            if proc_p.is_dir() and proc_p.stat().st_uid == os.getuid():
                os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    if pid_file.is_file():
        try:
            pid_file.unlink()
        except OSError:
            pass

    return True


def get_connected_monitors() -> list[dict[str, Any]]:
    """Query Hyprland for active connected monitors and their geometry."""
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            out = subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, stderr=subprocess.DEVNULL)
            data = json.loads(out)
            if isinstance(data, list):
                return [
                    {
                        "name": m.get("name"),
                        "width": m.get("width"),
                        "height": m.get("height"),
                        "refreshRate": m.get("refreshRate"),
                        "scale": m.get("scale"),
                    }
                    for m in data
                    if isinstance(m, dict) and m.get("name")
                ]
        except Exception:
            pass
    return []


def clear_static_wallpaper() -> bool:
    """Clear awww background buffer to solid black so no static wallpaper shines through."""
    if shutil.which("awww") is None:
        return False
    try:
        res = subprocess.run(
            ["awww", "clear", "000000ff"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        return res.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def apply_live_wallpaper(
    video_path: Path | str,
    output: str = "ALL",
    auto_mode: str = "FULL",
    hwdec: str = "auto",
    fit_mode: str = "cover",
    mpv_options: str | None = None,
    **kwargs: Any,
) -> dict[str, Any]:
    """Launch mpvpaper with verified parameters and lifecycle management."""
    v_path = Path(video_path).expanduser().resolve()
    if not v_path.is_file():
        return {"ok": False, "error": f"Video wallpaper not found: {v_path}"}

    if shutil.which("mpvpaper") is None:
        return {"ok": False, "error": "mpvpaper is not installed"}

    # Extract poster frame for theme extraction and state tracking
    poster_path = extract_poster_frame(v_path)
    if not poster_path or not poster_path.is_file():
        return {"ok": False, "error": f"Failed to extract poster frame for video: {v_path}"}

    # 1. Preserve current static wallpaper path before clearing awww
    current_wall = set_wallpaper.get_current_wallpaper()
    if current_wall and is_static_file(current_wall) and Path(current_wall).is_file():
        try:
            atomic_write(get_last_static_path(), str(Path(current_wall).resolve()) + "\n")
        except Exception:
            pass

    # 2. Clear awww background layer to solid black so no static wallpaper shows through
    clear_static_wallpaper()

    # 3. Stop any currently active mpvpaper processes to prevent duplicates
    stop_live_wallpaper()

    # 4. Configure aspect-ratio fit mode:
    # 'cover' (default) scales to completely cover the screen without letterboxing.
    # 'contain' fits inside screen with letterbox bars.
    panscan_val = "1.0" if fit_mode == "cover" else "0.0"
    base_mpv_opts = mpv_options or f"no-audio --loop-playlist=inf --panscan={panscan_val} --video-unscaled=no --background-color='#000000'"
    combined_mpv_opts = f"{base_mpv_opts} --hwdec={hwdec}"

    # 5. Assemble command
    cmd = [
        "mpvpaper",
        "-p",  # auto-pause when hidden
        "-a",
        auto_mode,  # extend auto-pause to fullscreen
        "-o",
        combined_mpv_opts,
        output,
        str(v_path),
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception as e:
        return {"ok": False, "error": f"Failed to spawn mpvpaper: {e}"}

    # Verify process didn't terminate immediately
    time.sleep(0.1)
    if proc.poll() is not None:
        return {"ok": False, "error": f"mpvpaper exited immediately with returncode {proc.returncode}"}

    # Save runtime PID
    pid_file = get_pid_file_path()
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        atomic_write(pid_file, f"{proc.pid}\n")
    except Exception:
        pass

    # Save state
    state = {
        "type": "video",
        "path": str(v_path),
        "poster": str(poster_path),
        "output": output,
        "auto_mode": auto_mode,
        "hwdec": hwdec,
        "fit_mode": fit_mode,
        "pid": proc.pid,
        "timestamp": time.time(),
    }
    atomic_write(get_state_file_path(), json.dumps(state, indent=2) + "\n")
    atomic_write(get_last_video_path(), str(v_path) + "\n")
    atomic_write(get_last_wall_path(), str(poster_path) + "\n")

    # Extract & propagate theme using the poster frame
    theme_res = set_wallpaper.apply_wallpaper(image_path=poster_path, skip_awww=True)

    return {
        "ok": True,
        "type": "video",
        "path": str(v_path),
        "poster": str(poster_path),
        "pid": proc.pid,
        "theme": theme_res.get("theme"),
    }


def apply_static_wallpaper(
    image_path: Path | str,
    transition_type: str = "outer",
    transition_pos: str = "0.92,0.06",
    transition_fps: int = 165,
    transition_duration: float = 1.1,
    **kwargs: Any,
) -> dict[str, Any]:
    """Stop any active video player and apply static wallpaper via awww."""
    img_path = Path(image_path).expanduser().resolve()
    if not img_path.is_file():
        return {"ok": False, "error": f"Static wallpaper not found: {img_path}"}

    # 1. Stop live video wallpaper
    stop_live_wallpaper()

    # 2. Record static state
    state = {
        "type": "static",
        "path": str(img_path),
        "timestamp": time.time(),
    }
    atomic_write(get_state_file_path(), json.dumps(state, indent=2) + "\n")
    atomic_write(get_last_static_path(), str(img_path) + "\n")

    # 3. Apply via awww pipeline
    res = set_wallpaper.apply_wallpaper(
        image_path=img_path,
        transition_type=transition_type,
        transition_pos=transition_pos,
        transition_fps=transition_fps,
        transition_duration=transition_duration,
    )
    if res.get("ok") and "path" not in res:
        res["path"] = res.get("wallpaper", str(img_path))
    return res


def apply_wallpaper(path: Path | str, **kwargs: Any) -> dict[str, Any]:
    """Auto-detect path type and delegate to video or static pipeline."""
    target = Path(path).expanduser().resolve()
    if not target.is_file():
        return {"ok": False, "error": f"Wallpaper file not found: {target}"}

    if is_video_file(target):
        return apply_live_wallpaper(target, **kwargs)
    else:
        return apply_static_wallpaper(target, **kwargs)


def get_last_valid_static_wallpaper() -> Path | None:
    """Retrieve last known valid static wallpaper path, with fallback to wallpaper dir."""
    last_static = get_last_static_path()
    if last_static.is_file():
        try:
            p = Path(last_static.read_text(encoding="utf-8").strip())
            if p.is_file() and is_static_file(p):
                return p
        except Exception:
            pass

    # Check gps-last-wall.txt
    last_wall = get_last_wall_path()
    if last_wall.is_file():
        try:
            p = Path(last_wall.read_text(encoding="utf-8").strip())
            if p.is_file() and is_static_file(p):
                return p
        except Exception:
            pass

    # Fallback to first static image in ~/Pictures/Wallpapers
    wall_dir = Path.home() / "Pictures" / "Wallpapers"
    if wall_dir.is_dir():
        for f in sorted(wall_dir.iterdir()):
            if f.is_file() and is_static_file(f):
                return f

    return None


def restore_wallpaper() -> dict[str, Any]:
    """Restore previous wallpaper state across restarts with robust fallback."""
    state_file = get_state_file_path()
    saved_state: dict[str, Any] = {}

    if state_file.is_file():
        try:
            saved_state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            saved_state = {}

    wall_type = saved_state.get("type")
    wall_path_str = saved_state.get("path")

    # If state recorded video
    if wall_type == "video" and wall_path_str:
        v_path = Path(wall_path_str)
        if v_path.is_file():
            res = apply_live_wallpaper(v_path)
            if res.get("ok"):
                return res
        # If video file was moved/deleted or mpvpaper failed, fall back to static
        fallback_static = get_last_valid_static_wallpaper()
        if fallback_static:
            return apply_static_wallpaper(fallback_static)

    # If state recorded static
    if wall_path_str:
        s_path = Path(wall_path_str)
        if s_path.is_file():
            return apply_static_wallpaper(s_path, transition_type="none")

    # Fallback: check gps-last-wall.txt
    last_wall = get_last_wall_path()
    if last_wall.is_file():
        try:
            candidate = Path(last_wall.read_text(encoding="utf-8").strip())
            if candidate.is_file():
                if is_video_file(candidate):
                    return apply_live_wallpaper(candidate)
                return apply_static_wallpaper(candidate, transition_type="none")
        except Exception:
            pass

    fallback_static = get_last_valid_static_wallpaper()
    if fallback_static:
        return apply_static_wallpaper(fallback_static, transition_type="none")

    return {"ok": False, "error": "No valid wallpaper found to restore"}


def inspect_wallpaper() -> dict[str, Any]:
    """Inspect the current wallpaper and running backend state."""
    state_file = get_state_file_path()
    state: dict[str, Any] = {}
    if state_file.is_file():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    running_pids = get_running_mpvpaper_pids()
    is_live_running = len(running_pids) > 0

    recorded_type = state.get("type", "static")
    active_type = "video" if is_live_running else ("static" if recorded_type == "static" else "video (stopped)")

    return {
        "ok": True,
        "type": active_type,
        "path": state.get("path", set_wallpaper.get_current_wallpaper()),
        "poster": state.get("poster"),
        "fit_mode": state.get("fit_mode", "cover"),
        "live_running": is_live_running,
        "mpvpaper_pids": running_pids,
        "monitors": get_connected_monitors(),
    }


def sync_posters(directory: Path | str | None = None) -> dict[str, str]:
    """Batch extract and cache poster thumbnails for all video files in directory."""
    target_dir = Path(directory).expanduser().resolve() if directory else (Path.home() / "Pictures" / "Wallpapers")
    result: dict[str, str] = {}
    if not target_dir.is_dir():
        return result

    for entry in sorted(target_dir.iterdir()):
        if entry.is_file() and is_video_file(entry):
            poster = extract_poster_frame(entry)
            if poster:
                result[str(entry)] = f"file://{poster.resolve()}"

    # Also persist a lookup map in the cache directory
    cache_meta = get_cache_dir() / "posters.json"
    try:
        atomic_write(cache_meta, json.dumps(result, indent=2) + "\n")
    except Exception:
        pass

    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="GPS Wallpaper Controller (awww static & mpvpaper live)")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # apply
    apply_p = subparsers.add_parser("apply", help="Apply a wallpaper (auto-detects video or static)")
    apply_p.add_argument("path", help="Path to wallpaper file")
    apply_p.add_argument("--output", default="ALL", help="Target display output for live wallpaper (default: ALL)")
    apply_p.add_argument("--auto-mode", default="FULL", help="Auto pause mode (default: FULL)")
    apply_p.add_argument("--fit", choices=["cover", "contain"], default="cover", help="Video fit mode: cover (default) or contain")

    # stop
    subparsers.add_parser("stop", help="Stop live wallpaper playback")

    # restore
    subparsers.add_parser("restore", help="Restore last wallpaper state")

    # inspect / status
    subparsers.add_parser("inspect", help="Inspect current wallpaper status")
    subparsers.add_parser("status", help="Inspect current wallpaper status")

    # sync-posters
    sync_p = subparsers.add_parser("sync-posters", help="Generate poster thumbnails for video files in directory")
    sync_p.add_argument("directory", nargs="?", default=None, help="Directory containing wallpapers")

    # get-poster
    thumb_p = subparsers.add_parser("get-poster", help="Generate or retrieve poster frame for a single video")
    thumb_p.add_argument("path", help="Path to video file")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    # If invoked with single positional path without subcommand
    if not args.command:
        # Check if sys.argv has a path as first argument
        raw_args = argv if argv is not None else sys.argv[1:]
        if raw_args and not raw_args[0].startswith("-"):
            res = apply_wallpaper(raw_args[0])
            if not res.get("ok"):
                print(f"Error: {res.get('error')}", file=sys.stderr)
                return 1
            print(f"Applied wallpaper: {res.get('path', raw_args[0])}")
            return 0
        parser.print_help()
        return 1

    if args.command == "apply":
        res = apply_wallpaper(args.path, output=args.output, auto_mode=args.auto_mode, fit_mode=args.fit)
        if not res.get("ok"):
            print(f"Error: {res.get('error')}", file=sys.stderr)
            return 1
        print(f"Applied wallpaper: {res.get('path', args.path)}")
        return 0

    elif args.command == "stop":
        stop_live_wallpaper()
        print("Live wallpaper stopped")
        return 0

    elif args.command == "restore":
        res = restore_wallpaper()
        if not res.get("ok"):
            print(f"Error: {res.get('error')}", file=sys.stderr)
            return 1
        print(f"Restored wallpaper: {res.get('path')}")
        return 0

    elif args.command in ("inspect", "status"):
        res = inspect_wallpaper()
        print(json.dumps(res, indent=2))
        return 0

    elif args.command == "sync-posters":
        res = sync_posters(args.directory)
        print(json.dumps(res, indent=2))
        return 0

    elif args.command == "get-poster":
        poster = extract_poster_frame(args.path)
        if not poster:
            print(f"Error: Failed to extract poster for {args.path}", file=sys.stderr)
            return 1
        print(str(poster.resolve()))
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
