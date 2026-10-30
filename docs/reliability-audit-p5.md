# GPS Daily-Driver Reliability & Architecture Audit (P5.1)

**Date:** 2026-10-30  
**Repository:** `/home/rice/Projects/my-rice`  
**Milestone:** P5 — GPS Daily-Driver Readiness & Reliability  
**Objective:** Operational reliability, predictable process lifecycles, atomic persistence, resilient IPC, and graceful service degradation.

---

## 1. Complete GPS Runtime Map

The GPS desktop environment consists of two cooperating QuickShell instances, an IPC routing layer, compositor configuration, and helper daemons:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Hyprland 0.57 Compositor                        │
│   (dots/hypr/hyprland.lua: window/layer rules, keybinds, autostart)    │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                  ┌──────────────────┴──────────────────┐
                  ▼                                     ▼
┌───────────────────────────────────┐ ┌───────────────────────────────────┐
│     Main QuickShell Instance      │ │    Island QuickShell Instance     │
│           (shell.qml)             │ │  (island/IslandProduction.qml)    │
├───────────────────────────────────┤ ├───────────────────────────────────┤
│ • LeftRail Dock (dock & power)    │ │ • Top-center Status Pill          │
│ • Popups: Battery, Wi-Fi, BT      │ │ • State Router: Alert, Music,     │
│ • HUD Dashboard (Home, Media,     │ │   Notify, Privacy, Focus, Control │
│   System, Tools panes)            │ │ • Built-in NotificationServer     │
│ • AI Chat Drawer (Ollama bridge)  │ │   (D-Bus org.freedesktop.Notifs)  │
│ • Media Hub & Toolbox Windows     │ │ • IPC Target: "island"            │
│ • Wallpaper Carousel              │ │                                   │
│ • Desktop Pet Companion           │ │                                   │
│ • IPC Targets: "dashboard",       │ │                                   │
│   "notifcenter", "wallpaper",     │ │                                   │
│   "aichat", "popup", "mediahub",  │ │                                   │
│   "toolbox", "pet", "rail"        │ │                                   │
└─────────────────┬─────────────────┘ └─────────────────┬─────────────────┘
                  │                                     │
                  └──────────────────┬──────────────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        IPC & CLI Routing Layer                         │
│   scripts/gps-ipc (shell, island, settings, clipboard, mediahub, ...)  │
│   scripts/gps-lock (unified lock wrapper with hyprlock duplicate check)│
│   scripts/gps-idle (managed hypridle lifecycle & status controller)    │
└────────────────────────────────────┬───────────────────────────────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      Helper Daemons & Pipelines                        │
│ • Wallpaper & Theme: awww-daemon, scripts/set_wallpaper.py             │
│ • Audio & Capture: PipeWire, WirePlumber, wpctl, parec, grim, slurp    │
│ • System & Hardware: UPower, power-profiles-daemon, nmcli, BlueZ       │
│ • Screen-time & Activity: awatcher (ActivityWatch REST API :5600)      │
│ • Local AI Inference: Ollama HTTP daemon (:11434), scripts/ai-chat.py  │
│ • Pet Alert Subsystem: scripts/pet-alert, $XDG_RUNTIME_DIR/pet/        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Identified Vulnerabilities & Failure Modes

### Priority 1: High Risk (Session Stability & Data Integrity)

1. **Unsafe Non-Atomic Settings Writes**
   - **Locations:** `settings.qml` (`writeFile()`), `components/AIChat.qml` (`persistModelChoice()`).
   - **Failure Mode:** `settings.qml` uses `printf "%s\n" "$2" > "$1"` and `AIChat.qml` uses Python `open(p, 'w')`. Both truncate existing files in-place without temporary file substitution or `fsync`.
   - **Impact:** An unexpected process kill, power cutoff, or race with a reactive `FileView` results in a zero-byte or malformed `rice-settings.json`, losing user preferences. In `AIChat.qml`, an unhandled JSON parse error wipes the entire settings dictionary.
   - **Remedy:** Implement atomic replacement (`mkstemp` / `.tmp` + `os.replace` / `mv -f`) with parent directory verification.

2. **Unsupervised Process Termination & Missing `--no-duplicate` on Master Shell**
   - **Location:** `scripts/run-gps.fish` lines 36, 112.
   - **Failure Mode:** Master shell is terminated with `pkill -9` without a graceful `SIGTERM` interval. Furthermore, the master shell is spawned without `--no-duplicate` (`quickshell -d -p "$REPO_DIR/shell.qml"`), whereas Island is spawned with `--no-duplicate`.
   - **Impact:** Rapid restarts or concurrent triggers launch stacked `shell.qml` instances competing for layer-shell positions and IPC sockets.
   - **Remedy:** Graceful `SIGTERM` with 0.5s timeout before `SIGKILL`; add `--no-duplicate` flag to master shell launch command; use canonical repo paths instead of hardcoded `my-rice/`.

3. **IPC Target & Function Desynchronization (Silently Failing Commands)**
   - **Locations:** `scripts/gps-ipc`, `island/Island.qml`, `components/NotifCenter.qml`.
   - **Failure Mode:**
     - `scripts/gps-ipc clipboard` executes `call island clipboard "$action"`. `island/Island.qml` only implements `clip()`, with no `clipboard` function. Calling `gps-ipc clipboard` fails.
     - `components/NotifCenter.qml` executes `quickshell ipc -p ~/.local/share/tide-island call island history` and `focusToggle`. When the GPS island is running, `history` and `focusToggle` are missing in `Island.qml`, leaving Notification Center permanently empty without actionable logs.
     - Missing top-level `gps-ipc pet` and `gps-ipc rail` router commands.
   - **Impact:** Super+V clipboard binding fails; notification center fails; pet IPC requires opaque `gps-ipc shell pet` syntax.
   - **Remedy:** Add `clipboard(action)` alias and `clip(action)` handler in `Island.qml`; implement `history(): string` and `focusToggle()` on `Island.qml`; add `pet` and `rail` subcommands in `scripts/gps-ipc`.

### Priority 2: Medium Risk (IPC Reliability & Responsiveness)

4. **Missing IPC Timeouts & Fragile Target Checks**
   - **Location:** `scripts/gps-ipc`.
   - **Failure Mode:** Direct `exec quickshell ipc ...` calls have no execution timeout. If a QuickShell instance is blocked, calling scripts or keybind dispatchers can hang indefinitely.
   - **Impact:** Compositor or script freezes when invoking IPC on a hung shell.
   - **Remedy:** Wrap QuickShell IPC invocations in `timeout 3s`; provide helpful exit codes and actionable errors when an instance is absent.

5. **Hardcoded Directory Names in Startup Scripts**
   - **Location:** `scripts/run-gps.fish` lines 94, 115 (`pgrep -f 'my-rice/...'`).
   - **Failure Mode:** PID checks match literal `my-rice/`. If the repository directory is renamed, symlinked, or cloned to another path, process detection falsely reports startup failure.
   - **Remedy:** Base process detection on `$REPO_DIR` basename or resolved path pattern.

### Priority 3: Low Risk / Defense in Depth (Graceful Service Degradation)

6. **External Tooling Missing Status Reporting**
   - **Location:** `scripts/toolkit.sh`.
   - **Failure Mode:** `write_status` assumes `$STATUS_FILE` parent directory exists.
   - **Remedy:** Ensure `mkdir -p "$(dirname "$STATUS_FILE")"` prior to status writes.

7. **Island Sysfs & Hardware Watchers Fallbacks**
   - **Status:** Already largely resolved during P4. `Brightness` and `UPower` use system services. Verify all UI components display clean offline notices rather than infinite loading spinners when services are missing.

---

## 3. Prioritized Implementation Plan

| Phase | Milestone | Scope | Deliverables |
|---|---|---|---|
| **1** | P5.2 | Session & Process Lifecycle | • Fix `scripts/run-gps.fish` graceful shutdown & `--no-duplicate`<br>• Dynamic path resolution for PIDs<br>• Structured startup logging & instance safety tests |
| **2** | P5.3 | IPC Reliability & Harmonization | • Harmonize `Island.qml` IPC methods (`clip`, `clipboard`, `history`, `focusToggle`)<br>• Add `gps-ipc pet` and `gps-ipc rail` subcommands<br>• Add timeouts (3s) and actionable failure messages in `scripts/gps-ipc`<br>• Automated IPC failure and contract test suite |
| **3** | P5.4 | Settings & Persistence Safety | • Atomic write helper in `settings.qml`<br>• Atomic Python writer with schema preservation in `components/AIChat.qml`<br>• Unit test suite for corrupted JSON recovery and atomic file writes |
| **4** | P5.5 | Graceful Dependency Handling | • Audit all external services (PipeWire, NM, BlueZ, UPower, awww, yt-dlp, Ollama)<br>• Ensure clear offline banners across all popups and dashboard tabs |
| **5** | P5.6 | Integration & Verification | • Live-session verification & soak tests<br>• Full regression suite run across all test harnesses |
