# Aetheric Shell: Wayland Rice Architecture & System Reference

**Aetheric Shell (GPS Desktop)** is a high-performance, ultra-responsive Wayland desktop environment and "rice" built for **Hyprland** (v0.42+) and **QuickShell** (Qt6/QML), featuring the integrated GPS Island status pill and notification center. Designed for high-refresh displays (165Hz VRR) and a minimal memory footprint (~220 MiB idle RAM) on Arch Linux / CachyOS.

---

## Documentation Navigation

- 📖 **[Installation, Packaging & Recovery Manual](docs/installation.md)**: Complete guide covering prerequisites, dry-run, atomic transactions, recovery, relocation, and troubleshooting.
- 📦 **[Package & Dependency Manifests](packages/README.md)**: Detailed dependency breakdown (`required.txt`, `optional.txt`, `aur.txt`) and `gps-deps` CLI reference.
- 🎨 **[Design System Specification](docs/design-system.md)**: Tokens, component styling, and visual rules.

---

## Table of Contents

1. [System Architecture & Dual-Shell Topology](#1-system-architecture--dual-shell-topology)
2. [Quick Start & Safe Installation](#2-quick-start--safe-installation)
3. [Master Keybind Matrix & Gesture Reference](#3-master-keybind-matrix--gesture-reference)
4. [Core Component Breakdown](#4-core-component-breakdown)
5. [Directory & File Organization](#5-directory--file-organization)
6. [Critical Workarounds & System Invariants](#6-critical-workarounds--system-invariants)
7. [How to Launch & Restart](#7-how-to-launch--restart)
8. [Verification Snapshot](#8-verification-snapshot)

---

## 1. System Architecture & Dual-Shell Topology

Aetheric Shell uses an isolated, collision-free dual-shell architecture:

1. **QuickShell (`shell.qml`)**:
   - Manages the exclusive vertical **Left Rail Dock** (`LeftRail.qml`), the edge-hover **Dashboard drawer** (`DashboardHost.qml` hosting `Dashboard.qml`, whose frame loads the four panes in `components/dashboard/`), the **Notification Center & To-Do Drawer** (`NotifCenter.qml`), the floating **Toast Banners** (`NotifToast.qml`), the Wi-Fi / Bluetooth popups (`WifiPopup.qml`, `BluetoothPopup.qml`), and the **3D Coverflow Wallpaper Carousel** (`WallpaperCarousel.qml`).
   - Operates as a passive notification consumer to prevent D-Bus collision.
2. **GPS Island (`island/IslandProduction.qml`, run as its own QuickShell instance)**:
   - Standalone top-center status pill (`quickshell -p island/IslandProduction.qml`).
   - Holds exclusive ownership of `org.freedesktop.Notifications`.
   - Provides live MPRIS media tickers, dynamic battery/volume indicators, and clipboard management via `cliphist`.
   - Reachable over IPC; the shell and scripts call it via `gps-ipc island <action>`.

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

## 2. Quick Start & Safe Installation

GPS provides a safe, idempotent, user-space installer that never requires `sudo` and never modifies system directories.

For complete documentation, see the [Installation, Packaging & Recovery Manual](docs/installation.md).

### Step 1: Clone Repository

```bash
git clone https://github.com/your-username/my-rice-pk1.git ~/Projects/my-rice-pk1
cd ~/Projects/my-rice-pk1
```

### Step 2: Inspect Dependencies (Read-Only)

GPS dependencies are declared in `packages/`. The dependency inspector is strictly read-only and never runs `sudo` or modifies your system:

```bash
# Check dependencies and view grouped installation commands
scripts/gps-deps

# Check only core-required dependencies
scripts/gps-deps --required-only
```

Install any missing required packages with the command provided in `gps-deps` output (e.g. `sudo pacman -S --needed <packages>`). See [packages/README.md](packages/README.md) for full dependency reference.

### Step 3: Dry-Run Inspection (Default)

Running `./install.sh` without flags inspects your environment and prints planned actions without modifying any files:

```bash
./install.sh
```

### Step 4: Apply Installation

Execute the installation plan within an atomic transaction:

```bash
./install.sh --apply
```

- Pre-existing conflicting configuration files are backed up to `$XDG_STATE_HOME/gps/backups/` with SHA-256 verification.
- Dotfile symlinks are created atomically using temporary file renaming.
- Configuration templates (`rice-settings.json`, `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`) are created only if absent; existing user settings are preserved.
- If interrupted (`Ctrl+C`), the installer automatically rolls back all applied changes cleanly.

### Step 5: Verify Installation

Confirm all symlinks, dependencies, and session diagnostics:

```bash
./install.sh --check
```

### Safe Uninstallation

To remove GPS symlinks and restore all original pre-installation files:

```bash
./install.sh --uninstall
```

User state files (`rice-settings.json`, `settings.ini`, `gps-theme.json`, logs) and user modifications are **intentionally preserved**.

### Repository Relocation

If you move or rename the repository, dotfile symlinks become broken because they use absolute paths. To update all symlinks cleanly, simply re-run:

```bash
cd /new/path/to/my-rice-pk1
./install.sh --apply
```

### Isolated Clean-Account Trial

To evaluate GPS without touching your primary desktop environment, we recommend testing in a separate Linux user account. See [docs/installation.md#8-isolated-clean-account-trial](docs/installation.md#8-isolated-clean-account-trial).

---

## 3. Master Keybind Matrix & Gesture Reference

| Keybind / Gesture | Subsystem / Action | Implementation / Target |
| :--- | :--- | :--- |
| **Bottom-Right Hot Zone** | **Slide Open Dashboard** | Invisible 22x22 edge sensor in `shell.qml`; 800ms re-arm cooldown; disabled entirely by the EDGE HOTSPOT toggle (System tab) |
| **Cursor Leave Drawer** | **Auto-Dismiss Drawers** | `hub.dashboardAutoHideMs` grace timer (default 400ms; 150–800ms in System tab) |
| `Super + D` | **Toggle Dashboard HUD** | `gps-ipc shell dashboard toggle` |
| `Super + N` | **Toggle Notification Center**| `gps-ipc shell notifcenter toggle` |
| `Super + W` | **Toggle 3D Wallpaper Carousel**| `gps-ipc shell wallpaper toggle` |
| `Super + ,` | **Toggle Settings Hub** | `gps-ipc settings toggle` (launches the app if not running) |
| `Super + Space` / `Super + R` | **App Launcher** | `rofi -show drun`; palette comes from the generated `~/.config/rofi/colors.rasi` (`@import` — regenerated on every wallpaper change, applied on next rofi launch; also from the dock logo). Single launcher by decision: `fuzzel` is installed but unconfigured — rofi stays |
| `Super + Q` | **Terminal Emulator** | `kitty` (`$terminal` in `hyprland.lua`) |
| `Super + E` | **File Manager** | `thunar` (`$fileManager`) |
| `Super + C` | **Close Active Window** | `hl.dsp.window.close()` |
| `Super + L` | **Lock Screen** | `hyprlock` (packaged, or the user-local staged build until `setup-lockscreen.sh` runs); no-op if already locked |
| `Super + V` | **Toggle Island Clipboard** | `gps-ipc clipboard toggle` (routes to active island backend) |
| `Super + Shift + V` | **Toggle Floating** | `hl.dsp.window.float({ action = "toggle" })` |
| `Super + M` | **Exit Hyprland** | `hyprshutdown` (falls back to `hl.dsp.exit()`) |
| `Super + P` / `Super + J` | **Pseudo-tile / Toggle Split** | `hl.dsp.window.pseudo()`, `hl.dsp.layout("togglesplit")` |
| `Super + Arrow Keys` | **Directional Focus** | `hl.dsp.focus({ direction = … })` |
| `Super + 1..5` / `Super + Shift + 1..5` | **Switch / Move-to Workspaces** | Native Hyprland workspace dispatcher |
| `Super + S` / `Super + Shift + S` | **Special Workspace (magic)** | `toggle_special("magic")` / move window to it |
| `Super + Mouse Wheel` | **Cycle Workspaces** | `focus workspace e+1` / `e-1`; the dock's workspace pills also scroll via their own wheel handler (`switchTo(current ± 1)`) |
| `Super + LMB / RMB drag` | **Move / Resize Window** | `window.drag()` / `window.resize()` mouse binds |
| `XF86AudioMicMute` | **Toggle Mic Mute** | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| `XF86AudioNext/Prev/PlayPause` | **Media Transport** | `playerctl next` / `previous` / `play-pause` |
| `PrtSc` | **Snip Screenshot** | `r=$(slurp) \|\| exit 0; grim -g "$r" - \| swappy -f -` (Esc cancels cleanly; nothing is written) |
| `XF86AudioRaiseVolume` | **Volume Up** | `wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+` |
| `XF86AudioLowerVolume` | **Volume Down** | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| `XF86AudioMute` | **Toggle Audio Mute** | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `XF86MonBrightnessUp` | **Backlight Up** | `brightnessctl -e4 -n2 set 5%+` |
| `XF86MonBrightnessDown`| **Backlight Down** | `brightnessctl -e4 -n2 set 5%-` |

Not bound in the live `hyprland.lua` (verified against `hyprctl binds -j`): `Super + Return` (terminal is `Super + Q`) and `Super + F1–F4` "vibes" (`scripts/vibe_switch.sh` only writes `$XDG_RUNTIME_DIR/gps-vibe-mode` — nothing consumes it yet and no keys are bound; night warmth would also need `hyprsunset`). The complete, live-verified keybind reference is `keybind.txt` in this repository.

---

## 4. Core Component Breakdown

### 4.1. Left Rail Taskbar Dock (`components/LeftRail.qml`)

- **Layer Shell Rules**: Anchored `top: true`, `bottom: true`, `left: true`. Enforces immutable positive width `implicitWidth: 54` and `exclusiveZone: 54` to eliminate the 0px fullscreen stretch bug.
- **Top Brandmark Launcher**: Constrained to `32×32px` container with `20×20px` inner cyber-crest SVG emblem (`~/.config/hypr/assets/rice-logo.svg`). Clicking triggers `rofi -show drun`.
- **Workspaces 1–5**: Reacts to `Hyprland.focusedWorkspace.id` with null-safety checks. Active workspace morphs into an animated vertical teal pill (`24×28px`) with spring overshoots; inactive workspaces render as subtle rounded dots.
- **Discrete Utility Tray**: No monolithic drawers opened on quick toggles:
  - **Wi-Fi (`󰖩`)**: Runs isolated `wifi-connect.sh` / `nm-connection-editor`.
  - **Bluetooth (`󰂯`)**: Opens `rofi-bluetooth` / `blueman-manager`.
  - **Audio (`󰕾`)**: Opens `pavucontrol` or toggles mute.
  - **Notification Bell (`󰂚`)**: Displays unread badge count; toggles `NotifCenter.qml`.
  - **Wallpaper Carousel (`󰸉`)**: Pops open the 3D wallpaper picker modal.
  - **Local AI (`󰧑`)**: Opens the Aetheric Neural Chat panel (local Ollama, loopback only); mutually exclusive with the carousel/dashboard/popups.
  - **Settings (`󰒓`)**: Triggers system settings.
  - **Battery Pill**: real UPower telemetry (glyph + live %) above the power button — teal while charging/full, amber ≤30%, coral ≤15%; hidden entirely when the device has no battery. Click opens the Power & Battery popup (§4.10).
  - **Vertical Time Stack & Power**: Stacked `HH` over `MM` in monospace typography; bottom red-accented power button opens the built-in confirm-gated power menu (lock / suspend / logout / reboot / shutdown) and closes any open radio popup first.

### 4.2. Right-Edge Dashboard (`components/DashboardHost.qml` + `components/Dashboard.qml`)

- **Host (`DashboardHost.qml`)**: single canonical drawer anchored `top/right/bottom` (layer geometry `830 8 440 784`). Every entry point (IPC, edge sensor, rail) routes through `hub.openDashboard()` → `dashboardHost.open()`; `open/close/toggle` are IPC-callable. Auto-hide on pointer exit uses `hub.dashboardAutoHideMs` (default 400ms, clamp 150–800ms); Escape closes. Opening the drawer closes any radio popup (mutual exclusion), and opening a popup closes the drawer.
- **Frame (`Dashboard.qml`)**: tab bar (`DashTabBar.qml`) + per-pane `Loader`s that are active **only while the drawer is covering** — closing the drawer destroys the panes, so their timers and child processes stop (verified: audio capture process count 1 → 0 on close).
- **HOME tab**: `SysProbe.qml` single shared probe tick (CPU from `/proc/cpuinfo` + thermal zones, RAM from `/proc/meminfo`, GPU, storage `df` at 30s, uptime — tick interval follows `hub.telemetryTickMs`); 3 stat cards; toggles for Wi-Fi / Bluetooth / Audio Output / Circadian (shows `unavailable · no backend` honestly); PipeWire volume slider; live 48kHz s16le spectrum; MPRIS now-playing with circular artwork; screen-time card (AW-compatible local API, AFK excluded, app-class labels only).
- **MEDIA tab**: MPRIS transport (prev / play-pause / next), seek + shuffle + loop **capability-gated** on the active player; audio output device list with honest `UNAVAILABLE` marks and verified `set-default`; volume + mute; spectrum from the same shared singleton capture (never a second `parec`); on-demand lyrics lookup (LRCLIB, user-initiated only).
- **SYSTEM tab**: LIVE telemetry header; controls that drive real behavior — edge-hotspot toggle, auto-dismiss grace slider, telemetry polling rate (1s/3s/5s); display brightness via `brightnessctl` with read-back verification; power profiles from `powerprofilesctl list` with verified writes.
- **TOOLS tab**: capture actions (snip region / copy region / full screen / color picker via `grim`+`slurp`+`swappy` / `hyprpicker`); wallpaper next / carousel / regenerate palette (`cycle-wall.fish`, `extract-theme.py`); Tide Island controls (notification center, clipboard history, clear clipboard, **confirm-gated** wipe); automation & power with honest unavailable states (no locker, no hyprsunset, no Wine running) and **confirm-gated** Suspend / Shut Down; RELOAD SHELL restarts the shell while preserving Tide Island.

### 4.3. Notification Center & Daily Objectives (`components/NotifCenter.qml`)

- **Layer Shell Rules**: Anchored `top: true`, `bottom: true`, `left: true` with `margins { left: 60 }` so it glides out alongside the 54px Left Rail without visual clipping.
- **Auto-Dismiss**: Cursor exit triggers a 350ms auto-close timer.
- **Interactive Calendar Strip**: Horizontal 7-day week view highlighting the current day.
- **Daily To-Do Task Hub**: Real task checklist (starts empty — no sample data) with task entry box, completion toggle (`[✓]` strikethrough) and filter tabs (*All*, *Pending*, *Done*).
- **Real Notification Feed**: *Recent notifications* are polled live (every 3 s while open) from Tide Island's history via `quickshell ipc -p ~/.local/share/tide-island call island history` — app, summary, body and relative time; empty state until a real notification arrives. No fabricated cards.
- **Focus / DND Control**: shows Tide Island's actual `focusEnabled` state and toggles it via `island focusToggle`; *Open Center* opens the Tide Island notification center (`tide toggleNotificationCenter`). Tide Island persists Focus across its restarts (`~/.cache/gps/dnd`) and **critical-urgency** notifications bypass it (they still surface while normal ones stay suppressed — verified live: `notify-send -u normal` hidden, `notify-send -u critical` shown + in history).

### 4.4. Floating Urgent Toast (`components/NotifToast.qml`)

- **Layer Shell Rules**: Anchored `top: true` only (`implicitWidth: 440`, `implicitHeight: 96`). In Wayland layer-shell, unconstrained edges automatically center horizontally.
- **Transient Alert Surface**: drives off the shell's real toast state (`toastApp` / `toastSummary` / `toastBody`, currently fired by the Pomodoro timer). Hidden while those are empty; single *Dismiss* action wired to `dismissToast()`; auto-dismiss after 8 s. No placeholder text or fake actions.

### 4.5. 3D Coverflow Wallpaper Carousel (`components/WallpaperCarousel.qml`)

- **Stage**: Centered modal stage (`840×520px`) with dark translucent glass backdrop.
- **3D Coverflow Perspective**: Interactive card strip using Y-axis rotation and depth scaling (`scale: 1.0` active, `scale: 0.8` flanks).
- **Keyboard & Mouse Control**: Navigate with left/right arrows or mouse wheel; hit `Enter` to apply wallpaper via `awww` / `swww`. Automatically runs `extract-theme.py` to regenerate the dynamic color palette.

### 4.6. Aetheric Neural Chat — Local AI Panel (`components/AIChat.qml`)

- **Window**: 860×680 centered `Overlay` layer surface (`topMargin: 80`); `Exclusive` keyboard focus while open, `Escape` closes. The thread survives close/reopen for the session and is discarded only via the two-tap CLEAR action — there is no on-disk chat history.
- **Streaming pipeline**: `scripts/ai-chat.py` (Python stdlib only) reads one JSON request line from stdin and streams NDJSON events (`chunk` / `done` / `error` / `offline`) from Ollama `POST /api/chat`. The panel renders tokens live via `Process` + `SplitParser`; TTFT, tok/s and prompt/output token counts come from the real final event (`prompt_eval_count`, `eval_count`, `eval_duration`) — never simulated.
- **UI states (all honest)**: backend pill `OLLAMA (ACTIVE/CONNECTING/OFFLINE)` in the footer, red banner + RETRY when the server is unreachable, suggestion chips in the empty state, model dropdown fed by `GET /api/tags` (only locally pulled models), VRAM pill from `nvidia-smi` (live, 5 s while open), token counter against the active context window.
- **Settings Hub sync (single source of truth)**: the panel watches `~/.config/quickshell/rice-settings.json` (`FileView` + `watchChanges`). The hub's assistant defaults — model, context size, temperature, system prompt — apply live to the next request (verified end-to-end: external store write + model pull switched the panel without a restart); picking a model in the panel's dropdown writes the choice back to the store with a stdlib-only Python JSON patch so the hub and panel never disagree. With no default set, the first installed model is used (currently `llama3.2:3b`).
- **Content actions**: fenced code blocks render as mono blocks with COPY (Wayland clipboard); STOP aborts the stream and marks the message *Stopped* without fabricated metrics; REGENERATE re-sends the last user turn; the header telemetry toggle hides/shows per-message metrics.
- **Exclusivity**: opening the chat closes the dashboard, radio popups and wallpaper carousel; opening any of those closes the chat (verified both directions).
- **IPC**: `gps-ipc shell aichat open|close|toggle|send <text>|stop|clear|regenerate`.
- **Privacy**: endpoint is hard-fixed to `127.0.0.1:11434`; prompts and replies never leave the machine, are never logged by the bridge, and no API keys exist anywhere in the pipeline.

### 4.7. Ollama Local Backend (user service)

- `~/.config/systemd/user/ollama.service` runs `ollama serve` bound to **`127.0.0.1:11434` only** (verified with `ss`), storing models in `~/.ollama/models`.
- Start/stop: `systemctl --user start|stop ollama` · status: `systemctl --user status ollama` · logs: `journalctl --user -u ollama -f`.
- Model used by the panel: the **Default model** selected in the Settings Hub (AI & Models); with none selected the first installed model is used (`llama3.2:3b`, ~2 GB, GPU offload on the RTX 4050). Pull with `ollama pull <model>` or from the hub's Pull card (free space on the models volume is checked first); list with `ollama list`. If the panel shows OFFLINE, start the service (`systemctl --user start ollama`, also possible from the hub) and hit RETRY.

### 4.8. Lockscreen (Hyprlock + Howdy face unlock)

- **Config**: `~/.config/hypr/hyprlock.conf`, visually matched to `design_refs/Lockscreen.html`. Two hard-won rules are documented in its header: every widget carries an explicit `zindex` (hyprlock sorts widgets by zindex with a non-stable sort — omitted zindexes scramble the layer order), and all dynamic text is shelled out to `scripts/lock-info.sh` (`bat|net|kb|caps|clients|media-title|media-artist|media-vol|user|host|auth|howdy-status|sockets`) because hyprlock's config parser rejects `#` and `$(...)` in values.
- **Entry points**: `Super + L` (global bind — prefers `hyprlock` from PATH, falls back to the staged build, no-op if already locked), Left Rail power menu → *Lock Screen*, and Dashboard → TOOLS → *LOCK SCREEN*; the menu entry points run `pidof hyprlock || hyprlock || loginctl lock-session`.
- **PAM stack**: `sudo scripts/setup-lockscreen.sh` installs `hyprlock` from the official repos and writes `/etc/pam.d/hyprlock` as a dedicated stack — `#%PAM-1.0` header, `auth sufficient /usr/lib/security/pam_howdy.so` (face, only when the module exists), then `auth|account|password|session include system-local-login` for every section (`login` is substituted only on systems without `system-local-login`). The include lines reuse this system's own login chain (`system-local-login → system-login → system-auth`) verbatim: nothing is copied out of `system-auth`, shared PAM files are never modified, and `pam_faillock`, `pam_shells`, `pam_nologin` and `pam_access` keep the distro behavior. Face is attempted first; the account password always remains a valid unlock and is the only method until a Howdy model exists. Any pre-existing file (the hyprlock package's shipped default `auth include login`, or a previous run's file that was later edited) is preserved with a timestamped, collision-safe backup before every overwrite; byte-identical re-runs change nothing. `scripts/setup-lockscreen.sh --self-test` rehearses the backup/write/verify logic in a temp dir without root.
- **Manual step (human only)**: face unlock stays inactive until enrolled — run `sudo howdy add` once (camera `/dev/video0`; the shared `/etc/howdy/config.ini` is never modified). Test at a safe moment with a TTY available: run `hyprlock`, unlock with the password. Recovery if a lock ever misbehaves: switch to a TTY and `pkill -x hyprlock`.
- **Rollback / precise restore**: the run prints the exact backup path — `sudo cp -a <backup-file> /etc/pam.d/hyprlock` restores the previous state; `sudo pacman -S hyprlock` reinstalls the package default; `sudo rm /etc/pam.d/hyprlock` leaves no stack (hyprlock falls back to `/etc/pam.d/su`); `sudo pacman -Rns hyprlock` removes the locker. Note: the package does not mark `/etc/pam.d/hyprlock` as a pacman backup file, so a future hyprlock upgrade may replace the stack — re-run the setup script afterwards.

### 4.9. Settings Hub (`settings.qml`)

- **Window**: standalone second QuickShell instance (`quickshell --no-duplicate -p settings.qml`), toggled with Super+, — the bind reuses a running instance via `gps-ipc settings toggle`.
- **Store**: `~/.config/quickshell/rice-settings.json` is the single source of truth for saved values; the Hub watches it (`watchChanges`) and the AI panel does too. Hyprland option writes go through `hyprctl keyword` with an automatic `hyprctl eval` fallback (required on the Lua parser: `keyword` is rejected there); monitor data comes from `hyprctl monitors -j`, binds from `hyprctl binds -j`.
- **Persistent Hyprland settings**: on save, a generated `rice-settings.lua` (or `.conf` outside Lua mode) is written and the exact include line is shown. The System page detects whether the include is already present in the active Hyprland config and offers a one-click **Add include line (with backup)** — it appends at the END (so saved values win) after a timestamped `cp -a` backup, never touching anything else.
- **AI & Models page (real backends only)**: Ollama status/version from the live API plus `systemctl --user is-active ollama`; **Start/Stop service** buttons drive the user unit (no detached `ollama serve` processes); the Endpoint field accepts only loopback URLs (`127.0.0.1` / `localhost` / `[::1]`) because the chat bridge is hard-fixed to loopback; model list and pull progress come from `GET /api/tags` + `POST /api/pull`; a pull only starts after a real free-space check on the models volume; **Open chat** / **Stop generation** buttons call the shell's `aichat` IPC.
- **Honesty rules**: tools that are not installed (e.g. `hyprsunset`) show as missing pills and their toggles hide; nothing is simulated.

### 4.10. Power & Battery Popup (`components/BatteryPopup.qml`)

- **Route**: uses the same popup router the Wi-Fi/BT/clock popups use (`hub.openPopup("battery", anchorY)` / `hub.dashboardOpen && hub.activePopup === "battery"`), docked 62px from the left edge next to the rail battery pill, vertically clamped on-screen, Escape + cursor-leave (350ms grace) dismissal. Opening it closes any other popup and the dashboard; it was routed in the shell long before a component existed — this fills that gap.
- **Battery telemetry**: the shared UPower service (`Quickshell.Services.UPower`, same singleton the island uses) — percentage, state, time-to-full/empty and health, all read live. The bolt glyph is shown only while actually `Charging`; a plugged-but-"Not charging" battery keeps the level glyph so the icon never contradicts the text. Hidden with an honest "No battery detected" note when `isPresent` is false.
- **Power profiles**: live `powerprofilesctl list` parse (same regex/degraded-driver handling as the System tab), current profile chip, per-profile accent, `degraded` tag; **writes are verified** — `powerprofilesctl set <id>` plus a bounded re-read loop before success is shown; real stderr/exit text is surfaced on failure. Empty list shows an honest daemon-not-running message.
- **IPC**: `gps-ipc popup open battery|wifi|bt|clock`, `close`, `powerProfiles`, `setPowerProfile <id>`. The rail battery pill and the dashboard System tab drive the same daemon — one backend, multiple surfaces, never a fabricated value.

### 4.11. Unified Theme Pipeline (`scripts/extract-theme.py` → `~/.config/quickshell/gps-theme.json`)

- **Source of truth**: `extract-theme.py` reads the *current* wallpaper (`awww query`), extracts the dominant hue via a weighted 36-bucket HSV histogram, and writes `~/.config/quickshell/gps-theme.json` (`wallpaper`, `surface`, `card`, `cardHover`, `track`, `border`, `brandAccent`, `brandAccentFg`, `textMain`, `textMuted`). It runs at shell startup (`run-gps.fish`), on every carousel apply, on the Tools-tab *Regenerate palette* action, and on wallpaper cycling.
- **Shell (Theme.qml)**: the singleton watches that file (`FileView` + `watchChanges`) and every mapped token follows it **live, without a restart** — verified blue → red → blue across wallpaper switches. Unmapped keys fall back to the built-in design defaults, so the shell always boots even with no palette file. Status colors (good/warn/danger) stay fixed by design.
- **Settings Hub**: palette probe order is `~/.config/quickshell/gps-theme.json` → pywal `colors.json` → Caelestia `scheme.json` → built-in fallback (`paletteSource` shows which is active on the Appearance card); the palette FileView watches the chosen file, so the hub restyles live too.
- **Rofi**: colors are no longer rewritten inside `config.rasi`; the extractor generates `~/.config/rofi/colors.rasi` and the config just `@import`s it — user config stays untouched, changes apply on next rofi launch.
- **Hyprland borders**: the extractor also sets `general:col.{active,inactive}_border` to match. On legacy (hyprlang) configs it uses `hyprctl keyword`; on the 0.55+ Lua parser — which silently rejects `keyword` — it falls back to `hyprctl eval 'hl.config(...)'` with the Lua gradient syntax (`{ colors = {...}, angle = 45 }`). Verified live.

### 4.12. GPS User-Space Installer & Relocation Contract

The GPS installer (`./install.sh` or `scripts/installer.py`) manages user-space dotfile symlinks, configuration templates, backups, rollback, and diagnostics. For full architectural specifications, see the [Installation, Packaging & Recovery Manual](docs/installation.md).

- **Command Modes**:
  - `./install.sh` (or `--dry-run`, default): Inspects all planned symlinks, templates, and conflicts without touching the filesystem.
  - `./install.sh --apply`: Executes the installation plan within an atomic transaction. Backs up pre-existing user files (with SHA-256 integrity hashing), deploys symlinks atomically via temporary file rename, instantiates user templates, and records an active installation manifest in `$XDG_STATE_HOME/gps/install_manifest.json`.
  - `./install.sh --uninstall`: Safely rolls back GPS-managed symlinks and restores original pre-installation files. Detects and preserves user modifications and state files (`settings.ini`, `rice-settings.json`, `gps-theme.json`).
  - `./install.sh --check`: Verifies that all managed files point to the active clone, verifies dependency availability, and runs `scripts/gps-doctor`.
- **Transaction Recovery & Concurrency Safety**:
  - Mutating operations (`--apply`, `--uninstall`) acquire an exclusive per-user lock (`$XDG_STATE_HOME/gps/installer.lock`) to prevent concurrent installer execution.
  - Transactions persist a durable, fsynced journal (`install_journal.json`) before making modifications. If interrupted (`SIGINT`, `SIGTERM`, crash), the installer automatically and idempotently recovers or rolls back the transaction.
- **Repository Relocation Contract**:
  - Dotfile symlinks are created using **absolute paths** to guarantee deterministic resolution regardless of working directory or shell context.
  - If the repository clone is moved, renamed, or relocated, existing symlinks will break.
  - **Relocation recovery**: Simply navigate to the relocated repository and re-run `./install.sh --apply`. The installer idempotently updates all symlinks to point to the new repository location without losing user settings or duplicating backups.

---

## 5. Directory & File Organization

```
my-rice-pk1/
├── shell.qml # Master QuickShell orchestrator, hub API, IPC handlers, edge sensor
├── settings.qml # Standalone Settings Hub app (own QuickShell instance; Super+comma)
├── install.sh # Safe, idempotent user-space installer entrypoint
├── packages/ # Declarative dependency manifests (required.txt, optional.txt, aur.txt)
├── docs/ # Architecture, installation, and design documentation
├── config/
│   └── Theme.qml # Live theme singleton: watches ~/.config/quickshell/gps-theme.json
├── components/
│   ├── LeftRail.qml # 54px exclusive Wayland taskbar dock
│   ├── DashboardHost.qml # Canonical right-edge drawer host (auto-hide, exclusivity)
│   ├── Dashboard.qml # Drawer frame: DashTabBar + per-pane loaders
│   ├── dashboard/ # HomeTab / MediaTab / SystemTab / ToolsTab + shared cards
│   ├── NotifCenter.qml # 360px notification & to-do drawer
│   ├── NotifToast.qml # Floating top-center transient banner toast
│   ├── WallpaperCarousel.qml # 840x520 3D coverflow wallpaper picker
│   ├── AIChat.qml # 860x680 local AI chat panel (Ollama streaming, loopback only)
│   ├── BatteryPopup.qml # Power & battery popup (UPower + verified powerprofilesctl)
│   └── WifiPopup.qml / BluetoothPopup.qml # Anchored radio popups
└── scripts/
    ├── installer.py # Transactional installer engine with lock, journal, and backup
    ├── gps-deps # Read-only dependency inspector with pacman/paru guidance
    ├── run-gps.fish # Master startup & restart orchestrator
    ├── gps-ipc # Unified IPC CLI for shell, island, settings, pet, and rail
    ├── ai-chat.py # Loopback-only Ollama bridge (NDJSON streaming, no persistence)
    ├── setup-lockscreen.sh # Root helper: install hyprlock + write PAM stack (Howdy → login)
    ├── lock-info.sh # Real-value provider for every dynamic hyprlock label
    ├── extract-theme.py # Wallpaper → ~/.config/quickshell/gps-theme.json + rofi colors.rasi
    ├── cycle-wall.fish / pick-wall.fish # Wallpaper rotation / selection
    ├── audio-spectrum.py # Real FFT spectrum (parec monitor, s16le 48kHz)
    ├── audio-sinks.py # Read-only WirePlumber sink enumeration
    └── wifi-connect.sh # Lightweight discrete Wi-Fi connection dialog
```

---

## 6. Critical Workarounds & System Invariants

1. **Positive Thickness Invariant (0px Layer Shell Bug)**: In `zwlr_layer_shell_v1`, setting `implicitWidth: 0` or `implicitHeight: 0` triggers an immediate compositor bug that expands the surface across the entire display (white screen freeze). All docks must have an explicit, non-zero dimension (`implicitWidth: 54`).
2. **Wayland Top-Center Geometry**: `PanelWindow.anchors` is an `AnchorGroup` accepting only boolean edges (`top`, `bottom`, `left`, `right`). It does **not** support `horizontalCenter`. To center a top window, anchor `top: true` only.
3. **TextInput Placeholder Text in QtQuick**: Primitive `QtQuick.TextInput` does not possess a `placeholderText` property (only `QtQuick.Controls.TextField` does). Placing `placeholderText` on `TextInput` crashes QML compilation and aborts the scene graph.
4. **D-Bus Exclusive Ownership**: `tide-island` holds exclusive ownership of `org.freedesktop.Notifications` — its shell instantiates exactly one QuickShell `NotificationServer` (`~/.local/share/tide-island/shell.qml`, verified via `GetServerInformation`). No other shell may instantiate one. Failure mode if that fails: `notify-send` errors with `ServiceUnknown` and no capsule appears — check `pgrep -af tide-island` and the D-Bus name owner first (`gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation`).
5. **Dynamic System Telemetry**: Never use hardcoded host strings. Telemetry must be read dynamically via QuickShell `Process` from `/proc/cpuinfo`, `/proc/meminfo`, and `/sys/class/thermal/`.
6. **Multi-Instance IPC Addressing**: with several QuickShell instances running (rice shell, Tide Island, Settings Hub), a bare `quickshell ipc call …` fails with `Could not find "default" config directory`. Every keybind and helper must pass `-p <the target instance's qml path>` or route via `gps-ipc`.

---

## 7. How to Launch & Restart

To start the entire desktop environment cleanly:

```fish
cd <path-to-gps-repo>
fish scripts/run-gps.fish
```

To run QuickShell in the foreground for debugging and live logs:

```fish
QS_LOG_LEVEL=debug quickshell -p <path-to-gps-repo>/shell.qml
```

### Tide Island & Screen-Time Tracker

- Tide Island runs as its own QuickShell instance (`quickshell -p ~/.local/share/tide-island`); `run-gps.fish` restarts only the rice shell and leaves Tide running. The island guard (`pgrep -f "share/tide-[i]sland"`) starts Tide Island only if absent — a second instance would fight for the D-Bus notification name.
- The GPS island production entrypoint is `island/IslandProduction.qml`. The desktop defaults to Tide because `shell.qml` still routes clipboard and notification-center IPC to Tide. A deliberate one-island cutover is `scripts/switch-island.fish gps`; it persists the choice in `~/.config/quickshell/gps-island-backend`, stops only Tide's exact QuickShell command line, and starts GPS. Roll back with `scripts/switch-island.fish tide`. Do not run both islands together: both own the top-center `island` layer and the notification service.
- `run-gps.fish` restarts the wallpaper daemon and re-applies the last wallpaper from `~/.config/quickshell/gps-last-wall.txt` (`awww-daemon` starts blank), so shell restarts never leave an empty background; `extract-theme.py` then regenerates `~/.config/quickshell/gps-theme.json` from it (and updates the file itself on every wallpaper change).
- Screen-time data comes from **awatcher** (`~/.local/opt/awatcher/awatcher --no-tray`), an ActivityWatch-compatible tracker serving `127.0.0.1:5600`. It is not managed by a systemd unit here — start it with that command (backgrounded) and disable it by killing the process; the screen-time card then honestly reports its `offline` state. The tracker stores window activity locally in its own database; the shell only reads **app-class-level** aggregates and excludes AFK time.
- **Auto-start**: `hyprland.lua` launches `scripts/run-gps.fish` via `hl.on("hyprland.start", …)` — once per compositor start, so every login/reboot brings up the full desktop. (A plain `exec_cmd` runs during config parse, before the Wayland socket accepts clients, which crashed the shell and every GUI daemon at login with `wl_display: Connection refused`.) Hyprland auto-reloads when the config file is edited, but `hyprland.start` does not re-fire on reload — editing `hyprland.lua` or running `hyprctl reload` does **not** restart the shell; use the Tools-tab RELOAD SHELL action or re-run the script.
- **Startup log**: `run-gps.fish` appends a timestamped line per step to `~/.config/quickshell/startup.log` (compositor-ready wait, wallpaper re-apply, island/shell up with pids, or an explicit `ERROR:` line if a process exited during startup). The script also waits up to 10 s for `hyprctl` to reach the compositor before launching anything, so the login race cannot recur.

---

## 8. Verification Snapshot (2026-10-18)

- `qmllint` over every `.qml`: 0 errors. Python scripts compile; fish/bash scripts pass syntax checks.
- Live E2E on the production config: drawer open/close (Super+D, IPC, edge sensor with 800ms re-arm), all four tabs rendered with live data, dashboard/popup mutual exclusion both directions, Super+N / Super+W / Super+comma binds (previously dead — see invariant 6), Print → slurp → Esc cancel (nothing written, swappy never spawned), spectrum process lifecycle 1 → 0 on pane unload, NotifCenter open/close, 0 QML runtime errors in the final shell log.
- **AI chat E2E (verified live via IPC + screenshots)**: panel open/close/toggle, real streamed generation on `llama3.2:3b` (TTFT 57–397 ms, 82–159 t/s on the RTX 4050), multi-turn history, STOP mid-generation (marks *Stopped*, no fabricated metrics), REGENERATE, CLEAR, offline banner + RETRY (service stopped/started), model dropdown from `/api/tags`, live VRAM pill, chat↔dashboard and chat↔carousel exclusivity both directions, port bound to `127.0.0.1` only. 0 QML warnings introduced (`qt.qpa.wayland.textinput` focus chatter from layer-shell text inputs is a known Qt/Wayland quirk, not a shell bug).
- **Lockscreen (verified in a nested Hyprland sandbox)**: config parses clean, ext-session-lock engages, password prompt served by `pam_unix` via the su fallback, full render matches `design_refs/Lockscreen.html` (clock, pills, glass card, input field, biometric/security tiles, media card, VT hint) with correct z-index layering.
- **Phases 4–6 E2E (verified live 2026-10-18)**: battery/power-profile popup drives real UPower + `powerprofilesctl` (set `power-saver` → read back → restored `balanced`); the unified theme pipeline was cycled blue → red → blue with **no restarts** (rail pills, Settings Hub hot-reload, rofi `colors.rasi`, Hyprland border via `eval`); island Focus persists across restarts (`~/.cache/gps/dnd`) and **critical-urgency notifications bypass DND** while normal ones stay suppressed (capsule screenshot + history IPC); `run-gps.fish` boot simulation re-applied the wallpaper from `~/.config/quickshell/gps-last-wall.txt` after killing `awww-daemon`, preserved a running island, and left exactly one rice shell / island / settings instance with 0 errors in all logs. Full sweep: 34 QML files `qmllint`-clean, fish/python/bash scripts syntax-checked.
- **Startup & keybinds (verified live 2026-10-18, second pass)**: root cause of "nothing appears after reboot" — the startup `exec_cmd` ran before the Wayland socket accepted clients; fixed by deferring to `hl.on("hyprland.start", …)` plus a compositor-ready wait and per-step logging in `run-gps.fish`. Verified: two scripted runs brought up exactly one shell / island / awatcher, island and settings untouched, wallpaper re-applied. Added `Super + L` (hyprlock) and `Super + V` (island clipboard toggle, verified live), moved floating to `Super + Shift + V`; full reference in `keybind.txt`.
- Known limitations (honest unavailable states by design, not bugs): face unlock stays **inactive until enrolled** (`sudo howdy add` — deliberately never automated); the system package install + PAM write is a `sudo scripts/setup-lockscreen.sh` human step; Night Warmth has no `hyprsunset`; End Wine reports none running; VRAM shows `—` when the GPU probe has no data. The rail's *Suspend* acts immediately while Log Out / Reboot / Shut Down are confirm-gated; the dashboard TOOLS suspend/shut-down are confirm-gated. `runCenterAction()` in `shell.qml` is currently uncalled. `WorkspaceIndicator.qml` references an undeclared `hub.isHorizontal` — the expression is silently falsy (vertical layout), left as-is. The `popup powerProfiles` IPC getter returns empty until the battery popup has been opened once per shell instance (the profile probe starts on open — by design).
- **Manual verification owed (human)**: correct-password unlock + Howdy face test on the live session (test with a TTY available; recovery `pkill -x hyprlock`), and the wrong-password retry prompt. AI panel: click the rail brain button and type directly (all IPC paths already verified).
