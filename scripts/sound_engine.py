#!/usr/bin/env python3
"""GPS Sound Engine - Pure logic and playback management for GPS desktop sound system.

Features:
- pw-play playback with explicit small latency, media-role Notification, detached execution
- Master mute & volume cap, per-event enable & volume
- Rate limiting: <= 1 sound per 1.5s, critical & agent-permission never dropped, volume tick throttled to 120ms
- Microphone privacy guard: quiet while mic in use unless critical or agent-permission
- DND integration: DND mutes all except critical & agent-permission (soundsBypassDnd setting)
- De-duplication: same event within 3s plays once, agent requests dedupe within 5s
- Graceful degradation if pw-play or sound files are missing
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

DEFAULT_SETTINGS: Dict[str, Any] = {
    "enabled": True,
    "muted": False,
    "volume": 0.8,
    "volumeCap": 1.0,
    "theme": "default",
    "soundsBypassDnd": True,
    "quietWhileMicInUse": True,
    "rateLimitSeconds": 1.5,
    "dedupeWindowSeconds": 3.0,
    "agentDedupeWindowSeconds": 5.0,
    "agentAppNames": [
        "Antigravity",
        "Codex",
        "opencode",
        "Claude Code",
        "Gemini CLI",
    ],
    "events": {},
}

CRITICAL_EVENTS = {"critical", "notification-critical", "agent-permission"}
AUDIO_CAPTURE_CLASSES = {"audio/stream", "stream/input/audio", "audio/source"}


@dataclass
class PlaybackDecision:
    allowed: bool
    volume: float = 0.0
    reason: str = "ok"
    sound_file: Optional[Path] = None


def get_repo_root() -> Path:
    if "GPS_ROOT" in os.environ and os.path.isdir(os.environ["GPS_ROOT"]):
        return Path(os.environ["GPS_ROOT"]).resolve()
    return Path(__file__).resolve().parent.parent


def get_config_path() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(config_home) / "quickshell" / "rice-settings.json"


def get_dnd_path() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(state_home) / "gps" / "dnd.json"


def get_runtime_state_path() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    target_dir = Path(runtime_dir) / "gps"
    target_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    return target_dir / "sound_state.json"


def load_settings(settings_path: Optional[Path] = None) -> Dict[str, Any]:
    path = settings_path or get_config_path()
    cfg = dict(DEFAULT_SETTINGS)
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and "sound" in data and isinstance(data["sound"], dict):
                sound_cfg = data["sound"]
                for k, v in sound_cfg.items():
                    if k == "events" and isinstance(v, dict):
                        cfg["events"] = dict(v)
                    else:
                        cfg[k] = v
        except Exception:
            pass
    return cfg


def save_settings(updates: Dict[str, Any], settings_path: Optional[Path] = None) -> bool:
    path = settings_path or get_config_path()
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        data: Dict[str, Any] = {}
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                    if isinstance(loaded, dict):
                        data = loaded
            except Exception:
                data = {}
        sound_section = data.setdefault("sound", dict(DEFAULT_SETTINGS))
        for k, v in updates.items():
            sound_section[k] = v

        tmp_path = path.parent / f".{path.name}.tmp.{os.getpid()}"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_path, path)
        return True
    except Exception:
        return False


def parse_time_to_minutes(time_str: str) -> int:
    if not time_str or not isinstance(time_str, str):
        return 0
    parts = time_str.split(":")
    try:
        h = int(parts[0])
        m = int(parts[1]) if len(parts) > 1 else 0
        return max(0, min(23, h)) * 60 + max(0, min(59, m))
    except (ValueError, IndexError):
        return 0


def is_dnd_active(dnd_path: Optional[Path] = None, now_ms: Optional[float] = None) -> bool:
    path = dnd_path or get_dnd_path()
    if not path.exists():
        return False
    try:
        with open(path, "r", encoding="utf-8") as f:
            dnd_state = json.load(f)
    except Exception:
        return False

    if not isinstance(dnd_state, dict):
        return False

    mode = dnd_state.get("mode", "off")
    if mode == "off":
        return False
    if mode == "dnd":
        return True

    now = (now_ms if now_ms is not None else time.time() * 1000.0)

    if mode == "snooze":
        snooze_until = float(dnd_state.get("snoozeUntil", 0))
        return now < snooze_until

    if mode == "schedule":
        sched = dnd_state.get("schedule", {})
        if not sched.get("enabled", False):
            return False
        # Calculate day of week (1=Mon ... 7=Sun)
        t = time.localtime(now / 1000.0)
        day = t.tm_wday + 1
        days = sched.get("days", [1, 2, 3, 4, 5, 6, 7])
        current_min = t.tm_hour * 60 + t.tm_min
        from_min = parse_time_to_minutes(sched.get("from", "22:00"))
        to_min = parse_time_to_minutes(sched.get("to", "07:00"))

        if from_min == to_min:
            return False
        if from_min < to_min:
            if day not in days:
                return False
            return from_min <= current_min < to_min
        else:
            if current_min >= from_min:
                return day in days
            elif current_min < to_min:
                prev_day = 7 if day == 1 else (day - 1)
                return prev_day in days
            return False

    return False


def is_mic_in_use(pw_dump_fn: Optional[Callable[[], Optional[List[Dict[str, Any]]]]] = None) -> bool:
    """Returns True if an active audio capture/microphone stream is currently running."""
    if pw_dump_fn is not None:
        nodes = pw_dump_fn()
    else:
        try:
            res = subprocess.run(
                ["pw-dump", "Node"],
                capture_output=True,
                text=True,
                timeout=1.0,
                check=False,
            )
            if res.returncode != 0 or not res.stdout.strip():
                return False
            nodes = json.loads(res.stdout)
        except Exception:
            return False

    if not isinstance(nodes, list):
        return False

    for node in nodes:
        if not isinstance(node, dict):
            continue
        info = node.get("info") or {}
        props = info.get("props") or node.get("props") or {}
        state = str(info.get("state") or node.get("state") or "").lower()
        if state != "running":
            continue

        media_class = str(props.get("media.class") or "").lower()
        if media_class not in AUDIO_CAPTURE_CLASSES:
            continue

        name = str(props.get("node.name") or props.get("media.name") or "").lower()
        role = str(props.get("media.role") or "").lower()

        # Exclude monitors and visualizers (e.g. cava)
        if ".monitor" in name or "monitor" in role or "cava" in name:
            continue

        return True

    return False


def get_allowed_sound_directories() -> List[Path]:
    home = Path.home()
    return [
        Path("/usr/share/sounds"),
        Path("/usr/local/share/sounds"),
        home / ".local/share/sounds",
        home / ".config/quickshell/sounds",
        get_repo_root() / "assets/sounds",
    ]


def is_allowed_sound_file(file_path: Path | str) -> bool:
    try:
        p = Path(file_path).expanduser().resolve()
        if not p.is_file():
            return False
        allowed = get_allowed_sound_directories()
        for base in allowed:
            try:
                base_resolved = base.resolve()
                p.relative_to(base_resolved)
                return True
            except (ValueError, RuntimeError):
                continue
        return False
    except Exception:
        return False


def resolve_sound_file(
    event: str,
    theme_name: Optional[str] = None,
    themes_root: Optional[Path] = None,
) -> Optional[Path]:
    root = themes_root or (get_repo_root() / "assets/sounds")
    theme = theme_name or "default"

    candidate_themes = [theme]
    if theme != "default":
        candidate_themes.append("default")

    for th in candidate_themes:
        theme_dir = root / th
        theme_manifest = theme_dir / "theme.json"
        if not theme_manifest.exists():
            continue
        try:
            with open(theme_manifest, "r", encoding="utf-8") as f:
                mapping = json.load(f)
            if isinstance(mapping, dict) and event in mapping:
                rel = mapping[event]
                candidate = (theme_dir / rel).resolve()
                if candidate.is_file():
                    return candidate
        except Exception:
            continue

    return None


class SoundStateStore:
    """Thread/process-safe persistent runtime state for rate limiting and deduplication."""

    def __init__(self, state_file: Optional[Path] = None):
        self.path = state_file or get_runtime_state_path()

    def update_and_check(
        self,
        event: str,
        dedupe_key: str,
        now: float,
        is_exempt: bool,
        rate_limit: float,
        dedupe_window: float,
    ) -> Tuple[bool, str]:
        """Atomically reads, checks rate limit and dedupe rules, and updates state."""
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        lock_file = self.path.parent / (self.path.name + ".lock")
        try:
            with open(lock_file, "w") as lock_fd:
                fcntl.flock(lock_fd, fcntl.LOCK_EX)
                try:
                    state: Dict[str, Any] = {
                        "last_played": 0.0,
                        "last_tick": 0.0,
                        "keys": {},
                    }
                    if self.path.exists():
                        try:
                            with open(self.path, "r", encoding="utf-8") as f:
                                loaded = json.load(f)
                                if isinstance(loaded, dict):
                                    state["last_played"] = float(loaded.get("last_played", 0.0))
                                    state["last_tick"] = float(loaded.get("last_tick", 0.0))
                                    if isinstance(loaded.get("keys"), dict):
                                        state["keys"] = {
                                            k: float(v)
                                            for k, v in loaded["keys"].items()
                                            if isinstance(v, (int, float))
                                        }
                        except Exception:
                            pass

                    # Clean up old keys older than 60s
                    state["keys"] = {
                        k: v for k, v in state["keys"].items() if now - v < 60.0
                    }

                    # Deduplication check
                    if dedupe_key in state["keys"]:
                        if now - state["keys"][dedupe_key] < dedupe_window:
                            return False, "deduplicated"

                    # Rate limit check
                    if is_exempt:
                        # Critical and agent-permission are NEVER dropped by rate limit
                        pass
                    elif event == "tick":
                        # Throttled to 120ms
                        if now - state["last_tick"] < 0.120:
                            return False, "rate_limited"
                    else:
                        if now - state["last_played"] < rate_limit:
                            return False, "rate_limited"

                    # Passed! Update timestamps
                    state["keys"][dedupe_key] = now
                    if event == "tick":
                        state["last_tick"] = now
                    else:
                        state["last_played"] = now

                    tmp_file = self.path.parent / f".{self.path.name}.tmp.{os.getpid()}"
                    with open(tmp_file, "w", encoding="utf-8") as f:
                        json.dump(state, f)
                    os.replace(tmp_file, self.path)
                    return True, "ok"

                finally:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except Exception as e:
            # Fallback if locking fails: allow sound
            return True, f"lock_fallback:{e}"


class SoundEngine:
    def __init__(
        self,
        settings: Optional[Dict[str, Any]] = None,
        dnd_active_fn: Optional[Callable[[], bool]] = None,
        mic_in_use_fn: Optional[Callable[[], bool]] = None,
        state_store: Optional[SoundStateStore] = None,
        clock_fn: Optional[Callable[[], float]] = None,
        themes_root: Optional[Path] = None,
    ):
        self.settings = settings if settings is not None else load_settings()
        self.dnd_active_fn = dnd_active_fn or is_dnd_active
        self.mic_in_use_fn = mic_in_use_fn or is_mic_in_use
        self.state_store = state_store or SoundStateStore()
        self.clock = clock_fn or time.time
        self.themes_root = themes_root

    def evaluate(
        self,
        event: str,
        custom_dedupe_key: Optional[str] = None,
        custom_sound_file: Optional[Path] = None,
        bypass_filters: bool = False,
    ) -> PlaybackDecision:
        now = self.clock()

        # 1. Master enabled / mute check
        if not self.settings.get("enabled", True):
            return PlaybackDecision(allowed=False, reason="disabled")
        if self.settings.get("muted", False) and not bypass_filters:
            return PlaybackDecision(allowed=False, reason="master_muted")

        # 2. Per-event enabled check
        event_cfg = self.settings.get("events", {}).get(event, {})
        if isinstance(event_cfg, dict) and not event_cfg.get("enabled", True):
            return PlaybackDecision(allowed=False, reason="event_disabled")

        # 3. Sound file resolution
        sound_file = custom_sound_file
        if sound_file is None:
            theme_name = self.settings.get("theme", "default")
            sound_file = resolve_sound_file(event, theme_name=theme_name, themes_root=self.themes_root)

        if sound_file is None or not sound_file.is_file():
            return PlaybackDecision(allowed=False, reason="sound_file_missing")

        # 4. Volume calculation
        master_vol = float(self.settings.get("volume", 0.8))
        vol_cap = float(self.settings.get("volumeCap", 1.0))
        event_vol = float(event_cfg.get("volume", 1.0)) if isinstance(event_cfg, dict) else 1.0
        effective_volume = max(0.0, min(master_vol * event_vol, vol_cap, 1.0))

        if bypass_filters:
            return PlaybackDecision(allowed=True, volume=effective_volume, reason="bypassed", sound_file=sound_file)

        is_exempt = event in CRITICAL_EVENTS

        # 5. DND Check
        if self.dnd_active_fn():
            bypass_dnd = bool(self.settings.get("soundsBypassDnd", True))
            if not (is_exempt and bypass_dnd):
                return PlaybackDecision(allowed=False, reason="dnd_active")

        # 6. Mic in use check
        if self.settings.get("quietWhileMicInUse", True) and self.mic_in_use_fn():
            if not is_exempt:
                return PlaybackDecision(allowed=False, reason="mic_in_use")

        # 7. Dedupe & Rate Limiting
        dedupe_key = custom_dedupe_key or event
        is_agent = event.startswith("agent-")
        dedupe_window = float(
            self.settings.get("agentDedupeWindowSeconds", 5.0)
            if is_agent
            else self.settings.get("dedupeWindowSeconds", 3.0)
        )
        rate_limit = float(self.settings.get("rateLimitSeconds", 1.5))

        ok, reason = self.state_store.update_and_check(
            event=event,
            dedupe_key=dedupe_key,
            now=now,
            is_exempt=is_exempt,
            rate_limit=rate_limit,
            dedupe_window=dedupe_window,
        )
        if not ok:
            return PlaybackDecision(allowed=False, reason=reason)

        return PlaybackDecision(
            allowed=True,
            volume=effective_volume,
            reason="ok",
            sound_file=sound_file,
        )

    def play(
        self,
        event: str,
        custom_dedupe_key: Optional[str] = None,
        custom_sound_file: Optional[Path] = None,
        bypass_filters: bool = False,
        latency: str = "50ms",
        media_role: str = "Notification",
    ) -> Tuple[bool, str]:
        decision = self.evaluate(
            event=event,
            custom_dedupe_key=custom_dedupe_key,
            custom_sound_file=custom_sound_file,
            bypass_filters=bypass_filters,
        )
        if not decision.allowed:
            return False, decision.reason

        if decision.sound_file is None:
            return False, "sound_file_missing"

        # Check pw-play availability
        pw_play_bin = shutil.which("pw-play")
        if not pw_play_bin:
            # Degrade silently if missing
            return True, "pw_play_missing_silent"

        cmd = [
            pw_play_bin,
            "--latency",
            latency,
            "--volume",
            f"{decision.volume:.3f}",
            "--media-role",
            media_role,
            str(decision.sound_file),
        ]

        try:
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return True, "played"
        except Exception as e:
            return False, f"exec_error:{e}"
