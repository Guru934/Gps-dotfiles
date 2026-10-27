#!/usr/bin/env python3
"""Screen-time summary for the Home dashboard.

Queries the local ActivityWatch-compatible tracker (the awatcher bundle) over
its REST API on 127.0.0.1:5600 and prints a single-line JSON object with
today's per-application active time. Idle (afk) intervals are subtracted and
overlapping events are merged, so the reported numbers are real active-usage
durations - never event counts or inferred values.

Output states (single line each):
  {"status":"ok","total_seconds":N,"apps":[...]}  real totals for the local day
  {"status":"nodata"}                             tracker up, no window history yet
  {"status":"offline"}                            tracker API not reachable
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

API = "http://127.0.0.1:5600/api/0"
TIMEOUT_SECONDS = 5

LABELS = {
    "brave-browser": "Brave",
    "brave": "Brave",
    "firefox": "Firefox",
    "kitty": "Kitty",
    "alacritty": "Alacritty",
    "code": "VS Code",
    "thunar": "Files",
    "org.gnome.Nautilus": "Files",
    "discord": "Discord",
    "vesktop": "Vesktop",
    "spotify": "Spotify",
    "mpv": "mpv",
}

_TS_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$"
)


def parse_ts(value):
    m = _TS_RE.match(value)
    if not m:
        raise ValueError("bad timestamp: %r" % value)
    base, frac, tz = m.groups()
    frac = (frac or "0")[:6].ljust(6, "0")
    offset = "+00:00" if tz in (None, "Z") else tz
    if len(offset) == 5:
        offset = offset[:3] + ":" + offset[3:]
    return datetime.fromisoformat("%s.%s%s" % (base, frac, offset))


def fetch(path):
    with urllib.request.urlopen(API + path, timeout=TIMEOUT_SECONDS) as resp:
        return json.load(resp)


def clamp(ts, dur, day_start, now):
    start = max(ts, day_start)
    end = min(ts + timedelta(seconds=dur), now)
    return (start, end) if end > start else None


def subtract(cuts, span):
    out = [span]
    for cs, ce in cuts:
        nxt = []
        for s, e in out:
            if ce <= s or cs >= e:
                nxt.append((s, e))
                continue
            if cs > s:
                nxt.append((s, cs))
            if ce < e:
                nxt.append((ce, e))
        out = nxt
    return out


def merged_total(spans):
    total = 0.0
    cur_s = cur_e = None
    for s, e in sorted(spans):
        if cur_e is None or s > cur_e:
            if cur_e is not None:
                total += (cur_e - cur_s).total_seconds()
            cur_s, cur_e = s, e
        else:
            cur_e = max(cur_e, e)
    if cur_e is not None:
        total += (cur_e - cur_s).total_seconds()
    return total


def label_for(app):
    if app in LABELS:
        return LABELS[app]
    base = app.split(".")[-1]
    return base[:1].upper() + base[1:] if base else app


def main():
    top_n = 5
    if len(sys.argv) > 1:
        try:
            top_n = max(1, min(20, int(sys.argv[1])))
        except ValueError:
            pass

    now = datetime.now().astimezone()
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    try:
        buckets = fetch("/buckets/")
    except Exception:
        print(json.dumps({"status": "offline"}))
        return

    win_ids = [b for b in buckets if b.startswith("aw-watcher-window_")]
    afk_ids = [b for b in buckets if b.startswith("aw-watcher-afk_")]
    if not win_ids:
        print(json.dumps({"status": "nodata"}))
        return

    query = "?start=%s&end=%s&limit=-1" % (
        urllib.parse.quote(day_start.isoformat()),
        urllib.parse.quote(now.isoformat()),
    )
    try:
        win_events = fetch("/buckets/%s/events%s" % (win_ids[0], query))
        afk_events = (
            fetch("/buckets/%s/events%s" % (afk_ids[0], query)) if afk_ids else []
        )
    except Exception:
        print(json.dumps({"status": "offline"}))
        return

    afk_cuts = []
    for ev in afk_events:
        data = ev.get("data") or {}
        if data.get("status") != "afk":
            continue
        try:
            span = clamp(parse_ts(ev["timestamp"]), float(ev["duration"]), day_start, now)
        except (KeyError, TypeError, ValueError):
            continue
        if span:
            afk_cuts.append(span)

    per_app = {}
    all_spans = []
    for ev in win_events:
        data = ev.get("data") or {}
        app = (data.get("app") or "").strip()
        if not app:
            continue
        try:
            span = clamp(parse_ts(ev["timestamp"]), float(ev["duration"]), day_start, now)
        except (KeyError, TypeError, ValueError):
            continue
        if not span:
            continue
        for active in subtract(afk_cuts, span):
            per_app.setdefault(app, []).append(active)
            all_spans.append(active)

    if not all_spans:
        print(json.dumps({"status": "nodata"}))
        return

    total = merged_total(all_spans)
    apps = []
    for app, spans in per_app.items():
        secs = merged_total(spans)
        if secs < 1:
            continue
        apps.append(
            {
                "app": app,
                "label": label_for(app),
                "seconds": int(round(secs)),
                "pct": int(round(100.0 * secs / total)) if total > 0 else 0,
            }
        )
    apps.sort(key=lambda a: a["seconds"], reverse=True)

    print(
        json.dumps(
            {
                "status": "ok",
                "total_seconds": int(round(total)),
                "app_count": len(apps),
                "apps": apps[:top_n],
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
