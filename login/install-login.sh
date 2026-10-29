#!/usr/bin/env bash
# GPS Desktop Login Theme Installer & Lifecycle Manager
#
# Safe, idempotent installer for the GPS SDDM login theme.
# Defaults to dry-run mode. Requires explicit --apply to make changes.
# Strictly respects SDDM configuration precedence rules (sddm.conf(5)).
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
UPDATE_SDDM_CONF=false
THEME_NAME="gps"
DROPIN_FILENAME="zz-gps-theme.conf"

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install, inspect, or roll back the GPS SDDM login screen theme package.
DEFAULTS TO DRY-RUN. No system changes are made unless --apply is passed.

Modes:
  --dry-run               Simulate installation and print precedence analysis (default)
  --apply                 Execute installation (requires elevated privileges for system paths)
  --rollback [PATH]       Revert to previous login configuration using latest or specified backup
  --status                Check current installation, effective theme, and precedence status
  --help, -h              Show this help message

Options:
  --update-sddm-conf      Safely back up and update /etc/sddm.conf if an explicit theme setting
                          in that file overrides drop-in configuration (reversible on rollback)
  --root-dir PATH         Set filesystem root prefix (e.g. temporary directory for tests)
  --etc-dir PATH          Override /etc destination directory
  --share-dir PATH        Override /usr/share destination directory
  --backup-dir PATH       Override /var/backups/gps-login directory

SDDM Precedence Rules (sddm.conf(5)):
  1. /usr/lib/sddm/sddm.conf.d/*.conf  (System defaults, lowest precedence)
  2. /etc/sddm.conf.d/*.conf          (Local drop-ins, loaded in alphabetical order)
  3. /etc/sddm.conf                   (Compatibility config, HIGHEST PRECEDENCE)

Safety guarantees:
  - Default mode is dry-run.
  - Never touches PAM, authentication files, or systemd display-manager services.
  - Never deletes existing default or user themes.
  - Detects precedence conflicts: --apply will refuse to run if /etc/sddm.conf or a
    higher-sorting drop-in would shadow the theme, preventing ineffective installation.
  - Creates timestamped backups with manifests before modifying any file.
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
        --update-sddm-conf)
            UPDATE_SDDM_CONF=true
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
MAIN_SDDM_CONF="${ETC_DIR}/sddm.conf"

# Detect Display Manager
detect_display_manager() {
    local dm="unknown"
    if [[ -x "/usr/bin/sddm-greeter-qt6" || -x "/usr/bin/sddm-greeter" || -d "${SHARE_DIR}/sddm" || -d "${ETC_DIR}/sddm.conf.d" ]]; then
        dm="sddm"
    fi
    echo "${dm}"
}

DM="$(detect_display_manager)"

# Parse [Theme] Current value from an INI file
parse_theme_current() {
    local file="$1"
    [[ -f "${file}" ]] || return 0
    awk '
        BEGIN { in_theme = 0 }
        /^[[:space:]]*\[Theme\]/ { in_theme = 1; next }
        /^[[:space:]]*\[/ { in_theme = 0 }
        in_theme && /^[[:space:]]*Current[[:space:]]*=/ {
            line = $0
            sub(/^[[:space:]]*Current[[:space:]]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "${file}"
}

# Comment out [Theme] Current in a file
comment_out_theme_current() {
    local src="$1"
    local dest="$2"
    awk '
        BEGIN { in_theme = 0 }
        /^[[:space:]]*\[Theme\]/ { in_theme = 1; print; next }
        /^[[:space:]]*\[/ { in_theme = 0 }
        in_theme && /^[[:space:]]*Current[[:space:]]*=/ {
            print "# " $0 " # Disabled by gps-login installer to allow drop-in precedence"
            next
        }
        { print }
    ' "${src}" > "${dest}"
}

# Determine currently effective theme according to sddm.conf(5) rules
# Returns: "theme_name|source_file"
get_current_effective_theme() {
    local effective_theme=""
    local effective_source="(default)"

    # 1. System directory: /usr/lib/sddm/sddm.conf.d/*.conf
    if [[ -d "/usr/lib/sddm/sddm.conf.d" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            local val
            val="$(parse_theme_current "$f")"
            if [[ -n "$val" ]]; then
                effective_theme="$val"
                effective_source="$f"
            fi
        done < <(find /usr/lib/sddm/sddm.conf.d -maxdepth 1 -name "*.conf" 2>/dev/null | LC_ALL=C sort)
    fi

    # 2. Local drop-in directory: ${DEST_CONF_DIR}/*.conf
    if [[ -d "${DEST_CONF_DIR}" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            local val
            val="$(parse_theme_current "$f")"
            if [[ -n "$val" ]]; then
                effective_theme="$val"
                effective_source="$f"
            fi
        done < <(find "${DEST_CONF_DIR}" -maxdepth 1 -name "*.conf" 2>/dev/null | LC_ALL=C sort)
    fi

    # 3. Main config file: ${MAIN_SDDM_CONF} (highest precedence)
    if [[ -f "${MAIN_SDDM_CONF}" ]]; then
        local val
        val="$(parse_theme_current "${MAIN_SDDM_CONF}")"
        if [[ -n "$val" ]]; then
            effective_theme="$val"
            effective_source="${MAIN_SDDM_CONF}"
        fi
    fi

    echo "${effective_theme}|${effective_source}"
}

# Simulate effective theme if GPS drop-in is installed
# Returns: "simulated_theme|source_file|has_conflict|conflict_reason"
simulate_post_install_effective_theme() {
    local sim_theme=""
    local sim_source=""
    local has_conflict=false
    local conflict_reason=""

    # 1. System directory
    if [[ -d "/usr/lib/sddm/sddm.conf.d" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            local val
            val="$(parse_theme_current "$f")"
            if [[ -n "$val" ]]; then
                sim_theme="$val"
                sim_source="$f"
            fi
        done < <(find /usr/lib/sddm/sddm.conf.d -maxdepth 1 -name "*.conf" 2>/dev/null | LC_ALL=C sort)
    fi

    # 2. Local drop-in directory merged with proposed drop-in in lexical order
    local conf_names=()
    if [[ -d "${DEST_CONF_DIR}" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            conf_names+=("$(basename "$f")")
        done < <(find "${DEST_CONF_DIR}" -maxdepth 1 -name "*.conf" 2>/dev/null)
    fi

    # Add our proposed drop-in if not present
    local found_ours=false
    for c in "${conf_names[@]:-}"; do
        if [[ "$c" == "${DROPIN_FILENAME}" ]]; then
            found_ours=true
            break
        fi
    done
    if [[ "${found_ours}" == false ]]; then
        conf_names+=("${DROPIN_FILENAME}")
    fi

    # Sort list
    local sorted_names
    sorted_names="$(printf '%s\n' "${conf_names[@]}" | LC_ALL=C sort)"

    while IFS= read -r cname; do
        [[ -n "$cname" ]] || continue
        if [[ "$cname" == "${DROPIN_FILENAME}" ]]; then
            sim_theme="${THEME_NAME}"
            sim_source="${DEST_CONF_DIR}/${DROPIN_FILENAME}"
        else
            local fpath="${DEST_CONF_DIR}/${cname}"
            local val
            val="$(parse_theme_current "$fpath")"
            if [[ -n "$val" ]]; then
                sim_theme="$val"
                sim_source="$fpath"
            fi
        fi
    done <<< "${sorted_names}"

    # Check if a higher-sorting drop-in overrode our theme
    if [[ "${sim_theme}" != "${THEME_NAME}" ]]; then
        has_conflict=true
        conflict_reason="Drop-in '${sim_source}' sorts after '${DROPIN_FILENAME}' and sets Current=${sim_theme}."
    fi

    # 3. Main configuration file: /etc/sddm.conf (highest precedence)
    if [[ -f "${MAIN_SDDM_CONF}" ]]; then
        local sddm_val
        sddm_val="$(parse_theme_current "${MAIN_SDDM_CONF}")"
        if [[ -n "$sddm_val" ]]; then
            # If sddm.conf has Current=..., it overrides all drop-in files
            if [[ "${UPDATE_SDDM_CONF}" == true ]]; then
                # With --update-sddm-conf, this conflict will be resolved by commenting out
                :
            elif [[ "$sddm_val" != "${THEME_NAME}" ]]; then
                sim_theme="$sddm_val"
                sim_source="${MAIN_SDDM_CONF}"
                has_conflict=true
                conflict_reason="'${MAIN_SDDM_CONF}' explicitly sets Current=${sddm_val}, which overrides /etc/sddm.conf.d/ per sddm.conf(5)."
            fi
        fi
    fi

    echo "${sim_theme}|${sim_source}|${has_conflict}|${conflict_reason}"
}

# Status command
do_status() {
    local cur_info
    cur_info="$(get_current_effective_theme)"
    local cur_theme="${cur_info%%|*}"
    local cur_src="${cur_info##*|}"

    echo "=== GPS Login Screen Status & SDDM Precedence ==="
    echo "Target Display Manager : ${DM}"
    echo "Theme Destination      : ${DEST_THEME_DIR}"
    echo "Drop-in Destination    : ${DEST_CONF_FILE}"
    echo "Main SDDM Config       : ${MAIN_SDDM_CONF}"
    echo "Backup Directory       : ${BACKUP_BASE_DIR}"
    echo ""
    echo "Current Effective Configuration (sddm.conf(5)): "
    echo "  Theme  : ${cur_theme:-<none/default>}"
    echo "  Source : ${cur_src}"
    echo ""

    local theme_installed=false
    local dropin_installed=false

    if [[ -d "${DEST_THEME_DIR}" && -f "${DEST_THEME_DIR}/metadata.desktop" ]]; then
        theme_installed=true
        echo "[✓] GPS theme assets present in ${DEST_THEME_DIR}"
    else
        echo "[ ] GPS theme assets are NOT installed"
    fi

    if [[ -f "${DEST_CONF_FILE}" ]]; then
        dropin_installed=true
        echo "[✓] GPS drop-in file is present (${DEST_CONF_FILE})"
    else
        echo "[ ] GPS drop-in file is NOT present"
    fi

    echo ""
    if [[ "${cur_theme}" == "${THEME_NAME}" ]]; then
        echo "Overall Status: GPS Login Theme is ACTIVE and EFFECTIVE (Source: ${cur_src})"
    elif [[ "${theme_installed}" == true && "${dropin_installed}" == true ]]; then
        echo "Overall Status: GPS Login Theme is INSTALLED but SHADOWED by higher-precedence config (${cur_src})"
    elif [[ "${theme_installed}" == true ]]; then
        echo "Overall Status: GPS Login Theme is INSTALLED but INACTIVE (no active drop-in)"
    else
        echo "Overall Status: GPS Login Theme is NOT INSTALLED (Package is unapplied)"
    fi

    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        echo ""
        echo "Available backups:"
        find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | sort -r | head -n 5 | sed 's/^/  - /'
    fi
}

# Dry-run command
do_dry_run() {
    local cur_info
    cur_info="$(get_current_effective_theme)"
    local cur_theme="${cur_info%%|*}"
    local cur_src="${cur_info##*|}"

    local sim_info
    sim_info="$(simulate_post_install_effective_theme)"
    local sim_theme sim_src has_conflict conflict_reason
    IFS='|' read -r sim_theme sim_src has_conflict conflict_reason <<< "${sim_info}"

    echo "=== GPS Login Screen Installation Plan (DRY-RUN) ==="
    echo "No files will be modified. Run with --apply to execute."
    echo ""
    echo "Target Display Manager : ${DM}"
    echo "Source Package         : ${SOURCE_THEME_DIR}"
    echo "Theme Destination      : ${DEST_THEME_DIR}"
    echo "Drop-in Destination    : ${DEST_CONF_FILE}"
    echo "Backup Root            : ${BACKUP_BASE_DIR}"
    echo ""
    echo "Configuration Precedence Evaluation (sddm.conf(5)):"
    echo "  Current Effective Theme  : ${cur_theme:-<default>} (determined by ${cur_src})"
    echo "  Simulated Post-Install   : ${sim_theme} (determined by ${sim_src})"
    echo ""

    if [[ "${has_conflict}" == "true" ]]; then
        echo "[!] PRECEDENCE CONFLICT DETECTED:"
        echo "    ${conflict_reason}"
        echo ""
        echo "    SDDM documented load order: configuration directories are read first,"
        echo "    followed by /etc/sddm.conf with the latter having HIGHEST PRECEDENCE."
        echo "    Therefore, installing '${DEST_CONF_FILE}' alone will NOT activate GPS."
        echo ""
        echo "    Resolution options:"
        echo "      1. Manual: Comment out or remove 'Current=' in '${MAIN_SDDM_CONF}'."
        echo "      2. Automated: Run with '--update-sddm-conf' to create a reversible backup and"
        echo "         comment out the conflicting setting in '${MAIN_SDDM_CONF}' automatically:"
        echo "         sudo $0 --apply --update-sddm-conf"
        echo ""
        echo "    NOTE: By default, '--apply' will refuse to proceed while an unresolved conflict exists."
    else
        echo "[✓] Precedence Check Passed:"
        echo "    Drop-in '${DROPIN_FILENAME}' will successfully govern the active theme."
    fi

    echo ""
    echo "Planned Actions:"
    local step=1
    echo "  ${step}. Record timestamped backup manifest under ${BACKUP_BASE_DIR}/backup-<timestamp>/"
    ((step++))

    if [[ "${has_conflict}" == "true" && "${UPDATE_SDDM_CONF}" == true ]]; then
        echo "  ${step}. Back up and update '${MAIN_SDDM_CONF}': comment out 'Current=${cur_theme}'"
        ((step++))
    fi

    echo "  ${step}. Install theme assets to '${DEST_THEME_DIR}'"
    ((step++))
    echo "  ${step}. Create drop-in configuration '${DEST_CONF_FILE}' with '[Theme] Current=${THEME_NAME}'"
    ((step++))
    echo "  ${step}. Update '${BACKUP_BASE_DIR}/latest' symlink"

    echo ""
    echo "Safety check:"
    echo "  - PAM configuration: UNTOUCHED"
    echo "  - Existing themes (/usr/share/sddm/themes/caelestia, etc.): UNTOUCHED"
    echo "  - Display manager services: UNTOUCHED"
    echo ""
    echo "DRY-RUN COMPLETE: 0 changes made."
}

# Apply command
do_apply() {
    # Check permissions if targeting real system paths
    if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        if [[ "${EUID}" -ne 0 ]]; then
            echo "Error: Applying changes to system paths requires root privileges." >&2
            echo "Please run: sudo $0 --apply" >&2
            exit 1
        fi
    fi

    # Precedence analysis before making any changes
    local sim_info
    sim_info="$(simulate_post_install_effective_theme)"
    local sim_theme sim_src has_conflict conflict_reason
    IFS='|' read -r sim_theme sim_src has_conflict conflict_reason <<< "${sim_info}"

    if [[ "${has_conflict}" == "true" ]]; then
        echo "Error: Cannot apply GPS login theme due to an unresolved SDDM precedence conflict." >&2
        echo "" >&2
        echo "Conflict Analysis:" >&2
        echo "  ${conflict_reason}" >&2
        echo "" >&2
        echo "Explanation:" >&2
        echo "  Per sddm.conf(5), /etc/sddm.conf overrides all files in /etc/sddm.conf.d/." >&2
        echo "  Writing drop-in '${DROPIN_FILENAME}' would be ineffective because '${sim_src}'" >&2
        echo "  takes precedence and would keep theme '${sim_theme}' active." >&2
        echo "" >&2
        echo "How to resolve:" >&2
        echo "  Option A (Manual prerequisite):" >&2
        echo "    Edit '${MAIN_SDDM_CONF}' and comment out or remove 'Current=' under [Theme]" >&2
        echo "    so that drop-in configurations can govern the active theme." >&2
        echo "" >&2
        echo "  Option B (Reversible automated resolution):" >&2
        echo "    Run with '--update-sddm-conf' to allow the installer to back up '${MAIN_SDDM_CONF}'" >&2
        echo "    and comment out 'Current=' reversibly (fully restored on rollback):" >&2
        echo "    sudo $0 --apply --update-sddm-conf" >&2
        exit 1
    fi

    echo "=== Applying GPS Login Screen Theme ==="

    # Check if already installed and up-to-date (Idempotent check)
    local cur_info
    cur_info="$(get_current_effective_theme)"
    local cur_theme="${cur_info%%|*}"
    if [[ "${cur_theme}" == "${THEME_NAME}" && -d "${DEST_THEME_DIR}" && -f "${DEST_CONF_FILE}" ]]; then
        if diff -rq "${SOURCE_THEME_DIR}" "${DEST_THEME_DIR}" >/dev/null 2>&1; then
            echo "Theme files and drop-in configuration are already installed, identical, and effective."
            echo "Installation is idempotent: no changes required."
            return 0
        fi
    fi

    # Create timestamped backup directory
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_BASE_DIR}/backup_${timestamp}"
    mkdir -p "${backup_dir}"

    local had_theme=false
    local had_conf=false
    local modified_sddm_conf=false

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

    # Handle /etc/sddm.conf if --update-sddm-conf was requested and needed
    if [[ "${UPDATE_SDDM_CONF}" == true && -f "${MAIN_SDDM_CONF}" ]]; then
        local sddm_curr
        sddm_curr="$(parse_theme_current "${MAIN_SDDM_CONF}")"
        if [[ -n "$sddm_curr" && "$sddm_curr" != "${THEME_NAME}" ]]; then
            modified_sddm_conf=true
            echo "Backing up ${MAIN_SDDM_CONF} to ${backup_dir}/sddm.conf.orig..."
            cp -a "${MAIN_SDDM_CONF}" "${backup_dir}/sddm.conf.orig"
            echo "Updating ${MAIN_SDDM_CONF}: commenting out 'Current=${sddm_curr}' under [Theme]..."
            comment_out_theme_current "${MAIN_SDDM_CONF}" "${MAIN_SDDM_CONF}.tmp"
            mv "${MAIN_SDDM_CONF}.tmp" "${MAIN_SDDM_CONF}"
        fi
    fi

    # Write manifest
    cat << EOF > "${backup_dir}/manifest.json"
{
  "timestamp": "${timestamp}",
  "theme_name": "${THEME_NAME}",
  "dest_theme_dir": "${DEST_THEME_DIR}",
  "dest_conf_file": "${DEST_CONF_FILE}",
  "had_preexisting_theme": ${had_theme},
  "had_preexisting_conf": ${had_conf},
  "modified_sddm_conf": ${modified_sddm_conf}
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
    echo "Effective Theme: ${THEME_NAME}"
    echo "Backup saved at: ${backup_dir}"
}

# Rollback command
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
        local had_theme had_conf mod_sddm
        had_theme="$(grep '"had_preexisting_theme":' "${backup_dir}/manifest.json" | grep -o 'true\|false')"
        had_conf="$(grep '"had_preexisting_conf":' "${backup_dir}/manifest.json" | grep -o 'true\|false')"
        mod_sddm="$(grep '"modified_sddm_conf":' "${backup_dir}/manifest.json" | grep -o 'true\|false')"

        # 1. Restore /etc/sddm.conf if it was modified
        if [[ "${mod_sddm}" == "true" && -f "${backup_dir}/sddm.conf.orig" ]]; then
            echo "Restoring ${MAIN_SDDM_CONF} from ${backup_dir}/sddm.conf.orig..."
            cp -a "${backup_dir}/sddm.conf.orig" "${MAIN_SDDM_CONF}"
        fi

        # 2. Restore or remove configuration drop-in
        if [[ "${had_conf}" == "true" && -f "${backup_dir}/${DROPIN_FILENAME}" ]]; then
            echo "Restoring previous drop-in configuration..."
            cp -a "${backup_dir}/${DROPIN_FILENAME}" "${DEST_CONF_FILE}"
        else
            echo "Removing GPS drop-in configuration (${DEST_CONF_FILE})..."
            rm -f "${DEST_CONF_FILE}"
        fi

        # Also clean up legacy 99-gps-theme.conf if present
        rm -f "${DEST_CONF_DIR}/99-gps-theme.conf"

        # 3. Restore or remove theme directory
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
        rm -f "${DEST_CONF_FILE}"
        rm -f "${DEST_CONF_DIR}/99-gps-theme.conf"
        rm -rf "${DEST_THEME_DIR}"
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
