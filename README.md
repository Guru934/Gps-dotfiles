# Aetheric Shell: Wayland Rice Architecture & System Reference

**Aetheric Shell** is a high-performance, ultra-responsive Wayland desktop environment and "rice" built for **Hyprland** (v0.42+) and **QuickShell** (Qt6/QML), paired with the standalone C++/Qt **Tide Island** status bar. Designed for high-refresh displays (165Hz VRR) and a minimal memory footprint (~220 MiB idle RAM) on Arch Linux / CachyOS.

---

## 1. System Architecture & Dual-Shell Topology

Aetheric Shell uses an isolated, collision-free dual-shell architecture:

1. **QuickShell (`~/Projects/my-rice/shell.qml`)**:
   - Manages the exclusive vertical **Left Rail Dock** (`LeftRail.qml`), the edge-hover **HUD Dashboard** (`Dashboard.qml`), the **Notification Center & To-Do Drawer** (`NotifCenter.qml`), the floating **Toast Banners** (`NotifToast.qml`), and the **3D Coverflow Wallpaper Carousel** (`WallpaperCarousel.qml`).
   - Operates as a passive notification consumer to prevent D-Bus collision.
2. **Tide Island (`~/.local/bin/tide-island`)**:
   - Standalone compiled C++/Qt top-center status pill.
   - Holds exclusive ownership of `org.freedesktop.Notifications`.
   - Provides live MPRIS media tickers, dynamic battery/volume indicators, and clipboard management via `cliphist`.

```
┌────────────────────────────────────────────────┐
│ Wayland Compositor                             │
│ Hyprland (v0.42.0+ / wlroots)                  │
└───────┬───────────────────────────────┬────────┘
        │                               │
        │ Layer Shell Protocol          │ IPC Socket (hyprctl)
        │ (zwlr_layer_shell_v1)         │
        │  ┌───────────────────────────┴───────────────────────────┐
        │  │                    QuickShell Engine                   │◄──┘
        │  │  ┌───────────────────┐  ┌──────────────────────┐       │
        │  │  │ Left Rail         │  │ HUD Dashboard        │       │
        │  │  │ (54px Taskbar)    │  │ (Right-Edge Hover)   │       │
        │  │  └───────────────────┘  └──────────────────────┘       │
        │  │  ┌───────────────────┐  ┌──────────────────────┐       │
        │  │  │ Notification &    │  │ 3D Wallpaper Modal   │       │
        │  │  │ To-Do Left Drawer  │  │ (Super+W Carousel)   │       │
        │  │  └───────────────────┘  └──────────────────────┘       │
        │  │  ┌───────────────────┐  ┌──────────────────────┐       │
        │  │  │ Transient Toast   │  │ Dynamic HSV Palette  │       │
        │  │  │ (NotifToast.qml)  │  │ (extract-theme.py)   │       │
        │  │  └───────────────────┘  └──────────────────────┘       │
        │  └───────────────────────────────────────────────────────┘
```

---

## 2. Master Keybind Matrix & Gesture Reference

| Keybind / Gesture | Subsystem / Action | Implementation / Target |
| :--- | :--- | :--- |
| **Far-Right Edge Hover** | **Slide Open Dashboard** | Invisible 4px edge sensor strip in `shell.qml` (`isOpen = true`) |
| **Cursor Leave Drawer** | **Auto-Dismiss Drawers** | 350ms grace timer (`autoCloseTimer`) in `Dashboard` & `NotifCenter` |
| `Super + D` | **Toggle Dashboard HUD** | `quickshell ipc call dashboard toggle` |
| `Super + N` | **Toggle Notification Center**| `quickshell ipc call notifcenter toggle` |
| `Super + W` | **Toggle 3D Wallpaper Carousel**| `quickshell ipc call wallpaper toggle` |
| `Super + Space` | **App Launcher** | `rofi -show drun` (themed with active dynamic palette) |
| `Super + Return` | **Terminal Emulator** | `ghostty` / `foot` |
| `Super + E` | **File Manager** | `thunar` / `yazi` |
| `Super + Q` | **Kill Active Window** | `hyprctl dispatch killactive` |
| `Super + V` | **Clipboard History** | `tide-island --toggle clipboard` (backed by `cliphist`) |
| `Super + L` | **Lock Screen** | `hyprlock` PAM session locker |
| `Super + 1..5` | **Switch Workspaces** | Native Hyprland workspace dispatcher |
| `Mouse Wheel on Dock`| **Scroll Workspaces** | `workspace e+1` / `workspace e-1` |
| `Super + F1` | **Vibe: Study & Focus** | 4500K warm shift, DND on, minimal border glow |
| `Super + F2` | **Vibe: Gaming Overdrive**| 165Hz VRR, blur bypass, red neon accent |
| `Super + F3` | **Vibe: Chill & Ambient** | Teal/Violet duotone glow, 5200K, smooth anims |
| `Super + F4` | **Vibe: Night Circadian** | 3200K amber cut, dimmed opacity |
| `PrtSc` | **Snip Screenshot** | `grimblast copysave area` |
| `Shift + PrtSc` | **Fullscreen Screenshot**| `grimblast copysave screen` |
| `XF86AudioRaiseVolume` | **Volume Up** | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` |
| `XF86AudioLowerVolume` | **Volume Down** | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| `XF86AudioMute` | **Toggle Audio Mute** | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `XF86MonBrightnessUp` | **Backlight Up** | `brightnessctl set 5%+` |
| `XF86MonBrightnessDown`| **Backlight Down** | `brightnessctl set 5%-` |

---

## 3. Core Component Breakdown

### 3.1. Left Rail Taskbar Dock (`components/LeftRail.qml`)

- **Layer Shell Rules**: Anchored `top: true`, `bottom: true`, `left: true`. Enforces immutable positive width `implicitWidth: 54` and `exclusiveZone: 54` to eliminate the 0px fullscreen stretch bug.
- **Top Brandmark Launcher**: Constrained to `32×32px` container with `20×20px` inner cyber-crest SVG emblem (`~/.config/hypr/assets/rice-logo.svg`). Clicking triggers `rofi -show drun`.
- **Workspaces 1–5**: Reacts to `Hyprland.focusedWorkspace.id` with null-safety checks. Active workspace morphs into an animated vertical teal pill (`24×28px`) with spring overshoots; inactive workspaces render as subtle rounded dots.
- **Discrete Utility Tray**: No monolithic drawers opened on quick toggles:
  - **Wi-Fi (`󰖩`)**: Runs isolated `wifi-connect.sh` / `nm-connection-editor`.
  - **Bluetooth (`󰂯`)**: Opens `rofi-bluetooth` / `blueman-manager`.
  - **Audio (`󰕾`)**: Opens `pavucontrol` or toggles mute.
  - **Notification Bell (`󰂚`)**: Displays unread badge count; toggles `NotifCenter.qml`.
  - **Wallpaper Carousel (`󰸉`)**: Pops open the 3D wallpaper picker modal.
  - **Settings (`󰒓`)**: Triggers system settings.
  - **Vertical Time Stack & Power**: Stacked `HH` over `MM` in monospace typography; bottom red-accented power button triggers `wlogout` / shutdown.

### 3.2. Right-Edge HUD Dashboard (`components/Dashboard.qml`)

- **Layer Shell Rules**: Anchored `top: true`, `bottom: true`, `right: true` with `implicitWidth: 440`. Slide animation on `x` and `opacity`.
- **Right-Edge Gesture & Auto-Dismiss**: Opens when moving cursor within 4px of the right screen edge. When cursor leaves the panel (`onExited`), a 350ms grace timer automatically closes and slides it away.
- **Uniform Tab Layout**: Strictly identical bounding box dimensions across all 4 tabs (`Home`, `Media`, `System`, `Tools`).
- **Dynamic Hardware Telemetry (No Hardcoded Strings)**:
  - **CPU**: Real-time probe of `/proc/cpuinfo` and `/sys/class/thermal/thermal_zone*/temp`.
  - **GPU**: Auto-detects active cards via `lspci | grep -iE 'vga|3d|display'`.
  - **RAM**: Computes live usage and percentage on-the-fly from `/proc/meminfo` (`MemTotal` vs `MemAvailable`).
  - **Uptime**: Live tracking via `uptime -p`.
  - **Audio Sink**: Reads PipeWire / WirePlumber default sink via `wpctl status`.
  - **MPRIS Mini Player**: Live track/artist via `playerctl metadata` with play/pause/skip triggers and vinyl disk rotation.
  - **Compositor Vibe Profiles**: 1-click switches for *Study*, *Gaming*, *Chill*, and *Night* modes executing `~/.config/hypr/scripts/vibe_switch.sh`.

### 3.3. Notification Center & Daily Objectives (`components/NotifCenter.qml`)

- **Layer Shell Rules**: Anchored `top: true`, `bottom: true`, `left: true` with `margins { left: 60 }` so it glides out alongside the 54px Left Rail without visual clipping.
- **Auto-Dismiss**: Cursor exit triggers a 350ms auto-close timer.
- **Interactive Calendar Strip**: Horizontal 7-day week view highlighting the current day.
- **Daily To-Do Task Hub**: Full task checklist with task entry box, completion toggle (`[✓]` strikethrough), priority tags (High, Medium, Normal), and filter tabs (*All*, *Pending*, *Done*).
- **Notification Stack**: Clean categorized history cards with dismiss and quick-action buttons.

### 3.4. Floating Urgent Toast (`components/NotifToast.qml`)

- **Layer Shell Rules**: Anchored `top: true` only (`implicitWidth: 440`, `implicitHeight: 96`). In Wayland layer-shell, unconstrained edges automatically center horizontally.
- **Transient Alert Surface**: Designed for single notifications (e.g. *Pomodoro 25m Focus Break*) with auto-dismiss after 8 seconds and action buttons (*Take Break*, *Snooze 5m*).

### 3.5. 3D Coverflow Wallpaper Carousel (`components/WallpaperCarousel.qml`)

- **Stage**: Centered modal stage (`840×520px`) with dark translucent glass backdrop.
- **3D Coverflow Perspective**: Interactive card strip using Y-axis rotation and depth scaling (`scale: 1.0` active, `scale: 0.8` flanks).
- **Keyboard & Mouse Control**: Navigate with left/right arrows or mouse wheel; hit `Enter` to apply wallpaper via `awww` / `swww`. Automatically runs `extract-theme.py` to regenerate the dynamic color palette.

---

## 4. Directory & File Organization

```
~/Projects/my-rice/
├── shell.qml # Master QuickShell orchestrator & edge sensor
├── config/
│   └── Theme.qml # Singleton theme tokens loaded from /tmp/gps-theme.json
├── components/
│   ├── LeftRail.qml # 54px exclusive Wayland taskbar dock
│   ├── Dashboard.qml # 440px right-edge hover HUD with live telemetry
│   ├── NotifCenter.qml # 360px notification & to-do drawer
│   ├── NotifToast.qml # Floating top-center transient banner toast
│   └── WallpaperCarousel.qml # 840x520 3D coverflow wallpaper picker
├── components_backup/ # Archived experimental / legacy components
└── scripts/
    ├── run-gps.fish # Master startup & restart orchestrator
    ├── extract-theme.py # Dynamic HSV palette extractor from wallpaper
    ├── cycle-wall.fish # Wallpaper rotation script
    └── wifi-connect.sh # Lightweight discrete Wi-Fi connection dialog
```

---

## 5. Critical Workarounds & System Invariants

1. **Positive Thickness Invariant (0px Layer Shell Bug)**: In `zwlr_layer_shell_v1`, setting `implicitWidth: 0` or `implicitHeight: 0` triggers an immediate compositor bug that expands the surface across the entire display (white screen freeze). All docks must have an explicit, non-zero dimension (`implicitWidth: 54`).
2. **Wayland Top-Center Geometry**: `PanelWindow.anchors` is an `AnchorGroup` accepting only boolean edges (`top`, `bottom`, `left`, `right`). It does **not** support `horizontalCenter`. To center a top window, anchor `top: true` only.
3. **TextInput Placeholder Text in QtQuick**: Primitive `QtQuick.TextInput` does not possess a `placeholderText` property (only `QtQuick.Controls.TextField` does). Placing `placeholderText` on `TextInput` crashes QML compilation and aborts the scene graph.
4. **D-Bus Exclusive Ownership**: `tide-island` holds exclusive ownership of `org.freedesktop.Notifications`. QuickShell must never instantiate a `NotificationServer`.
5. **Dynamic System Telemetry**: Never use hardcoded host strings. Telemetry must be read dynamically via QuickShell `Process` from `/proc/cpuinfo`, `/proc/meminfo`, and `/sys/class/thermal/`.

---

## 6. How to Launch & Restart

To start the entire desktop environment cleanly:

```fish
cd ~/Projects/my-rice
fish scripts/run-gps.fish
```

To run QuickShell in the foreground for debugging and live logs:

```fish
QS_LOG_LEVEL=debug quickshell -p ~/Projects/my-rice/shell.qml
```
