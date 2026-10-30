#!/usr/bin/env python3
"""GPS User-Space Icon Theme Generator.

Creates and synchronizes ~/.local/share/icons/GPS-Icons:
- Inherits from Papirus-Dark (or best detected installed theme)
- Overrides places/ folder icons with current GPS wallpaper accent
- Preserves original SVG geometry and valid SVG syntax
- Uses atomic directory replacement and temporary staging
- Fast no-op path when accent has not changed
- Generates valid index.theme and updates gtk icon cache
- Preserves user settings across GTK and Qt
"""
from __future__ import annotations

import colorsys
import configparser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any

# Add parent directory for theme_common
script_dir = Path(__file__).resolve().parent
if str(script_dir) not in sys.path:
    sys.path.insert(0, str(script_dir))

import theme_common

THEME_NAME = "GPS-Icons"
PREFERRED_BASE_THEMES = ["Papirus-Dark", "Papirus", "breeze-dark", "breeze", "Adwaita", "hicolor"]
STANDARD_PLACES_DIRS = [
    ("16x16/places", 16),
    ("22x22/places", 22),
    ("24x24/places", 24),
    ("32x32/places", 32),
    ("48x48/places", 48),
    ("64x64/places", 64),
]

# Minimal safe fallback SVG when base theme places cannot be found
MINIMAL_FOLDER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
 <path style="fill:{back}" d="M 4,34 C 4,35.108 4.892,36 6,36 H 42 C 43.108,36 44,35.108 44,34 V 12 C 44,10.892 43.108,10 42,10 H 24 C 21,10 20,6 17,6 H 6 C 4.892,6 4,6.892 4,8"/>
 <rect style="fill:#e4e4e4" width="36" height="16" x="6" y="13" rx="2" ry="2"/>
 <rect style="fill:{front}" width="40" height="26" x="4" y="16" rx="2" ry="2"/>
</svg>"""


def get_default_icon_roots() -> list[Path]:
    """Return standard Freedesktop icon search roots in priority order."""
    data_home = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
    roots = [
        data_home / "icons",
        Path.home() / ".icons",
        Path("/usr/local/share/icons"),
        Path("/usr/share/icons"),
    ]
    return [r for r in roots if r.is_dir()]


def detect_base_icon_theme(custom_roots: list[Path] | None = None) -> tuple[str, Path | None]:
    """Detect the best installed base icon theme, preferring Papirus-Dark."""
    roots = custom_roots if custom_roots is not None else get_default_icon_roots()
    for preferred in PREFERRED_BASE_THEMES:
        for root in roots:
            candidate = root / preferred
            if candidate.is_dir() and (candidate / "index.theme").is_file():
                return preferred, candidate
    return "hicolor", None


def compute_folder_shades(accent_hex: str) -> tuple[str, str, str]:
    """Compute front, back, and glyph colors in #RRGGBB format from an accent color."""
    r, g, b = theme_common.parse_hex_color(accent_hex)
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    h, l, s = colorsys.rgb_to_hls(rf, gf, bf)

    # Front flap: normalized input accent
    front_hex = f"#{r:02x}{g:02x}{b:02x}"

    # Back flap: darker shade of same hue (~20% darker)
    l_back = max(0.08, l * 0.80)
    s_back = min(1.0, s * 1.05)
    rb, gb, bb = colorsys.hls_to_rgb(h, l_back, s_back)
    back_hex = f"#{int(round(rb * 255)):02x}{int(round(gb * 255)):02x}{int(round(bb * 255)):02x}"

    # Emblem/glyph: high-contrast dark or light shade
    if l >= 0.40:
        l_glyph = max(0.06, l * 0.25)
        s_glyph = min(1.0, s * 0.85)
    else:
        l_glyph = min(0.95, l + 0.55)
        s_glyph = min(1.0, s * 0.70)
    rg, gg, bg = colorsys.hls_to_rgb(h, l_glyph, s_glyph)
    glyph_hex = f"#{int(round(rg * 255)):02x}{int(round(gg * 255)):02x}{int(round(bg * 255)):02x}"

    return front_hex, back_hex, glyph_hex


def recolor_svg_content(svg_text: str, front_hex: str, back_hex: str, glyph_hex: str) -> str:
    """Recolor Papirus/standard folder SVG text preserving geometry and XML structure."""
    res = svg_text

    # Standard Papirus blue colors
    # Front flap: #5294e2
    res = re.sub(r"#5294e2", front_hex, res, flags=re.IGNORECASE)
    # Back flap: #4877b1
    res = re.sub(r"#4877b1", back_hex, res, flags=re.IGNORECASE)
    # Glyph / emblem: #1d344f
    res = re.sub(r"#1d344f", glyph_hex, res, flags=re.IGNORECASE)

    # 16x16 symbolic highlights
    res = re.sub(r"#4285f4", front_hex, res, flags=re.IGNORECASE)

    # For 16x16 single-color paths using fill:currentColor or #444444
    if 'width="16"' in res and 'height="16"' in res:
        res = re.sub(r'style="fill:currentColor"', f'style="fill:{front_hex}"', res)
        res = re.sub(r'\.ColorScheme-Text\s*\{\s*color:#444444;\s*\}', f'.ColorScheme-Text {{ color:{front_hex}; }}', res)

    return res


def generate_index_theme(base_theme: str, directories: list[tuple[str, int]]) -> str:
    """Generate a valid Freedesktop index.theme string with inheritance."""
    inherits = [base_theme]
    if "hicolor" not in inherits:
        inherits.append("hicolor")
    inherits_str = ",".join(inherits)

    dir_list = ",".join([d[0] for d in directories])
    lines = [
        "[Icon Theme]",
        f"Name={THEME_NAME}",
        "Comment=GPS wallpaper-adaptive folder icons",
        f"Inherits={inherits_str}",
        f"Directories={dir_list}",
        "",
    ]
    for dir_name, size in directories:
        lines.append(f"[{dir_name}]")
        lines.append("Context=Places")
        lines.append(f"Size={size}")
        lines.append("Type=Fixed")
        lines.append("")

    return "\n".join(lines)


def update_gtk_icon_theme(config_dir: Path, icon_theme: str = THEME_NAME) -> None:
    """Ensure gtk-icon-theme-name is set to GPS-Icons in gtk-3.0 and gtk-4.0 settings.ini."""
    for gtk_ver in ["gtk-3.0", "gtk-4.0"]:
        settings_file = config_dir / gtk_ver / "settings.ini"
        config = configparser.RawConfigParser()
        if settings_file.is_file():
            try:
                config.read(str(settings_file), encoding="utf-8")
            except Exception:
                pass

        if not config.has_section("Settings"):
            config.add_section("Settings")

        curr_icon = config.get("Settings", "gtk-icon-theme-name", fallback=None)
        if curr_icon != icon_theme:
            config.set("Settings", "gtk-icon-theme-name", icon_theme)
            theme_common.backup_file_once(settings_file)
            from io import StringIO
            sio = StringIO()
            config.write(sio)
            theme_common.atomic_write(settings_file, sio.getvalue())


def update_qt6ct_icon_theme(qt6ct_conf_path: Path, icon_theme: str = THEME_NAME) -> None:
    """Update icon_theme under [Appearance] in qt6ct.conf if present."""
    if not qt6ct_conf_path.is_file():
        return

    config = configparser.RawConfigParser()
    try:
        config.read(str(qt6ct_conf_path), encoding="utf-8")
    except Exception:
        return

    if not config.has_section("Appearance"):
        config.add_section("Appearance")

    curr = config.get("Appearance", "icon_theme", fallback=None)
    if curr != icon_theme:
        config.set("Appearance", "icon_theme", icon_theme)
        from io import StringIO
        sio = StringIO()
        config.write(sio)
        theme_common.atomic_write(qt6ct_conf_path, sio.getvalue())


def set_gsettings_icon_theme(icon_theme: str = THEME_NAME) -> None:
    """Apply icon theme via gsettings if running in a desktop session."""
    try:
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", icon_theme],
            capture_output=True,
            timeout=2,
        )
    except Exception:
        pass


def run_gtk_update_icon_cache(theme_dir: Path) -> bool:
    """Execute gtk-update-icon-cache on the theme directory."""
    try:
        res = subprocess.run(
            ["gtk-update-icon-cache", "-f", "-t", str(theme_dir)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return res.returncode == 0
    except Exception:
        return False


def generate_gps_icon_theme(
    palette_path: Path | str,
    target_icons_root: Path | None = None,
    custom_icon_roots: list[Path] | None = None,
    state_dir: Path | None = None,
    config_dir: Path | None = None,
    force: bool = False,
) -> dict[str, Any]:
    """Execute complete atomic GPS icon theme generation pipeline."""
    pal_p = Path(palette_path).expanduser().resolve()
    theme, is_valid = theme_common.load_and_validate_palette(pal_p)

    raw_accent = theme.get("brandAccent") or theme.get("accentPrimary") or "#2DD4BF"
    try:
        accent_hex = theme_common.to_hex6(raw_accent)
    except Exception:
        accent_hex = "#2DD4BF"

    # State file for no-op detection
    sdir = state_dir or (Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state")) / "gps")
    accent_state_file = sdir / "last-icon-accent.txt"

    # Target directory
    data_home = target_icons_root or Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share")) / "icons"
    target_theme_dir = data_home / THEME_NAME

    # Quick no-op path: if accent is identical and index.theme + cache exist
    if not force and accent_state_file.is_file() and (target_theme_dir / "index.theme").is_file():
        try:
            last_accent = accent_state_file.read_text(encoding="utf-8").strip()
            if last_accent.lower() == accent_hex.lower():
                return {
                    "ok": True,
                    "recolored": False,
                    "reason": "Accent unchanged (no-op)",
                    "accent": accent_hex,
                    "target": str(target_theme_dir),
                }
        except OSError:
            pass

    # Compute color shades
    front_hex, back_hex, glyph_hex = compute_folder_shades(accent_hex)

    # Detect base theme
    base_theme_name, base_theme_path = detect_base_icon_theme(custom_icon_roots)

    # Use atomic staging directory on the same filesystem
    target_theme_dir.parent.mkdir(parents=True, exist_ok=True)
    staging_dir = Path(tempfile.mkdtemp(dir=str(target_theme_dir.parent), prefix=".GPS-Icons.tmp-"))

    generated_dirs: list[tuple[str, int]] = []
    total_recolored = 0

    try:
        if base_theme_path and base_theme_path.is_dir():
            # Source can be Papirus or Papirus-Dark; check for places directories
            for dir_rel, size in STANDARD_PLACES_DIRS:
                src_places = base_theme_path / dir_rel
                # If directory doesn't exist directly (e.g. Papirus-Dark symlinks to Papirus), resolve it
                if not src_places.exists():
                    parent_src = base_theme_path.parent / "Papirus" / dir_rel
                    if parent_src.exists():
                        src_places = parent_src

                if not src_places.is_dir():
                    continue

                dest_places = staging_dir / dir_rel
                dest_places.mkdir(parents=True, exist_ok=True)

                # Collect files to recolor and symlinks
                blue_files: dict[str, Path] = {}
                symlinks: dict[str, str] = {}

                for entry in src_places.iterdir():
                    name = entry.name
                    if entry.is_symlink():
                        target_name = os.readlink(entry)
                        if "blue" in target_name or "folder" in name or "user" in name or name == "desktop.svg":
                            symlinks[name] = target_name
                    elif entry.is_file():
                        if name.startswith("folder-blue") or name.startswith("user-blue") or (dir_rel.startswith("16x16") and name.startswith("folder")):
                            blue_files[name] = entry

                # Write recolored SVGs
                for fname, src_file in blue_files.items():
                    try:
                        raw_svg = src_file.read_text(encoding="utf-8")
                        recolored = recolor_svg_content(raw_svg, front_hex, back_hex, glyph_hex)
                        (dest_places / fname).write_text(recolored, encoding="utf-8")
                        total_recolored += 1
                    except OSError:
                        pass

                # Create relative symlinks
                for link_name, target in symlinks.items():
                    dest_link = dest_places / link_name
                    if not dest_link.exists():
                        try:
                            dest_link.symlink_to(target)
                        except OSError:
                            pass

                # Ensure canonical folder.svg exists in this places dir
                if not (dest_places / "folder.svg").exists():
                    if (dest_places / "folder-blue.svg").exists():
                        try:
                            (dest_places / "folder.svg").symlink_to("folder-blue.svg")
                        except OSError:
                            pass
                    elif blue_files:
                        first_blue = next(iter(blue_files.keys()))
                        try:
                            (dest_places / "folder.svg").symlink_to(first_blue)
                        except OSError:
                            pass

                generated_dirs.append((dir_rel, size))

        # Fallback if no places directories were processed
        if not generated_dirs:
            fallback_dir = staging_dir / "48x48/places"
            fallback_dir.mkdir(parents=True, exist_ok=True)
            svg_content = MINIMAL_FOLDER_SVG.format(front=front_hex, back=back_hex)
            (fallback_dir / "folder.svg").write_text(svg_content, encoding="utf-8")
            try:
                (fallback_dir / "folder-open.svg").symlink_to("folder.svg")
            except OSError:
                pass
            generated_dirs.append(("48x48/places", 48))
            total_recolored = 1

        # Write index.theme
        index_content = generate_index_theme(base_theme_name, generated_dirs)
        (staging_dir / "index.theme").write_text(index_content, encoding="utf-8")

        # Update gtk icon cache on the staging dir
        run_gtk_update_icon_cache(staging_dir)

        # Atomic replacement of target theme directory
        if target_theme_dir.exists():
            shutil.rmtree(target_theme_dir)
        staging_dir.rename(target_theme_dir)

        # Record accent state atomically
        theme_common.atomic_write(accent_state_file, f"{accent_hex}\n")

    except Exception:
        if staging_dir.exists():
            try:
                shutil.rmtree(staging_dir)
            except OSError:
                pass
        raise

    # Synchronize GTK settings and gsettings
    cfg_root = config_dir or Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    update_gtk_icon_theme(cfg_root, THEME_NAME)
    set_gsettings_icon_theme(THEME_NAME)

    # Update qt6ct if configuration exists
    qt6ct_file = cfg_root / "qt6ct" / "qt6ct.conf"
    update_qt6ct_icon_theme(qt6ct_file, THEME_NAME)

    return {
        "ok": True,
        "recolored": True,
        "base_theme": base_theme_name,
        "accent": accent_hex,
        "front": front_hex,
        "back": back_hex,
        "glyph": glyph_hex,
        "total_files": total_recolored,
        "directories": [d[0] for d in generated_dirs],
        "target": str(target_theme_dir),
    }


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print(f"Usage: {sys.argv[0]} <path-to-gps-theme.json>", file=sys.stderr)
        return 1

    palette_file = Path(args[0]).expanduser().resolve()
    try:
        res = generate_gps_icon_theme(palette_file)
        if res.get("recolored"):
            print(
                f"Generated {THEME_NAME} with accent {res['accent']} "
                f"({res['total_files']} SVGs, base={res['base_theme']})"
            )
        else:
            print(f"{THEME_NAME} theme is up to date ({res.get('reason')})")
        return 0
    except Exception as e:
        print(f"Error generating {THEME_NAME}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
