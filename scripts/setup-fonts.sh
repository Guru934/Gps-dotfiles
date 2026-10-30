#!/usr/bin/env bash
# ==============================================================================
# setup-fonts.sh - GPS Desktop User-Space Font Configuration Installer
# ==============================================================================
# Installs dots/fontconfig/fonts.conf into user configuration.
#
# Safety rules:
# - User-space only ($XDG_CONFIG_HOME/fontconfig or ~/.config/fontconfig).
# - Never touches /etc/fonts or system files.
# - Existing configurations are backed up to fonts.conf.bak.<timestamp>.
# - Re-running on an already-linked config is an idempotent no-op.
# - Supports --dry-run for inspection and --dest-dir for custom test roots.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_CONF="${REPO_ROOT}/dots/fontconfig/fonts.conf"

DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
DRY_RUN=false
UPDATE_CACHE=true

show_help() {
    cat <<EOF
Usage: setup-fonts.sh [OPTIONS]

Options:
  --dest-dir <path>   Target fontconfig directory (default: ~/.config/fontconfig)
  --dry-run           Print planned actions without modifying files
  --no-cache          Skip running fc-cache after installation
  -h, --help          Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest-dir)
            DEST_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-cache)
            UPDATE_CACHE=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "$SOURCE_CONF" ]]; then
    echo "ERROR: Source configuration not found: $SOURCE_CONF" >&2
    exit 1
fi

DEST_CONF="${DEST_DIR}/fonts.conf"

echo "=== GPS Desktop Font Configuration Setup ==="
echo "Source:      $SOURCE_CONF"
echo "Destination: $DEST_CONF"
echo "Dry run:     $DRY_RUN"

# 1. Check if already properly linked
if [[ -L "$DEST_CONF" ]]; then
    CURRENT_TARGET="$(readlink -f "$DEST_CONF" 2>/dev/null || true)"
    SOURCE_CANONICAL="$(readlink -f "$SOURCE_CONF" 2>/dev/null || true)"
    if [[ "$CURRENT_TARGET" == "$SOURCE_CANONICAL" ]]; then
        echo "OK: $DEST_CONF is already linked to $SOURCE_CONF (up to date)."
        exit 0
    fi
fi

# 2. Plan backup if destination already exists and is not our symlink
BACKUP_PATH=""
if [[ -e "$DEST_CONF" || -L "$DEST_CONF" ]]; then
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_PATH="${DEST_CONF}.bak.${TIMESTAMP}"
    echo "Notice: Existing fonts.conf will be backed up to: $BACKUP_PATH"
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would ensure directory: $DEST_DIR"
    if [[ -n "$BACKUP_PATH" ]]; then
        echo "[DRY-RUN] Would move $DEST_CONF -> $BACKUP_PATH"
    fi
    echo "[DRY-RUN] Would symlink $SOURCE_CONF -> $DEST_CONF"
    if [[ "$UPDATE_CACHE" == true ]]; then
        echo "[DRY-RUN] Would run fc-cache to refresh font cache"
    fi
    echo "[DRY-RUN] Completed without modifying files."
    exit 0
fi

# 3. Create destination directory
mkdir -p "$DEST_DIR"

# 4. Perform backup if necessary
if [[ -n "$BACKUP_PATH" ]]; then
    mv "$DEST_CONF" "$BACKUP_PATH"
    echo "Backed up previous configuration to: $BACKUP_PATH"
fi

# 5. Create symlink
ln -s "$SOURCE_CONF" "$DEST_CONF"
echo "Linked $DEST_CONF -> $SOURCE_CONF"

# 6. Refresh font cache
if [[ "$UPDATE_CACHE" == true ]] && command -v fc-cache >/dev/null 2>&1; then
    echo "Refreshing fontconfig cache..."
    fc-cache -f "$DEST_DIR" >/dev/null 2>&1 || true
fi

echo "=== Font setup completed successfully ==="
