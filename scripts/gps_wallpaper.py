#!/usr/bin/env python3
"""Unified GPS Wallpaper Controller (Static awww + Live mpvpaper)."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import socket
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


def get_watcher_pid_file_path() -> Path:
    return get_runtime_dir() / "wallpaper-watcher.pid"


def get_watcher_lock_file_path() -> Path:
    return get_runtime_dir() / "wallpaper-watcher.lock"


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


def stop_live_wallpaper(timeout: float = 1.5, stop_watcher: bool = False) -> bool:
    """Safely terminate any running mpvpaper processes owned by current user."""
    if stop_watcher:
        stop_watcher_daemon(timeout=timeout)

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


def is_ac_connected() -> bool:
    """Check if external AC power is currently connected.

    Conservatively returns False if power state is unavailable or unknown.
    """
    # 1. Inspect sysfs power_supply devices
    try:
        power_supply_dir = Path("/sys/class/power_supply")
        if power_supply_dir.is_dir():
            ac_found = False
            for dev_path in power_supply_dir.iterdir():
                type_file = dev_path / "type"
                online_file = dev_path / "online"
                if type_file.is_file():
                    try:
                        dev_type = type_file.read_text(encoding="utf-8").strip().lower()
                    except Exception:
                        continue
                    if dev_type in {"mains", "usb", "ac"}:
                        ac_found = True
                        if online_file.is_file():
                            try:
                                if online_file.read_text(encoding="utf-8").strip() == "1":
                                    return True
                            except Exception:
                                pass
            if ac_found:
                # AC adapters were found in sysfs and none reported online == 1
                return False
    except Exception:
        pass

    # 2. Inspect UPower via D-Bus / gdbus
    if shutil.which("gdbus"):
        try:
            res = subprocess.run(
                [
                    "gdbus", "call", "--system", "--dest", "org.freedesktop.UPower",
                    "--object-path", "/org/freedesktop/UPower",
                    "--method", "org.freedesktop.DBus.Properties.Get",
                    "org.freedesktop.UPower", "OnBattery"
                ],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            if res.returncode == 0:
                out = res.stdout.strip()
                if "<false>" in out:
                    return True
                elif "<true>" in out:
                    return False
        except Exception:
            pass

    # 3. Inspect UPower via upower CLI
    if shutil.which("upower"):
        try:
            res = subprocess.run(["upower", "-d"], capture_output=True, text=True, timeout=1.0)
            if res.returncode == 0:
                for line in res.stdout.splitlines():
                    line_s = line.strip().lower()
                    if line_s.startswith("on-battery:"):
                        if "no" in line_s:
                            return True
                        elif "yes" in line_s:
                            return False
        except Exception:
            pass

    return False


def get_visible_application_window_count() -> int:
    """Count normal (tiled or floating) application windows visible on active workspaces across all monitors."""
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return 0
    if not shutil.which("hyprctl"):
        return 0

    try:
        # 1. Fetch monitor workspace configuration
        mons_raw = subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, stderr=subprocess.DEVNULL)
        monitors = json.loads(mons_raw)
        if not isinstance(monitors, list):
            return 0

        active_ws_ids = set()
        active_special_names = set()
        for m in monitors:
            if not isinstance(m, dict):
                continue
            ws = m.get("activeWorkspace") or {}
            ws_id = ws.get("id")
            if ws_id is not None:
                active_ws_ids.add(ws_id)
            special = m.get("specialWorkspace") or {}
            special_name = special.get("name")
            if special_name:
                active_special_names.add(special_name)

        # 2. Fetch clients
        clients_raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True, stderr=subprocess.DEVNULL)
        clients = json.loads(clients_raw)
        if not isinstance(clients, list):
            return 0

        visible_count = 0
        for c in clients:
            if not isinstance(c, dict):
                continue
            # Ignored if unmapped or hidden
            if not c.get("mapped", True) or c.get("hidden", False):
                continue

            c_ws = c.get("workspace") or {}
            c_ws_id = c_ws.get("id")
            c_ws_name = c_ws.get("name", "")

            # If client is pinned, it appears on all workspaces
            if c.get("pinned", False):
                visible_count += 1
                continue

            # Otherwise check active normal or active special workspace
            if (c_ws_id is not None and c_ws_id in active_ws_ids) or (c_ws_name and c_ws_name in active_special_names):
                visible_count += 1

        return visible_count
    except Exception:
        # Conservative fallback if hyprctl fails during session
        return 1


def get_running_watcher_pid() -> int | None:
    """Inspect and return verified PID of running wallpaper watcher daemon."""
    pid_file = get_watcher_pid_file_path()
    candidate_pid: int | None = None
    if pid_file.is_file():
        try:
            candidate_pid = int(pid_file.read_text(encoding="utf-8").strip())
        except (ValueError, OSError):
            candidate_pid = None

    if candidate_pid is not None:
        proc_dir = Path(f"/proc/{candidate_pid}")
        if proc_dir.is_dir():
            try:
                if proc_dir.stat().st_uid == os.getuid():
                    cmdline = (proc_dir / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
                    if ("gps_wallpaper" in cmdline or "gps-wallpaper" in cmdline) and "watch" in cmdline:
                        return candidate_pid
            except (OSError, PermissionError):
                pass

    # Fallback: scan /proc for watcher owned by current user
    my_uid = os.getuid()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != my_uid:
                continue
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
            if ("gps_wallpaper" in cmdline or "gps-wallpaper" in cmdline) and "watch" in cmdline:
                pid = int(entry.name)
                if pid != os.getpid():
                    return pid
        except (OSError, PermissionError, ValueError):
            continue

    return None


def stop_watcher_daemon(timeout: float = 1.5) -> bool:
    """Safely terminate wallpaper watcher daemon owned by current user."""
    pid_file = get_watcher_pid_file_path()
    pid = get_running_watcher_pid()

    if pid is None:
        if pid_file.is_file():
            try:
                pid_file.unlink()
            except OSError:
                pass
        return True

    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass

    deadline = time.time() + timeout
    while time.time() < deadline:
        if not Path(f"/proc/{pid}").is_dir():
            break
        time.sleep(0.05)

    if Path(f"/proc/{pid}").is_dir():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    if pid_file.is_file():
        try:
            pid_file.unlink()
        except OSError:
            pass

    return True


def start_watcher_daemon() -> bool:
    """Launch wallpaper watcher daemon in background if not already running."""
    if get_running_watcher_pid() is not None:
        return True

    log_dir = get_runtime_dir()
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "wallpaper-watcher.log"

    cmd = [sys.executable, str(Path(__file__).resolve()), "watch"]
    try:
        with open(log_file, "a") as f:
            proc = subprocess.Popen(
                cmd,
                stdout=f,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        time.sleep(0.1)
        if proc.poll() is not None:
            return False
        return True
    except Exception:
        return False


def evaluate_playback_policy(state: dict[str, Any] | None = None) -> dict[str, Any]:
    """Evaluate power and window state and transition wallpaper playback accordingly.

    Condition:
      live_enabled = (ac_power_connected is True) and (visible_application_window_count == 0)

    If live_enabled:
      Clear static background and launch mpvpaper if not already running.
      Status: 'LIVE PLAYING'
    Else:
      Stop mpvpaper if running and display last valid static wallpaper (or video poster).
      Status: 'PAUSED: BATTERY POWER' or 'PAUSED: APPLICATION OPEN'
    """
    state_file = get_state_file_path()
    if state is None:
        if state_file.is_file():
            try:
                state = json.loads(state_file.read_text(encoding="utf-8"))
            except Exception:
                state = {}
        else:
            state = {}

    target_type = state.get("type", "static")
    if target_type != "video":
        # Manual static wallpaper selected; policy does not apply live playback
        stop_live_wallpaper()
        return {
            "ok": True,
            "type": "static",
            "status": "STATIC",
            "live_enabled": False,
        }

    v_path_str = state.get("path")
    if not v_path_str:
        return {"ok": False, "error": "No video wallpaper path in state", "status": "ERROR"}

    v_path = Path(v_path_str).expanduser().resolve()
    if not v_path.is_file():
        # Video file was deleted or moved while paused
        stop_live_wallpaper()
        fallback = get_last_valid_static_wallpaper()
        if not fallback or not fallback.is_file():
            poster = state.get("poster")
            if poster and Path(poster).is_file():
                fallback = Path(poster)
        if fallback and fallback.is_file():
            apply_static_wallpaper(fallback, is_fallback=True)
        state["status"] = "ERROR: VIDEO MISSING"
        state["live_enabled"] = False
        atomic_write(state_file, json.dumps(state, indent=2) + "\n")
        return {
            "ok": False,
            "error": f"Live video file not found: {v_path}",
            "status": "ERROR: VIDEO MISSING",
            "live_enabled": False,
        }

    # Evaluate conditions
    ac_conn = is_ac_connected()
    win_count = get_visible_application_window_count()
    live_enabled = (ac_conn is True) and (win_count == 0)

    if live_enabled:
        status_str = "LIVE PLAYING"
        reason = "none"
    elif not ac_conn:
        status_str = "PAUSED: BATTERY POWER"
        reason = "battery"
    else:
        status_str = "PAUSED: APPLICATION OPEN"
        reason = "windows"

    running_pids = get_running_mpvpaper_pids()
    is_live_running = len(running_pids) > 0

    if live_enabled:
        if not is_live_running:
            # Transition to PLAYING
            clear_static_wallpaper()
            launch_res = apply_live_wallpaper(
                v_path,
                output=state.get("output", "ALL"),
                auto_mode=state.get("auto_mode", "FULL"),
                hwdec=state.get("hwdec", "auto"),
                fit_mode=state.get("fit_mode", "cover"),
                start_watcher=False,
                policy_transition=True,
            )
            if not launch_res.get("ok"):
                fallback = get_last_valid_static_wallpaper()
                if fallback and fallback.is_file():
                    apply_static_wallpaper(fallback, is_fallback=True)
                return {
                    "ok": False,
                    "error": launch_res.get("error"),
                    "status": "ERROR: BACKEND FAILED",
                    "live_enabled": False,
                }
    else:
        # live_enabled is False
        if is_live_running:
            # Transition to PAUSED
            stop_live_wallpaper(stop_watcher=False)
            fallback = get_last_valid_static_wallpaper()
            if not fallback or not fallback.is_file():
                poster = state.get("poster")
                if poster and Path(poster).is_file():
                    fallback = Path(poster)
                else:
                    fallback = extract_poster_frame(v_path)
            if fallback and fallback.is_file():
                set_wallpaper.apply_wallpaper(image_path=fallback, transition_type="none")

    # Update state
    state["status"] = status_str
    state["paused_reason"] = reason
    state["ac_connected"] = ac_conn
    state["visible_windows"] = win_count
    state["live_enabled"] = live_enabled
    atomic_write(state_file, json.dumps(state, indent=2) + "\n")

    return {
        "ok": True,
        "type": "video",
        "path": str(v_path),
        "status": status_str,
        "paused_reason": reason,
        "ac_connected": ac_conn,
        "visible_windows": win_count,
        "live_enabled": live_enabled,
    }


def run_watcher() -> None:
    """Foreground event-driven watcher loop for power and window awareness."""
    # Ensure single instance via file lock
    lock_file = get_watcher_lock_file_path()
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock_fd = open(lock_file, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (BlockingIOError, OSError):
        return

    pid_file = get_watcher_pid_file_path()
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(pid_file, f"{os.getpid()}\n")

    running = True

    def _sig_handler(signum: int, frame: Any) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, _sig_handler)
    signal.signal(signal.SIGINT, _sig_handler)

    # Initial policy evaluation
    evaluate_playback_policy()

    # Setup upower monitor process if available
    upower_proc = None
    if shutil.which("upower"):
        try:
            upower_proc = subprocess.Popen(
                ["upower", "--monitor"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except Exception:
            upower_proc = None

    def _connect_socket() -> socket.socket | None:
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        if not sig or not runtime:
            return None
        sock_p = Path(runtime) / "hypr" / sig / ".socket2.sock"
        if not sock_p.is_socket():
            return None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(str(sock_p))
            s.setblocking(False)
            return s
        except Exception:
            return None

    sock = _connect_socket()

    try:
        while running:
            if sock is None:
                sock = _connect_socket()

            r_fds = []
            if sock:
                r_fds.append(sock)
            if upower_proc and upower_proc.stdout:
                r_fds.append(upower_proc.stdout)

            try:
                readable, _, _ = select.select(r_fds, [], [], 5.0)
            except (InterruptedError, select.error):
                if not running:
                    break
                continue

            has_event = False
            if sock and sock in readable:
                try:
                    data = sock.recv(4096)
                    if not data:
                        try:
                            sock.close()
                        except Exception:
                            pass
                        sock = None
                    else:
                        has_event = True
                except Exception:
                    sock = None

            if upower_proc and upower_proc.stdout and (upower_proc.stdout in readable):
                try:
                    line = upower_proc.stdout.readline()
                    if line:
                        has_event = True
                except Exception:
                    pass

            if has_event:
                time.sleep(0.2)
                if sock:
                    try:
                        while True:
                            d = sock.recv(4096)
                            if not d:
                                break
                    except (BlockingIOError, OSError):
                        pass

            evaluate_playback_policy()

    finally:
        if upower_proc:
            try:
                upower_proc.terminate()
                upower_proc.wait(timeout=1.0)
            except Exception:
                pass
        if sock:
            try:
                sock.close()
            except Exception:
                pass
        if pid_file.is_file():
            try:
                pid_file.unlink()
            except OSError:
                pass
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            lock_fd.close()
        except Exception:
            pass


def apply_live_wallpaper(
    video_path: Path | str,
    output: str = "ALL",
    auto_mode: str = "FULL",
    hwdec: str = "auto",
    fit_mode: str = "cover",
    mpv_options: str | None = None,
    start_watcher: bool = True,
    policy_transition: bool = False,
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
        "status": "LIVE PLAYING",
        "paused_reason": "none",
        "live_enabled": True,
        "timestamp": time.time(),
    }
    atomic_write(get_state_file_path(), json.dumps(state, indent=2) + "\n")
    atomic_write(get_last_video_path(), str(v_path) + "\n")
    atomic_write(get_last_wall_path(), str(poster_path) + "\n")

    # Extract & propagate theme using the poster frame
    theme_res = set_wallpaper.apply_wallpaper(image_path=poster_path, skip_awww=True)

    if start_watcher:
        start_watcher_daemon()

    return {
        "ok": True,
        "type": "video",
        "path": str(v_path),
        "poster": str(poster_path),
        "pid": proc.pid,
        "status": "LIVE PLAYING",
        "theme": theme_res.get("theme"),
    }


def apply_static_wallpaper(
    image_path: Path | str,
    transition_type: str = "outer",
    transition_pos: str = "0.92,0.06",
    transition_fps: int = 165,
    transition_duration: float = 1.1,
    is_fallback: bool = False,
    **kwargs: Any,
) -> dict[str, Any]:
    """Stop any active video player and apply static wallpaper via awww."""
    img_path = Path(image_path).expanduser().resolve()
    if not img_path.is_file():
        return {"ok": False, "error": f"Static wallpaper not found: {img_path}"}

    # 1. Stop live video wallpaper (and stop watcher if this is manual static selection)
    stop_live_wallpaper(stop_watcher=not is_fallback)

    # 2. Record static state only if not a temporary policy fallback!
    if not is_fallback:
        state = {
            "type": "static",
            "path": str(img_path),
            "status": "STATIC",
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
        res = apply_live_wallpaper(target, **kwargs)
        if not res.get("ok"):
            return res
        policy_res = evaluate_playback_policy()
        if policy_res.get("ok"):
            res.update(policy_res)
        return res
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
            start_watcher_daemon()
            return evaluate_playback_policy(saved_state)
        # If video file was moved/deleted or mpvpaper failed, fall back to static
        fallback_static = get_last_valid_static_wallpaper()
        if fallback_static:
            return apply_static_wallpaper(fallback_static)

    # If state recorded static
    if wall_path_str:
        s_path = Path(wall_path_str)
        if s_path.is_file():
            stop_watcher_daemon()
            return apply_static_wallpaper(s_path, transition_type="none")

    # Fallback: check gps-last-wall.txt
    last_wall = get_last_wall_path()
    if last_wall.is_file():
        try:
            candidate = Path(last_wall.read_text(encoding="utf-8").strip())
            if candidate.is_file():
                if is_video_file(candidate):
                    start_watcher_daemon()
                    return evaluate_playback_policy({"type": "video", "path": str(candidate)})
                stop_watcher_daemon()
                return apply_static_wallpaper(candidate, transition_type="none")
        except Exception:
            pass

    fallback_static = get_last_valid_static_wallpaper()
    if fallback_static:
        stop_watcher_daemon()
        return apply_static_wallpaper(fallback_static, transition_type="none")

    return {"ok": False, "error": "No valid wallpaper found to restore"}


def inspect_wallpaper() -> dict[str, Any]:
    """Inspect current wallpaper, live backend state, power status, and window count."""
    state_file = get_state_file_path()
    state: dict[str, Any] = {}
    if state_file.is_file():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    running_pids = get_running_mpvpaper_pids()
    is_live_running = len(running_pids) > 0
    watcher_pid = get_running_watcher_pid()

    recorded_type = state.get("type", "static")
    ac_conn = is_ac_connected()
    win_count = get_visible_application_window_count()
    live_enabled = (ac_conn is True) and (win_count == 0)

    status = state.get("status")
    if not status:
        if recorded_type == "static":
            status = "STATIC"
        elif is_live_running:
            status = "LIVE PLAYING"
        elif not ac_conn:
            status = "PAUSED: BATTERY POWER"
        elif win_count > 0:
            status = "PAUSED: APPLICATION OPEN"
        else:
            status = "LIVE (STOPPED)"

    return {
        "ok": True,
        "type": recorded_type,
        "path": state.get("path", set_wallpaper.get_current_wallpaper()),
        "poster": state.get("poster"),
        "fit_mode": state.get("fit_mode", "cover"),
        "status": status,
        "paused_reason": state.get("paused_reason", "none"),
        "ac_connected": ac_conn,
        "visible_windows": win_count,
        "live_enabled": live_enabled,
        "live_running": is_live_running,
        "mpvpaper_pids": running_pids,
        "watcher_running": watcher_pid is not None,
        "watcher_pid": watcher_pid,
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
    subparsers.add_parser("stop", help="Stop live wallpaper playback and watcher")

    # restore
    subparsers.add_parser("restore", help="Restore last wallpaper state with policy evaluation")

    # inspect / status
    subparsers.add_parser("inspect", help="Inspect current wallpaper status")
    subparsers.add_parser("status", help="Inspect current wallpaper status")

    # watch
    subparsers.add_parser("watch", help="Run wallpaper awareness watcher loop in foreground")

    # start-watcher
    subparsers.add_parser("start-watcher", help="Start wallpaper awareness watcher daemon in background")

    # stop-watcher
    subparsers.add_parser("stop-watcher", help="Stop wallpaper awareness watcher daemon")

    # evaluate
    subparsers.add_parser("evaluate", help="Evaluate power and window playback policy once")

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
        stop_live_wallpaper(stop_watcher=True)
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

    elif args.command == "watch":
        run_watcher()
        return 0

    elif args.command == "start-watcher":
        ok = start_watcher_daemon()
        print(f"Watcher started: {ok}")
        return 0 if ok else 1

    elif args.command == "stop-watcher":
        ok = stop_watcher_daemon()
        print(f"Watcher stopped: {ok}")
        return 0

    elif args.command == "evaluate":
        res = evaluate_playback_policy()
        print(json.dumps(res, indent=2))
        return 0 if res.get("ok") else 1

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
