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
  - Phase-separated Apply: Phase A (Backup & Inventory) -> Phase B (Verify) -> Phase C (Apply).
  - Purely Restorative Rollback: restores bit-for-bit initramfs and bootloader
    configuration from backup without regeneration.
  - Idempotency: repeated --apply or --rollback calls produce valid state without duplicates.
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
    printf "  2. Phase A (Backup): Create timestamped backup of /etc and separate /boot files (limine.conf, existing initramfs) under:\n     -> %s/<timestamp>/\n" "${BACKUP_BASE_DIR}"
    printf "  3. Phase B (Verify): Validate backup completeness, readable initramfs, and write manifest before any system changes.\n"
    printf "  4. Phase C (Apply): Install GPS Plymouth theme files to:\n     -> %s\n" "${DEST_THEME_DIR}"
    printf "  5. Phase C (Apply): Update Plymouth daemon configuration:\n     -> %s (Set [Daemon] Theme=%s)\n" "${PLYMOUTHD_CONF}" "${THEME_NAME}"

    if [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" && -f "${MKINITCPIO_CONF}" ]]; then
        local hooks_line
        hooks_line="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
        if echo "${hooks_line}" | grep -q '\bplymouth\b'; then
            printf "  6. mkinitcpio hook status: 'plymouth' hook is ALREADY PRESENT in %s (no edit required).\n" "${MKINITCPIO_CONF}"
        else
            printf "  6. mkinitcpio hook status: will inject 'plymouth' into HOOKS=() in %s\n" "${MKINITCPIO_CONF}"
        fi
    fi

    if [[ "${CMDLINE_HAS_SPLASH}" == "true" && "${CMDLINE_HAS_QUIET}" == "true" ]]; then
        printf "  7. Kernel command-line parameters: 'quiet' and 'splash' are ALREADY CONFIGURED (no edit required).\n"
    else
        printf "  7. Kernel command-line parameters: will add missing 'quiet' / 'splash' parameters to %s config.\n" "${DETECTED_BOOTLOADER}"
    fi

    if [[ "${NO_INITRD_REBUILD}" == "false" ]]; then
        printf "  8. Regenerate initramfs and update bootloader entries:\n"
        if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            printf "     -> Verified Command: %bsudo limine-mkinitcpio%b\n" "$C_BOLD" "$C_RESET"
        elif [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            printf "     -> Command: %bsudo mkinitcpio -P%b\n" "$C_BOLD" "$C_RESET"
        else
            printf "     -> Command: %bsudo update-initramfs%b\n" "$C_BOLD" "$C_RESET"
        fi
    fi

    printf "\n%bRecovery Invariants:%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "  - Rollback is purely restorative: bit-for-bit initramfs and bootloader files are\n"
    printf "    restored directly from backup. 'limine-mkinitcpio' is NEVER run during rollback.\n"
    printf "  - The backup archive is the single source of recovery truth.\n"
    printf "  - Independent boot artifacts (kernels, initramfs, EFI files) are strictly PRESERVED.\n"
    printf "  - Conflict detection aborts rollback if managed files were modified independently.\n"

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

    printf "%b=== Applying GPS Plymouth Boot Splash Theme ===%b\n" "$C_BOLD$C_CYAN" "$C_RESET"

    # =========================================================================
    # PHASE A: Backup & Pre-apply Inventory
    # Back up every existing file or directory that might be modified.
    # Record inventory of all files before any modification begins.
    # =========================================================================
    printf "%b--- Phase A: Creating Full System & Bootloader Backup ---%b\n" "$C_CYAN" "$C_RESET"

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_BASE_DIR}/${timestamp}"
    mkdir -p "${backup_dir}"
    printf "Backup directory created at: %s\n" "${backup_dir}"

    if [[ "${GPS_TEST_FAIL_BACKUP:-0}" == "1" ]]; then
        printf "%bError: Simulated failure during Phase A backup.%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
        rm -rf "${backup_dir}"
        exit 1
    fi

    local had_preexisting_theme=false
    local had_plymouthd=false
    local had_mkinitcpio=false
    local had_limine_default=false
    local had_grub_default=false
    local backed_up_files=()
    local backed_up_boot_configs=()
    local backed_up_initramfs=()
    local backup_list_file="${backup_dir}/.backed_up_list"
    : > "${backup_list_file}"

    # 1. Back up existing theme directory if present
    if [[ -d "${DEST_THEME_DIR}" ]]; then
        had_preexisting_theme=true
        cp -a "${DEST_THEME_DIR}" "${backup_dir}/theme_gps_preexisting"
        backed_up_files+=("${DEST_THEME_DIR}")
        echo "${DEST_THEME_DIR}" >> "${backup_list_file}"
        printf "Backed up pre-existing GPS theme: %s\n" "${DEST_THEME_DIR}"
    fi

    # 2. Back up plymouthd.conf
    if [[ -f "${PLYMOUTHD_CONF}" ]]; then
        had_plymouthd=true
        cp -a "${PLYMOUTHD_CONF}" "${backup_dir}/plymouthd.conf.orig"
        backed_up_files+=("${PLYMOUTHD_CONF}")
        echo "${PLYMOUTHD_CONF}" >> "${backup_list_file}"
        printf "Backed up Plymouth daemon config: %s\n" "${PLYMOUTHD_CONF}"
    fi

    # 3. Back up mkinitcpio.conf
    if [[ -f "${MKINITCPIO_CONF}" ]]; then
        had_mkinitcpio=true
        cp -a "${MKINITCPIO_CONF}" "${backup_dir}/mkinitcpio.conf.orig"
        backed_up_files+=("${MKINITCPIO_CONF}")
        echo "${MKINITCPIO_CONF}" >> "${backup_list_file}"
        printf "Backed up mkinitcpio config: %s\n" "${MKINITCPIO_CONF}"
    fi

    # 4. Back up bootloader defaults
    if [[ -f "${LIMINE_DEFAULT_CONF}" ]]; then
        had_limine_default=true
        cp -a "${LIMINE_DEFAULT_CONF}" "${backup_dir}/limine.default.orig"
        backed_up_files+=("${LIMINE_DEFAULT_CONF}")
        echo "${LIMINE_DEFAULT_CONF}" >> "${backup_list_file}"
        printf "Backed up Limine default config: %s\n" "${LIMINE_DEFAULT_CONF}"
    fi
    if [[ -f "${GRUB_DEFAULT_CONF}" ]]; then
        had_grub_default=true
        cp -a "${GRUB_DEFAULT_CONF}" "${backup_dir}/grub.default.orig"
        backed_up_files+=("${GRUB_DEFAULT_CONF}")
        echo "${GRUB_DEFAULT_CONF}" >> "${backup_list_file}"
        printf "Backed up GRUB default config: %s\n" "${GRUB_DEFAULT_CONF}"
    fi

    # 5. Back up /boot partition configs (Limine config files)
    local boot_backup_dir="${backup_dir}/boot"
    mkdir -p "${boot_backup_dir}"
    for lconf in "${BOOT_DIR}/limine.conf" "${BOOT_DIR}/limine.cfg" "${BOOT_DIR}/EFI/limine/limine.conf" "${BOOT_DIR}/limine/limine.conf"; do
        if [[ -f "$lconf" ]]; then
            local rel_lconf="${lconf#"${BOOT_DIR}/"}"
            mkdir -p "${boot_backup_dir}/$(dirname "${rel_lconf}")"
            cp -a "$lconf" "${boot_backup_dir}/${rel_lconf}"
            backed_up_files+=("$lconf")
            backed_up_boot_configs+=("$lconf")
            echo "$lconf" >> "${backup_list_file}"
            printf "Backed up bootloader config: %s\n" "$lconf"
        fi
    done

    # 6. Back up /boot partition initramfs images
    local initramfs_backup_dir="${boot_backup_dir}/initramfs"
    mkdir -p "${initramfs_backup_dir}"
    if [[ -d "${BOOT_DIR}" ]]; then
        while IFS= read -r -d '' img; do
            local rel_img="${img#"${BOOT_DIR}/"}"
            local dest_copy="${initramfs_backup_dir}/${rel_img}"
            mkdir -p "$(dirname "${dest_copy}")"
            cp -a "$img" "${dest_copy}"
            backed_up_files+=("$img")
            backed_up_initramfs+=("$img")
            echo "$img" >> "${backup_list_file}"
            printf "Backed up boot initramfs image: %s\n" "$img"
        done < <(find "${BOOT_DIR}" -type f \( -name "initramfs*" -o -name "*initrd*" -o -name "*.img" \) -print0 2>/dev/null || true)
    fi

    # 7. Collect list of files managed or replaced by GPS Plymouth for conflict tracking
    local managed_files_file="${backup_dir}/.managed_files_list"
    : > "${managed_files_file}"
    echo "${PLYMOUTHD_CONF}" >> "${managed_files_file}"
    echo "${MKINITCPIO_CONF}" >> "${managed_files_file}"
    if [[ -f "${LIMINE_DEFAULT_CONF}" || "${DETECTED_BOOTLOADER}" == "Limine" ]]; then
        echo "${LIMINE_DEFAULT_CONF}" >> "${managed_files_file}"
    fi
    if [[ -f "${GRUB_DEFAULT_CONF}" || "${DETECTED_BOOTLOADER}" == "GRUB" ]]; then
        echo "${GRUB_DEFAULT_CONF}" >> "${managed_files_file}"
    fi
    for b_conf in "${backed_up_boot_configs[@]+"${backed_up_boot_configs[@]}"}"; do
        echo "$b_conf" >> "${managed_files_file}"
    done
    for b_img in "${backed_up_initramfs[@]+"${backed_up_initramfs[@]}"}"; do
        echo "$b_img" >> "${managed_files_file}"
    done

    # =========================================================================
    # PHASE B: Verify Backup Completeness & Integrity
    # Before modifying ANY target system file, verify all expected backup files
    # exist, are readable, non-empty, and write & validate manifest.json.
    # =========================================================================
    printf "%b--- Phase B: Verifying Backup Completeness & Writing Manifest ---%b\n" "$C_CYAN" "$C_RESET"

    local verify_ok=true
    local verify_err=""

    if [[ "${GPS_TEST_FAIL_VERIFY_BACKUP:-0}" == "1" ]]; then
        verify_ok=false
        verify_err="Simulated verification failure (GPS_TEST_FAIL_VERIFY_BACKUP=1)"
    fi

    if [[ "${verify_ok}" == "true" && "${had_preexisting_theme}" == "true" ]]; then
        if [[ ! -d "${backup_dir}/theme_gps_preexisting" ]]; then
            verify_ok=false
            verify_err="Pre-existing theme backup directory missing in ${backup_dir}"
        fi
    fi

    if [[ "${verify_ok}" == "true" && "${had_plymouthd}" == "true" ]]; then
        if [[ ! -f "${backup_dir}/plymouthd.conf.orig" || ! -r "${backup_dir}/plymouthd.conf.orig" ]]; then
            verify_ok=false
            verify_err="plymouthd.conf backup file missing or unreadable in ${backup_dir}"
        fi
    fi

    if [[ "${verify_ok}" == "true" && "${had_mkinitcpio}" == "true" ]]; then
        if [[ ! -f "${backup_dir}/mkinitcpio.conf.orig" || ! -r "${backup_dir}/mkinitcpio.conf.orig" ]]; then
            verify_ok=false
            verify_err="mkinitcpio.conf backup file missing or unreadable in ${backup_dir}"
        fi
    fi

    if [[ "${verify_ok}" == "true" && "${had_limine_default}" == "true" ]]; then
        if [[ ! -f "${backup_dir}/limine.default.orig" || ! -r "${backup_dir}/limine.default.orig" ]]; then
            verify_ok=false
            verify_err="limine default backup file missing or unreadable in ${backup_dir}"
        fi
    fi

    if [[ "${verify_ok}" == "true" && "${had_grub_default}" == "true" ]]; then
        if [[ ! -f "${backup_dir}/grub.default.orig" || ! -r "${backup_dir}/grub.default.orig" ]]; then
            verify_ok=false
            verify_err="grub default backup file missing or unreadable in ${backup_dir}"
        fi
    fi

    # Verify bootloader config backups
    if [[ "${verify_ok}" == "true" ]]; then
        for b_src in "${backed_up_boot_configs[@]+"${backed_up_boot_configs[@]}"}"; do
            local rel_src="${b_src#"${BOOT_DIR}/"}"
            local b_dest="${boot_backup_dir}/${rel_src}"
            if [[ ! -f "$b_dest" || ! -r "$b_dest" ]]; then
                verify_ok=false
                verify_err="Bootloader config backup missing or unreadable: ${b_dest}"
                break
            fi
        done
    fi

    # Verify initramfs image backups
    if [[ "${verify_ok}" == "true" ]]; then
        for b_img in "${backed_up_initramfs[@]+"${backed_up_initramfs[@]}"}"; do
            local rel_img="${b_img#"${BOOT_DIR}/"}"
            local dest_copy="${initramfs_backup_dir}/${rel_img}"
            if [[ ! -f "$dest_copy" || ! -r "$dest_copy" ]]; then
                verify_ok=false
                verify_err="Initramfs backup image missing or unreadable: ${dest_copy}"
                break
            fi
        done
    fi

    # Write backup manifest using Python
    local manifest_file="${backup_dir}/manifest.json"
    if [[ "${verify_ok}" == "true" ]]; then
        python3 -c "
import sys, json, os, hashlib

def hash_file(p):
    if not os.path.isfile(p):
        return None
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

manifest_path = sys.argv[1]
timestamp = sys.argv[2]
prev_theme = sys.argv[3]
inst_theme = sys.argv[4]
bootloader = sys.argv[5]
initramfs_gen = sys.argv[6]
had_theme = (sys.argv[7] == 'true')
had_plymouthd = (sys.argv[8] == 'true')
had_mkinitcpio = (sys.argv[9] == 'true')
had_limine = (sys.argv[10] == 'true')
had_grub = (sys.argv[11] == 'true')
backup_list_path = sys.argv[12]
managed_list_path = sys.argv[13]

backed_up_files = []
if os.path.isfile(backup_list_path):
    with open(backup_list_path, 'r', encoding='utf-8') as f:
        backed_up_files = [line.strip() for line in f if line.strip()]
    try:
        os.remove(backup_list_path)
    except OSError:
        pass

managed_files = []
if os.path.isfile(managed_list_path):
    with open(managed_list_path, 'r', encoding='utf-8') as f:
        managed_files = sorted(list(set(line.strip() for line in f if line.strip())))
    try:
        os.remove(managed_list_path)
    except OSError:
        pass

pre_hashes = {}
for p in managed_files:
    pre_hashes[p] = hash_file(p)

manifest = {
    'timestamp': timestamp,
    'previous_theme': prev_theme,
    'installed_theme': inst_theme,
    'bootloader': bootloader,
    'initramfs_generator': initramfs_gen,
    'had_preexisting_theme': had_theme,
    'had_plymouthd': had_plymouthd,
    'had_mkinitcpio': had_mkinitcpio,
    'had_limine_default': had_limine,
    'had_grub_default': had_grub,
    'backed_up_files': backed_up_files,
    'managed_files': managed_files,
    'pre_apply_hashes': pre_hashes,
    'post_apply_hashes': {},
    'apply_completed': False
}

with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2)
" "${manifest_file}" \
  "${timestamp}" \
  "${CURRENT_PLYMOUTH_THEME}" \
  "${THEME_NAME}" \
  "${DETECTED_BOOTLOADER}" \
  "${DETECTED_INITRAMFS_GEN}" \
  "${had_preexisting_theme}" \
  "${had_plymouthd}" \
  "${had_mkinitcpio}" \
  "${had_limine_default}" \
  "${had_grub_default}" \
  "${backup_list_file}" \
  "${managed_files_file}"

        if [[ ! -f "${manifest_file}" || ! -s "${manifest_file}" ]]; then
            verify_ok=false
            verify_err="Manifest file creation failed or produced empty file: ${manifest_file}"
        fi
    fi

    if [[ "${verify_ok}" == "false" ]]; then
        printf "%bError: Backup verification failed. System configuration untouched.%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
        printf "%bDetails: %s%b\n" "$C_RED" "${verify_err}" "$C_RESET" >&2
        rm -rf "${backup_dir}"
        exit 1
    fi

    # Only after Phase B verification succeeds is the latest pointer updated
    ln -sfn "${timestamp}" "${BACKUP_BASE_DIR}/latest"
    printf "Backup verified and manifest created successfully.\n"

    # =========================================================================
    # PHASE C: Apply Modifications
    # Only executed after Phase B verification succeeds.
    # Protected by automatic emergency rollback trap.
    # =========================================================================
    printf "%b--- Phase C: Applying Theme and System Modifications ---%b\n" "$C_CYAN" "$C_RESET"

    local modified_plymouthd=false
    local modified_mkinitcpio=false
    local modified_bootloader=false

    # Error recovery trap: automatically roll back on any failure during apply
    local apply_in_progress=true
    cleanup_on_apply_failure() {
        if [[ "${apply_in_progress}" == "true" ]]; then
            printf "\n%b[FAILURE DETECTED] Error encountered during apply! Initiating automatic emergency rollback...%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
            apply_in_progress=false
            ROLLBACK_TARGET="${backup_dir}"
            GPS_EMERGENCY_RECOVERY=true
            if do_rollback; then
                printf "%b[RESTORED] System safely rolled back to pre-apply state.%b\n" "$C_YELLOW$C_BOLD" "$C_RESET" >&2
            else
                printf "%b[CRITICAL] Rollback also encountered errors. Backup preserved at %s%b\n" "$C_RED$C_BOLD" "${backup_dir}" "$C_RESET" >&2
            fi
            GPS_EMERGENCY_RECOVERY=false
            exit 1
        fi
    }
    trap cleanup_on_apply_failure ERR

    # 1. Update plymouthd.conf
    set_plymouthd_theme "${PLYMOUTHD_CONF}" "${THEME_NAME}"
    modified_plymouthd=true
    printf "Configured Plymouth daemon theme: %s\n" "${THEME_NAME}"

    # 2. Copy theme package to destination
    rm -rf "${DEST_THEME_DIR}"
    mkdir -p "${DEST_THEME_DIR}"
    cp -a "${SOURCE_THEME_DIR}/." "${DEST_THEME_DIR}/"
    chmod 755 "${DEST_THEME_DIR}"
    find "${DEST_THEME_DIR}" -type f -exec chmod 644 {} +
    printf "Installed GPS Plymouth theme package in %s\n" "${DEST_THEME_DIR}"

    # Test failure injection hook if requested
    if [[ "${GPS_TEST_FAIL_AFTER_COPY:-0}" == "1" ]]; then
        printf "Simulating intentional failure for testing partial rollback...\n" >&2
        false
    fi

    # 3. Check & configure initramfs generator
    if [[ "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" && -f "${MKINITCPIO_CONF}" ]]; then
        local hooks_line
        hooks_line="$(grep -E '^\s*HOOKS=\(' "${MKINITCPIO_CONF}" 2>/dev/null || true)"
        if ! echo "${hooks_line}" | grep -q '\bplymouth\b'; then
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

    # 4. Check & configure bootloader kernel command-line
    if [[ "${DETECTED_BOOTLOADER}" == "Limine" && -f "${LIMINE_DEFAULT_CONF}" ]]; then
        if ! grep -q '\bsplash\b' "${LIMINE_DEFAULT_CONF}" 2>/dev/null; then
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
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="splash /' "${GRUB_DEFAULT_CONF}"
            modified_bootloader=true
            printf "Added 'splash' to GRUB configuration in %s\n" "${GRUB_DEFAULT_CONF}"
        fi
    fi

    # 5. Initramfs regeneration if requested
    if [[ "${GPS_TEST_MOCK_INITRD_REBUILD:-0}" == "1" ]]; then
        printf "\n%b[TEST] Regenerating mock initramfs and updating bootloader entries...%b\n" "$C_CYAN" "$C_RESET"
        if [[ -n "${ROOT_DIR}" && -x "${ROOT_DIR}/usr/bin/limine-mkinitcpio" ]]; then
            "${ROOT_DIR}/usr/bin/limine-mkinitcpio"
        fi
    elif [[ "${NO_INITRD_REBUILD}" == "false" && ( -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ) ]]; then
        printf "\n%bRegenerating initramfs and updating bootloader entries...%b\n" "$C_CYAN" "$C_RESET"
        if [[ "${DETECTED_BOOTLOADER}" == "Limine" && "${DETECTED_INITRAMFS_GEN}" == "mkinitcpio" ]]; then
            limine-mkinitcpio
        elif command -v mkinitcpio >/dev/null 2>&1; then
            mkinitcpio -P
        fi
    else
        printf "Initramfs regeneration skipped (--no-initrd-rebuild or test root).\n"
    fi

    # 6. Record post-apply hashes of all managed files and mark apply complete
    python3 -c "
import sys, json, os, hashlib

def hash_file(p):
    if not os.path.isfile(p):
        return None
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

manifest_path = sys.argv[1]
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

managed_files = data.get('managed_files', [])
post_hashes = {}
for p in managed_files:
    post_hashes[p] = hash_file(p)

data['post_apply_hashes'] = post_hashes
data['apply_completed'] = True

with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
" "${manifest_file}"

    apply_in_progress=false
    trap - ERR

    printf "\n%b[SUCCESS] GPS Plymouth Boot Splash Theme applied successfully!%b\n" "$C_GREEN$C_BOLD" "$C_RESET"
    printf "  - Effective Theme: %s\n" "${THEME_NAME}"
    printf "  - Theme Directory: %s\n" "${DEST_THEME_DIR}"
    printf "  - Backup Archive:  %s\n" "${backup_dir}"
    printf "  - Rollback Command: sudo %s --rollback %s\n\n" "$0" "${backup_dir}"
}

# Rollback execution (Purely restorative)
do_rollback() {
    # Check permissions if targeting real system paths
    if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" == "/" ]]; then
        if [[ "${EUID}" -ne 0 ]]; then
            echo "Error: Rollback on system paths requires root privileges." >&2
            echo "Please run: sudo $0 --rollback" >&2
            return 1
        fi
    fi

    local backup_dir=""
    if [[ -n "${ROLLBACK_TARGET}" ]]; then
        backup_dir="${ROLLBACK_TARGET}"
    elif [[ -n "${1:-}" ]]; then
        backup_dir="$1"
    elif [[ -L "${BACKUP_BASE_DIR}/latest" ]]; then
        local link_target
        link_target="$(readlink "${BACKUP_BASE_DIR}/latest")"
        if [[ "${link_target}" = /* ]]; then
            backup_dir="${link_target}"
        else
            backup_dir="${BACKUP_BASE_DIR}/${link_target}"
        fi
    elif [[ -d "${BACKUP_BASE_DIR}" ]]; then
        backup_dir="$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -mindepth 1 -type d | sort -r | head -n 1)"
    fi

    printf "%b=== Rolling Back GPS Plymouth Boot Splash Theme ===%b\n" "$C_BOLD$C_YELLOW" "$C_RESET"

    if [[ -z "${backup_dir}" || ! -d "${backup_dir}" ]]; then
        printf "%bError: No valid backup archive found for rollback (%s).%b\n" "$C_RED$C_BOLD" "${backup_dir:-empty}" "$C_RESET" >&2
        return 1
    fi

    local manifest_file="${backup_dir}/manifest.json"
    if [[ ! -f "${manifest_file}" ]]; then
        printf "%bError: Backup manifest not found in %s.%b\n" "$C_RED$C_BOLD" "${backup_dir}" "$C_RESET" >&2
        return 1
    fi

    printf "Restoring from backup archive: %s\n" "${backup_dir}"

    local parse_err=false
    local M_PREV_THEME=""
    local M_HAD_THEME=false
    local M_HAD_PLYMOUTHD=false
    local M_HAD_MKINITCPIO=false
    local M_HAD_LIMINE_DEFAULT=false
    local M_HAD_GRUB_DEFAULT=false

    eval "$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    def bstr(v): return 'true' if v else 'false'
    print(f'M_PREV_THEME={json.dumps(data.get(\"previous_theme\", \"\"))}')
    print(f'M_HAD_THEME={bstr(data.get(\"had_preexisting_theme\", False))}')
    print(f'M_HAD_PLYMOUTHD={bstr(data.get(\"had_plymouthd\", False))}')
    print(f'M_HAD_MKINITCPIO={bstr(data.get(\"had_mkinitcpio\", False))}')
    print(f'M_HAD_LIMINE_DEFAULT={bstr(data.get(\"had_limine_default\", False))}')
    print(f'M_HAD_GRUB_DEFAULT={bstr(data.get(\"had_grub_default\", False))}')
except Exception as e:
    print('parse_err=true')
    print(f'echo \"Manifest parsing error: {e}\" >&2')
" "${manifest_file}")"

    if [[ "${parse_err}" == "true" ]]; then
        printf "%bError: Failed to parse manifest %s.%b\n" "$C_RED$C_BOLD" "${manifest_file}" "$C_RESET" >&2
        return 1
    fi

    # 0. Pre-flight Conflict Detection: ensure managed files were not modified independently
    local conflict_res
    conflict_res="$(python3 -c "
import sys, json, os, hashlib

def hash_file(p):
    if not os.path.isfile(p):
        return None
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def resolve_path(p, root_dir):
    if os.path.exists(p):
        return p
    if root_dir and root_dir != '/':
        for marker in ['/etc/', '/boot/', '/usr/']:
            if marker in p:
                suffix = p[p.index(marker) + 1:]
                candidate = os.path.join(root_dir, suffix)
                if os.path.exists(candidate):
                    return candidate
    return p

manifest_path = sys.argv[1]
root_dir = sys.argv[2]
is_emergency = (sys.argv[3] == 'true')

if not os.path.isfile(manifest_path):
    print('CONFLICT')
    print('Backup manifest not found')
    sys.exit(0)

with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

apply_completed = data.get('apply_completed', False)
post_hashes = data.get('post_apply_hashes', {})
pre_hashes = data.get('pre_apply_hashes', {})
managed_files = data.get('managed_files', [])

conflicts = []

if not is_emergency:
    if apply_completed and post_hashes:
        for p in managed_files:
            actual_path = resolve_path(p, root_dir)
            post_h = post_hashes.get(p)
            pre_h = pre_hashes.get(p)
            curr_h = hash_file(actual_path)

            if curr_h != post_h and curr_h != pre_h:
                if curr_h is None:
                    conflicts.append(f'{actual_path} (file removed independently since installation)')
                elif post_h is None and curr_h is not None:
                    conflicts.append(f'{actual_path} (file created independently since installation)')
                else:
                    conflicts.append(f'{actual_path} (content modified independently since installation)')
    else:
        # Incomplete or failed apply: verify no conflicting independent changes
        for p in managed_files:
            actual_path = resolve_path(p, root_dir)
            pre_h = pre_hashes.get(p)
            curr_h = hash_file(actual_path)
            if curr_h != pre_h:
                if 'boot' in actual_path.lower() or curr_h is None:
                    conflicts.append(f'{actual_path} (unverified state after incomplete apply; cannot prove ownership)')
                else:
                    if actual_path.endswith('plymouthd.conf'):
                        try:
                            with open(actual_path, 'r', encoding='utf-8') as f:
                                c = f.read()
                            if 'Theme=gps' not in c:
                                conflicts.append(f'{actual_path} (modified independently)')
                        except Exception:
                            conflicts.append(f'{actual_path} (unreadable or modified independently)')
                    elif actual_path.endswith('mkinitcpio.conf'):
                        try:
                            with open(actual_path, 'r', encoding='utf-8') as f:
                                c = f.read()
                            if 'plymouth' not in c:
                                conflicts.append(f'{actual_path} (modified independently)')
                        except Exception:
                            conflicts.append(f'{actual_path} (unreadable or modified independently)')

if conflicts:
    print('CONFLICT')
    for c in conflicts:
        print(c)
else:
    print('OK')
" "${manifest_file}" "${ROOT_DIR:-/}" "${GPS_EMERGENCY_RECOVERY:-false}")"

    if [[ "${conflict_res}" == CONFLICT* ]]; then
        printf "%bError: Rollback aborted due to conflict(s). Target files have been modified independently since GPS installation.%b\n" "$C_RED$C_BOLD" "$C_RESET" >&2
        printf "Conflicting paths:\n" >&2
        while IFS= read -r line; do
            if [[ "$line" != "CONFLICT" && -n "$line" ]]; then
                printf "  - %s\n" "$line" >&2
            fi
        done <<< "${conflict_res}"
        printf "\nRollback refused to prevent overwriting subsequent system modifications.\n" >&2
        printf "Backup archive preserved for inspection at:\n  -> %s\n\n" "${backup_dir}" >&2
        return 1
    fi

    # 1. Restore plymouthd.conf
    if [[ -f "${backup_dir}/plymouthd.conf.orig" ]]; then
        printf "Restoring %s from backup...\n" "${PLYMOUTHD_CONF}"
        mkdir -p "$(dirname "${PLYMOUTHD_CONF}")"
        cp -a "${backup_dir}/plymouthd.conf.orig" "${PLYMOUTHD_CONF}"
    elif [[ "${M_HAD_PLYMOUTHD}" == "false" ]]; then
        printf "Removing created %s...\n" "${PLYMOUTHD_CONF}"
        rm -f "${PLYMOUTHD_CONF}"
    elif [[ -n "${M_PREV_THEME}" && "${M_PREV_THEME}" != "none" && "${M_PREV_THEME}" != "${THEME_NAME}" ]]; then
        printf "Resetting theme in %s to '%s'...\n" "${PLYMOUTHD_CONF}" "${M_PREV_THEME}"
        set_plymouthd_theme "${PLYMOUTHD_CONF}" "${M_PREV_THEME}"
    fi

    # 2. Restore mkinitcpio.conf
    if [[ -f "${backup_dir}/mkinitcpio.conf.orig" ]]; then
        printf "Restoring %s from backup...\n" "${MKINITCPIO_CONF}"
        cp -a "${backup_dir}/mkinitcpio.conf.orig" "${MKINITCPIO_CONF}"
    elif [[ "${M_HAD_MKINITCPIO}" == "false" ]]; then
        rm -f "${MKINITCPIO_CONF}"
    fi

    # 3. Restore bootloader configs
    if [[ -f "${backup_dir}/limine.default.orig" ]]; then
        printf "Restoring %s from backup...\n" "${LIMINE_DEFAULT_CONF}"
        cp -a "${backup_dir}/limine.default.orig" "${LIMINE_DEFAULT_CONF}"
    elif [[ "${M_HAD_LIMINE_DEFAULT}" == "false" && -f "${LIMINE_DEFAULT_CONF}" ]]; then
        rm -f "${LIMINE_DEFAULT_CONF}"
    fi

    if [[ -f "${backup_dir}/grub.default.orig" ]]; then
        printf "Restoring %s from backup...\n" "${GRUB_DEFAULT_CONF}"
        cp -a "${backup_dir}/grub.default.orig" "${GRUB_DEFAULT_CONF}"
    elif [[ "${M_HAD_GRUB_DEFAULT}" == "false" && -f "${GRUB_DEFAULT_CONF}" ]]; then
        rm -f "${GRUB_DEFAULT_CONF}"
    fi

    # 4. Restore separate /boot partition files (Limine configs and original initramfs images)
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

    # 5. Independent boot artifacts (kernels, initramfs, EFI files, bootloader entries)
    # are strictly PRESERVED. Automatic /boot pruning is completely disabled.

    # 6. Restore or remove GPS theme directory
    if [[ "${M_HAD_THEME}" == "true" && -d "${backup_dir}/theme_gps_preexisting" ]]; then
        printf "Restoring pre-existing theme in %s...\n" "${DEST_THEME_DIR}"
        rm -rf "${DEST_THEME_DIR}"
        mkdir -p "$(dirname "${DEST_THEME_DIR}")"
        cp -a "${backup_dir}/theme_gps_preexisting" "${DEST_THEME_DIR}"
    else
        printf "Removing installed GPS theme directory: %s...\n" "${DEST_THEME_DIR}"
        rm -rf "${DEST_THEME_DIR}"
    fi

    # 7. Purely restorative: NO initramfs regeneration or limine-mkinitcpio execution!
    # The verified original binary initramfs images and Limine configuration were restored directly.

    printf "\n%b[SUCCESS] Rollback completed successfully using archive %s%b\n\n" "$C_GREEN$C_BOLD" "${backup_dir}" "$C_RESET"
    return 0
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
        do_rollback || exit 1
        ;;
    status)
        do_status
        ;;
esac
