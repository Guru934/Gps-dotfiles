#!/usr/bin/env python3
"""Manage PipeWire audio sinks (via wpctl and pactl) as JSON for GPS.

One-shot helper:
  - Default (no args): parses `wpctl status` and prints available sinks:
      {"sinks": [{"id": 56, "name": "...", "default": true, "available": true}], "default_id": 56}
  - `--switch <id>`: sets default sink via `wpctl set-default <id>` AND moves
    all active sink-inputs to that sink via `pactl move-sink-input`.
"""

import json
import re
import subprocess
import sys

VOL_SUFFIX = re.compile(r"\s*\[vol:.*?\]\s*$")
SINK_LINE = re.compile(r"^[\s\u2502\u251c\u2514]*?(?:(\*)\s+)?(\d+)\.\s+(.*?)\s*$")
SECTION_LINE = re.compile(r"^[\u2502\u251c\u2514\u2500\s]*([A-Za-z][A-Za-z ]*):\s*$")
ENGINE_LINE = re.compile(r"^PipeWire '([^']+)' \[([^,\]]+)")


def sink_availability():
    """Map sink description -> availability via one `pactl` JSON read."""
    try:
        out = subprocess.run(
            ["pactl", "--format=json", "list", "sinks"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if out.returncode != 0:
            return {}
        data = json.loads(out.stdout)
    except Exception:
        return {}
    result = {}
    for sink in data:
        desc = sink.get("description")
        if not desc:
            continue
        active = sink.get("active_port")
        ports = {p.get("name"): p.get("availability") for p in sink.get("ports", [])}
        if active and ports.get(active) == "not available":
            result[desc] = False
        else:
            result[desc] = True
    return result


def parse_wpctl_status(status_text: str) -> tuple[str, list[dict], int | None]:
    group = ""
    in_sinks = False
    sinks = []
    engine = ""
    lines = status_text.splitlines()
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if not engine:
            em = ENGINE_LINE.match(line)
            if em:
                engine = "PipeWire %s" % em.group(2)
                continue
        if raw and not raw[0].isspace() and re.match(r"^[A-Za-z]", raw):
            group = line
            in_sinks = False
            continue
        if "\u251c\u2500" in raw or "\u2514\u2500" in raw:
            msec = SECTION_LINE.match(line)
            in_sinks = group == "Audio" and msec is not None and msec.group(1) == "Sinks"
            continue
        if not in_sinks:
            continue
        m = SINK_LINE.match(raw)
        if not m:
            continue
        sink_id = int(m.group(2))
        name = VOL_SUFFIX.sub("", m.group(3))
        sinks.append({"id": sink_id, "name": name, "default": bool(m.group(1))})

    default_id = None
    for s in sinks:
        if s["default"]:
            default_id = s["id"]
            break

    return engine, sinks, default_id


def switch_sink(target_id: int) -> dict:
    """Set default sink via wpctl and move all active streams to it."""
    try:
        res = subprocess.run(
            ["wpctl", "set-default", str(target_id)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if res.returncode != 0:
            err = res.stderr.strip() or f"wpctl set-default failed ({res.returncode})"
            return {"ok": False, "error": err}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

    streams_moved = 0
    try:
        inputs_res = subprocess.run(
            ["pactl", "list", "short", "sink-inputs"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if inputs_res.returncode == 0:
            for line in inputs_res.stdout.splitlines():
                parts = line.strip().split()
                if parts:
                    input_id = parts[0]
                    subprocess.run(
                        ["pactl", "move-sink-input", str(input_id), str(target_id)],
                        capture_output=True,
                        timeout=2,
                    )
                    streams_moved += 1
    except Exception:
        pass

    return {"ok": True, "target_id": target_id, "streams_moved": streams_moved}


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("--switch", "--set-default", "switch", "set-default"):
        if len(sys.argv) < 3:
            print(json.dumps({"error": "Missing target sink ID"}))
            sys.exit(1)
        try:
            target_id = int(sys.argv[2])
        except ValueError:
            print(json.dumps({"error": f"Invalid sink ID: {sys.argv[2]}"}))
            sys.exit(1)
        res = switch_sink(target_id)
        print(json.dumps(res))
        sys.exit(0 if res.get("ok") else 1)

    try:
        out = subprocess.run(
            ["wpctl", "status"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:
        print(json.dumps({"error": "wpctl failed: %s" % exc}))
        return

    if out.returncode != 0:
        msg = (out.stderr or "").strip() or ("wpctl exit %d" % out.returncode)
        print(json.dumps({"error": msg}))
        return

    engine, sinks, default_id = parse_wpctl_status(out.stdout)
    availability = sink_availability()
    for s in sinks:
        if s["name"] in availability:
            s["available"] = availability[s["name"]]

    print(json.dumps({"engine": engine, "sinks": sinks, "default_id": default_id}))


if __name__ == "__main__":
    main()
