# GPS Package & Dependency Manifests

This directory contains declarative dependency manifests for the Aetheric Shell / GPS desktop session on CachyOS / Arch Linux, alongside documentation explaining dependency categorization and verification policies.

## Manifest Files

- **`required.txt`**: Core official repository dependencies required for the session to start and run.
- **`optional.txt`**: Feature, utility, and hardware-specific enhancements from official repositories.
- **`aur.txt`**: Packages maintained in the Arch User Repository (AUR), classified by requirement level.

---

## Dependency Classification

### 1. Core Required Dependencies (`required.txt`)

These packages must be present for the primary GPS desktop session (`hyprland` + `quickshell` + core IPC) to function correctly:

| Package | Role in GPS Session |
|---|---|
| `hyprland` | Core Wayland compositor and window manager orchestrating the desktop session |
| `quickshell` | Primary shell framework executing QML/C++ UI (`shell.qml`, `island`, `settings`) |
| `python` | Script runtime for wallpaper dynamic theming, audio IPC, sounds, and watchers |
| `fish` | Shell interpreter for `run-gps.fish` startup orchestrator and wallpaper scripts |
| `bash` | POSIX shell runtime for session scripts (`gps-idle`, `gps-lock`, `gps-shot`, `gps-ipc`) |
| `nodejs` | JavaScript runtime engine for `gps-clipboard` and `ClipboardService` backend |
| `pipewire` | Core multimedia server and `pw-play` audio output for the sound engine |
| `wireplumber` | Modular PipeWire session manager providing `wpctl` volume and sink routing |
| `pipewire-pulse` | PulseAudio daemon replacement for PipeWire audio spectrum analysis |
| `python-pillow` | Image processing library used by `set_wallpaper.py` for palette extraction |
| `python-gobject` | GObject Python bindings (`gi.repository.GLib`) required by `gps-device-watcher` |
| `python-dbus` | Python D-Bus bindings required by `gps-device-watcher` for system event bus |
| `networkmanager` | Network management daemon and `nmcli` CLI queried by `shell.qml` and `LeftRail` |
| `bluez` | Linux Bluetooth protocol stack daemon (`bluetoothd`) |
| `bluez-utils` | Bluetooth management CLI (`bluetoothctl`) queried by `LeftRail` and Control island |
| `awww` | High-performance Wayland wallpaper daemon (`awww-daemon`) and control client |
| `wl-clipboard` | Wayland clipboard utilities (`wl-copy`, `wl-paste`) for clip store and picker |
| `cliphist` | Wayland clipboard history daemon and binary cache manager |
| `hypridle` | Hyprland idle daemon managed by `scripts/gps-idle` for display sleep policies |
| `hyprlock` | Hyprland screen lock utility invoked by `scripts/gps-lock` |
| `qt6-wayland` | Qt6 Wayland platform plugin required for Quickshell GUI surfaces |
| `xdg-desktop-portal` | Core desktop portal service for screen sharing, open URI, and file dialogs |
| `xdg-desktop-portal-hyprland` | Hyprland portal backend for screen capture and display management |
| `xdg-desktop-portal-gtk` | GTK portal backend providing file dialogs and desktop picker fallback |
| `hyprpolkitagent` | Polkit graphical authentication agent for privilege escalation dialogs |
| `gnome-keyring` | D-Bus secrets service daemon (`org.freedesktop.secrets`) for credentials |
| `ttf-jetbrains-mono-nerd` | Primary monospace font and Nerd Font symbol glyphs for all UI icons |
| `noto-fonts` | Standard high-legibility UI sans-serif fallback font |

### 2. Optional & Feature Dependencies (`optional.txt`)

These packages enhance the desktop experience or provide support for specific tools. When absent, the shell degrades gracefully with actionable UI notices:

| Package | Category | Feature / Fallback |
|---|---|---|
| `kitty` | Optional | Default terminal emulator bound to Super+Q in `hyprland.lua` |
| `thunar` | Optional | Default graphical file manager bound to Super+E in `hyprland.lua` |
| `rofi` | Optional | Application launcher menu bound to Super+R and Super+Space |
| `grim` | Feature | Screenshot capture utility used by `scripts/gps-shot` (Print key) |
| `slurp` | Feature | Interactive region selector used by `gps-shot` and `gps-record` |
| `hyprpicker` | Feature | Wayland color picker used by `scripts/gps-picker` (Super+Shift+P) |
| `playerctl` | Feature | Media player CLI queried for now-playing metadata and media keys |
| `libnotify` | Feature | Desktop notification CLI (`notify-send`) used for capture/picker alerts |
| `mpv` | Feature | Recommended hardware-accelerated video player for Media Hub playback |
| `ffmpeg` | Feature | Video transcoding and `ffprobe` audio metadata extractor for Media Hub |
| `yt-dlp` | Feature | Command-line video and audio downloader for Media Hub Downloads queue |
| `7zip` | Feature | Archive utility (`7z`) providing CBR extraction for Media Hub Manga Reader |
| `gpu-screen-recorder` | Feature | High-performance hardware-accelerated recorder for `gps-record` |
| `wf-recorder` | Feature | Fallback software Wayland screen recorder for `gps-record` |
| `swappy` | Feature | Interactive screenshot annotation and markup tool for `gps-shot` |
| `libpulse` | Feature | PulseAudio client libraries providing `parec` for audio spectrum analysis |
| `python-numpy` | Feature | Numerical computing library for audio spectrum fast Fourier transforms |
| `cava` | Feature | Console audio visualizer backend for reactive Island sound bars |
| `noto-fonts-cjk` | Optional | CJK (Chinese, Japanese, Korean) glyph fallback coverage |
| `noto-fonts-emoji` | Optional | Color emoji glyph fallback coverage for notifications and UI |

### 3. Hardware-Specific Dependencies

Needed only when particular hardware components are present on the host system:

- **`brightnessctl`**: Backlight brightness controller for laptop display hotkeys. (Desktop systems with external DDC/CI monitors do not require this).
- **`upower`**: Power management daemon used for laptop battery level and charging status in `LeftRail` and `Island`. (Desktops display "No battery detected").
- **`power-profiles-daemon`**: Switch between power-saver, balanced, and performance profiles.
- **`nvidia-utils`**: Provides `nvidia-smi` used in `SysProbe.qml` and `AIChat.qml` to report GPU utilization, memory, and temperature on NVIDIA GPUs.

### 4. Arch User Repository (AUR) Dependencies (`aur.txt`)

| Package | Requirement | Role / Fallback |
|---|---|---|
| `ttf-plus-jakarta-sans` | Optional | Preferred brand typeface for GPS UI typography (`Noto Sans` fallback) |
| `awatcher-bundle` | Optional | ActivityWatch screen-time tracking daemon with bundled web UI for ScreenTime card |
| `ani-cli` | Optional | Interactive anime streaming CLI for Media Hub Tools |
| `tide-island` | Optional | Alternative dynamic island implementation for Quickshell |

### 5. Development & Test-Only Dependencies

Not required by end users during normal desktop operation:

- `python-pytest` / `unittest`: Python automated test runner and hermetic test suite.
- `nodejs` (for tests): Headless JS test runner (`tests/*.js`, `island/tests/*.js`, `pet/tests/*.js`).
- `plymouth`: Plymouth boot splash development and preview testing (`boot/`).
- `sddm`: SDDM login theme testing and preview verification (`login/`).

---

## Inspecting Dependencies with `gps-deps`

The `scripts/gps-deps` tool non-destructively inspects your system and outputs clean installation commands.

### Usage

```bash
# Default check: readable summary and grouped commands for missing packages
scripts/gps-deps

# Check only core-required dependencies
scripts/gps-deps --required-only

# Check all dependencies including optional and AUR
scripts/gps-deps --all

# Machine-readable JSON output
scripts/gps-deps --json
```

### Example Output

```text
GPS Dependency Check

Core required:
  [OK] quickshell
  [OK] python
  [MISSING] hyprlock

Optional:
  [OK] kitty
  [MISSING] mpv

AUR:
  [OK] ttf-plus-jakarta-sans
  [MISSING] awatcher-bundle

Suggested commands:
  sudo pacman -S --needed hyprlock
  paru -S --needed awatcher-bundle
```

---

## Installing Missing Packages Manually

Once `gps-deps` identifies missing dependencies, install them with your package manager:

### Official Packages

```bash
sudo pacman -S --needed <package-names...>
```

### AUR Packages

```bash
paru -S --needed <package-names...>
```

Alternatively, AUR packages can be compiled and installed with `makepkg`:

```bash
git clone https://aur.archlinux.org/<package-name>.git /tmp/<package-name>
cd /tmp/<package-name>
makepkg -si
```

---

## Why `gps-deps` Never Installs Automatically

The dependency checker strictly adheres to non-destructive principles:

1. **User Autonomy**: Package installation requires administrative decisions (e.g. provider selection, repository trust).
2. **Security & Least Privilege**: The checker never requests `sudo` elevation and never runs arbitrary installation hooks.
3. **Reproducibility**: Operating systems and package configurations must not be mutated without explicit administrator approval.
4. **Hermetic Testing**: Diagnostic tools must be safe to run in CI, automated tests, and restricted environments without altering system state.
