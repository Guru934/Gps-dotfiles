# GPS Desktop — Login Screen Theme Package (Unapplied)

> [!IMPORTANT]
> **This package is STANDALONE and UNAPPLIED.**
> The active system login configuration has NOT been modified, and the GPS theme has NOT been activated. The system continues to use its default display manager theme (`caelestia`).

---

## 1. Audit & Detected Display Manager

An audit of the host system detected the following active display manager configuration:

| Component | Detected Specification |
| :--- | :--- |
| **Display Manager** | **SDDM** (Simple Desktop Display Manager) `0.21.0-8` |
| **Active Service** | `display-manager.service -> /usr/lib/systemd/system/sddm.service` (enabled) |
| **Greeter Binary** | `/usr/bin/sddm-greeter-qt6` (Qt 6.12.0) |
| **Display Server** | X11/XCB display server for greeter, launching Wayland sessions (`Hyprland`, `GNOME`) |
| **Active Theme** | `caelestia` |
| **Active Config Files** | `/etc/sddm.conf` (sets `[Theme] Current=caelestia`)<br>`/etc/sddm.conf.d/caelestia.conf`<br>`/etc/sddm.conf.d/theme.conf` |
| **System Accounts** | `guru` (UID 1000), `rice` (UID 1001) |

---

## 2. SDDM Configuration Precedence Rules

According to `sddm.conf(5)`, SDDM evaluates configuration in the following order:

1. `/usr/lib/sddm/sddm.conf.d/*.conf` — System configuration directory (lowest precedence).
2. `/etc/sddm.conf.d/*.conf` — Local configuration drop-in directory (evaluated in alphabetical order; files sorting later override earlier ones).
3. `/etc/sddm.conf` — Local configuration file for compatibility (**HIGHEST PRECEDENCE**).

### Confirmed Precedence Conflict on This Machine
On this machine, `/etc/sddm.conf` explicitly contains:
```ini
[Theme]
Current=caelestia
```
Because `/etc/sddm.conf` is loaded last and has higher precedence than `/etc/sddm.conf.d/`, a drop-in file placed in `/etc/sddm.conf.d/` will be **shadowed** and ineffective unless `/etc/sddm.conf` is updated.

The installer strictly enforces this rule:
- It uses the drop-in name `zz-gps-theme.conf` (sorting after `caelestia.conf` and `theme.conf` in `/etc/sddm.conf.d/`).
- By default, `--apply` evaluates SDDM precedence and will **refuse to run** if `/etc/sddm.conf` or a conflicting drop-in would shadow the theme.

---

## 3. Package Contents

The `login/` directory contains a self-contained, offline-ready theme package:

```text
login/
├── README.md                 # This documentation and recovery guide
├── install-login.sh          # Safe, precedence-aware installer (defaults to dry-run)
├── preview.sh                # Test-mode runner and screenshot generator
├── preview.png               # Rendered 1280x800 preview screenshot
└── theme/                    # SDDM Qt6 theme package
    ├── metadata.desktop      # SDDM theme metadata (QtVersion=6)
    ├── theme.conf            # Greeter configuration & color assignments
    ├── palette.json          # Static GPS color tokens
    ├── Theme.js              # QML palette binding module
    ├── Main.qml              # Root login interface (responsive 1280x800 layout)
    ├── components/
    │   ├── GlassCard.qml     # GPS translucent glass container
    │   ├── Clock.qml         # Real-time clock and localized date
    │   ├── UserSelector.qml  # Multi-user switcher with avatar fallback
    │   ├── SessionSelector.qml # Wayland/X11 session picker pill
    │   ├── PasswordInput.qml # Password field with reveal toggle & Caps Lock badge
    │   ├── LoginCard.qml     # Core card with auth feedback & shake animation
    │   └── PowerBar.qml      # Power, reboot, and suspend actions
    └── assets/
        ├── background.jpg    # Bundled cinematic dark wallpaper (114 KB)
        ├── user-avatar.svg   # Default user silhouette
        ├── session-hyprland.svg # Hyprland desktop icon
        ├── lock.svg          # Password field lock icon
        ├── eye-open.svg      # Reveal password icon
        ├── eye-closed.svg    # Conceal password icon
        ├── power.svg         # Power off icon
        ├── reboot.svg        # Reboot icon
        └── suspend.svg       # Suspend icon
```

---

## 4. How to Preview the Package

You can test and preview the theme safely without root privileges and without modifying system files.

### Interactive Preview (Windowed)
To open the theme in a test window using the installed SDDM Qt6 greeter:
```bash
./login/preview.sh
# Or directly:
sddm-greeter-qt6 --test-mode --theme "$(pwd)/login/theme"
```

### Headless Verification
To verify QML loading and component bindings headlessly:
```bash
./login/preview.sh --offscreen
```

### Capture Preview Screenshot
To generate a 1280 × 800 screenshot image (`login/preview.png`):
```bash
./login/preview.sh --screenshot login/preview.png
```

---

## 5. How to Inspect Installation (Dry-Run)

The installer script **defaults to dry-run mode** and will never modify your system unless explicitly commanded with `--apply`.

```bash
./login/install-login.sh
# Or explicitly:
./login/install-login.sh --dry-run
```

To inspect current system installation status and effective theme:
```bash
./login/install-login.sh --status
```

---

## 6. Manual Installation (When Ready)

> [!WARNING]
> Do not run this command unless you explicitly intend to activate the GPS login screen on your machine.
> Root permissions (`sudo`) are required because display manager themes live in root-owned directories.

Because `/etc/sddm.conf` explicitly sets `[Theme] Current=caelestia`, you have two supported methods to install:

### Method A: Automated Resolution with Reversible Backup (Recommended)
Allow the installer to back up `/etc/sddm.conf` and comment out `Current=caelestia` so that drop-ins govern the theme:
```bash
sudo ./login/install-login.sh --apply --update-sddm-conf
```

### Method B: Manual Prerequisite Resolution
1. Edit `/etc/sddm.conf` and comment out `Current=caelestia`:
   ```ini
   [Theme]
   # Current=caelestia
   ```
2. Apply the drop-in:
   ```bash
   sudo ./login/install-login.sh --apply
   ```

### Exact Files Modified by the Installer:
1. **Theme Files Copied**:
   - Destination: `/usr/share/sddm/themes/gps/`
   - Copies: `login/theme/*`
2. **Drop-in Configuration Created**:
   - Destination: `/etc/sddm.conf.d/zz-gps-theme.conf`
   - Contents:
     ```ini
     [Theme]
     Current=gps
     ```
   - *Why `zz-`?* In `/etc/sddm.conf.d/`, files sort in alphabetical order (`LC_ALL=C`). `zz-gps-theme.conf` sorts after `caelestia.conf` and `theme.conf`, ensuring GPS overrides prior drop-ins.
3. **Compatibility Config Updated** (only with `--update-sddm-conf`):
   - Modifies `/etc/sddm.conf` by commenting out `Current=caelestia`. Preserves `[General] Numlock=on` and all other settings.
4. **Timestamped Backup Created**:
   - Directory: `/var/backups/gps-login/backup_<timestamp>/`
   - Files backed up: original `/etc/sddm.conf` (if modified), pre-existing drop-in or theme files.
   - Manifest: `/var/backups/gps-login/backup_<timestamp>/manifest.json`
   - Symlink: `/var/backups/gps-login/latest`

---

## 7. Rollback Procedure

To cleanly roll back the theme and restore the previous login configuration:

```bash
sudo ./login/install-login.sh --rollback
```

What the rollback command does:
1. Reads the latest backup manifest from `/var/backups/gps-login/latest/manifest.json`.
2. Restores `/etc/sddm.conf` from backup if it was updated by the installer.
3. Removes `/etc/sddm.conf.d/zz-gps-theme.conf`.
4. Removes `/usr/share/sddm/themes/gps/`.
5. Leaves pre-existing `/etc/sddm.conf.d/caelestia.conf` and `/etc/sddm.conf.d/theme.conf` completely intact.
6. SDDM immediately reverts to `caelestia`.

---

## 8. Emergency Recovery Instructions

If SDDM fails to start or display the greeter following a manual system modification:

### Option A: Remove the drop-in override (Instant reversion)
Switch to a virtual TTY (`Ctrl` + `Alt` + `F3`), log in as `rice` or `guru`, and remove the override file:
```bash
sudo rm -f /etc/sddm.conf.d/zz-gps-theme.conf
sudo systemctl restart sddm.service
```
SDDM will automatically fall back to the existing theme (`caelestia`).

### Option B: Restore `/etc/sddm.conf` from backup
If `/etc/sddm.conf` was modified:
```bash
sudo cp /var/backups/gps-login/latest/sddm.conf.orig /etc/sddm.conf
sudo systemctl restart sddm.service
```

### Option C: Fallback to SDDM built-in default
If all custom themes are corrupted, temporarily configure SDDM to use its embedded default:
```bash
echo -e "[Theme]\nCurrent=" | sudo tee /etc/sddm.conf.d/99-fallback.conf
sudo systemctl restart sddm.service
```

> [!NOTE]
> The GPS login package does **not** alter PAM files (`/etc/pam.d/*`). Password verification and system access mechanisms remain completely standard and untouched.
