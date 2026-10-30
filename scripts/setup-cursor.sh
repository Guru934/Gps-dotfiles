#!/usr/bin/env bash
# ==============================================================================
# setup-cursor.sh - GPS Desktop User-Space Cursor Configuration Installer
# ==============================================================================
# Configures consistent cursor theme and size across:
# - Hyprland (hyprctl setcursor)
# - GTK 3 & GTK 4 (settings.ini and gsettings)
# - Qt applications (XCURSOR_THEME/SIZE, ~/.icons/default)
# - XWayland applications (~/.icons/default/index.theme)
#
# Safety rules:
# - Strictly user-space ($XDG_CONFIG_HOME, ~/.icons, ~/.local/share/icons).
# - Never touches /usr or system files.
# - Existing configurations are preserved.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(which python3 || echo "python3")"

exec "$PYTHON_BIN" "${SCRIPT_DIR}/cursor_setup.py" "$@"
