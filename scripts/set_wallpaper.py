#!/usr/bin/env python3
"""Unified wallpaper application and dynamic theme extraction pipeline."""
from __future__ import annotations

import argparse
import colorsys
import json
import os
from pathlib import Path
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


def generate_theme(wall_path: Path | str) -> dict[str, Any]:
    """Generate color palette tokens from wallpaper image."""
    wall_str = str(Path(wall_path).expanduser().resolve())
    h, s, _ = extract_dominant_hsv(wall_str)
    acc_s = max(0.55, min(0.82, s * 0.95))
    acc_v = 0.96

    r, g, b = colorsys.hsv_to_rgb(h, acc_s, acc_v)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    accent_fg = "#140E14" if lum > 0.48 else "#FFFFFF"

    theme = {
        "wallpaper": wall_str,
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


def write_theme_files(
    theme: dict[str, Any],
    json_path: Path | None = None,
    rofi_path: Path | None = None,
) -> None:
    """Atomically write theme JSON and rofi colors.rasi."""
    json_path = json_path or get_theme_json_path()
    rofi_path = rofi_path or get_rofi_colors_path()

    # 1. Write gps-theme.json atomically
    json_content = json.dumps(theme, indent=2) + "\n"
    atomic_write(json_path, json_content)

    # 2. Write rofi colors.rasi atomically
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
            f"    accent-fg: {theme['brandAccentFg']}FF;\n"
            f"    text: {theme['textMain']}FF;\n"
            f"    muted: {theme['textMuted']}FF;\n"
            f"    border-col: {hsv_rgba_hex(h, 0.45, 0.36)};\n"
            "}\n"
        )
        atomic_write(rofi_path, colors_rasi)

    # 3. Update Hyprland border
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
        write_theme_files(theme, json_path=theme_json_path, rofi_path=rofi_path)
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
