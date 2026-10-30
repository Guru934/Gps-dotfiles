#!/usr/bin/env python3
"""Shared theme utilities, contrast protection, and atomic helpers for GPS."""
from __future__ import annotations

import colorsys
import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any

# Canonical safe fallback palette matching config/Theme.qml defaults.
DEFAULT_FALLBACK_THEME: dict[str, Any] = {
    "wallpaper": "fallback",
    "leftLuminance": 0.20,
    "surface": "#F20F131C",
    "card": "#1C1F29",
    "cardHover": "#262A34",
    "track": "#0B1016",
    "border": "#3C4A46",
    "brandAccent": "#2DD4BF",
    "brandAccentFg": "#003731",
    "textMain": "#DFE2EF",
    "textMuted": "#BACAC5",
    "surfaceDeep": "#0F131C",
    "surfaceBase": "#181B25",
    "surfaceHigh": "#262A34",
    "accentPrimary": "#57F1DB",
    "outlineSoft": "#2F3A40",
}

REQUIRED_PALETTE_KEYS = [
    "surface",
    "card",
    "track",
    "border",
    "brandAccent",
    "textMain",
    "textMuted",
]


def atomic_write(target_path: Path | str, content: str) -> None:
    """Atomically write text content to target_path using a temporary file and atomic replace."""
    target = Path(target_path).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_file = tempfile.mkstemp(
        dir=str(target.parent),
        prefix=f".{target.name}.tmp-",
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_file, target)
    except Exception:
        if os.path.exists(tmp_file):
            try:
                os.unlink(tmp_file)
            except OSError:
                pass
        raise


def backup_file_once(target_path: Path | str) -> Path | None:
    """Create a .bak copy of target_path if it exists and backup doesn't already exist."""
    path = Path(target_path).expanduser().resolve()
    if not path.is_file():
        return None
    backup = path.with_name(f"{path.name}.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
        return backup
    return None


def parse_hex_color(hex_str: str) -> tuple[int, int, int]:
    """Parse #RGB, #RRGGBB, or #AARRGGBB hex color to (R, G, B) in [0, 255]."""
    c = hex_str.strip().lstrip("#")
    if len(c) == 3:
        r = int(c[0] * 2, 16)
        g = int(c[1] * 2, 16)
        b = int(c[2] * 2, 16)
    elif len(c) == 6:
        r = int(c[0:2], 16)
        g = int(c[2:4], 16)
        b = int(c[4:6], 16)
    elif len(c) == 8:
        # AARRGGBB
        r = int(c[2:4], 16)
        g = int(c[4:6], 16)
        b = int(c[6:8], 16)
    else:
        raise ValueError(f"Invalid hex color format: {hex_str}")
    return r, g, b


def srgb_to_linear(c: float) -> float:
    """Convert an sRGB color component in [0.0, 1.0] to linear light per IEC 61966-2-1."""
    if c <= 0.04045:
        return max(0.0, c / 12.92)
    return max(0.0, ((c + 0.055) / 1.055) ** 2.4)


def relative_luminance(hex_str: str) -> float:
    """Calculate WCAG 2.1 relative luminance for a hex color."""
    r, g, b = parse_hex_color(hex_str)
    r_lin = srgb_to_linear(r / 255.0)
    g_lin = srgb_to_linear(g / 255.0)
    b_lin = srgb_to_linear(b / 255.0)
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin


def contrast_ratio(hex1: str, hex2: str) -> float:
    """Calculate WCAG 2.1 contrast ratio between two hex colors."""
    l1 = relative_luminance(hex1)
    l2 = relative_luminance(hex2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def is_contrast_sufficient(fg_hex: str, bg_hex: str, min_ratio: float = 4.5) -> bool:
    """Check if contrast between foreground and background meets min_ratio (default 4.5:1)."""
    try:
        return contrast_ratio(fg_hex, bg_hex) >= min_ratio
    except Exception:
        return False


def validate_palette_dict(palette: dict[str, Any]) -> tuple[bool, str]:
    """Validate that palette dictionary contains all required keys and valid color values."""
    if not isinstance(palette, dict):
        return False, "Palette is not a dictionary"
    for key in REQUIRED_PALETTE_KEYS:
        if key not in palette:
            return False, f"Missing required palette key: {key}"
        val = palette[key]
        if not isinstance(val, str) or not val.startswith("#"):
            return False, f"Invalid color value for key {key}: {val}"
        try:
            parse_hex_color(val)
        except Exception as e:
            return False, f"Could not parse color for key {key}: {e}"
    return True, "Valid"


def load_and_validate_palette(palette_path: Path | str) -> tuple[dict[str, Any], bool]:
    """Load palette from JSON file and validate contrast.

    Returns (theme_dict, is_valid). If invalid or contrast check fails, returns
    (DEFAULT_FALLBACK_THEME, False).
    """
    path = Path(palette_path).expanduser().resolve()
    if not path.is_file():
        return dict(DEFAULT_FALLBACK_THEME), False

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return dict(DEFAULT_FALLBACK_THEME), False

    valid, _ = validate_palette_dict(data)
    if not valid:
        return dict(DEFAULT_FALLBACK_THEME), False

    # Check textMain against card and track / surface
    fg = data.get("textMain", "#FFFFFF")
    bg_card = data.get("card", "#1C1F29")
    bg_track = data.get("track", "#0B1016")

    if not is_contrast_sufficient(fg, bg_card, 4.5) or not is_contrast_sufficient(fg, bg_track, 4.5):
        # Unsuitable palette (e.g. light background with light text)
        return dict(DEFAULT_FALLBACK_THEME), False

    return data, True


def to_hex6(hex_str: str) -> str:
    """Ensure color is in standard 6-digit #RRGGBB format."""
    r, g, b = parse_hex_color(hex_str)
    return f"#{r:02X}{g:02X}{b:02X}"


def to_hex8_rgba(hex_str: str, alpha_hex: str = "FF") -> str:
    """Ensure color is in #RRGGBBAA format."""
    r, g, b = parse_hex_color(hex_str)
    return f"#{r:02X}{g:02X}{b:02X}{alpha_hex}"


def to_hex8_argb(hex_str: str, alpha_hex: str = "ff") -> str:
    """Ensure color is in #AARRGGBB format (qt6ct format, lowercase)."""
    r, g, b = parse_hex_color(hex_str)
    return f"#{alpha_hex.lower()}{r:02x}{g:02x}{b:02x}"
