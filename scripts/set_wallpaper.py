#!/usr/bin/env python3
"""Unified wallpaper application and dynamic theme extraction pipeline."""
from __future__ import annotations

import argparse
import colorsys
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any


def get_config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "quickshell"


def get_theme_json_path() -> Path:
    return get_config_dir() / "gps-theme.json"


def get_last_wall_path() -> Path:
    return get_config_dir() / "gps-last-wall.txt"


def get_rofi_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "rofi"


def get_rofi_colors_path() -> Path:
    return get_rofi_dir() / "colors.rasi"


def get_hypr_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "hypr"


def get_lock_colors_path() -> Path:
    return get_hypr_dir() / "lock-colors.conf"


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


def ensure_awww_daemon() -> bool:
    """Ensure awww-daemon is running."""
    if shutil.which("awww") is None:
        return False
    try:
        check = subprocess.run(["awww", "query"], capture_output=True, text=True, timeout=2)
        if check.returncode == 0:
            return True
    except (subprocess.TimeoutExpired, OSError):
        pass

    try:
        subprocess.Popen(
            ["awww-daemon"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(15):
            time.sleep(0.1)
            check = subprocess.run(["awww", "query"], capture_output=True, text=True, timeout=1)
            if check.returncode == 0:
                return True
    except OSError:
        pass
    return False


def get_current_wallpaper() -> str:
    """Query currently displayed wallpaper from awww query or last-wall file."""
    try:
        out = subprocess.check_output(["awww", "query"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if "image:" in line:
                val = line.split("image:", 1)[1].strip()
                if val and os.path.exists(val):
                    return val
    except Exception:
        pass

    last_wall = get_last_wall_path()
    if last_wall.exists():
        try:
            val = last_wall.read_text(encoding="utf-8").strip()
            if val and os.path.exists(val):
                return val
        except OSError:
            pass
    return ""


def extract_dominant_hsv(img_path: Path | str) -> tuple[float, float, float]:
    """Calculate dominant HSV from an image file using weighted HSV histogram."""
    from PIL import Image

    try:
        with Image.open(img_path) as raw_img:
            img = raw_img.convert("RGB").resize((64, 64))
    except Exception:
        return 0.92, 0.45, 0.90

    buckets = [0.0] * 36
    r_sum = [0.0] * 36
    g_sum = [0.0] * 36
    b_sum = [0.0] * 36

    try:
        pixels = img.get_flattened_data()
    except AttributeError:
        pixels = img.getdata()

    for r, g, b in pixels:
        rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
        if v < 0.15 or s < 0.18:
            continue
        idx = int(h * 36) % 36
        weight = (s ** 1.4) * (v ** 1.1)
        buckets[idx] += weight
        r_sum[idx] += rf * weight
        g_sum[idx] += gf * weight
        b_sum[idx] += bf * weight

    best = max(range(36), key=lambda i: buckets[i])
    if buckets[best] <= 0:
        return 0.92, 0.45, 0.90
    w = buckets[best]
    return colorsys.rgb_to_hsv(r_sum[best] / w, g_sum[best] / w, b_sum[best] / w)


def hsv_hex(h: float, s: float, v: float, alpha: str = "") -> str:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return f"#{alpha}{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}"


def hsv_rgba_hex(h: float, s: float, v: float, alpha_hex: str = "FF") -> str:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return f"#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}{alpha_hex}"


def srgb_to_linear(c: float) -> float:
    """Convert an sRGB color component in [0.0, 1.0] to linear light per IEC 61966-2-1."""
    if c <= 0.04045:
        return max(0.0, c / 12.92)
    return max(0.0, ((c + 0.055) / 1.055) ** 2.4)


def get_monitor_geometry() -> tuple[int, int, float]:
    """Detect primary monitor physical resolution and scale factor, fallback to 1920x1200@1.5."""
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            out = subprocess.check_output(["hyprctl", "monitors"], text=True, stderr=subprocess.DEVNULL)
            match_res = re.search(r"(\d+)x(\d+)@[\d\.]+", out)
            match_scale = re.search(r"scale:\s*([\d\.]+)", out)
            if match_res:
                w, h = int(match_res.group(1)), int(match_res.group(2))
                scale = float(match_scale.group(1)) if match_scale else 1.0
                return w, h, scale
        except Exception:
            pass
    return 1920, 1200, 1.5


def calculate_left_strip_luminance(
    img_path: Path | str,
    logical_strip_width: int = 120,
    monitor_res: tuple[int, int] | None = None,
    monitor_scale: float | None = None,
) -> float:
    """Calculate the average relative luminance of the left wallpaper strip.

    Handles sRGB -> linear conversion, monitor aspect-fill crop geometry,
    black, white, gradients, and returns safe fallback for missing/corrupt images.
    """
    from PIL import Image

    DEFAULT_FALLBACK = 0.20

    if not img_path:
        return DEFAULT_FALLBACK

    path = Path(img_path).expanduser().resolve()
    if not path.is_file():
        return DEFAULT_FALLBACK

    try:
        with Image.open(path) as raw_img:
            img = raw_img.convert("RGB")
    except Exception:
        return DEFAULT_FALLBACK

    w_img, h_img = img.size
    if w_img <= 0 or h_img <= 0:
        return DEFAULT_FALLBACK

    if monitor_res is not None and monitor_scale is not None:
        w_mon, h_mon = monitor_res
        scale = float(monitor_scale)
    else:
        det_w, det_h, det_scale = get_monitor_geometry()
        w_mon = monitor_res[0] if monitor_res else det_w
        h_mon = monitor_res[1] if monitor_res else det_h
        scale = monitor_scale if monitor_scale is not None else det_scale

    scale = max(0.1, scale)
    physical_strip_w = max(1, int(round(logical_strip_width * scale)))

    s = max(w_mon / float(w_img), h_mon / float(h_img))

    x0_raw = (w_img - (w_mon / s)) / 2.0
    x1_raw = x0_raw + (physical_strip_w / s)
    y0_raw = (h_img - (h_mon / s)) / 2.0
    y1_raw = y0_raw + (h_mon / s)

    x0 = max(0, min(w_img - 1, int(round(x0_raw))))
    x1 = max(x0 + 1, min(w_img, int(round(x1_raw))))
    y0 = max(0, min(h_img - 1, int(round(y0_raw))))
    y1 = max(y0 + 1, min(h_img, int(round(y1_raw))))

    strip = img.crop((x0, y0, x1, y1))
    sample_w = max(1, min(32, strip.width))
    sample_h = max(1, min(128, strip.height))

    resample_filter = getattr(Image, "Resampling", Image).BILINEAR
    sample = strip.resize((sample_w, sample_h), resample=resample_filter)

    try:
        pixels = sample.get_flattened_data()
    except AttributeError:
        pixels = sample.getdata()

    total_lum = 0.0
    count = 0
    for r, g, b in pixels:
        r_lin = srgb_to_linear(r / 255.0)
        g_lin = srgb_to_linear(g / 255.0)
        b_lin = srgb_to_linear(b / 255.0)
        y = 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
        total_lum += y
        count += 1

    if count == 0:
        return DEFAULT_FALLBACK

    return round(max(0.0, min(1.0, total_lum / count)), 4)


def generate_theme(wall_path: Path | str) -> dict[str, Any]:
    """Generate color palette tokens from wallpaper image."""
    wall_str = str(Path(wall_path).expanduser().resolve())
    h, s, _ = extract_dominant_hsv(wall_str)
    left_lum = calculate_left_strip_luminance(wall_str)
    acc_s = max(0.55, min(0.82, s * 0.95))
    acc_v = 0.96

    r, g, b = colorsys.hsv_to_rgb(h, acc_s, acc_v)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    accent_fg = "#140E14" if lum > 0.48 else "#FFFFFF"

    theme = {
        "wallpaper": wall_str,
        "leftLuminance": left_lum,
        "surface": hsv_hex(h, 0.48, 0.13, "F2"),
        "card": hsv_hex(h, 0.44, 0.20),
        "cardHover": hsv_hex(h, 0.46, 0.28),
        "track": hsv_hex(h, 0.50, 0.09),
        "border": hsv_hex(h, 0.45, 0.36),
        "brandAccent": hsv_hex(h, acc_s, acc_v),
        "brandAccentFg": accent_fg,
        "textMain": "#FFFFFF",
        "textMuted": hsv_hex(h, 0.14, 0.86),
        # Additive tokens
        "surfaceDeep": hsv_hex(h, 0.50, 0.09),
        "surfaceBase": hsv_hex(h, 0.44, 0.20),
        "surfaceHigh": hsv_hex(h, 0.46, 0.28),
        "accentPrimary": hsv_hex(h, acc_s, acc_v),
        "outlineSoft": hsv_hex(h, 0.40, 0.30),
    }
    return theme


def update_hyprland_borders(theme: dict[str, Any]) -> None:
    """Update Hyprland active and inactive window border colors."""
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    h, s, _ = extract_dominant_hsv(theme["wallpaper"])
    acc_s = max(0.55, min(0.82, s * 0.95))
    acc_v = 0.96
    b1 = hsv_hex(h, acc_s, acc_v)[1:].lower()
    b2 = hsv_hex((h + 0.08) % 1.0, acc_s, 0.92)[1:].lower()
    inact = hsv_hex(h, 0.40, 0.32)[1:].lower()

    lua = (
        "hl.config({ general = { col = { "
        'active_border = { colors = { "rgba(%see)", "rgba(%see)" }, angle = 45 }, '
        'inactive_border = "rgba(%saa)"'
        " } } })"
    ) % (b1, b2, inact)
    try:
        subprocess.run(["hyprctl", "eval", lua], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    except Exception:
        pass


def generate_lock_colors(theme: dict[str, Any]) -> str:
    """Generate hyprlock palette tokens in hyprlang configuration syntax."""
    wall_str = str(theme.get("wallpaper") or "screenshot")
    if wall_str != "screenshot" and os.path.exists(wall_str):
        h, s, _ = extract_dominant_hsv(wall_str)
    else:
        h, s, _ = 0.92, 0.45, 0.90

    acc_s = max(0.55, min(0.82, s * 0.95))
    acc_v = 0.96

    def to_hypr_rgba(h_: float, s_: float, v_: float, a_: float = 1.0) -> str:
        r, g, b = colorsys.hsv_to_rgb(h_ % 1.0, max(0.0, min(1.0, s_)), max(0.0, min(1.0, v_)))
        return f"rgba({int(r*255)}, {int(g*255)}, {int(b*255)}, {a_:.2f})"

    def hex_to_hypr_rgba(hex_val: str, a_: float = 1.0) -> str:
        c = hex_val.lstrip("#")
        if len(c) == 6:
            r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
            return f"rgba({r}, {g}, {b}, {a_:.2f})"
        elif len(c) == 8:
            r, g, b = int(c[2:4], 16), int(c[4:6], 16), int(c[6:8], 16)
            return f"rgba({r}, {g}, {b}, {a_:.2f})"
        return f"rgba(255, 255, 255, {a_:.2f})"

    muted_rgba = hex_to_hypr_rgba(str(theme.get("textMuted", "#BACAC5")), 0.85)
    subtle_rgba = hex_to_hypr_rgba(str(theme.get("textMuted", "#BACAC5")), 0.55)

    return (
        "# Generated by scripts/set_wallpaper.py — do not edit by hand.\n"
        f"$wallpaper = {wall_str}\n\n"
        "# Background / Depth\n"
        f"$colorBackdrop = {to_hypr_rgba(h, 0.50, 0.09, 0.42)}\n"
        f"$colorBackdropSolid = {to_hypr_rgba(h, 0.50, 0.09, 0.55)}\n"
        f"$colorSurface = {to_hypr_rgba(h, 0.48, 0.13, 0.72)}\n\n"
        "# Card Surfaces\n"
        f"$colorCard = {to_hypr_rgba(h, 0.44, 0.20, 0.85)}\n"
        f"$colorCardSoft = {to_hypr_rgba(h, 0.44, 0.20, 0.55)}\n"
        f"$colorCardHover = {to_hypr_rgba(h, 0.46, 0.28, 0.95)}\n\n"
        "# Primary Accent (Brand Accent)\n"
        f"$colorAccent = {to_hypr_rgba(h, acc_s, acc_v, 1.0)}\n"
        f"$colorAccentAlpha = {to_hypr_rgba(h, acc_s, acc_v, 0.30)}\n"
        f"$colorAccentBorder = {to_hypr_rgba(h, acc_s, acc_v, 0.25)}\n"
        f"$colorAccentBorderSoft = {to_hypr_rgba(h, acc_s, acc_v, 0.14)}\n"
        f"$colorAccentMuted = {to_hypr_rgba(h, acc_s, acc_v, 0.65)}\n"
        f"$colorAccentSubtle = {to_hypr_rgba(h, acc_s, acc_v, 0.06)}\n\n"
        "# Secondary Accent\n"
        f"$colorSecondary = {to_hypr_rgba((h + 0.55) % 1.0, 0.28, 0.98, 1.0)}\n"
        f"$colorSecondarySubtle = {to_hypr_rgba((h + 0.55) % 1.0, 0.28, 0.98, 0.05)}\n"
        f"$colorSecondaryAlpha = {to_hypr_rgba((h + 0.55) % 1.0, 0.28, 0.98, 0.16)}\n\n"
        "# Typography\n"
        "$colorText = rgba(223, 226, 239, 1.0)\n"
        f"$colorTextMuted = {muted_rgba}\n"
        f"$colorTextSubtle = {subtle_rgba}\n\n"
        "# Status & Validation\n"
        "$colorFail = rgba(255, 92, 119, 0.95)\n"
        f"$colorCheck = {to_hypr_rgba(h, acc_s, acc_v, 0.95)}\n"
        "$colorCaps = rgba(255, 212, 123, 0.95)\n"
    )


def write_theme_files(
    theme: dict[str, Any],
    json_path: Path | None = None,
    rofi_path: Path | None = None,
    lock_colors_path: Path | None = None,
) -> None:
    """Atomically write theme JSON, rofi colors.rasi, and hyprlock lock-colors.conf."""
    json_path = json_path or get_theme_json_path()
    rofi_path = rofi_path or get_rofi_colors_path()
    lock_colors_path = lock_colors_path or get_lock_colors_path()

    # 1. Read existing JSON if present to preserve unrelated theme fields
    existing: dict[str, Any] = {}
    if json_path.exists():
        try:
            content = json_path.read_text(encoding="utf-8")
            parsed = json.loads(content)
            if isinstance(parsed, dict):
                existing = parsed
        except Exception:
            existing = {}

    merged_theme = {**existing, **theme}

    # 2. Write gps-theme.json atomically
    json_content = json.dumps(merged_theme, indent=2) + "\n"
    atomic_write(json_path, json_content)

    # 3. Write rofi colors.rasi atomically
    rofi_dir = rofi_path.parent
    if rofi_dir.exists():
        h, s, _ = extract_dominant_hsv(theme["wallpaper"])
        acc_s = max(0.55, min(0.82, s * 0.95))
        acc_v = 0.96
        colors_rasi = (
            "/* Generated by scripts/set-wallpaper — do not edit by hand. */\n"
            "* {\n"
            f"    bg: {hsv_rgba_hex(h, 0.48, 0.13, 'F0')};\n"
            f"    card: {hsv_rgba_hex(h, 0.44, 0.20)};\n"
            f"    hover: {hsv_rgba_hex(h, 0.46, 0.28)};\n"
            f"    accent: {hsv_rgba_hex(h, acc_s, acc_v)};\n"
            f"    accent-fg: {merged_theme.get('brandAccentFg', '#140E14')}FF;\n"
            f"    text: {merged_theme.get('textMain', '#FFFFFF')}FF;\n"
            f"    muted: {merged_theme.get('textMuted', '#DBBCBC')}FF;\n"
            f"    border-col: {hsv_rgba_hex(h, 0.45, 0.36)};\n"
            "}\n"
        )
        atomic_write(rofi_path, colors_rasi)

    # 4. Write hyprlock lock-colors.conf atomically
    try:
        lock_content = generate_lock_colors(merged_theme)
        atomic_write(lock_colors_path, lock_content)
    except Exception:
        pass

    # 5. Update Hyprland border
    update_hyprland_borders(theme)


def apply_wallpaper(
    image_path: str | Path | None = None,
    *,
    restore: bool = False,
    transition_type: str = "outer",
    transition_pos: str = "0.92,0.06",
    transition_fps: int = 165,
    transition_duration: float = 1.1,
    skip_awww: bool = False,
    last_wall_path: Path | None = None,
    theme_json_path: Path | None = None,
    rofi_path: Path | None = None,
    lock_colors_path: Path | None = None,
) -> dict[str, Any]:
    """Execute the complete atomic wallpaper and theme application pipeline."""
    last_wall = last_wall_path or get_last_wall_path()

    if restore:
        if not last_wall.exists():
            return {"ok": False, "error": "No previous wallpaper recorded to restore"}
        try:
            image_path = last_wall.read_text(encoding="utf-8").strip()
        except OSError as e:
            return {"ok": False, "error": f"Failed to read last wallpaper: {e}"}
        transition_type = "none"

    if not image_path:
        image_path = get_current_wallpaper()
        if not image_path:
            return {"ok": False, "error": "No wallpaper image specified and could not detect current wallpaper"}

    path = Path(image_path).expanduser().resolve()
    if not path.is_file():
        return {"ok": False, "error": f"Wallpaper file not found: {path}"}

    if not skip_awww:
        ensure_awww_daemon()
        cmd = [
            "awww", "img", str(path),
            "--transition-type", transition_type,
        ]
        if transition_type != "none":
            cmd.extend([
                "--transition-pos", str(transition_pos),
                "--transition-fps", str(transition_fps),
                "--transition-duration", str(transition_duration),
            ])
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if res.returncode != 0:
                err_msg = (res.stderr or res.stdout or "").strip()
                return {"ok": False, "error": f"awww rejected wallpaper: {err_msg}"}
        except Exception as e:
            return {"ok": False, "error": f"Failed to execute awww: {e}"}

    # Record last-wall atomically
    try:
        atomic_write(last_wall, str(path) + "\n")
    except Exception as e:
        return {"ok": False, "error": f"Failed to write last-wall state: {e}"}

    # Extract theme and write atomically
    try:
        theme = generate_theme(path)
        write_theme_files(
            theme,
            json_path=theme_json_path,
            rofi_path=rofi_path,
            lock_colors_path=lock_colors_path,
        )
    except Exception as e:
        return {"ok": False, "error": f"Failed to extract or write theme: {e}"}

    return {"ok": True, "wallpaper": str(path), "theme": theme}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Unified wallpaper application and theme extraction pipeline")
    parser.add_argument("wallpaper", nargs="?", help="Path to wallpaper image file")
    parser.add_argument("--restore", action="store_true", help="Restore last applied wallpaper")
    parser.add_argument("--transition-type", default="outer", help="awww transition type (default: outer)")
    parser.add_argument("--transition-pos", default="0.92,0.06", help="awww transition position")
    parser.add_argument("--transition-fps", type=int, default=165, help="awww transition FPS")
    parser.add_argument("--transition-duration", type=float, default=1.1, help="awww transition duration in seconds")
    parser.add_argument("--skip-awww", action="store_true", help="Only extract and write theme without calling awww")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    res = apply_wallpaper(
        image_path=args.wallpaper,
        restore=args.restore,
        transition_type=args.transition_type,
        transition_pos=args.transition_pos,
        transition_fps=args.transition_fps,
        transition_duration=args.transition_duration,
        skip_awww=args.skip_awww,
    )

    if not res.get("ok"):
        print(f"Error: {res.get('error')}", file=sys.stderr)
        return 1

    print(f"Applied wallpaper: {res.get('wallpaper')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
