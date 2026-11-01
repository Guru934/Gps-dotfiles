#!/usr/bin/env bash
# ==============================================================================
# install.sh — GPS Desktop Safe, Idempotent User-Space Installer
# ==============================================================================
# Usage:
#   ./install.sh                # Dry-run inspection (default, 0 changes made)
#   ./install.sh --apply        # Apply installation with backup & rollback
#   ./install.sh --uninstall    # Safe uninstallation with conflict detection
#   ./install.sh --check        # Check installation status & run doctor
#
# Repository Relocation Contract:
#   The installer creates absolute symlinks to configuration files in this repo.
#   If you move or rename the repository directory, re-run './install.sh --apply'
#   from the new path to update all symlinks cleanly and idempotently.
# ==============================================================================

set -euo pipefail

# 1. Enforce safety rule: never run as root or via sudo
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    printf "\033[31m\033[1mERROR: The GPS installer must not be run as root or via sudo.\033[0m\n" >&2
    printf "It is strictly a user-space installer and modifies only user directories.\033[0m\n" >&2
    exit 1
fi

# 2. Resolve repository root dynamically from this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GPS_ROOT="$SCRIPT_DIR"

# 3. Ensure python3 is available
if ! command -v python3 >/dev/null 2>&1; then
    printf "\033[31m\033[1mERROR: python3 is required for the GPS installer.\033[0m\n" >&2
    exit 1
fi

# 4. Delegate to the installer engine
exec python3 "${SCRIPT_DIR}/scripts/installer.py" "$@"
