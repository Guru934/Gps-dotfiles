#!/usr/bin/env python3
"""List PipeWire audio sinks (via wpctl) as JSON for the GPS dashboard.

One-shot helper: parses `wpctl status` and prints a single JSON object:

    {"sinks": [{"id": 56, "name": "700 Series ... Speaker", "default": true}],
     "default_id": 56}

On failure prints {"error": "<message>"}. Read-only: never changes the
default device; selection is performed by the caller with `wpctl set-default`.
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
    """Map sink description -> availability via one `pactl` JSON read.

    A sink is unavailable when its active port is explicitly marked "not
    available" (e.g. an HDMI/DP output with no display connected). Unknown
    or missing availability is treated as available. Failures degrade to an
    empty map; the caller then omits the field.
    """
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


def main():
    try:
        out = subprocess.run(
            ["wpctl", "status"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:  # missing binary, timeout, ...
        print(json.dumps({"error": "wpctl failed: %s" % exc}))
        return

    if out.returncode != 0:
        msg = (out.stderr or "").strip() or ("wpctl exit %d" % out.returncode)
        print(json.dumps({"error": msg}))
        return

    group = ""
    in_sinks = False
    sinks = []
    engine = ""
    lines = out.stdout.splitlines()
    if lines:
        em = ENGINE_LINE.match(lines[0].strip())
        if em:
            engine = "PipeWire %s" % em.group(2)
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        # Top-level group headers ("Audio", "Video", "Settings") start at
        # column zero; tree section headers live inside a group.
        if raw and not raw[0].isspace() and re.match(r"^[A-Za-z]", raw):
            group = line
            in_sinks = False
            continue
        if "\u251c\u2500" in raw or "\u2514\u2500" in raw:  # tree branch char
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

    availability = sink_availability()
    for s in sinks:
        if s["name"] in availability:
            s["available"] = availability[s["name"]]

    print(json.dumps({"engine": engine, "sinks": sinks, "default_id": default_id}))


if __name__ == "__main__":
    main()
