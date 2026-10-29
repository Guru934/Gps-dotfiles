#!/usr/bin/env python3
"""Compatibility wrapper for extract-theme.py pointing to set_wallpaper pipeline."""
import sys
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import set_wallpaper


def main() -> int:
    image = sys.argv[1] if len(sys.argv) > 1 else None
    res = set_wallpaper.apply_wallpaper(image_path=image, skip_awww=True)
    if not res.get("ok"):
        print(f"extract-theme error: {res.get('error')}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
