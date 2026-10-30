#!/usr/bin/env python3
"""GPS Theme Hook: Synchronize wallpaper-adaptive GPS folder icons."""
from __future__ import annotations

import os
from pathlib import Path
import sys

# Add parent directory for theme_common and gps_icons
script_dir = Path(__file__).resolve().parent
parent_dir = script_dir.parent
if str(parent_dir) not in sys.path:
    sys.path.insert(0, str(parent_dir))

import gps_icons
import theme_common


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print("Usage: 04-icons.py <path-to-gps-theme.json>", file=sys.stderr)
        return 1

    palette_path = Path(args[0]).expanduser().resolve()
    try:
        res = gps_icons.generate_gps_icon_theme(palette_path)
        if res.get("ok"):
            accent = res.get("accent", "unknown")
            recolored = res.get("recolored", False)
            print(f"Synchronized GPS-Icons folder icons with accent {accent} (recolored={recolored})")
            return 0
        else:
            print(f"Failed to synchronize GPS-Icons: {res.get('error')}", file=sys.stderr)
            return 1
    except Exception as e:
        # Log error to theme-hooks.log
        state_dir = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state")) / "gps"
        log_file = state_dir / "theme-hooks.log"
        try:
            log_file.parent.mkdir(parents=True, exist_ok=True)
            import time
            timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(f"[{timestamp}] Hook '04-icons.py' failed: {e}\n")
        except Exception:
            pass
        print(f"Error in 04-icons hook: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
