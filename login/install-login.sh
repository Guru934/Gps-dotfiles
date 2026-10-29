#!/usr/bin/env bash
# GPS Desktop Login Theme Installer & Lifecycle Manager
#
# Safe, idempotent installer for the GPS SDDM login theme.
# Defaults to dry-run mode. Requires explicit --apply to make changes.
# Supports isolated testing via --root-dir or environment overrides.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_THEME_DIR="${SCRIPT_DIR}/theme"

# Configuration defaults
ROOT_DIR="${GPS_INSTALL_ROOT:-}"
ETC_DIR="${GPS_ETC_DIR:-${ROOT_DIR}/etc}"
SHARE_DIR="${GPS_SHARE_DIR:-${ROOT_DIR}/usr/share}"
BACKUP_BASE_DIR="${GPS_BACKUP_DIR:-${ROOT_DIR}/var/backups/gps-login}"

MODE="dry-run" # Default mode is always dry-run
ROLLBACK_TARGET=""
THEME_NAME="gps"
DROPIN_FILENAME="99-gps-theme.conf"

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install, inspect, or roll back the GPS SDDM login screen theme package.
DEFAULTS TO DRY-RUN. No system changes are made unless --apply is passed.

Modes:
  --dry-run             Simulate installation and print actions (default)
  --apply               Execute installation (requires elevated privileges for system paths)
  --rollback [PATH]     Revert to previous login configuration using latest or specified backup
  --status              Check current installation and theme configuration status
  --help, -h            Show this help message

Options for isolated testing / custom targets:
  --root-dir PATH       Set filesystem root prefix (e.g. temporary directory for tests)
  --etc-dir PATH        Override /etc destination directory
  --share-dir PATH      Override /usr/share destination directory
  --backup-dir PATH     Override /var/backups/gps-login directory

Safety guarantees:
  - Default mode is dry-run.
  - Never touches PAM or authentication files.
  - Never deletes existing default or user themes.
  - Uses drop-in configuration (/etc/sddm.conf.d/${DROPIN_FILENAME}) for non-destructive overrides.
  - Creates timestamped backups with manifests before writing files.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --rollback)
            MODE="rollback"
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                ROLLBACK_TARGET="$2"
                shift
            fi
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --root-dir)
            ROOT_DIR="$2"
            ETC_DIR="${ROOT_DIR}/etc"
            SHARE_DIR="${ROOT_DIR}/usr/share"
            BACKUP_BASE_DIR="${ROOT_DIR}/var/backups/gps-login"
            shift 2
            ;;
        --etc-dir)
            ETC_DIR="$2"
            shift 2
            ;;
        --share-dir)
            SHARE_DIR="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# Validate source package
if [[ ! -d "${SOURCE_THEME_DIR}" || ! -f "${SOURCE_THEME_DIR}/metadata.desktop" ]]; then
    echo "Error: GPS theme source not found at '${SOURCE_THEME_DIR}'" >&2
    exit 1
fi

DEST_THEME_DIR="${SHARE_DIR}/sddm/themes/${THEME_NAME}"
DEST_CONF_DIR="${ETC_DIR}/sddm.conf.d"
DEST_CONF_FILE="${DEST_CONF_DIR}/${DROPIN_FILENAME}"

# Detect Display Manager
detect_display_manager() {
    local dm="unknown"
    if [[ -x "/usr/bin/sddm-greeter-qt6" || -x "/usr/bin/sddm-greeter" || -d "${SHARE_DIR}/sddm" || -d "${ETC_DIR}/sddm.conf.d" ]]; then
        dm="sddm"
    fi
    echo "${dm}"
}

DM="$(detect_display_manager)"
if [[ "${DM}" != "sddm" ]]; then
    echo "Warning: Supported display manager (SDDM) was not detected in target environment."
fi

# Status check
do_status() {
    echo "=== GPS Login Screen Status ==="
    echo "Target Display Manager : ${DM}"
    echo "Theme Destination      : ${DEST_THEME_DIR}"
    echo "Drop-in Configuration  : ${DEST_CONF_FILE}"
    echo "Backup Directory       : ${BACKUP_BASE_DIR}"
    echo ""

    local theme_installed=false
    local dropin_active=false

    if [[ -d "${DEST_THEME_DIR}" && -f "${DEST_THEME_DIR}/metadata.desktop" ]]; then
        theme_installed=true
        echo "[✓] GPS theme files are present in ${DEST_THEME_DIR}"
    else
        echo "[ ] GPS theme files are NOT installed"
    fi

    if [[ -f "${DEST_CONF_FILE}" ]]; then
        dropin_active=true
        echo "[✓] GPS drop-in configuration is active (${DEST_CONF_FILE})"
        echo "    Contents:"
        sed 's/^/      /' "${DEST_CONF_FILE}"
    else
        echo "[ ] GPS drop-in configuration is NOT active"
    fi

    if [[ "${theme_installed}" == true && "${dropin_active}" == true ]]; then
        echo ""
        echo "Overall Status: GPS Login Theme is ACTIVE"
    elif [[ "${theme_installed}" == true ]]; then
        echo ""
        echo "Overall Status: GPS Login Theme is INSTALLED but INACTIVE (drop-in missing)"
    else
        echo ""
        echo "Overall Status: GPS Login Theme is NOT INSTALLED (Package is unapplied)"
    fi

    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        echo ""
        echo "Available backups:"
        find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | sort -r | head -n 5 | sed 's/^/  - /'
    fi
}

# Dry-run execution
do_dry_run() {
    echo "=== GPS Login Screen Installation Plan (DRY-RUN) ==="
    echo "No files will be modified. Run with --apply to execute."
    echo ""
    echo "Source package     : ${SOURCE_THEME_DIR}"
    echo "Target display mgr : ${DM}"
    echo "Theme destination  : ${DEST_THEME_DIR}"
    echo "Drop-in config     : ${DEST_CONF_FILE}"
    echo "Backup root        : ${BACKUP_BASE_DIR}"
    echo ""

    # Check if already installed and matching
    local already_installed=false
    if [[ -d "${DEST_THEME_DIR}" && -f "${DEST_CONF_FILE}" ]]; then
        if diff -rq "${SOURCE_THEME_DIR}" "${DEST_THEME_DIR}" >/dev/null 2>&1; then
            if grep -q "Current=${THEME_NAME}" "${DEST_CONF_FILE}" 2>/dev/null; then
                already_installed=true
            fi
        fi
    fi

    if [[ "${already_installed}" == true ]]; then
        echo "Status: Theme and drop-in configuration are already up-to-date (Idempotent)."
        echo "Action: No actions needed."
        return 0
    fi

    echo "Planned Actions:"
    if [[ -d "${DEST_THEME_DIR}" || -f "${DEST_CONF_FILE}" ]]; then
        echo "  1. Create timestamped backup under ${BACKUP_BASE_DIR}/backup-<timestamp>/"
        [[ -d "${DEST_THEME_DIR}" ]] && echo "     - Back up existing ${DEST_THEME_DIR}"
        [[ -f "${DEST_CONF_FILE}" ]] && echo "     - Back up existing ${DEST_CONF_FILE}"
    else
        echo "  1. Record clean installation manifest under ${BACKUP_BASE_DIR}/backup-<timestamp>/"
    fi

    echo "  2. Create directory: ${SHARE_DIR}/sddm/themes"
    echo "  3. Copy theme package to: ${DEST_THEME_DIR}"
    echo "  4. Create directory: ${DEST_CONF_DIR}"
    echo "  5. Write drop-in configuration: ${DEST_CONF_FILE}"
    echo "     ---"
    echo "     [Theme]"
    echo "     Current=${THEME_NAME}"
    echo "     ---"
    echo "  6. Create/update symlink: ${BACKUP_BASE_DIR}/latest"
    echo ""
    echo "Safety check:"
    echo "  - PAM configuration: UNTOUCHED"
    echo "  - Existing themes (/usr/share/sddm/themes/caelestia, etc.): UNTOUCHED"
    echo "  - Main /etc/sddm.conf: UNTOUCHED"
    echo ""
    echo "DRY-RUN COMPLETE: 0 changes made."
}

# Apply installation
do_apply() {
    # Check permissions if targeting real system paths
    if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        if [[ "${EUID}" -ne 0 ]]; then
            echo "Error: Applying changes to system paths requires root privileges." >&2
            echo "Please run: sudo $0 --apply" >&2
            exit 1
        fi
    fi

    echo "=== Applying GPS Login Screen Theme ==="

    # Check if already up-to-date (Idempotent check)
    if [[ -d "${DEST_THEME_DIR}" && -f "${DEST_CONF_FILE}" ]]; then
        if diff -rq "${SOURCE_THEME_DIR}" "${DEST_THEME_DIR}" >/dev/null 2>&1; then
            if grep -q "Current=${THEME_NAME}" "${DEST_CONF_FILE}" 2>/dev/null; then
                echo "Theme files and drop-in configuration are already installed and identical."
                echo "Installation is idempotent: no changes required."
                return 0
            fi
        fi
    fi

    # Create backup directory
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_BASE_DIR}/backup_${timestamp}"
    mkdir -p "${backup_dir}"

    local had_theme=false
    local had_conf=false

    if [[ -d "${DEST_THEME_DIR}" ]]; then
        had_theme=true
        echo "Backing up pre-existing theme to ${backup_dir}/theme_backup..."
        cp -a "${DEST_THEME_DIR}" "${backup_dir}/theme_backup"
    fi

    if [[ -f "${DEST_CONF_FILE}" ]]; then
        had_conf=true
        echo "Backing up pre-existing drop-in config to ${backup_dir}/${DROPIN_FILENAME}..."
        cp -a "${DEST_CONF_FILE}" "${backup_dir}/${DROPIN_FILENAME}"
    fi

    # Write manifest
    cat << EOF > "${backup_dir}/manifest.json"
{
  "timestamp": "${timestamp}",
  "theme_name": "${THEME_NAME}",
  "dest_theme_dir": "${DEST_THEME_DIR}",
  "dest_conf_file": "${DEST_CONF_FILE}",
  "had_preexisting_theme": ${had_theme},
  "had_preexisting_conf": ${had_conf}
}
EOF

    # Update latest symlink
    ln -sfn "backup_${timestamp}" "${BACKUP_BASE_DIR}/latest"

    # Install theme files
    echo "Installing theme files to ${DEST_THEME_DIR}..."
    mkdir -p "$(dirname "${DEST_THEME_DIR}")"
    rm -rf "${DEST_THEME_DIR}"
    cp -a "${SOURCE_THEME_DIR}" "${DEST_THEME_DIR}"

    # Install drop-in configuration
    echo "Writing drop-in configuration to ${DEST_CONF_FILE}..."
    mkdir -p "${DEST_CONF_DIR}"
    cat << EOF > "${DEST_CONF_FILE}"
# GPS Desktop Theme Drop-In Configuration
# Managed by gps-login installer. Safe to remove or edit.
[Theme]
Current=${THEME_NAME}
EOF

    echo "Installation completed successfully."
    echo "Backup saved at: ${backup_dir}"
}

# Rollback installation
do_rollback() {
    # Check permissions if targeting real system paths
    if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        if [[ "${EUID}" -ne 0 ]]; then
            echo "Error: Rollback on system paths requires root privileges." >&2
            echo "Please run: sudo $0 --rollback" >&2
            exit 1
        fi
    fi

    local backup_dir=""
    if [[ -n "${ROLLBACK_TARGET}" ]]; then
        backup_dir="${ROLLBACK_TARGET}"
    elif [[ -L "${BACKUP_BASE_DIR}/latest" ]]; then
        backup_dir="$(readlink -f "${BACKUP_BASE_DIR}/latest")"
    elif [[ -d "${BACKUP_BASE_DIR}" ]]; then
        backup_dir="$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | sort -r | head -n 1)"
    fi

    echo "=== Rolling Back GPS Login Screen Theme ==="

    if [[ -n "${backup_dir}" && -f "${backup_dir}/manifest.json" ]]; then
        echo "Using backup manifest from: ${backup_dir}"
        local had_theme
        local had_conf
        had_theme="$(grep '"had_preexisting_theme":' "${backup_dir}/manifest.json" | grep -o 'true\|false')"
        had_conf="$(grep '"had_preexisting_conf":' "${backup_dir}/manifest.json" | grep -o 'true\|false')"

        # Restore or remove configuration drop-in
        if [[ "${had_conf}" == "true" && -f "${backup_dir}/${DROPIN_FILENAME}" ]]; then
            echo "Restoring previous drop-in configuration..."
            cp -a "${backup_dir}/${DROPIN_FILENAME}" "${DEST_CONF_FILE}"
        else
            echo "Removing GPS drop-in configuration (${DEST_CONF_FILE})..."
            rm -f "${DEST_CONF_FILE}"
        fi

        # Restore or remove theme directory
        if [[ "${had_theme}" == "true" && -d "${backup_dir}/theme_backup" ]]; then
            echo "Restoring previous theme files..."
            rm -rf "${DEST_THEME_DIR}"
            cp -a "${backup_dir}/theme_backup" "${DEST_THEME_DIR}"
        else
            echo "Removing GPS theme directory (${DEST_THEME_DIR})..."
            rm -rf "${DEST_THEME_DIR}"
        fi

        echo "Rollback completed successfully using ${backup_dir}."
    else
        echo "No backup manifest found. Performing safe direct cleanup of GPS files..."
        if [[ -f "${DEST_CONF_FILE}" ]]; then
            echo "Removing ${DEST_CONF_FILE}..."
            rm -f "${DEST_CONF_FILE}"
        fi
        if [[ -d "${DEST_THEME_DIR}" ]]; then
            echo "Removing ${DEST_THEME_DIR}..."
            rm -rf "${DEST_THEME_DIR}"
        fi
        echo "Direct cleanup completed. Existing system themes remain active."
    fi
}

case "${MODE}" in
    dry-run)
        do_dry_run
        ;;
    apply)
        do_apply
        ;;
    rollback)
        do_rollback
        ;;
    status)
        do_status
        ;;
esac
