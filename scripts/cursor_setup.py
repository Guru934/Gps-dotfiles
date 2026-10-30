#!/usr/bin/env python3
"""GPS Desktop User-Space Cursor Configuration.

Configures consistent cursor theme and size across:
- Hyprland (via hyprctl setcursor)
- GTK 3 & GTK 4 (via settings.ini and gsettings)
- Qt applications (via XCURSOR_THEME/SIZE and ~/.icons/default/index.theme)
- XWayland applications (via ~/.icons/default/index.theme)

Safety rules:
- Strictly user-space ($XDG_CONFIG_HOME, ~/.icons, ~/.local/share/icons).
- Never modifies /usr or system-wide files.
- Preserves existing user settings in settings.ini.
- Provides fallback to Adwaita or default if the requested theme is unavailable.
"""
from __future__ import annotations

import argparse
import configparser
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

DEFAULT_CURSOR_THEME = "Adwaita"
DEFAULT_CURSOR_SIZE = 24


def get_available_cursor_themes(custom_roots: list[Path] | None = None) -> list[str]:
    """Find installed cursor themes in standard icon directories."""
    roots = custom_roots or [
        Path.home() / ".local" / "share" / "icons",
        Path.home() / ".icons",
        Path("/usr/local/share/icons"),
        Path("/usr/share/icons"),
    ]
    themes: list[str] = []
    for root in roots:
        if not root.is_dir():
            continue
        try:
            for d in root.iterdir():
                if not d.is_dir():
                    continue
                # A directory is a cursor theme if it has a cursors/ subdir or index.theme inheriting one
                if (d / "cursors").is_dir() or (d / "hyprcursors").is_dir():
                    if d.name not in themes:
                        themes.append(d.name)
                elif (d / "index.theme").is_file():
                    try:
                        content = (d / "index.theme").read_text(encoding="utf-8")
                        if "Inherits" in content and any(c in content for c in ["cursor", "Cursor", "Adwaita", "Breeze"]):
                            if d.name not in themes:
                                themes.append(d.name)
                    except OSError:
                        pass
        except OSError:
            continue
    return themes


def resolve_cursor_theme(preferred: str, custom_roots: list[Path] | None = None) -> str:
    """Resolve preferred theme or fall back to an available cursor theme."""
    available = get_available_cursor_themes(custom_roots)
    if preferred in available:
        return preferred
    if DEFAULT_CURSOR_THEME in available:
        return DEFAULT_CURSOR_THEME
    if "default" in available:
        return "default"
    return preferred or DEFAULT_CURSOR_THEME


def update_gtk_settings_ini(
    settings_path: Path,
    theme_name: str,
    size: int,
    dry_run: bool = False,
) -> bool:
    """Safely update cursor settings in a GTK settings.ini preserving existing settings."""
    config = configparser.RawConfigParser()
    if settings_path.is_file():
        try:
            config.read(str(settings_path), encoding="utf-8")
        except Exception:
            pass

    if not config.has_section("Settings"):
        config.add_section("Settings")

    # Update only cursor properties if changed
    curr_theme = config.get("Settings", "gtk-cursor-theme-name", fallback=None)
    curr_size = config.get("Settings", "gtk-cursor-theme-size", fallback=None)

    changed = (curr_theme != theme_name) or (curr_size != str(size))
    if not changed and settings_path.is_file():
        return False

    config.set("Settings", "gtk-cursor-theme-name", theme_name)
    config.set("Settings", "gtk-cursor-theme-size", str(size))

    if not config.has_option("Settings", "gtk-application-prefer-dark-theme"):
        config.set("Settings", "gtk-application-prefer-dark-theme", "1")

    if dry_run:
        return True

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    from io import StringIO
    sio = StringIO()
    config.write(sio)
    content = sio.getvalue()

    # Atomic write
    tmp = settings_path.with_name(f".{settings_path.name}.tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(settings_path)
    return True


def update_xwayland_default_theme(
    icons_default_dir: Path,
    theme_name: str,
    dry_run: bool = False,
) -> bool:
    """Write ~/.icons/default/index.theme to provide fallback for XWayland and X11 apps."""
    index_file = icons_default_dir / "index.theme"
    expected = (
        "[Icon Theme]\n"
        "Name=Default\n"
        "Comment=Default Cursor Theme\n"
        f"Inherits={theme_name}\n"
    )

    if index_file.is_file():
        try:
            current = index_file.read_text(encoding="utf-8")
            if current == expected:
                return False
        except OSError:
            pass

    if dry_run:
        return True

    icons_default_dir.mkdir(parents=True, exist_ok=True)
    tmp = index_file.with_name(f".{index_file.name}.tmp")
    tmp.write_text(expected, encoding="utf-8")
    tmp.replace(index_file)
    return True


def apply_gsettings_cursor(theme_name: str, size: int) -> None:
    """Apply cursor theme and size via gsettings if available."""
    schema = "org.gnome.desktop.interface"
    try:
        subprocess.run(
            ["gsettings", "set", schema, "cursor-theme", theme_name],
            capture_output=True,
            timeout=2,
        )
        subprocess.run(
            ["gsettings", "set", schema, "cursor-size", str(size)],
            capture_output=True,
            timeout=2,
        )
    except Exception:
        pass


def apply_hyprctl_cursor(theme_name: str, size: int) -> bool:
    """Apply cursor dynamically to Hyprland compositor if running."""
    try:
        res = subprocess.run(
            ["hyprctl", "setcursor", theme_name, str(size)],
            capture_output=True,
            text=True,
            timeout=2,
        )
        return res.returncode == 0 and "ok" in (res.stdout or "").lower()
    except Exception:
        return False


def setup_cursor(
    theme: str = DEFAULT_CURSOR_THEME,
    size: int = DEFAULT_CURSOR_SIZE,
    config_dir: Path | None = None,
    icons_dir: Path | None = None,
    dry_run: bool = False,
    apply_live: bool = True,
) -> dict[str, Any]:
    """Configure unified cursor across user-space destinations."""
    resolved_theme = resolve_cursor_theme(theme)

    cfg_root = config_dir or Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    icn_root = icons_dir or (Path.home() / ".icons")

    gtk3_path = cfg_root / "gtk-3.0" / "settings.ini"
    gtk4_path = cfg_root / "gtk-4.0" / "settings.ini"
    x11_default_dir = icn_root / "default"

    gtk3_updated = update_gtk_settings_ini(gtk3_path, resolved_theme, size, dry_run=dry_run)
    gtk4_updated = update_gtk_settings_ini(gtk4_path, resolved_theme, size, dry_run=dry_run)
    x11_updated = update_xwayland_default_theme(x11_default_dir, resolved_theme, dry_run=dry_run)

    hypr_applied = False
    if apply_live and not dry_run:
        apply_gsettings_cursor(resolved_theme, size)
        hypr_applied = apply_hyprctl_cursor(resolved_theme, size)

    return {
        "ok": True,
        "requested_theme": theme,
        "resolved_theme": resolved_theme,
        "size": size,
        "gtk3_updated": gtk3_updated,
        "gtk4_updated": gtk4_updated,
        "x11_updated": x11_updated,
        "hyprctl_applied": hypr_applied,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Configure unified cursor theme and size for GPS Desktop")
    parser.add_argument("--theme", default=DEFAULT_CURSOR_THEME, help=f"Cursor theme name (default: {DEFAULT_CURSOR_THEME})")
    parser.add_argument("--size", type=int, default=DEFAULT_CURSOR_SIZE, help=f"Cursor size (default: {DEFAULT_CURSOR_SIZE})")
    parser.add_argument("--config-dir", type=Path, default=None, help="Target XDG_CONFIG_HOME directory")
    parser.add_argument("--icons-dir", type=Path, default=None, help="Target ~/.icons directory")
    parser.add_argument("--dry-run", action="store_true", help="Inspect planned changes without writing")
    parser.add_argument("--no-live", action="store_true", help="Skip live hyprctl/gsettings updates")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    res = setup_cursor(
        theme=args.theme,
        size=args.size,
        config_dir=args.config_dir,
        icons_dir=args.icons_dir,
        dry_run=args.dry_run,
        apply_live=not args.no_live,
    )

    print(
        f"Cursor configured: theme='{res['resolved_theme']}', size={res['size']} "
        f"(hyprctl={'yes' if res['hyprctl_applied'] else 'deferred'}, dry_run={args.dry_run})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
