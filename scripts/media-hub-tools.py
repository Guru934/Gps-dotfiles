#!/usr/bin/env python3
"""Narrow external-tool bridge for the GPS Media Hub.

The helper only detects optional playback tools, validates a user-selected
local video and returns an argv array. It never starts a process, never uses a
shell and never accepts a title as an implicit ani-cli argument. Interactive
terminal hand-off stays in QML so the terminal remains attached to its menu.
"""

import argparse
import json
import os
import shutil
import sys
import urllib.parse
from pathlib import Path


MAX_PATH = 4096
VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".ts", ".m2ts",
    ".ogv", ".flv", ".wmv",
}
PLAYERS = (
    ("mpv", "MPV"),
    ("ffplay", "FFplay"),
    ("vlc", "VLC"),
    ("celluloid", "Celluloid"),
    ("haruna", "Haruna"),
    ("mplayer", "MPlayer"),
)
TERMINALS = (
    ("kitty", "Kitty"),
    ("alacritty", "Alacritty"),
    ("foot", "Foot"),
    ("wezterm", "WezTerm"),
    ("konsole", "Konsole"),
    ("xterm", "Xterm"),
    ("gnome-terminal", "GNOME Terminal"),
)
INSTALL_GUIDANCE = {
    "ani-cli": "Install ani-cli separately and ensure it is on PATH. GPS does not install or update it.",
    "terminal": "Install a supported terminal emulator such as kitty, alacritty or foot.",
    "player": "Install MPV or another supported local video player, then retry.",
    "yt-dlp": "Install yt-dlp separately and ensure it is on PATH.",
    "ffmpeg": "Install FFmpeg separately for audio extraction and muxing.",
}


class ToolError(Exception):
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


def tool_list(specs):
    found = []
    for command, label in specs:
        path = executable(command)
        if path:
            found.append({"id": command, "label": label, "path": path})
    return found


def safe_local_path(value):
    if not isinstance(value, str):
        raise ToolError("invalid_path", "A local file path is required.")
    raw = value.strip()
    if not raw or len(raw) > MAX_PATH:
        raise ToolError("invalid_path", "That local file path is not valid.")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in raw):
        raise ToolError("invalid_path", "That local file path contains control characters.")
    if raw.lower().startswith("file://"):
        parsed = urllib.parse.urlsplit(raw)
        if parsed.scheme.lower() != "file" or parsed.netloc not in ("", "localhost"):
            raise ToolError("invalid_path", "Only local file URLs are supported.")
        raw = urllib.parse.unquote(parsed.path)
    path = Path(raw)
    if not path.is_absolute():
        raise ToolError("invalid_path", "Choose an absolute local file path.")
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError):
        raise ToolError("not_found", "That local file does not exist.") from None
    if not resolved.is_file():
        raise ToolError("not_file", "The selected path is not a regular file.")
    if resolved.suffix.lower() not in VIDEO_EXTENSIONS:
        raise ToolError("unsupported_file", "That file type is not a supported video.")
    return str(resolved)


def status_payload():
    ani = executable("ani-cli")
    terminals = tool_list(TERMINALS)
    players = tool_list(PLAYERS)
    ytdlp = executable("yt-dlp")
    ffmpeg = executable("ffmpeg")
    ffprobe = executable("ffprobe")
    return {
        "ok": True,
        "aniCli": ani,
        "aniReady": bool(ani and terminals),
        "terminals": terminals,
        "players": players,
        "ytDlp": ytdlp,
        "ffmpeg": ffmpeg,
        "ffprobe": ffprobe,
        "guidance": {
            "aniCli": "" if ani else INSTALL_GUIDANCE["ani-cli"],
            "terminal": "" if terminals else INSTALL_GUIDANCE["terminal"],
            "player": "" if players else INSTALL_GUIDANCE["player"],
            "ytDlp": "" if ytdlp else INSTALL_GUIDANCE["yt-dlp"],
            "ffmpeg": "" if ffmpeg else INSTALL_GUIDANCE["ffmpeg"],
        },
    }


def ani_command():
    ani = executable("ani-cli")
    if not ani:
        raise ToolError("ani_cli_missing", INSTALL_GUIDANCE["ani-cli"])
    terminal = None
    for command, label in TERMINALS:
        path = executable(command)
        if path:
            terminal = {"id": command, "label": label, "path": path}
            break
    if terminal is None:
        raise ToolError("terminal_missing", INSTALL_GUIDANCE["terminal"])
    tid = terminal["id"]
    if tid == "kitty":
        command = [terminal["path"], "--title", "GPS ani-cli", ani]
    elif tid == "wezterm":
        command = [terminal["path"], "start", "--", ani]
    elif tid == "gnome-terminal":
        command = [terminal["path"], "--", ani]
    else:
        command = [terminal["path"], "-e", ani]
    return {
        "ok": True,
        "action": "ani-cli",
        "command": command,
        "terminal": terminal,
        "aniCli": ani,
        "message": "Opened ani-cli in an external terminal. Choose a title in its interactive menu.",
    }


def video_command(value):
    path = safe_local_path(value)
    player = None
    for command, label in PLAYERS:
        found = executable(command)
        if found:
            player = {"id": command, "label": label, "path": found}
            break
    if player is None:
        raise ToolError("player_missing", INSTALL_GUIDANCE["player"])
    if player["id"] == "ffplay":
        command = [player["path"], "-autoexit", path]
    else:
        command = [player["path"], path]
    return {
        "ok": True,
        "action": "local-video",
        "command": command,
        "player": player,
        "path": path,
        "message": "Opened the selected video in " + player["label"] + ".",
    }


def emit(payload, code=0):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return code


def main(argv=None):
    parser = argparse.ArgumentParser(description="GPS Media Hub external playback tools")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("ani-command")
    video = sub.add_parser("video-command")
    video.add_argument("--path", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "status":
            return emit(status_payload())
        if args.command == "ani-command":
            return emit(ani_command())
        if args.command == "video-command":
            return emit(video_command(args.path))
    except ToolError as error:
        return emit({"ok": False, "code": error.code, "message": error.message}, 1)
    except Exception:
        return emit({
            "ok": False,
            "code": "internal_error",
            "message": "The playback helper could not complete that request.",
        }, 1)
    return emit({"ok": False, "code": "invalid_request", "message": "Unknown command."}, 1)


if __name__ == "__main__":
    raise SystemExit(main())
