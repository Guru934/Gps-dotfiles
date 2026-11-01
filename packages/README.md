# GPS Package & Dependency Manifests

This directory contains declarative dependency manifests for the Aetheric Shell / GPS desktop session on CachyOS / Arch Linux, alongside documentation explaining dependency categorization, inspection commands, and verification policies.

For the full installation, packaging, recovery, and relocation manual, see [docs/installation.md](../docs/installation.md).

---

## Manifest Files

- **`required.txt`**: Core official repository dependencies strictly required for the session to start and run safely.
- **`optional.txt`**: Feature, utility, application, and hardware-specific enhancements from official repositories.
- **`aur.txt`**: Packages maintained in the Arch User Repository (AUR), classified by requirement level.

---

## Dependency Classification

### 1. Core Required Dependencies (`required.txt`)

A package belongs in `required.txt` only when GPS cannot provide its intended core session functionality safely without it. Without these 13 dependencies, the primary GPS desktop session cannot start or function:

| Package | Role in GPS Session |
|---|---|
| `hyprland` | Core Wayland compositor and window manager orchestrating the desktop session |
| `quickshell` | Primary shell framework executing QML/C++ UI (`shell.qml`, `island`, `settings`) |
| `qt6-wayland` | Qt6 Wayland platform plugin required for Quickshell GUI surfaces |
| `pipewire` | Core multimedia server and `pw-play` audio output for the sound engine |
| `wireplumber` | Modular PipeWire session manager providing `wpctl` volume and sink routing |
| `xdg-desktop-portal` | Core desktop portal service for screen sharing, open URI, and file dialogs |
| `xdg-desktop-portal-hyprland` | Hyprland portal backend for screen capture and display management |
| `xdg-desktop-portal-gtk` | GTK portal backend providing file dialogs and desktop picker fallback |
| `python` | Script runtime for wallpaper dynamic theming, audio IPC, sounds, and watchers |
| `fish` | Shell interpreter for `run-gps.fish` startup orchestrator and wallpaper scripts |
| `bash` | POSIX shell runtime for session scripts (`gps-idle`, `gps-lock`, `gps-shot`, `gps-ipc`) |
| `nodejs` | JavaScript runtime engine for `gps-clipboard` and `ClipboardService` backend |
| `noto-fonts` | Standard high-legibility UI sans-serif fallback font |

---

### 2. Optional & Feature Dependencies (`optional.txt`)

These packages enhance the desktop experience or provide support for specific subsystems. When absent, the shell degrades gracefully with actionable UI notices and built-in fallbacks:

| Package | Category | Feature / Fallback |
|---|---|---|
| `kitty` | Optional | Default terminal emulator bound to Super+Q in `hyprland.lua` |
| `thunar` | Optional | Default graphical file manager bound to Super+E in `hyprland.lua` |
| `rofi` | Optional | Application launcher menu bound to Super+R and Super+Space |
| `qt6ct` | Feature | Qt 6 configuration utility for external Qt application theming (not needed by QML shell) |
| `networkmanager` | Feature | Network management daemon and `nmcli` CLI; shell falls back to actionable error in Wi-Fi popup |
| `bluez` | Hardware | Linux Bluetooth protocol stack daemon (`bluetoothd`) |
| `bluez-utils` | Hardware | Bluetooth management CLI (`bluetoothctl`); shell falls back to actionable error in Bluetooth popup |
| `wl-clipboard` | Feature | Wayland clipboard utilities (`wl-copy`, `wl-paste`) for clip store and picker |
| `cliphist` | Feature | Wayland clipboard history daemon and binary cache manager |
| `awww` | Feature | High-performance Wayland wallpaper daemon (`awww-daemon`) and control client |
| `gnome-keyring` | Feature | D-Bus secrets service daemon (`org.freedesktop.secrets`); `kwallet` or `keepassxc` also supported |
| `python-dbus` | Feature | Python D-Bus bindings required by `gps-device-watcher` for device connect events |
| `python-gobject` | Feature | GObject Python bindings (`gi.repository.GLib`) required by `gps-device-watcher` |
| `hyprpolkitagent` | Feature | Polkit graphical elevation agent; `polkit-kde-agent` or `polkit-gnome` also supported |
| `pipewire-pulse` | Feature | PulseAudio daemon replacement for PipeWire audio spectrum analysis |
| `hyprlock` | Feature | Hyprland screen lock utility invoked by `scripts/gps-lock` |
| `hypridle` | Feature | Hyprland idle daemon managed by `scripts/gps-idle` for display sleep policies |
| `python-pillow` | Feature | Image processing library used by `set_wallpaper.py`; falls back to canonical built-in theme tokens |
| `ttf-jetbrains-mono-nerd` | Feature | Monospace font and Nerd Font symbol glyphs for all UI icons (`Noto Sans` fallback) |
| `noto-fonts-cjk` | Optional | CJK (Chinese, Japanese, Korean) glyph fallback coverage |
| `noto-fonts-emoji` | Optional | Color emoji glyph fallback coverage for notifications and UI |
| `grim` | Feature | Screenshot capture utility used by `scripts/gps-shot` (Print key) |
| `slurp` | Feature | Interactive region selector used by `gps-shot` and `gps-record` |
| `hyprpicker` | Feature | Wayland color picker used by `scripts/gps-picker` (Super+Shift+P) |
| `gpu-screen-recorder` | Feature | High-performance hardware-accelerated recorder for `gps-record` |
| `wf-recorder` | Feature | Fallback software Wayland screen recorder for `gps-record` |
| `swappy` | Feature | Interactive screenshot annotation and markup tool for `gps-shot` |
| `playerctl` | Feature | Media player CLI queried for now-playing metadata and media keys |
| `brightnessctl` | Hardware | Display backlight brightness controller for laptop display hotkeys |
| `libnotify` | Feature | Desktop notification CLI (`notify-send`) used for capture/picker alerts |
| `upower` | Hardware | UPower daemon for battery status monitoring in laptop `LeftRail`/`Island` |
| `power-profiles-daemon` | Hardware | Power profile switching (`performance`, `balanced`, `power-saver`) |
| `mpv` | Feature | Recommended hardware-accelerated video player for Media Hub playback |
| `ffmpeg` | Feature | Video transcoding and `ffprobe` audio metadata extractor for Media Hub |
| `yt-dlp` | Feature | Command-line video and audio downloader for Media Hub Downloads queue |
| `7zip` | Feature | Archive utility (`7z`) providing CBR extraction for Media Hub Manga Reader |
| `libpulse` | Feature | PulseAudio client libraries providing `parec` for audio spectrum analysis |
| `python-numpy` | Feature | Numerical computing library for audio spectrum fast Fourier transforms |
| `cava` | Feature | Console audio visualizer backend for reactive Island sound bars |
| `nvidia-utils` | Hardware | NVIDIA GPU management utilities providing `nvidia-smi` for `SysProbe` |

---

### 3. Arch User Repository (AUR) Dependencies (`aur.txt`)

| Package | Requirement | Role / Fallback |
|---|---|---|
| `ttf-plus-jakarta-sans` | Optional | Preferred brand typeface for GPS UI typography (`Noto Sans` fallback) |
| `awatcher-bundle` | Optional | ActivityWatch screen-time tracking daemon with bundled web UI for ScreenTime card |
| `ani-cli` | Optional | Interactive anime streaming CLI for Media Hub Tools |
| `tide-island` | Optional | Alternative dynamic island implementation for Quickshell |

---

### 4. Required, Optional, and Unavailable (Unverified) Dependencies

Understanding dependency status reporting is essential for safe configuration:

- **Core Required**: Dependencies in `packages/required.txt`. If any core-required package is missing, GPS **cannot start or run safely**.
- **Optional / Feature**: Dependencies in `packages/optional.txt` or `packages/aur.txt`. If missing, the desktop environment still starts and functions cleanly, with specific widgets or actions showing honest UI notices or fallbacks (e.g. absent `hyprsunset` shows circadian as unavailable).
- **Missing vs Unavailable (Unverified)**:
  - **`[MISSING]`**: The dependency is not installed locally, but `gps-deps` verified that it **is available** in configured package databases (official repos via `pacman -Si`, or AUR via `paru -Si`). You can install it immediately with the suggested command (`sudo pacman -S --needed <pkg>` or `paru -S --needed <pkg>`).
  - **`[UNVERIFIED]`**: The dependency is not installed locally and **is not found** in your active pacman repositories. It cannot be installed with standard pacman commands until corresponding repositories or PKGBUILDs are configured.

---

### 5. Quickshell Package Selection

The official Arch Linux and CachyOS repositories contain the `quickshell` package in `extra` / `cachyos-extra-v3`.
- **Clean Installation Recommendation**: Fresh installations should install the official `quickshell` package (`sudo pacman -S --needed quickshell`).
- **Development/VCS Builds**: If `quickshell-git` is already installed, `gps-deps` recognizes it via pacman provides and marks the dependency satisfied while continuing to confirm that the official `quickshell` package remains available in configured repositories.

---

### 6. Executable vs Package Providers (hyprlock & Polkit)

- **`hyprlock`**: In addition to package inspection via `pacman -Q`, `gps-deps` checks for standalone or user-built binaries (such as `~/.local/bin/hyprlock` or `~/.local/opt/hyprlock/bin/hyprlock`). If the binary is executable and reachable, the dependency is marked satisfied with its source path identified.
- **Polkit Agents**: `run-gps.fish` supports a fallback chain for GUI elevation (`hyprpolkitagent`, `polkit-kde-authentication-agent-1`, `polkit-gnome-authentication-agent-1`, `pantheon-polkit-agent`, `lxpolkit`). Any compliant running agent satisfies the polkit requirement without forcing `hyprpolkitagent` as a rigid core requirement.
- **Secret Services**: `gnome-keyring`, `kwallet`, and `keepassxc` are supported interchangeable providers for `org.freedesktop.secrets`.

---

## Inspecting Dependencies with `gps-deps`

The inspection script `scripts/gps-deps` provides comprehensive dependency validation with zero modification to your system:

```bash
# Default check: readable summary and grouped commands for missing packages
scripts/gps-deps

# Check only core-required dependencies
scripts/gps-deps --required-only

# Check all dependencies including optional and AUR
scripts/gps-deps --all

# Machine-readable JSON output (includes dependency list, status, and suggested commands)
scripts/gps-deps --json

# Override manifest directory (defaults to packages/)
scripts/gps-deps --manifest-dir packages/

# Disable terminal color output
scripts/gps-deps --no-color
```

### Exit Codes of `gps-deps`

The script returns structured exit codes suitable for shell scripting and automation:
- **`0`**: All inspected dependencies are satisfied.
- **`1`**: One or more **core-required** dependencies are missing.
- **`2`**: Core-required dependencies are satisfied, but one or more **optional or feature** dependencies are missing or unverified.

---

## Why `gps-deps` Never Installs Automatically

The dependency checker strictly adheres to non-destructive principles:

1. **User Autonomy**: Package installation requires administrative decisions (e.g. provider selection, repository trust).
2. **Security & Least Privilege**: The checker never requests `sudo` elevation and never runs arbitrary installation hooks.
3. **Reproducibility**: Operating systems and package configurations must not be mutated without explicit administrator approval.
4. **Hermetic Testing**: Diagnostic tools must be safe to run in CI, automated tests, and restricted environments without altering system state.
