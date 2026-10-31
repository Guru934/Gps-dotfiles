#!/usr/bin/env bash
# ==============================================================================
# setup-uwsm.sh - GPS Desktop User-Space UWSM Environment Setup
# ==============================================================================
# Installs dots/uwsm/env into user configuration (~/.config/uwsm/env).
#
# Safety rules:
# - User-space only ($XDG_CONFIG_HOME/uwsm or ~/.config/uwsm).
# - Never touches system files or guru account.
# - Re-running on an already-linked config is an idempotent no-op.
# - If a conflicting file or different symlink exists, preserves it and reports
#   the conflict rather than overwriting.
# - Supports --dry-run for inspection and --dest-dir for custom test roots.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ENV="${REPO_ROOT}/dots/uwsm/env"

DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm"
DRY_RUN=false

show_help() {
    cat <<EOF
Usage: setup-uwsm.sh [OPTIONS]

Options:
  --dest-dir <path>   Target uwsm directory (default: ~/.config/uwsm)
  --dry-run           Print planned actions without modifying files
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

if [[ ! -f "$SOURCE_ENV" ]]; then
    echo "ERROR: Source configuration not found: $SOURCE_ENV" >&2
    exit 1
fi

DEST_FILE="${DEST_DIR}/env"

echo "=== GPS Desktop UWSM Environment Setup ==="
echo "Source:      $SOURCE_ENV"
echo "Destination: $DEST_FILE"
echo "Dry run:     $DRY_RUN"

# 1. Detect an existing correct symlink and leave it unchanged
if [[ -L "$DEST_FILE" ]]; then
    CURRENT_TARGET="$(readlink -f "$DEST_FILE" 2>/dev/null || true)"
    SOURCE_CANONICAL="$(readlink -f "$SOURCE_ENV" 2>/dev/null || true)"
    if [[ "$CURRENT_TARGET" == "$SOURCE_CANONICAL" ]]; then
        echo "OK: $DEST_FILE is already linked to $SOURCE_ENV (up to date)."
        exit 0
    fi
fi

# 2. If a conflicting file or different symlink exists, preserve it and report conflict
if [[ -e "$DEST_FILE" || -L "$DEST_FILE" ]]; then
    echo "Conflict: Existing file or different symlink at $DEST_FILE. Preserving existing configuration without overwriting." >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would ensure directory: $DEST_DIR"
    echo "[DRY-RUN] Would symlink $SOURCE_ENV -> $DEST_FILE"
    echo "[DRY-RUN] Completed without modifying files."
    exit 0
fi

# 3. Create destination directory
mkdir -p "$DEST_DIR"

# 4. Create symlink
ln -s "$SOURCE_ENV" "$DEST_FILE"
echo "Linked $DEST_FILE -> $SOURCE_ENV"

echo "=== UWSM environment setup completed successfully ==="
