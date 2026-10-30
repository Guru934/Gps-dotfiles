#!/usr/bin/env python3
"""Metadata-only privacy activity detector for the GPS island.

PipeWire is monitored as a stream of concatenated JSON values.  V4L2 is a
small, bounded fallback poll because direct device opens do not create
PipeWire graph events.  No media frames are opened or read.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import selectors
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterable


UNKNOWN_APP = "Unknown application"
UNKNOWN_DETAIL = "Unknown device"
POLL_SECONDS = 1.5
MAX_ITEMS = 32
AUDIO_CAPTURE_CLASSES = {"audio/stream", "stream/input/audio"}
VIDEO_STREAM_CLASSES = {"video/stream", "stream/input/video"}
VIDEO_SOURCE_CLASSES = {"video/source", "video/input"}


def props(obj: dict[str, Any]) -> dict[str, Any]:
    info = obj.get("info")
    if isinstance(info, dict) and isinstance(info.get("props"), dict):
        return info["props"]
    return obj.get("props") if isinstance(obj.get("props"), dict) else {}


def state(obj: dict[str, Any]) -> str:
    info = obj.get("info")
    return str(info.get("state", "")) if isinstance(info, dict) else str(obj.get("state", ""))


def text_value(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def first(props_: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = text_value(props_.get(key))
        if value:
            return value
    return ""


def pid_from(value: Any) -> int | None:
    try:
        pid = int(value)
        return pid if pid > 0 else None
    except (TypeError, ValueError):
        return None


def application(stream_props: dict[str, Any], client_props: dict[str, Any]) -> str:
    value = first(stream_props, "application.name", "application.process.binary", "node.name", "media.name")
    if not value:
        value = first(client_props, "application.name", "application.process.binary", "node.name", "media.name")
    return value or UNKNOWN_APP


def stream_pid(stream_props: dict[str, Any], client_props: dict[str, Any]) -> int | None:
    return pid_from(first(stream_props, "application.process.id", "pipewire.sec.pid")) or pid_from(
        first(client_props, "application.process.id", "pipewire.sec.pid")
    )


def active_stream(obj: dict[str, Any]) -> bool:
    return state(obj).lower() == "running"


def sample_rate(props_: dict[str, Any]) -> str:
    for key in ("audio.rate", "format.rate", "stream.audio.rate", "node.rate"):
        value = first(props_, key)
        if value.isdigit():
            return value
        parts = value.split("/", 1)
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            numerator, denominator = int(parts[0]), int(parts[1])
            if denominator > 0 and numerator > 0:
                # PipeWire commonly reports node.rate as a fraction such as 1/48000.
                return str(denominator if numerator == 1 else round(numerator / denominator))
    return ""


def audio_capture(obj: dict[str, Any], objects: dict[int, dict[str, Any]], clients: dict[int, dict[str, Any]]) -> dict[str, Any] | None:
    p = props(obj)
    media = first(p, "media.class").lower()
    if media not in AUDIO_CAPTURE_CLASSES or not active_stream(obj):
        return None
    name = " ".join(first(p, "node.name", "media.name", "application.name", "application.process.binary").lower().split())
    target = objects.get(int(p["target.object"])) if str(p.get("target.object", "")).isdigit() else None
    target_p = props(target) if target else {}
    target_name = " ".join(first(target_p, "node.name", "object.path", "media.name").lower().split())
    role = first(p, "media.role").lower()
    if ".monitor" in name or ".monitor" in target_name or "monitor" in role:
        return None
    if "cava" in name or "cava" in target_name:
        return None
    # A stream aimed at a playback sink/monitor is playback or sink capture.
    target_media = first(target_p, "media.class").lower()
    if target_media == "audio/sink" or (target_media == "audio/source" and ".monitor" in target_name):
        return None
    client_id = pid_from(p.get("client.id"))
    client_p = props(clients.get(client_id)) if client_id is not None else {}
    detail = first(p, "node.description", "node.nick", "media.name", "node.name")
    rate = sample_rate(p)
    if rate:
        detail = f"{detail} · {rate} Hz" if detail else f"{rate} Hz"
    elif not detail:
        detail = UNKNOWN_DETAIL
    return {
        "kind": "mic", "app": application(p, client_p), "detail": detail,
        "pid": stream_pid(p, client_p), "id": f"pw:{obj.get('id')}",
    }


def video_stream(obj: dict[str, Any], objects: dict[int, dict[str, Any]], clients: dict[int, dict[str, Any]]) -> dict[str, Any] | None:
    p = props(obj)
    media = first(p, "media.class").lower()
    if media not in VIDEO_STREAM_CLASSES | VIDEO_SOURCE_CLASSES or not active_stream(obj):
        return None
    target = objects.get(int(p["target.object"])) if str(p.get("target.object", "")).isdigit() else None
    target_p = props(target) if target else {}
    role = first(p, "media.role").lower()
    capture_type = first(p, "stream.capture.type", "media.capture.type").lower()
    node_name = " ".join(first(p, "node.name", "media.name").lower().split())
    target_name = " ".join(first(target_p, "node.name", "object.path", "media.name").lower().split())
    source_class = first(target_p, "media.class").lower()
    device_api = first(p, "device.api", "api.v4l2.path").lower()
    portal_flag = first(p, "pipewire.access.portal.is_portal").lower() in {"1", "true", "yes"}
    portal_identity = bool(first(p, "portal.app_id", "portal.app-id"))
    client_id = pid_from(p.get("client.id"))
    client_p = props(clients.get(client_id)) if client_id is not None else {}
    portal_process = any(
        "xdg-desktop-portal" in value.lower()
        for value in (
            first(p, "application.name", "application.process.binary"),
            first(client_p, "application.name", "application.process.binary"),
        )
    )
    # Camera evidence must describe a capture source, not merely a video node.
    camera = (
        role in {"camera", "webcam"}
        or device_api == "v4l2"
        or "v4l2" in target_name
        or (media in VIDEO_STREAM_CLASSES and source_class in VIDEO_SOURCE_CLASSES
            and any(token in node_name + " " + target_name for token in ("camera", "webcam")))
    )
    # Portal/role/capture-type metadata is intentional evidence. A generic
    # name containing "monitor" is not enough: playback and monitor nodes
    # are common in ordinary PipeWire graphs.
    screen = (
        role in {"screen", "monitor", "desktop", "window"}
        or capture_type in {"screen", "monitor", "desktop", "window", "output"}
        or (media in VIDEO_SOURCE_CLASSES and (portal_flag or portal_identity)
            and any(token in node_name + " " + target_name for token in ("screen", "output", "desktop", "xdph")))
        or (media in VIDEO_SOURCE_CLASSES and portal_process
            and ("xdg-desktop-portal" in node_name or "xdph-streaming" in node_name))
    )
    if camera and not screen:
        kind = "cam"
    elif screen and not camera:
        kind = "screen"
    else:
        return None
    detail = first(p, "node.description", "node.nick", "media.name", "node.name") or (
        "Screen capture" if kind == "screen" else UNKNOWN_DETAIL
    )
    return {
        "kind": kind, "app": application(p, client_p), "detail": detail,
        "pid": stream_pid(p, client_p), "id": f"pw:{obj.get('id')}",
    }


def classify_pipewire(objects: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id = {int(o["id"]): o for o in objects if isinstance(o, dict) and str(o.get("id", "")).isdigit()}
    clients = {i: o for i, o in by_id.items() if str(o.get("type", "")).endswith(":Client")}
    result: list[dict[str, Any]] = []
    for obj in by_id.values():
        item = audio_capture(obj, by_id, clients) or video_stream(obj, by_id, clients)
        if item:
            result.append(item)
    return result


def apply_pipewire_value(graph: dict[int, dict[str, Any]], value: Any) -> None:
    """Apply monitor values incrementally; monitor arrays are not replacements."""
    events = value if isinstance(value, list) else [value]
    for obj in events:
        if not isinstance(obj, dict) or not str(obj.get("id", "")).isdigit():
            continue
        ident = int(obj["id"])
        if obj.get("info") is None:
            graph.pop(ident, None)
        else:
            # pw-dump --monitor sends partial updates. Retain the last known
            # state/props when an update only contains one half of `info`.
            previous = graph.get(ident, {})
            merged = dict(previous)
            merged.update({key: val for key, val in obj.items() if key != "info"})
            old_info = previous.get("info") if isinstance(previous.get("info"), dict) else {}
            new_info = obj.get("info") if isinstance(obj.get("info"), dict) else {}
            info = dict(old_info)
            info.update(new_info)
            old_props = old_info.get("props") if isinstance(old_info.get("props"), dict) else {}
            new_props = new_info.get("props") if isinstance(new_info.get("props"), dict) else {}
            if old_props or new_props:
                info["props"] = {**old_props, **new_props}
            merged["info"] = info
            graph[ident] = merged


def check_screen_recorder(runtime_dir: str | None = None, proc_root: str = "/proc") -> list[dict[str, Any]]:
    r_dir = Path(runtime_dir or os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "gps"
    state_file = r_dir / "record-state.json"
    if not state_file.is_file():
        return []
    try:
        data = json.loads(state_file.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not data.get("recording"):
            return []
        pid = int(data.get("pid") or 0)
        if pid <= 0 or not Path(proc_root, str(pid)).is_dir():
            return []
        cmdline = Path(proc_root, str(pid), "cmdline").read_bytes()
        rec_name = str(data.get("recorder") or "screen-recorder")
        if rec_name.encode() not in cmdline and b"screen-recorder" not in cmdline and b"recorder" not in cmdline:
            return []
        mode = str(data.get("mode") or "monitor")
        detail = "Region recording" if mode == "region" else "Screen recording"
        return [{
            "kind": "screen",
            "app": "GPS Screen Recorder",
            "detail": detail,
            "pid": pid,
            "id": f"rec:{pid}",
        }]
    except Exception:
        return []


def privacy_items(graph: dict[int, dict[str, Any]], v4l2_items: Iterable[dict[str, Any]],
                  recorder_items: Iterable[dict[str, Any]] = ()) -> list[dict[str, Any]]:
    """Return one stable snapshot from both event-driven and polled sources."""
    return merge_items(list(classify_pipewire(graph.values())) + list(v4l2_items) + list(recorder_items))


def _proc_name(pid: int) -> str:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        return Path((raw[0] or b"").decode(errors="replace")).name or Path(f"/proc/{pid}/comm").read_text().strip()
    except (OSError, UnicodeError):
        return UNKNOWN_APP


def _is_capture_node(node: str) -> bool:
    """Query capabilities only; never starts streaming or reads frames."""
    try:
        with open(node, "rb", buffering=0) as device:
            capability = bytearray(104)
            fcntl.ioctl(device, 0x80685600, capability)  # VIDIOC_QUERYCAP
            caps = struct.unpack_from("I", capability, 84)[0]
            device_caps = struct.unpack_from("I", capability, 88)[0]
            return bool((device_caps or caps) & (0x00000001 | 0x00001000))
    except (OSError, ValueError, struct.error):
        return False


def enumerate_v4l2(sys_root: str = "/sys/class/video4linux", proc_root: str = "/proc",
                   capture_nodes: set[str] | None = None) -> list[dict[str, Any]]:
    devices: dict[str, str] = {}
    try:
        for entry in Path(sys_root).glob("video*"):
            name = (entry / "name").read_text(errors="replace").strip()
            node = f"/dev/{entry.name}"
            if name and (capture_nodes is not None and node in capture_nodes or capture_nodes is None and _is_capture_node(node)):
                devices[node] = name
    except OSError:
        return []
    result: list[dict[str, Any]] = []
    for pid_entry in Path(proc_root).glob("[0-9]*"):
        try:
            pid = int(pid_entry.name)
            for fd in (pid_entry / "fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                node = link if link in devices else None
                if not node:
                    continue
                result.append({"kind": "cam", "app": _proc_name(pid), "detail": devices[node],
                               "pid": pid, "id": f"v4l2:{node}:{pid}"})
                break
        except (OSError, ValueError):
            continue
    return result


def merge_items(items: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[tuple[Any, ...], dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict) or item.get("kind") not in {"mic", "cam", "screen"}:
            continue
        pid = item.get("pid") or 0
        detail = text_value(item.get("detail")) or UNKNOWN_DETAIL
        app = text_value(item.get("app")) or UNKNOWN_APP
        # A PipeWire stream and its direct V4L2 handle commonly report the
        # same client PID with different device descriptions. Treat that as
        # one capture; retain detail from the first source in the snapshot.
        key = (item["kind"], pid) if pid else (item["kind"], pid, detail.lower())
        merged.setdefault(key, {"kind": item["kind"], "app": app, "detail": detail,
                                "pid": item.get("pid"), "id": text_value(item.get("id")) or f"{item['kind']}:{pid}:{detail}"})
    return sorted(merged.values(), key=lambda i: (i["kind"], str(i["app"]).lower(), str(i["detail"]).lower()))[:MAX_ITEMS]


class MonitorParser:
    def __init__(self) -> None:
        self.decoder = json.JSONDecoder()
        self.buffer = ""

    def feed(self, chunk: str) -> list[Any]:
        self.buffer += chunk
        values: list[Any] = []
        while self.buffer:
            self.buffer = self.buffer.lstrip()
            if not self.buffer:
                break
            try:
                value, end = self.decoder.raw_decode(self.buffer)
            except json.JSONDecodeError:
                # Monitor reconnects should not be poisoned by a stray log line
                # or malformed frame. Keep an incomplete JSON value, but skip
                # obvious non-JSON prefixes until the next array/object start.
                if self.buffer[0] not in "[{":
                    starts = [i for i in (self.buffer.find("["), self.buffer.find("{")) if i >= 0]
                    if starts:
                        self.buffer = self.buffer[min(starts):]
                        continue
                    self.buffer = self.buffer[-1:]
                break
            values.append(value)
            self.buffer = self.buffer[end:]
        if len(self.buffer) > 4_000_000:
            self.buffer = self.buffer[-100_000:]
        return values


def emit(items: list[dict[str, Any]], available: bool, diagnostic: str = "") -> None:
    payload = {"items": merge_items(items), "available": available, "diagnostic": diagnostic}
    print(json.dumps(payload, separators=(",", ":"), ensure_ascii=True), flush=True)


def run() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pipewire", default="pw-dump")
    args = parser.parse_args()
    graph: dict[int, dict[str, Any]] = {}
    pw: subprocess.Popen[str] | None = None
    selector = selectors.DefaultSelector()
    decoder = MonitorParser()
    last_poll = 0.0
    last_payload: str | None = None
    restart_at = 0.0
    emit([], False, "starting PipeWire monitor")
    while True:
        now = time.monotonic()
        if pw is None and now >= restart_at:
            try:
                pw = subprocess.Popen([args.pipewire, "--monitor"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                selector.register(pw.stdout, selectors.EVENT_READ)
                decoder = MonitorParser()
            except OSError as exc:
                emit([], False, f"PipeWire monitor unavailable: {exc}")
                restart_at = now + 5.0
        timeout = max(0.05, min(POLL_SECONDS, (last_poll + POLL_SECONDS) - now))
        for key, _ in selector.select(timeout):
            try:
                chunk = os.read(key.fileobj.fileno(), 65536)
            except (OSError, ValueError):
                chunk = b""
            if not chunk:
                if pw is not None:
                    try: selector.unregister(key.fileobj)
                    except Exception: pass
                    pw.wait(timeout=0.2)
                pw = None
                graph = {}
                restart_at = time.monotonic() + 2.0
                emit([], False, "PipeWire monitor disconnected; retrying")
                break
            for value in decoder.feed(chunk.decode("utf-8", errors="replace")):
                apply_pipewire_value(graph, value)
                payload = json.dumps(privacy_items(graph, enumerate_v4l2(), check_screen_recorder()), separators=(",", ":"))
                if payload != last_payload:
                    emit(json.loads(payload), True, "")
                    last_payload = payload
        now = time.monotonic()
        if now - last_poll >= POLL_SECONDS:
            last_poll = now
            combined = privacy_items(graph, enumerate_v4l2(), check_screen_recorder())
            payload = json.dumps(combined, separators=(",", ":"))
            if payload != last_payload:
                emit(combined, pw is not None, "")
                last_payload = payload


if __name__ == "__main__":
    raise SystemExit(run())
