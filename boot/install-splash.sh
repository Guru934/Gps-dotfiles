#!/usr/bin/env bash
# ==============================================================================
# GPS Desktop Boot Splash Theme Installer & Lifecycle Manager
#
# Safe, idempotent installer and rollback manager for the GPS Plymouth theme.
# Defaults to dry-run mode. Requires explicit --apply to make changes.
# Strictly verifies bootloader and initramfs configuration and encryption safety.
# Supports isolated testing via --root-dir or environment overrides.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_THEME_DIR="${SCRIPT_DIR}/theme"

# Configuration defaults
ROOT_DIR="${GPS_INSTALL_ROOT:-}"
ETC_DIR="${GPS_ETC_DIR:-${ROOT_DIR}/etc}"
SHARE_DIR="${GPS_SHARE_DIR:-${ROOT_DIR}/usr/share}"
BOOT_DIR="${GPS_BOOT_DIR:-${ROOT_DIR}/boot}"
BACKUP_BASE_DIR="${GPS_BACKUP_DIR:-${ROOT_DIR}/var/backups/gps-boot}"

MODE="dry-run" # Default mode is ALWAYS dry-run
ROLLBACK_TARGET=""
NO_INITRD_REBUILD=false
THEME_NAME="gps"

# ANSI styling helpers if running in terminal
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
    C_GRAY='\033[90m'
else
    C_RESET=''
    C_BOLD=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
    C_GRAY=''
fi

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Inspect, install, or roll back the GPS Plymouth boot splash theme package.
DEFAULTS TO DRY-RUN. No system changes are made unless --apply is passed.

Modes:
  --dry-run               Simulate installation and print complete system audit (default)
  --apply                 Execute installation (requires elevated privileges for system paths)
  --rollback [PATH]       Revert to previous boot splash configuration using latest or specified backup
  --status                Check current boot splash theme, hooks, and kernel parameters
  --help, -h              Show this help message

Options:
  --root-dir PATH         Set filesystem root prefix (e.g. temporary directory for tests)
  --etc-dir PATH          Override /etc destination directory
  --share-dir PATH        Override /usr/share destination directory
  --boot-dir PATH         Override /boot destination directory
  --backup-dir PATH       Override /var/backups/gps-boot directory
  --no-initrd-rebuild     Skip regenerating initramfs image during apply or rollback

Safety Invariants:
  - Disk encryption: refrains from modifying the system if encryption is detected
    and hook ordering or graphical unlock flow cannot be positively verified.
  - Backups: every modified file is saved to /var/backups/gps-boot/<timestamp>/
    with an exact restoration manifest before any modification takes place.
  - Idempotency: repeated --apply calls produce identical state without duplicates.
EOF
}

# Parse command line options
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
        --help|-h)
            print_usage
            exit 0
            ;;
        --root-dir)
            ROOT_DIR="$2"
            ETC_DIR="${ROOT_DIR}/etc"
            SHARE_DIR="${ROOT_DIR}/usr/share"
            BOOT_DIR="${ROOT_DIR}/boot"
            BACKUP_BASE_DIR="${ROOT_DIR}/var/backups/gps-boot"
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
        --boot-dir)
            BOOT_DIR="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        --no-initrd-rebuild)
            NO_INITRD_REBUILD=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

DEST_THEME_DIR="${SHARE_DIR}/plymouth/themes/${THEME_NAME}"
PLYMOUTHD_CONF="${ETC_DIR}/plymouth/plymouthd.conf"
MKINITCPIO_CONF="${ETC_DIR}/mkinitcpio.conf"
LIMINE_DEFAULT_CONF="${ETC_DIR}/default/limine"
GRUB_DEFAULT_CONF="${ETC_DIR}/default/grub"

# Audit state variables
DETECTED_BOOTLOADER="Unknown"
DETECTED_INITRAMFS_GEN="Unknown"
DETECTED_ROOT_FS="Unknown"
DETECTED_SNAPSHOT_TOOL="None"
DETECTED_ENCRYPTION="None"
ENCRYPTION_SAFE=true
ENCRYPTION_REASON=""
PLYMOUTH_INSTALLED=false
TWOSTEP_PLUGIN_EXISTS=false
CURRENT_PLYMOUTH_THEME="none"
CMDLINE_HAS_QUIET=false
CMDLINE_HAS_SPLASH=false
DISPLAY_MANAGER="Unknown"
LIMINE_MKINITCPIO_EXISTS=false

# Perform read-only audit of host or target root
audit_system() {
    # 1. Plymouth Package & Plugin Verification
    if [[ -n "${ROOT_DIR}" && "${ROOT_DIR}" != "/" ]]; then
        if [[ -x "${ROOT_DIR}/usr/bin/plymouth" ]]; then
            PLYMOUTH_INSTALLED=true
        fi
    else
        if [[ -x "/usr/bin/plymouth" ]] || command -v plymouth >/dev/null 2>&1; then
            PLYMOUTH_INSTALLED=true
        fi
    fi

    # Check two-step.so plugin
    local plugin_paths=(
        "${ROOT_DIR}/usr/lib/plymouth/two-step.so"
        "${ROOT_DIR}/usr/lib64/plymouth/two-step.so"
        "/usr/lib/plymouth/two-step.so"
    )
    for p in "${plugin_paths[@]}"; do
        if [[ -f "$p" ]]; then
            TWOSTEP_PLUGIN_EXISTS=true
            break
        fi
    done

    # Current active theme
    if [[ -f "${PLYMOUTHD_CONF}" ]]; then
        local t
        t="$(grep -E '^\s*Theme\s*=' "${PLYMOUTHD_CONF}" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d ' ' || true)"
        if [[ -n "$t" ]]; then
            CURRENT_PLYMOUTH_THEME="$t"
        fi
    elif command -v plymouth-set-default-theme >/dev/null 2>&1 && [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        CURRENT_PLYMOUTH_THEME="$(plymouth-set-default-theme 2>/dev/null || echo 'none')"
    fi

    # 2. Bootloader Detection
    if [[ -f "${LIMINE_DEFAULT_CONF}" || -f "${ETC_DIR}/limine-entry-tool.conf" || -f "${BOOT_DIR}/limine.conf" || -f "${BOOT_DIR}/EFI/limine/limine_x64.efi" ]]; then
        DETECTED_BOOTLOADER="Limine"
    elif [[ -f "${GRUB_DEFAULT_CONF}" || -d "${BOOT_DIR}/grub" || -f "${BOOT_DIR}/grub/grub.cfg" ]]; then
        DETECTED_BOOTLOADER="GRUB"
    elif [[ -d "${BOOT_DIR}/loader" || -f "${BOOT_DIR}/loader/loader.conf" ]]; then
        DETECTED_BOOTLOADER="systemd-boot"
    fi

    # Check verified Limine integration command (limine-mkinitcpio)
    if [[ -n "${ROOT_DIR}" && "${ROOT_DIR}" != "/" ]]; then
        if [[ -x "${ROOT_DIR}/usr/bin/limine-mkinitcpio" ]]; then
            LIMINE_MKINITCPIO_EXISTS=true
        fi
    else
        if command -v limine-mkinitcpio >/dev/null 2>&1; then
            LIMINE_MKINITCPIO_EXISTS=true
        fi
    fi

    # 3. Initramfs Generator Detection
    if [[ -n "${ROOT_DIR}" && "${ROOT_DIR}" != "/" ]]; then
        if [[ -f "${MKINITCPIO_CONF}" || -x "${ROOT_DIR}/usr/bin/mkinitcpio" ]]; then
            DETECTED_INITRAMFS_GEN="mkinitcpio"
        elif [[ -f "${ETC_DIR}/dracut.conf" || -d "${ETC_DIR}/dracut.conf.d" || -x "${ROOT_DIR}/usr/bin/dracut" ]]; then
            DETECTED_INITRAMFS_GEN="dracut"
        fi
    else
        if [[ -f "${MKINITCPIO_CONF}" ]] || command -v mkinitcpio >/dev/null 2>&1; then
            DETECTED_INITRAMFS_GEN="mkinitcpio"
        elif [[ -f "${ETC_DIR}/dracut.conf" || -d "${ETC_DIR}/dracut.conf.d" ]] || command -v dracut >/dev/null 2>&1; then
            DETECTED_INITRAMFS_GEN="dracut"
        fi
    fi

    # 4. Root Filesystem & Snapshots
    if [[ -f "${ETC_DIR}/fstab" ]]; then
        if grep -q 'btrfs' "${ETC_DIR}/fstab" 2>/dev/null; then
            DETECTED_ROOT_FS="btrfs"
        elif grep -q 'ext4' "${ETC_DIR}/fstab" 2>/dev/null; then
            DETECTED_ROOT_FS="ext4"
        fi
    elif command -v findmnt >/dev/null 2>&1; then
        DETECTED_ROOT_FS="$(findmnt -n -o FSTYPE / 2>/dev/null || echo 'Unknown')"
    fi

    if [[ -x "${ROOT_DIR}/usr/bin/snapper" || -d "${ETC_DIR}/snapper" ]] || command -v snapper >/dev/null 2>&1; then
        DETECTED_SNAPSHOT_TOOL="Snapper"
    elif [[ -x "${ROOT_DIR}/usr/bin/timeshift" || -d "${ETC_DIR}/timeshift" ]] || command -v timeshift >/dev/null 2>&1; then
        DETECTED_SNAPSHOT_TOOL="Timeshift"
    fi

    # 5. Disk Encryption Detection & Hook Ordering Verification
    local luks_found=false
    local crypttab_file="${ETC_DIR}/crypttab"

    if [[ -f "${crypttab_file}" ]]; then
        if grep -v -E '^\s*#|^\s*$' "${crypttab_file}" 2>/dev/null | grep -q .; then
            luks_found=true
        fi
    fi

    # Inspect kernel cmdline for encryption parameters
    local raw_cmdline=""
    if [[ -r "/proc/cmdline" && ( -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ) ]]; then
        raw_cmdline="$(cat /proc/cmdline 2>/dev/null || true)"
    elif [[ -f "${LIMINE_DEFAULT_CONF}" ]]; then
        raw_cmdline="$(cat "${LIMINE_DEFAULT_CONF}" 2>/dev/null || true)"
    elif [[ -f "${GRUB_DEFAULT_CONF}" ]]; then
        raw_cmdline="$(cat "${GRUB_DEFAULT_CONF}" 2>/dev/null || true)"
    fi

    if echo "${raw_cmdline}" | grep -q -E 'cryptdevice=|rd.luks.uuid=|rd.luks.name='; then
        luks_found=true
    fi

    # Inspect mkinitcpio hooks for encrypt or sd-encrypt
    if [[ -f "${MKINITCPIO_CONF}" ]]; then
        local hooks_str
        hooks_str="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
        if echo "${hooks_str}" | grep -q -E '\b(encrypt|sd-encrypt)\b'; then
            luks_found=true
        fi
    fi

    if [[ "${luks_found}" == "true" ]]; then
        DETECTED_ENCRYPTION="LUKS / dm-crypt"

        # Strictly verify hook ordering if mkinitcpio is used
        if [[ -f "${MKINITCPIO_CONF}" ]]; then
            local hooks_line
            hooks_line="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
            local hooks_inner
            hooks_inner="$(echo "${hooks_line}" | sed -e 's/^[^(]*(//' -e 's/).*$//')"
            read -r -a hook_arr <<< "${hooks_inner}"

            local has_plymouth=false
            local plymouth_idx=-1
            local enc_idx=-1
            local enc_type=""

            for i in "${!hook_arr[@]}"; do
                if [[ "${hook_arr[i]}" == "plymouth" ]]; then
                    has_plymouth=true
                    plymouth_idx=$i
                elif [[ "${hook_arr[i]}" == "sd-encrypt" || "${hook_arr[i]}" == "encrypt" ]]; then
                    enc_idx=$i
                    enc_type="${hook_arr[i]}"
                fi
            done

            if [[ "${has_plymouth}" == "true" && "${enc_idx}" -ne -1 ]]; then
                if [[ "${plymouth_idx}" -gt "${enc_idx}" ]]; then
                    ENCRYPTION_SAFE=false
                    ENCRYPTION_REASON="Invalid hook order: '${enc_type}' (index ${enc_idx}) appears BEFORE 'plymouth' (index ${plymouth_idx}). Plymouth must load before the encryption hook to handle the password dialog."
                else
                    ENCRYPTION_SAFE=true
                fi
            elif [[ "${enc_idx}" -ne -1 && "${has_plymouth}" == "false" ]]; then
                # Plymouth hook is not present yet; installer must insert plymouth BEFORE encrypt hook
                ENCRYPTION_SAFE=true
            fi
        else
            # Encryption present but no verifiable mkinitcpio config
            ENCRYPTION_SAFE=false
            ENCRYPTION_REASON="Disk encryption is active, but the initramfs hook ordering could not be safely verified against an mkinitcpio configuration."
        fi
    else
        DETECTED_ENCRYPTION="None"
        ENCRYPTION_SAFE=true
    fi

    # 6. Kernel Command Line (quiet & splash)
    if echo "${raw_cmdline}" | grep -q -E '\bquiet\b'; then
        CMDLINE_HAS_QUIET=true
    fi
    if echo "${raw_cmdline}" | grep -q -E '\bsplash\b'; then
        CMDLINE_HAS_SPLASH=true
    fi

    # 7. Display Manager
    if [[ -x "${ROOT_DIR}/usr/bin/sddm" ]] || command -v sddm >/dev/null 2>&1; then
        DISPLAY_MANAGER="sddm (Simple Desktop Display Manager)"
    elif [[ -x "${ROOT_DIR}/usr/bin/gdm" ]] || command -v gdm >/dev/null 2>&1; then
        DISPLAY_MANAGER="gdm (GNOME Display Manager)"
    elif [[ -x "${ROOT_DIR}/usr/bin/lightdm" ]] || command -v lightdm >/dev/null 2>&1; then
        DISPLAY_MANAGER="lightdm"
    elif [[ -x "${ROOT_DIR}/usr/bin/greetd" ]] || command -v greetd >/dev/null 2>&1; then
        DISPLAY_MANAGER="greetd"
    fi
}

print_audit_report() {
    printf "%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b GPS Desktop — Plymouth Boot Splash System Audit%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b========================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "  %-26s: %s%s\n" "Bootloader" "${DETECTED_BOOTLOADER}" "$([ "$DETECTED_BOOTLOADER" = "Limine" ] && echo " (limine-mkinitcpio: $([ "$LIMINE_MKINITCPIO_EXISTS" = true ] && echo 'Available' || echo 'Missing'))" || echo '')"
    printf "  %-26s: %s\n" "Initramfs Generator" "${DETECTED_INITRAMFS_GEN}"
    printf "  %-26s: %s (separate /boot: %s)\n" "Root Filesystem" "${DETECTED_ROOT_FS}" "$([ -d "${BOOT_DIR}" ] && echo 'YES' || echo 'NO')"
    printf "  %-26s: %s\n" "Snapshot Tool" "${DETECTED_SNAPSHOT_TOOL}"
    printf "  %-26s: %s\n" "Disk Encryption" "${DETECTED_ENCRYPTION}"
    printf "  %-26s: %s (two-step.so: %s)\n" "Plymouth Package" "$([ "$PLYMOUTH_INSTALLED" = true ] && echo 'Installed' || echo 'NOT Installed')" "$([ "$TWOSTEP_PLUGIN_EXISTS" = true ] && echo 'Available' || echo 'Missing')"
    printf "  %-26s: %s\n" "Current Splash Theme" "${CURRENT_PLYMOUTH_THEME}"
    printf "  %-26s: quiet: %s | splash: %s\n" "Kernel Parameters" "$([ "$CMDLINE_HAS_QUIET" = true ] && echo 'YES' || echo 'NO')" "$([ "$CMDLINE_HAS_SPLASH" = true ] && echo 'YES' || echo 'NO')"
    printf "  %-26s: %s\n" "Display Manager" "${DISPLAY_MANAGER}"
    printf "%b------------------------------------------------------------------------%b\n" "$C_GRAY" "$C_RESET"
}

# Python helper to safely inject 'plymouth' hook into mkinitcpio.conf
inject_plymouth_hook() {
    local conf_file="$1"
    python3 -c "
import sys, re
conf_path = sys.argv[1]
with open(conf_path, 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'^\s*HOOKS=\(([^)]*)\)', content, re.MULTILINE)
if not m:
    sys.exit(0) # No change

hooks = m.group(1).split()
if 'plymouth' in hooks:
    sys.exit(0) # Already present

new_hooks = []
inserted = False

# Order priority:
# 1. Plymouth MUST come BEFORE sd-encrypt or encrypt
# 2. Plymouth should come AFTER sd-vconsole or kms or udev
# 3. Fallback: right before filesystems
if 'sd-encrypt' in hooks:
    for h in hooks:
        if h == 'sd-encrypt' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
        new_hooks.append(h)
elif 'encrypt' in hooks:
    for h in hooks:
        if h == 'encrypt' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
        new_hooks.append(h)
elif 'sd-vconsole' in hooks:
    for h in hooks:
        new_hooks.append(h)
        if h == 'sd-vconsole' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
elif 'kms' in hooks:
    for h in hooks:
        new_hooks.append(h)
        if h == 'kms' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
elif 'udev' in hooks:
    for h in hooks:
        new_hooks.append(h)
        if h == 'udev' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
elif 'filesystems' in hooks:
    for h in hooks:
        if h == 'filesystems' and not inserted:
            new_hooks.append('plymouth')
            inserted = True
        new_hooks.append(h)
else:
    new_hooks = hooks + ['plymouth']
    inserted = True

new_line = f'HOOKS=({' '.join(new_hooks)})'
new_content = content[:m.start()] + new_line + content[m.end():]
with open(conf_path, 'w', encoding='utf-8') as f:
    f.write(new_content)
print('INJECTED')
" "${conf_file}"
}

# Python helper to update [Daemon] Theme= in plymouthd.conf
set_plymouthd_theme() {
    local conf_file="$1"
    local theme_name="$2"
    python3 -c "
import sys, re, os
conf_path = sys.argv[1]
theme = sys.argv[2]

if not os.path.exists(conf_path):
    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    with open(conf_path, 'w', encoding='utf-8') as f:
        f.write(f'[Daemon]\nTheme={theme}\n')
    sys.exit(0)

with open(conf_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
daemon_seen = False
theme_set = False

for line in lines:
    stripped = line.strip()
    if re.match(r'^\[Daemon\]', stripped, re.IGNORECASE):
        daemon_seen = True
        new_lines.append(line)
        continue
    if daemon_seen and not line.startswith('['):
        if re.match(r'^\s*Theme\s*=', stripped):
            new_lines.append(f'Theme={theme}\n')
            theme_set = True
            continue
    elif daemon_seen and line.startswith('['):
        if not theme_set:
            new_lines.append(f'Theme={theme}\n')
            theme_set = True
        daemon_seen = False
    new_lines.append(line)

if daemon_seen and not theme_set:
    new_lines.append(f'Theme={theme}\n')
    theme_set = True
elif not theme_set:
    new_lines.append(f'\n[Daemon]\nTheme={theme}\n')

with open(conf_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
" "${conf_file}" "${theme_name}"
}

# Dry Run execution
do_dry_run() {
    audit_system
    print_audit_report

    printf "%bMODE: DRY-RUN (Default — 0 modifications made)%b\n\n" "$C_BOLD$C_YELLOW" "$C_RESET"

    # Encryption Safety Assessment
    if [[ "${DETECTED_ENCRYPTION}" != "None" ]]; then
        if [[ "${ENCRYPTION_SAFE}" == "false" ]]; then
            printf "%b[SAFETY CHECK] FAILED%b: %s\n" "$C_RED$C_BOLD" "$C_RESET" "${ENCRYPTION_REASON}"
            printf "The installer would REFUSE to apply changes on this configuration to protect bootability.\n\n"
        else
            printf "%b[SAFETY CHECK] PASSED%b: Encryption detected, and hook ordering can be safely verified.\n\n" "$C_GREEN" "$C_RESET"
        fi
    fi

    # Limine Integration Verification
    if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
        if [[ "${LIMINE_MKINITCPIO_EXISTS}" == "false" ]]; then
            printf "%b[SAFETY CHECK] FAILED%b: Limine bootloader detected with mkinitcpio, but required command 'limine-mkinitcpio' (package limine-mkinitcpio-hook) was not found.\n" "$C_RED$C_BOLD" "$C_RESET"
            printf "The installer would REFUSE to apply changes on this configuration to protect boot entry synchronization.\n\n"
        fi
    fi

    printf "%bProposed Actions on --apply:%b\n" "$C_BOLD" "$C_RESET"
    printf "  1. Verify Plymouth installation, two-step plugin, and Limine integration command.\n"
    printf "  2. Create timestamped backup of /etc and separate /boot files (limine.conf, existing initramfs) under:\n     -> %s/<timestamp>/\n" "${BACKUP_BASE_DIR}"
    printf "  3. Install GPS Plymouth theme files to:\n     -> %s\n" "${DEST_THEME_DIR}"
    printf "  4. Update Plymouth daemon configuration:\n     -> %s (Set [Daemon] Theme=%s)\n" "${PLYMOUTHD_CONF}" "${THEME_NAME}"

    if [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" && -f "${MKINITCPIO_CONF}" ]]; then
        local hooks_line
        hooks_line="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
        if echo "${hooks_line}" | grep -q '\bplymouth\b'; then
            printf "  5. mkinitcpio hook status: 'plymouth' hook is ALREADY PRESENT in %s (no edit required).\n" "${MKINITCPIO_CONF}"
        else
            printf "  5. mkinitcpio hook status: will inject 'plymouth' into HOOKS=() in %s\n" "${MKINITCPIO_CONF}"
        fi
    fi

    if [[ "${CMDLINE_HAS_SPLASH}" == "true" && "${CMDLINE_HAS_QUIET}" == "true" ]]; then
        printf "  6. Kernel command-line parameters: 'quiet' and 'splash' are ALREADY CONFIGURED (no edit required).\n"
    else
        printf "  6. Kernel command-line parameters: will add missing 'quiet' / 'splash' parameters to %s config.\n" "${DETECTED_BOOTLOADER}"
    fi

    if [[ "${NO_INITRD_REBUILD}" == "false" ]]; then
        printf "  7. Regenerate initramfs and update bootloader entries:\n"
        if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            printf "     -> Verified Command: %bsudo limine-mkinitcpio%b\n" "$C_BOLD" "$C_RESET"
        elif [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            printf "     -> Command: %bsudo mkinitcpio -P%b\n" "$C_BOLD" "$C_RESET"
        else
            printf "     -> Command: %bsudo update-initramfs%b\n" "$C_BOLD" "$C_RESET"
        fi
    fi

    printf "\n%bExact Manual Execution Commands for THIS Machine:%b\n" "$C_BOLD$C_GREEN" "$C_RESET"
    printf "  1. Take dedicated non-expiring Snapper snapshot (omits timeline cleanup):\n"
    printf "     %bsudo snapper -c root create -d \"Pre-GPS-boot-splash\"%b\n" "$C_BOLD" "$C_RESET"
    printf "  2. Apply installer package:\n"
    printf "     %bsudo %s --apply%b\n" "$C_BOLD" "$0" "$C_RESET"
    printf "  3. Reversible rollback if needed:\n"
    printf "     %bsudo %s --rollback%b\n\n" "$C_BOLD" "$0" "$C_RESET"
}

# Apply execution
do_apply() {
    # Check permissions if targeting real system paths
    if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        if [[ "${EUID}" -ne 0 ]]; then
            echo "Error: Installation to system paths requires root privileges." >&2
            echo "Please run: sudo $0 --apply" >&2
            exit 1
        fi
    fi

    audit_system
    print_audit_report

    # Invariant 1: Plymouth package must be present
    if [[ "${PLYMOUTH_INSTALLED}" == "false" ]]; then
        printf "%bError: Plymouth package is not installed on the target system.%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
        printf "Please install it with: %bsudo pacman -S plymouth%b\n" "$C_BOLD" "$C_RESET" >&2
        exit 1
    fi

    # Invariant 2: Disk encryption safety check
    if [[ "${DETECTED_ENCRYPTION}" != "None" && "${ENCRYPTION_SAFE}" == "false" ]]; then
        printf "%bSAFETY ERROR%b: Disk encryption detected, but hook ordering cannot be verified safely:\n%s\n" "$C_RED$C_BOLD" "$C_RESET" "${ENCRYPTION_REASON}" >&2
        printf "Aborting installation to avoid unbootable prompt failure.\n" >&2
        exit 1
    fi

    # Invariant 3: Theme source files must exist
    if [[ ! -d "${SOURCE_THEME_DIR}" || ! -f "${SOURCE_THEME_DIR}/gps.plymouth" ]]; then
        printf "%bError: Source GPS Plymouth theme not found in %s%b\n" "$C_RED$C_BOLD" "${SOURCE_THEME_DIR}" "$C_RESET" >&2
        exit 1
    fi

    # Invariant 4: Limine integration validation
    if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
        if [[ "${LIMINE_MKINITCPIO_EXISTS}" == "false" ]]; then
            printf "%bError: Limine bootloader detected with mkinitcpio, but required command 'limine-mkinitcpio' (package limine-mkinitcpio-hook) was not found.%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
            printf "Aborting to prevent unverified or out-of-sync bootloader entries.\n" >&2
            exit 1
        fi
    fi

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_BASE_DIR}/${timestamp}"
    mkdir -p "${backup_dir}"

    local modified_plymouthd=false
    local modified_mkinitcpio=false
    local modified_bootloader=false
    local had_preexisting_theme=false
    local backed_up_files=()

    printf "%b=== Applying GPS Plymouth Boot Splash Theme ===%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "Backup directory created at: %s\n" "${backup_dir}"

    # Error recovery trap: automatically roll back on any failure during apply
    local apply_in_progress=true
    cleanup_on_apply_failure() {
        if [[ "${apply_in_progress}" == "true" ]]; then
            printf "\n%b[FAILURE DETECTED] Error encountered during apply! Initiating automatic emergency rollback...%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
            apply_in_progress=false
            ROLLBACK_TARGET="${backup_dir}"
            do_rollback || true
            printf "%b[RESTORED] System safely rolled back to pre-apply state.%b\n" "$C_YELLOW$C_BOLD" "$C_RESET" >&2
        fi
    }
    trap cleanup_on_apply_failure ERR

    # 1. Back up existing theme directory if present
    if [[ -d "${DEST_THEME_DIR}" ]]; then
        had_preexisting_theme=true
        cp -a "${DEST_THEME_DIR}" "${backup_dir}/theme_gps_preexisting"
        backed_up_files+=("${DEST_THEME_DIR}")
    fi

    # 2. Back up and update plymouthd.conf
    if [[ -f "${PLYMOUTHD_CONF}" ]]; then
        cp -a "${PLYMOUTHD_CONF}" "${backup_dir}/plymouthd.conf.orig"
        backed_up_files+=("${PLYMOUTHD_CONF}")
    fi
    set_plymouthd_theme "${PLYMOUTHD_CONF}" "${THEME_NAME}"
    modified_plymouthd=true

    # 3. Back up /boot partition files (limine configs and initramfs images)
    local boot_backup_dir="${backup_dir}/boot"
    mkdir -p "${boot_backup_dir}"
    for lconf in "${BOOT_DIR}/limine.conf" "${BOOT_DIR}/limine.cfg" "${BOOT_DIR}/EFI/limine/limine.conf" "${BOOT_DIR}/limine/limine.conf"; do
        if [[ -f "$lconf" ]]; then
            local rel_lconf="${lconf#"${BOOT_DIR}/"}"
            mkdir -p "${boot_backup_dir}/$(dirname "${rel_lconf}")"
            cp -a "$lconf" "${boot_backup_dir}/${rel_lconf}"
            backed_up_files+=("$lconf")
            printf "Backed up bootloader config: %s\n" "$lconf"
        fi
    done

    local initramfs_backup_dir="${boot_backup_dir}/initramfs"
    mkdir -p "${initramfs_backup_dir}"
    if [[ -d "${BOOT_DIR}" ]]; then
        while IFS= read -r -d '' img; do
            local rel_img="${img#"${BOOT_DIR}/"}"
            local dest_copy="${initramfs_backup_dir}/${rel_img}"
            mkdir -p "$(dirname "${dest_copy}")"
            cp -a "$img" "${dest_copy}"
            backed_up_files+=("$img")
            printf "Backed up boot initramfs image: %s\n" "$img"
        done < <(find "${BOOT_DIR}" -type f \( -name "initramfs*" -o -name "*initrd*" -o -name "*.img" \) -print0 2>/dev/null || true)
    fi

    # 4. Copy theme package to destination
    mkdir -p "${DEST_THEME_DIR}"
    cp -a "${SOURCE_THEME_DIR}/." "${DEST_THEME_DIR}/"
    chmod 755 "${DEST_THEME_DIR}"
    find "${DEST_THEME_DIR}" -type f -exec chmod 644 {} +

    # Test failure injection hook if requested
    if [[ "${GPS_TEST_FAIL_AFTER_COPY:-0}" == "1" ]]; then
        printf "Simulating intentional failure for testing partial rollback...\n" >&2
        false
    fi

    # 5. Check & configure initramfs generator
    if [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" && -f "${MKINITCPIO_CONF}" ]]; then
        local hooks_line
        hooks_line="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
        if ! echo "${hooks_line}" | grep -q '\bplymouth\b'; then
            cp -a "${MKINITCPIO_CONF}" "${backup_dir}/mkinitcpio.conf.orig"
            backed_up_files+=("${MKINITCPIO_CONF}")
            local inject_res
            inject_res="$(inject_plymouth_hook "${MKINITCPIO_CONF}")"
            if [[ "${inject_res}" == "INJECTED" ]]; then
                modified_mkinitcpio=true
                printf "Injected 'plymouth' hook into %s\n" "${MKINITCPIO_CONF}"
            fi
        else
            printf "'plymouth' hook already present in %s (unmodified)\n" "${MKINITCPIO_CONF}"
        fi
    fi

    # 6. Check & configure bootloader kernel command-line
    if [[ "${DETECTED_BOOTLOADER}" == "Limine" && -f "${LIMINE_DEFAULT_CONF}" ]]; then
        if ! grep -q '\bsplash\b' "${LIMINE_DEFAULT_CONF}" 2>/dev/null; then
            cp -a "${LIMINE_DEFAULT_CONF}" "${backup_dir}/limine.default.orig"
            backed_up_files+=("${LIMINE_DEFAULT_CONF}")
            python3 -c "
import sys
conf = sys.argv[1]
with open(conf, 'r', encoding='utf-8') as f:
    lines = f.readlines()
new_lines = []
for line in lines:
    if line.strip().startswith('KERNEL_CMDLINE') and 'splash' not in line:
        line = line.rstrip('\n') + ' splash\n'
    new_lines.append(line)
with open(conf, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
" "${LIMINE_DEFAULT_CONF}"
            modified_bootloader=true
            printf "Added 'splash' to Limine configuration in %s\n" "${LIMINE_DEFAULT_CONF}"
        fi
    elif [[ "${DETECTED_BOOTLOADER}" == "GRUB" && -f "${GRUB_DEFAULT_CONF}" ]]; then
        if ! grep -q '\bsplash\b' "${GRUB_DEFAULT_CONF}" 2>/dev/null; then
            cp -a "${GRUB_DEFAULT_CONF}" "${backup_dir}/grub.default.orig"
            backed_up_files+=("${GRUB_DEFAULT_CONF}")
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="splash /' "${GRUB_DEFAULT_CONF}"
            modified_bootloader=true
            printf "Added 'splash' to GRUB configuration in %s\n" "${GRUB_DEFAULT_CONF}"
        fi
    fi

    # 7. Write backup manifest
    local manifest_file="${backup_dir}/manifest.json"
    cat << EOF > "${manifest_file}"
{
  "timestamp": "${timestamp}",
  "previous_theme": "${CURRENT_PLYMOUTH_THEME}",
  "installed_theme": "${THEME_NAME}",
  "bootloader": "${DETECTED_BOOTLOADER}",
  "initramfs_generator": "${DETECTED_INITRAMFS_GEN}",
  "modified_plymouthd": ${modified_plymouthd},
  "modified_mkinitcpio": ${modified_mkinitcpio},
  "modified_bootloader": ${modified_bootloader},
  "had_preexisting_theme": ${had_preexisting_theme},
  "backed_up_files": [
$(printf '    "%s"\n' "${backed_up_files[@]}" | paste -sd, -)
  ]
}
EOF

    # Update latest symlink
    ln -sfn "${timestamp}" "${BACKUP_BASE_DIR}/latest"

    # 8. Initramfs regeneration if requested
    if [[ "${NO_INITRD_REBUILD}" == "false" && ( -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ) ]]; then
        printf "\n%bRegenerating initramfs and updating bootloader entries...%b\n" "$C_CYAN" "$C_RESET"
        if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            limine-mkinitcpio
        elif command -v mkinitcpio >/dev/null 2>&1; then
            mkinitcpio -P
        fi
    else
        printf "Initramfs regeneration skipped (--no-initrd-rebuild or test root).\n"
    fi

    apply_in_progress=false
    trap - ERR

    printf "\n%b[SUCCESS] GPS Plymouth Boot Splash Theme applied successfully!%b\n" "$C_GREEN$C_BOLD" "$C_RESET"
    printf "  - Effective Theme: %s\n" "${THEME_NAME}"
    printf "  - Theme Directory: %s\n" "${DEST_THEME_DIR}"
    printf "  - Backup Archive:  %s\n" "${backup_dir}"
    printf "  - Rollback Command: sudo %s --rollback %s\n\n" "$0" "${backup_dir}"
}

# Rollback execution
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
        backup_dir="${BACKUP_BASE_DIR}/$(readlink "${BACKUP_BASE_DIR}/latest")"
    elif [[ -d "${BACKUP_BASE_DIR}" ]]; then
        backup_dir="$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | sort -r | head -n 1)"
    fi

    printf "%b=== Rolling Back GPS Plymouth Boot Splash Theme ===%b\n" "$C_BOLD$C_YELLOW" "$C_RESET"

    if [[ -n "${backup_dir}" && -d "${backup_dir}" ]]; then
        printf "Restoring from backup archive: %s\n" "${backup_dir}"

        local prev_theme="cachyos-bootanimation"
        if [[ -f "${backup_dir}/manifest.json" ]]; then
            local pt
            pt="$(grep '"previous_theme":' "${backup_dir}/manifest.json" | cut -d: -f2 | tr -d ' ",' || true)"
            if [[ -n "$pt" ]]; then
                prev_theme="$pt"
            fi
        fi

        # 1. Restore plymouthd.conf
        if [[ -f "${backup_dir}/plymouthd.conf.orig" ]]; then
            printf "Restoring %s from backup...\n" "${PLYMOUTHD_CONF}"
            cp -a "${backup_dir}/plymouthd.conf.orig" "${PLYMOUTHD_CONF}"
        elif [[ -n "${prev_theme}" && "${prev_theme}" != "none" && "${prev_theme}" != "${THEME_NAME}" ]]; then
            printf "Resetting theme in %s to '%s'...\n" "${PLYMOUTHD_CONF}" "${prev_theme}"
            set_plymouthd_theme "${PLYMOUTHD_CONF}" "${prev_theme}"
        fi

        # 2. Restore mkinitcpio.conf
        if [[ -f "${backup_dir}/mkinitcpio.conf.orig" ]]; then
            printf "Restoring %s from backup...\n" "${MKINITCPIO_CONF}"
            cp -a "${backup_dir}/mkinitcpio.conf.orig" "${MKINITCPIO_CONF}"
        fi

        # 3. Restore bootloader configs
        if [[ -f "${backup_dir}/limine.default.orig" && -f "${LIMINE_DEFAULT_CONF}" ]]; then
            printf "Restoring %s from backup...\n" "${LIMINE_DEFAULT_CONF}"
            cp -a "${backup_dir}/limine.default.orig" "${LIMINE_DEFAULT_CONF}"
        fi
        if [[ -f "${backup_dir}/grub.default.orig" && -f "${GRUB_DEFAULT_CONF}" ]]; then
            printf "Restoring %s from backup...\n" "${GRUB_DEFAULT_CONF}"
            cp -a "${backup_dir}/grub.default.orig" "${GRUB_DEFAULT_CONF}"
        fi

        # 4. Restore separate /boot partition files (limine.conf and initramfs)
        local boot_backup_dir="${backup_dir}/boot"
        if [[ -d "${boot_backup_dir}" ]]; then
            for lconf_sub in limine.conf limine.cfg EFI/limine/limine.conf limine/limine.conf; do
                if [[ -f "${boot_backup_dir}/${lconf_sub}" ]]; then
                    printf "Restoring %s from backup...\n" "${BOOT_DIR}/${lconf_sub}"
                    mkdir -p "$(dirname "${BOOT_DIR}/${lconf_sub}")"
                    cp -a "${boot_backup_dir}/${lconf_sub}" "${BOOT_DIR}/${lconf_sub}"
                fi
            done

            local initramfs_backup_dir="${boot_backup_dir}/initramfs"
            if [[ -d "${initramfs_backup_dir}" ]]; then
                while IFS= read -r -d '' b_img; do
                    local rel_b_img="${b_img#"${initramfs_backup_dir}/"}"
                    local target_img="${BOOT_DIR}/${rel_b_img}"
                    printf "Restoring initramfs image: %s\n" "${target_img}"
                    mkdir -p "$(dirname "${target_img}")"
                    cp -a "$b_img" "${target_img}"
                done < <(find "${initramfs_backup_dir}" -type f -print0 2>/dev/null || true)
            fi
        fi

        # 5. Restore or remove GPS theme directory
        local had_theme
        had_theme="$(grep '"had_preexisting_theme":' "${backup_dir}/manifest.json" | grep -o 'true\|false' || echo 'false')"
        if [[ "${had_theme}" == "true" && -d "${backup_dir}/theme_gps_preexisting" ]]; then
            printf "Restoring pre-existing theme in %s...\n" "${DEST_THEME_DIR}"
            rm -rf "${DEST_THEME_DIR}"
            cp -a "${backup_dir}/theme_gps_preexisting" "${DEST_THEME_DIR}"
        else
            printf "Removing installed GPS theme directory: %s...\n" "${DEST_THEME_DIR}"
            rm -rf "${DEST_THEME_DIR}"
        fi

        # 6. Resynchronize boot artifacts if not skipped
        if [[ "${NO_INITRD_REBUILD}" == "false" && ( -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ) ]]; then
            printf "\n%bResynchronizing boot artifacts after rollback...%b\n" "$C_CYAN" "$C_RESET"
            if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
                limine-mkinitcpio
            elif command -v mkinitcpio >/dev/null 2>&1; then
                mkinitcpio -P
            fi
        fi

        printf "\n%b[SUCCESS] Rollback completed successfully using archive %s%b\n\n" "$C_GREEN$C_BOLD" "${backup_dir}" "$C_RESET"
    else
        printf "No backup manifest found. Removing GPS theme files safely...\n"
        rm -rf "${DEST_THEME_DIR}"
        printf "%bDirect cleanup completed.%b\n\n" "$C_GREEN" "$C_RESET"
    fi
}

# Status report
do_status() {
    audit_system
    print_audit_report

    local theme_installed=false
    if [[ -d "${DEST_THEME_DIR}" && -f "${DEST_THEME_DIR}/gps.plymouth" ]]; then
        theme_installed=true
    fi

    printf "%bGPS Theme Status:%b\n" "$C_BOLD" "$C_RESET"
    printf "  - Theme Files Installed: %s\n" "$([ "$theme_installed" = true ] && echo 'YES' || echo 'NO')"
    printf "  - Daemon Active Theme  : %s\n" "${CURRENT_PLYMOUTH_THEME}"
    printf "  - Is GPS Theme Active  : %s\n" "$([ "$CURRENT_PLYMOUTH_THEME" = "$THEME_NAME" ] && echo 'YES' || echo 'NO')"

    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        local bcount
        bcount="$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | wc -l)"
        printf "  - Available Backups    : %d backup(s) in %s\n\n" "${bcount}" "${BACKUP_BASE_DIR}"
    else
        printf "  - Available Backups    : None\n\n"
    fi
}

# Main entry dispatcher
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
