# GPS Desktop — Installation, Packaging & Recovery Manual

This guide provides the authoritative reference for inspecting prerequisites, installing, relocating, recovering, and uninstalling the **GPS Desktop (Aetheric Shell)** environment safely and idempotently on Arch Linux and CachyOS.

---

## Table of Contents

1. [Architecture & Desktop Stack](#1-architecture--desktop-stack)
2. [Prerequisites & Supported Environments](#2-prerequisites--supported-environments)
3. [Dependency Inspection (`gps-deps`)](#3-dependency-inspection-gps-deps)
4. [Installation Workflow (`install.sh`)](#4-installation-workflow-installsh)
5. [Repository Relocation Contract](#5-repository-relocation-contract)
6. [Transaction Safety, Backups & Recovery](#6-transaction-safety-backups--recovery)
7. [Safe Uninstallation](#7-safe-uninstallation)
8. [Isolated Clean-Account Trial](#8-isolated-clean-account-trial)
9. [Troubleshooting Matrix](#9-troubleshooting-matrix)

---

## 1. Architecture & Desktop Stack

GPS (Aetheric Shell) is a Wayland desktop environment composed of an isolated dual-shell layer architecture on top of the Hyprland compositor:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Wayland Compositor (Hyprland)                   │
└──────────────────┬─────────────────────────────────┬───────────────────┘
                   │ zwlr_layer_shell_v1             │ IPC Socket (hyprctl)
        ┌──────────┴───────────────┐                 │
        │                          │                 │
┌───────▼────────────────┐ ┌───────▼──────────────┐  │
│  Main Shell Instance   │ │      GPS Island        │  │
│  (Quickshell Qt6/QML)  │ │ (Quickshell Qt6/QML) │◄─┘
│  - LeftRail 54px Dock  │ │ - Top Status Pill    │
│  - Dashboard Drawer    │ │ - Notification D-Bus │
│  - Notification Center │ │ - Live MPRIS / Audio │
│  - Media Hub & Popups  │ │ - Clipboard History  │
└────────────────────────┘ └──────────────────────┘
```

### Core Design & Safety Principles

- **Strictly User-Space**: The installer and runtime operate solely within user directories (`$HOME`, `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME`, `$XDG_DATA_HOME`, `~/.local/bin`). They never request `sudo`, never invoke `pacman`, and never touch `/etc`, `/usr`, `/boot`, or other system directories.
- **Advisory Concurrency Lock**: All mutating operations acquire an exclusive per-user file lock (`$XDG_STATE_HOME/gps/installer.lock`) to prevent race conditions from concurrent runs.
- **Deterministic Absolute Symlinks**: Managed dotfiles are symlinked to repository paths to ensure immediate updates during development.
- **Durable Transaction Journaling**: Every mutating action is fsynced to an atomic journal (`install_journal.json`) before changes occur, enabling automated, zero-data-loss rollback on failure or signal interruption (`SIGINT`/`SIGTERM`).
- **Cryptographic Backup Verification**: Conflicting files are archived with pre-flight SHA-256 integrity verification before being replaced.
- **Conflict-Preserving**: Pre-existing user modifications, independent configurations, and user state files are never overwritten.

---

## 2. Prerequisites & Supported Environments

### Operating System & Compositor Requirements

| Component | Requirement | Verification Command | Notes |
|---|---|---|---|
| **Distribution** | Arch Linux or CachyOS | `cat /etc/os-release` | Pacman package database expected |
| **Compositor** | Hyprland `v0.42.0+` | `hyprctl version` | Wayland protocol support required |
| **Shell Engine** | QuickShell (Qt 6) | `quickshell --version` | Official repo package or `quickshell-git` |
| **Session Manager** | systemd + logind / UWSM | `loginctl session-status` | Supports standard Wayland session launch |
| **Python** | Python `3.10+` | `python3 --version` | Standard library used for installer engine |

### Supported Environment Assumptions & Known Limitations

- **Wayland Exclusively**: GPS requires a Wayland session with the `zwlr_layer_shell_v1` protocol. It will not run on X11 or with compositors lacking layer-shell extensions (e.g. vanilla GNOME Shell).
- **GPU & Hardware Acceleration**:
  - AMD & Intel GPUs: Supported out of the box via Mesa Wayland drivers.
  - NVIDIA GPUs: Requires proprietary NVIDIA drivers with DRM KMS enabled (`nvidia_drm.modeset=1`). Install `nvidia-utils` for hardware telemetry in `SysProbe`.
- **Display Backlight & Battery**:
  - `brightnessctl` is required for laptop backlight hotkeys.
  - `upower` is queried for battery telemetry; on desktop systems without batteries, battery widgets hide automatically without errors.
- **Face Unlock (Optional)**:
  - Howdy face unlock integration via PAM is completely optional. It requires manual enrollment (`sudo howdy add`) and is never configured automatically.
- **Night Warmth (Optional)**:
  - Circadian blue light filters require `hyprsunset` if installed; otherwise the UI displays an honest "unavailable · no backend" status without crashing.

---

## 3. Dependency Inspection (`gps-deps`)

GPS provides a dedicated, non-destructive dependency inspection tool at `scripts/gps-deps`.

> [!NOTE]
> **Read-Only Guarantee**: `gps-deps` is strictly an inspection tool. It never invokes `sudo`, never runs `pacman -S` or `pacman -Sy`, never modifies system databases, and never alters user configurations. It is 100% safe to run at any time.

### Dependency Classifications

1. **Core Required (`packages/required.txt`)**:
   Strictly necessary for Hyprland, QuickShell, audio routing, desktop portals, and basic script execution. Without these 13 dependencies, GPS cannot start:
   - `hyprland`, `quickshell`, `qt6-wayland`, `pipewire`, `wireplumber`
   - `xdg-desktop-portal`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`
   - `python`, `fish`, `bash`, `nodejs`, `noto-fonts`
2. **Optional & Feature Dependencies (`packages/optional.txt`)**:
   - `[optional]`: Desktop applications like terminal (`kitty`), file manager (`thunar`), and application launcher (`rofi`).
   - `[feature]`: Powers individual subsystems like screenshots (`grim`, `slurp`, `swappy`), clipboard history (`cliphist`, `wl-clipboard`), wallpaper management (`awww`), audio visualizer (`cava`, `pipewire-pulse`), screen lock (`hyprlock`), and idle management (`hypridle`).
   - `[hardware]`: Relevant only when corresponding hardware is present: battery (`upower`), power profiles (`power-profiles-daemon`), backlight (`brightnessctl`), Bluetooth (`bluez`, `bluez-utils`), GPU metrics (`nvidia-utils`).
3. **Arch User Repository (`packages/aur.txt`)**:
   Optional packages available from the AUR: preferred typography (`ttf-plus-jakarta-sans`), activity logging (`awatcher-bundle`), and anime streaming CLI (`ani-cli`).

### Difference Between Required, Optional, and Unavailable Dependencies

- **`[OK]`**: Satisfied locally via package (`pacman -Q`), virtual package provides, VCS alias (e.g. `quickshell-git`), alternative provider (e.g. `polkit-kde-agent`), or standalone binary on `$PATH`.
- **`[MISSING]`**: Not installed locally, but verified available in configured official repositories (or AUR via `paru`). Can be installed directly using the suggested manual command.
- **`[UNVERIFIED]`**: Not installed locally and **not found** in configured repository databases. These dependencies cannot be installed with a standard pacman command until appropriate repositories or packaging are configured.

### Running `gps-deps`

```bash
# Standard check: inspects core-required and common optional dependencies
scripts/gps-deps

# Check only core-required dependencies
scripts/gps-deps --required-only

# Check all dependencies including optional, hardware, and AUR packages
scripts/gps-deps --all

# Machine-readable JSON output (used by installer and diagnostic tools)
scripts/gps-deps --json
```

### Exit Codes of `gps-deps`

- **`0`**: All inspected dependencies are fully satisfied.
- **`1`**: One or more **core-required** dependencies are missing.
- **`2`**: Core-required dependencies are satisfied, but optional or feature dependencies are missing.

---

## 4. Installation Workflow (`install.sh`)

All user-space installation actions are driven by `./install.sh` (or `scripts/installer.py`).

### Step 1: Clone Repository

Clone GPS to your preferred location in user space (e.g. `~/Projects/my-rice-pk1`):

```bash
git clone https://github.com/your-username/my-rice-pk1.git ~/Projects/my-rice-pk1
cd ~/Projects/my-rice-pk1
```

### Step 2: Dry-Run Inspection (Default)

Running `./install.sh` without arguments executes a read-only dry-run:

```bash
./install.sh
# or explicitly:
./install.sh --dry-run
```

**What the Dry-Run Does**:
- Validates that all repository source files exist.
- Inspects target destinations in `$XDG_CONFIG_HOME` and `~/.local/bin`.
- Categorizes planned actions for each destination:
  - `[LINK]`: Target does not exist; new symlink will be created.
  - `[UP TO DATE]`: Symlink already points to the repository file; no action needed.
  - `[CREATE TEMPLATE]`: User settings template will be created (if absent).
  - `[BACKUP & LINK]`: Conflicting file exists; will be safely backed up before linking.
  - `[PRESERVE]`: Conflicting user file/symlink or template preserved without modification.
- Queries `gps-deps` to alert on missing system packages.
- **Makes ZERO changes to the filesystem.**

### Step 3: Apply Installation

> [!IMPORTANT]
> `--apply` modifies user configurations under `~/.config` and creates user binary symlinks under `~/.local/bin`. Pre-existing files that would be replaced are automatically backed up with SHA-256 integrity verification before any changes are made.

To execute the installation plan:

```bash
./install.sh --apply
```

**The Atomic Transaction Lifecycle**:
1. **Advisory Lock**: Acquires an exclusive lock on `$XDG_STATE_HOME/gps/installer.lock`.
2. **Crash Recovery**: Checks for any uncommitted transaction from a previous interrupted run and rolls it back cleanly before continuing.
3. **Pre-Flight Backup**: Conflicting destination files are copied to `$XDG_STATE_HOME/gps/backups/<YYYYMMDD_HHMMSS>/files/`. File attributes and SHA-256 hashes are verified.
4. **Durable Journaling**: The full transaction plan is fsynced to `$XDG_STATE_HOME/gps/install_journal.json`.
5. **Signal Interception**: Traps `SIGINT` (Ctrl+C) and `SIGTERM` to perform an automated rollback if interrupted.
6. **Atomic Symlink Deployment**: Each symlink is created using a unique temporary file (`.<dest>.tmp.<PID>`) and committed atomically using `os.replace` (POSIX `rename`).
7. **Template Instantiation**: Configuration templates (`rice-settings.json`, `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`) are copied **only if absent**. If user files already exist, they are preserved untouched.
8. **Manifest Commit**: The active state is written to `$XDG_STATE_HOME/gps/install_manifest.json`, the journal is cleanly closed, and the lock is released.

### Step 4: Verification & Diagnostics (`--check`)

After installation, verify the integrity of all symlinks, templates, and runtime dependencies:

```bash
./install.sh --check
```

The check verifies:
1. **Managed Files**: Confirms that all symlinks point to the active repository clone.
2. **Dependencies**: Runs `gps-deps` to report any missing packages.
3. **Session Health**: Invokes `scripts/gps-doctor` to test compositor rules, audio pipelines, and IPC sockets.

---

## 5. Repository Relocation Contract

### Why Relocation Affects Symlinks

The GPS installer deploys dotfiles using **absolute symlinks** (e.g. `~/.config/hypr/hyprland.lua -> /home/user/Projects/my-rice-pk1/dots/hypr/hyprland.lua`). Absolute symlinks guarantee deterministic resolution regardless of working directory or shell invocation.

However, if you move, rename, or relocate the repository directory (e.g. from `~/Downloads/my-rice-pk1` to `~/Projects/my-rice-pk1`), the existing symlinks will break because their targets no longer exist.

### Verified Relocation Procedure

If you relocate or rename the repository, update your dotfiles cleanly in two steps:

```bash
# 1. Navigate to the NEW repository directory
cd /new/path/to/my-rice-pk1

# 2. Re-apply the installer
./install.sh --apply
```

**What Happens During Relocation Re-Apply**:
- The installer detects that existing symlinks point to the old repository location.
- It atomically updates all symlinks to point to the new location.
- **Existing user settings and templates are completely preserved.**
- **No duplicate or redundant backups are created.**

Verify the new paths with:
```bash
./install.sh --check
```

---

## 6. Transaction Safety, Backups & Recovery

### Storage Locations

| Path | Purpose | Behavior |
|---|---|---|
| `$XDG_STATE_HOME/gps/installer.lock` | Advisory concurrency lock | Locked via `fcntl.flock(2)`; never unlinked |
| `$XDG_STATE_HOME/gps/install_journal.json` | Active transaction journal | fsynced during `--apply`; unlinked upon completion |
| `$XDG_STATE_HOME/gps/install_manifest.json` | Record of active installation | Preserves original file types, targets, and backup links |
| `$XDG_STATE_HOME/gps/backups/<timestamp>/` | Pre-apply backup archive | Contains `manifest.json`, `journal.json`, and original `files/` |

### How Interrupted Installations are Detected & Recovered

If an installer run is terminated prematurely (by user `Ctrl+C`, `kill`, or system power failure):

1. **Signal Interception**: If `SIGINT` or `SIGTERM` is received, the active Python process catches the signal, traverses journal steps in reverse order, removes partially applied symlinks, restores any backed-up originals, cleans up temporary files, and exits cleanly.
2. **Automatic Crash Recovery**: If the process was terminated violently (e.g. `SIGKILL` or power cut) leaving an uncommitted journal on disk:
   - The very next time `./install.sh --apply` or `./install.sh --uninstall` is run, the installer detects the lingering `in_progress` journal.
   - It outputs:
     ```
     [RECOVERY] Incomplete previous transaction detected! Initiating safe rollback...
     [RECOVERY] Previous incomplete transaction rolled back safely. State restored.
     ```
   - It reconciles filesystem state against the journal and restores all pre-transaction files before starting the requested operation.

### How Backup Integrity is Verified

Every backup operation performs pre-flight cryptographic verification:
- Regular files: The SHA-256 hash of the target is recorded, the file is copied to the backup directory, and the backup file's SHA-256 hash is immediately verified against the recorded digest.
- Symlinks: The destination symlink's target path is read and confirmed identical in the backup directory.
- Restorations: Before restoring any file during rollback or uninstallation, the backup file's SHA-256 is re-verified to prevent restoring corrupted or truncated data.

---

## 7. Safe Uninstallation

To remove GPS configuration symlinks and restore your original pre-installation files:

```bash
./install.sh --uninstall
```

### Uninstallation Guarantees

1. **GPS Symlinks Removed**: All symlinks pointing into the GPS repository are cleanly unlinked.
2. **Original Files Restored**: If an original configuration file was backed up during installation, it is verified against its backup SHA-256 hash and restored to its original destination.
3. **User State Preserved**: User runtime state and independent data files are **never deleted**. The uninstaller intentionally preserves:
   - `rice-settings.json` (Settings Hub configuration)
   - `settings.ini` (GTK 3 and GTK 4 themes)
   - `gps-theme.json` and `gps-last-wall.txt` (extracted wallpaper palette and history)
   - `pet.json` (desktop companion settings)
   - `dnd`, `notifications.json` (island notification history and DND status)
   - `clipboard_*.json` (pinned clipboard history)
   - `planner.json`, `gamemode_state.json` (user objectives and game mode states)
   - All session log files (`startup.log`, `island.log`, `theme.log`)
4. **Conflict Detection**: If a user modified a symlink to point to an external configuration or replaced a symlink with a customized file after running `--apply`, the uninstaller will **refuse to delete the user file**, report a conflict notice, and exit with code `2`.

---

## 8. Isolated Clean-Account Trial

Before deploying GPS to your primary desktop user account, you can evaluate the entire stack inside an isolated Linux user account.

> [!TIP]
> A clean-account trial guarantees 100% isolation from your primary user's dotfiles, configurations, shell history, and credentials.

### Step-by-Step Trial Procedure

1. **Create a Dedicated Test User**:
   ```bash
   # Create user 'gpstest' with home directory and bash shell
   sudo useradd -m -s /bin/bash gpstest
   sudo passwd gpstest
   ```

2. **Log into the Test Account**:
   Switch to a virtual terminal (`Ctrl+Alt+F3`) or run:
   ```bash
   sudo -u gpstest -i
   ```

3. **Clone GPS in the Test Account**:
   ```bash
   git clone https://github.com/your-username/my-rice-pk1.git ~/my-rice-pk1
   cd ~/my-rice-pk1
   ```

4. **Inspect Dependencies & Dry-Run**:
   ```bash
   scripts/gps-deps
   ./install.sh
   ```

5. **Apply Installation**:
   ```bash
   ./install.sh --apply
   ./install.sh --check
   ```

6. **Test the Wayland Session**:
   Start Hyprland from the test user's TTY:
   ```bash
   Hyprland
   ```
   Explore the LeftRail dock, Dashboard (`Super+D`), Notification Center (`Super+N`), Wallpaper Carousel (`Super+W`), and Settings Hub (`Super+,`).

7. **Clean Up After Testing**:
   When finished testing, exit Hyprland, uninstall GPS, and remove the test account:
   ```bash
   cd ~/my-rice-pk1
   ./install.sh --uninstall
   exit
   # From your administrative account:
   sudo userdel -r gpstest
   ```

---

## 9. Troubleshooting Matrix

| Issue | Root Cause | Diagnostic Command | Verified Resolution |
|---|---|---|---|
| **Installer fails with "Another GPS installer operation in progress"** | Another process holds `$XDG_STATE_HOME/gps/installer.lock`, or previous process did not release lock | `cat ~/.local/state/gps/installer.lock` | Check if PID in lockfile is still running (`ps -p <PID>`). If process exited, lock is freed automatically by kernel; if live, wait for it or terminate it cleanly. **Never delete the lockfile while installer runs.** |
| **Installer fails with "The GPS installer must not be run as root or via sudo"** | Installer was invoked with `sudo ./install.sh` | `id -u` (returns 0) | Run as your regular unprivileged user: `./install.sh`. GPS is strictly a user-space environment. |
| **Broken symlinks after moving repository** | Repository clone was moved or renamed, breaking absolute symlinks | `./install.sh --check` | Navigate to the new repository path and run `./install.sh --apply`. Symlinks will be updated cleanly. |
| **Missing Core-Required Dependencies** | Required package missing (e.g. `hyprland`, `quickshell`, `wireplumber`) | `scripts/gps-deps --required-only` | Run the suggested pacman command: `sudo pacman -S --needed <packages>` |
| **"Critical Security Warning: Lock & Idle facilities incomplete"** | `hyprlock` or `hypridle` not installed | `scripts/gps-deps` | Install security packages: `sudo pacman -S --needed hyprlock hypridle` |
| **Uninstall reports conflicts and exits with code 2** | A destination file or symlink was modified or replaced after installation | `./install.sh --uninstall` | Review the reported conflict files. The uninstaller safely preserves your modified files; manually inspect and remove them if no longer wanted. |
| **Corrupted backup error during uninstall** | Backup archive file was deleted or altered, failing SHA-256 check | `ls -la ~/.local/state/gps/backups/` | The uninstaller halts restoration of the damaged file to prevent writing corrupted data. Manually verify destination configuration. |
| **Incomplete transaction detected on start** | Previous installer run crashed or was killed via `SIGKILL` | `./install.sh` or `./install.sh --apply` | The installer automatically rolls back the incomplete transaction on startup. Re-run `./install.sh --apply` once recovery completes. |
| **"not found in official repositories" for AUR packages** | Package is hosted on AUR (e.g. `ttf-plus-jakarta-sans`, `awatcher-bundle`) | `scripts/gps-deps --all` | Install via an AUR helper (e.g. `paru -S --needed <pkg>`) or manual PKGBUILD build. Core functionality works with default fallbacks. |
