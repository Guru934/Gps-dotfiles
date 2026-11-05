# GPS Toolbox Architectural Analysis & Integration Plan

> **Scope**: Read-only analysis and architectural design for transforming `components/Toolbox.qml` from an in-memory UI prototype into an integrated desktop utility.  
> **Target Environment**: CachyOS (Arch Linux), Hyprland 0.57.0, QuickShell 0.3.2, Fish/Bash, Python 3.14.  
> **Working Branch**: `feature/toolbox-integration`  
> **Date**: November 5, 2026  

---

## 1. Toolbox Structure & UI Inventory

### 1.1 File Locations & Window Management
- **Content Component**: [`components/Toolbox.qml`](file:///home/guru/Projects/my-rice/components/Toolbox.qml) (2,542 lines). A self-contained QML item utilizing `QtQuick`, `QtQuick.Controls` (ScrollBar only), `QtQuick.Layouts`, and `qs.config` (`Theme`).
- **Window Wrapper**: [`components/ToolboxWindow.qml`](file:///home/guru/Projects/my-rice/components/ToolboxWindow.qml) (99 lines). A `FloatingWindow` surface configured with:
  - Default size: 80% screen width/height (clamped to 960×600 minimum, 1400×900 maximum).
  - Lazy loading: Instantiated once at shell startup with `toolboxLoaded: false`. First open triggers `toolboxLoaded = true`, keeping content alive across subsequent toggles to preserve page state without paying startup cost.
  - Hyprland Window Rule: Configured in [`dots/hypr/hyprland.lua`](file:///home/guru/Projects/my-rice/dots/hypr/hyprland.lua#L434-L440):
    ```lua
    hl.window_rule({
        name  = "gps-hubs-float",
        match = { title = "^(Media Hub|GPS Toolbox|Settings Hub)$" },
        float  = true,
        center = true,
    })
    ```
- **Shell Instantiation**: [`shell.qml`](file:///home/guru/Projects/my-rice/shell.qml#L1173):
  ```qml
  ToolboxWindow { id: toolboxWindow; hub: root }
  ```
- **Invocation Triggers**:
  1. **IPC**: Handled in `shell.qml` ([L273-L278](file:///home/guru/Projects/my-rice/shell.qml#L273-L278)) via `IpcHandler { target: "toolbox" }` routing to `root.toggleToolbox()`, `openToolbox()`, and `closeToolbox()`. Called from CLI via `scripts/gps-ipc toolbox [toggle|open|close]`.
  2. **Island Control Hub**: [`island/states/Control.qml`](file:///home/guru/Projects/my-rice/island/states/Control.qml#L1409-L1410) invokes `st.openToolbox()` -> [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L466-L468) executes `Quickshell.execDetached([root.repoRoot + "/scripts/gps-ipc", "toolbox", "toggle"])`.
  3. **Keybind**: Currently **no dedicated keybind** is assigned in `dots/hypr/hyprland.lua` (Media Hub has `Super+M`, Wallpaper has `Super+W`, Dashboard has `Super+D`).
- **Current Wire-Up Defect**:
  In [`components/ToolboxWindow.qml`](file:///home/guru/Projects/my-rice/components/ToolboxWindow.qml#L94-L97):
  ```qml
  Toolbox {
      showCloseButton: true
      onCloseRequested: root.close()
  }
  ```
  **None** of the public status properties (`hostName`, `compositorName`, `compositorState`, `devices`, `activityEvents`, `integrationAvailable`) or action signals (`actionRunRequested`, `automationSaved`, `presetActivateRequested`, etc.) are wired to any backend or shell service. Clicking any action calls `sysRequest()`, which immediately warns: `"Integration unavailable: ... can't run - no backend is connected to this component."`

---

### 1.2 Page-by-Page Element & Signal Inventory

#### Global Header & Status Strip ([L1226-L1257](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1226-L1257), [L649-L657](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L649-L657))
| UI Element | Line(s) | Current Status | Target / Signal | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Global Search (`Ctrl+K`) | 1232-1241 | In-memory query | `root.pickResult()` | Searches in-memory arrays only. |
| Status: `HOST` | 651, 1395 | Unconnected | Default: `"Not connected"` | Needs hostname / OS detection. |
| Status: `COMPOSITOR` | 652, 1387 | Stub | Default: `"unknown"` | Needs `Hyprland` check. |
| Status: `DEVICE BRIDGE`| 653, 1395 | Stub | Default: `"Not connected"` | Needs KDE Connect / adb polling. |
| Status: `BATTERY` | 654 | Stub | Hidden unless device battery >= 0 | Needs device battery query. |
| Status: `INTEGRATION` | 655, 1243 | Hardcoded | `integrationAvailable: false` | Amber warning pill displayed. |
| Phone Chip | 1244-1246 | Stub | Hidden (no devices connected) | Visible when phone connects. |
| Notifications Drawer | 1249-1253 | In-memory model | `root.notifications` | Local UI event log only. |
| Settings Dialog Button | 1254 | Functional UI | `settingsDlg.open = true` | Local in-memory settings. |

---

#### Page 0: Home (`homePage`, [L1370-L1574](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1370-L1574))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Quick Action: `lock_screen` | 185, 1416 | Reviewed stub | `actionRunRequested("lock_screen", {})` | Calls `scripts/gps-lock`. |
| Quick Action: `open_terminal` | 186, 1416 | Reviewed stub | `actionRunRequested("open_terminal", {})` | Launches `kitty`. |
| Quick Action: `open_dev_ws` | 187, 1416 | Needs-review stub | `actionRunRequested("open_dev_ws", {})` | Hyprland dispatch dev layout. |
| Quick Action: `focus_start` | 188, 1416 | Reviewed stub | `actionRunRequested("focus_start", {minutes: 25})` | Routes to Island focus timer. |
| Quick Action: `scrcpy_launch` | 189, 1416 | Reviewed stub | `actionRunRequested("scrcpy_launch", {profile: "default"})` | Runs `scrcpy` with safe flags. |
| Quick Action: `Open Saved Space` | 190, 1416 | Functional Nav | `root.go(1)` | Internal page navigation. |
| Quick Action: `audio_controls` | 191, 1416 | Reviewed stub | `actionRunRequested("audio_controls", {})` | Opens Media Hub or `pavucontrol`. |
| Quick Action: `New Workflow` | 192, 1416 | Functional Nav | `root.newRoutine()` -> `root.go(4)` | Switches to Routine Builder. |
| Scheduled Automations Preview | 1452-1477 | Sample data | Reads `sampleAutomations()` [L1060] | Top 4 items with Test/Pause/Edit. |
| Saved Space Summary | 1478-1507 | Sample data | Reads `sampleSavedItems()` [L1047] | Shows type pills & 3 pinned/recent. |
| Device Bridge Card | 1511-1536 | Sample/Empty | Empty state rendered (no devices) | Shows device status & battery. |
| Workspace Presets Grid | 1537-1556 | Sample data | `presetActivateRequested(p.id)` | Renders layout preview blocks. |
| Recent Activity List | 1557-1570 | Empty / Sample | Empty state rendered | Needs journal events array. |

---

#### Page 1: Saved Space (`savedPage`, [L1576-L1715](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1576-L1715))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Quick Capture Button | 1587 | In-memory modal | Opens `capDlg` ([L2276](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2276)) | Persist item to JSON backend. |
| Filter & Search Bar | 1589-1596 | In-memory filter | Updates `root.savedQuery`, `savedSort` | Local QML filtering over items. |
| Type Pills (All, Bookmarks, Notes, Snippets, Pinned, Favorites) | 1597-1603 | In-memory filter | Updates `root.savedType` | Counts and filters active model. |
| Collections Sidebar / Row | 1607-1652 | In-memory array | `collDlg` ([L2321](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2321)), delete/rename | Persist collection metadata. |
| Item: Open Bookmark | 1689 | Signal | `openUrlRequested(it.url)` | Opens default browser via `xdg-open`. |
| Item: Copy URL / Content | 1690-1691 | In-memory text | `root.copyText(content)` | Calls internal hidden `TextEdit`. |
| Item: Edit / Delete | 1693-1694 | In-memory edit | `savedItemSaved()`, `savedItemDeleted()` | Persist mutation to JSON storage. |
| Snippet Display | 1678-1684 | Read-only render | Enforces Zero-Execution Principle | **Never executes** directly from page. |

---

#### Page 2: Automations (`autoPage`, [L1717-L1823](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1717-L1823))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Templates Drawer | 1734-1743 | Sample data | Reads `automationTemplates()` [L1070] | Prefills wizard from template. |
| Create Automation Button | 1724 | In-memory modal | Opens `autoDlg` ([L2331](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2331)) | 6-step creation wizard. |
| Automation Toggle | 1765 | Signal | `automationStateChangeRequested(id, enabled)` | Enable/disable systemd user timer. |
| Test Button | 1796 | Signal | `automationTestRequested(id)` | Dry-run / immediate execution. |
| Cancel Schedule (Power) | 1797-1798 | Signal | `scheduleCancelRequested(id)` | Safely removes scheduled power timers. |
| Duplicate / Delete | 1801, 1803 | In-memory | `automationSaved()`, `automationDeleted()`| Mutates persistent automations store. |
| Execution History Subtab | 1809-1820 | Empty array | Reads `activityEvents` | Filtered list of automation runs. |

---

#### Page 3: Action Library (`actionPage`, [L1825-L1914](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1825-L1914))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Category Filters | 1834-1838 | In-memory filter | 10 categories: Desktop, Power, Audio... | Local QML filtering. |
| Action Card "Run" Button | 1868 | Signal | `actionRunRequested(a.id, params)` | Validates whitelist; executes action. |
| Action Card "Inspect" | 1867 | Local sidebar | Opens inspector panel ([L1881](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1881)) | Displays reference, args, and cwd. |
| Custom Action Editor | 1831, 2461 | Modal | Opens `actDlg` ([L2461](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2461)) | Enforces "Needs Review" / "Restricted". |
| Enable/Disable Toggle | 1872 | In-memory patch | Modifies `actionsData` | Saves custom enabled overrides. |

---

#### Page 4: Routine Builder (`routinePage`, [L1916-L2043](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L1916-L2043))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Workflow Selector | 1932-1957 | Sample data | Reads `sampleRoutines()` [L1116] | Loads workflow definition into view. |
| Step List & Reordering | 1991-2030 | In-memory edit | `moveStep()`, `addStep()`, `delStep()` | Reorders action sequence. |
| Step Condition Editor | 2019-2025 | In-memory edit | `always`, `integration`, `prev_ok` | Step gatekeeper logic. |
| Preview Routine | 2036 | Modal | Opens `pvDlg` ([L2264](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2264)) | Read-only simulation of steps. |
| Save Workflow Button | 2037 | Signal | `workflowSaved(r)` | Persists routine to JSON store. |

---

#### Page 5: Device Bridge (`devicePage`, [L2045-L2135](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2045-L2135))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Device Cards | 2057-2083 | Empty (or Preview) | Reads `devices` ([L61](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L61)) | Real-time KDE Connect D-Bus polling. |
| Device Mirror (`scrcpy`) | 2105 | Signal | `deviceActionRequested(devId, "mirror", {})`| Executes `scrcpy` with `--otg` or wireless. |
| Send File | 2105 | Signal | `deviceActionRequested(devId, "file", {})` | Opens file picker -> `kdeconnect-cli --share`. |
| Share URL / Text | 2106 | Signal | `deviceActionRequested(devId, "share", {})` | `kdeconnect-cli --share-text`. |
| Find Phone | 2106 | Signal | `deviceActionRequested(devId, "find", {})` | `kdeconnect-cli --ring`. |
| Shared Link Inbox | 2111-2133 | Empty / Preview | Reads `sharedLinks` ([L62](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L62)) | KDE Connect clipboard/share listener. |

---

#### Page 6: Workspace Presets (`presetPage`, [L2137-L2177](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2137-L2177))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Preset Cards | 2148-2174 | Sample data | Reads `samplePresets()` [L1129] | 6 presets: Coding, Study, Presentation... |
| Layout Preview Blocks | 2160 | QML Graphic | Pure geometry preview | Draws normalized layout rectangles. |
| Activate Button | 2168 | Signal | `presetActivateRequested(p.id)` | Emits dispatch commands to Hyprland. |
| Edit Preset | 2170 | Modal | Opens `presetDlg` ([L2491](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2491)) | Updates apps, DND flag, focus timer. |

---

#### Page 7: Activity & History (`historyPage`, [L2179-L2245](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L2179-L2245))
| UI Element | Line(s) | Current State | Signal / Invocation | Backend Requirement |
| :--- | :--- | :--- | :--- | :--- |
| Filter Strip | 2188-2204 | In-memory filter | Status, Date (24h/7d), Category, Auto | Dynamic filtering over logged events. |
| Journal Entries | 2205-2241 | Empty / Sample | Reads `activityEvents` ([L63](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L63)) | Reads append-only journal file. |
| Expand Details | 2226-2236 | QML visual | Shows error trace, duration, category | Audit visibility for user peace-of-mind. |

---

## 2. Inventory of Existing Rice Assets

| Subsystem / Feature | Exists? | File Path | Invocation / Access Method | Can Toolbox Reuse As-Is? |
| :--- | :---: | :--- | :--- | :--- |
| **GPS IPC Router** | Yes | [`scripts/gps-ipc`](file:///home/guru/Projects/my-rice/scripts/gps-ipc) | Bash CLI: `gps-ipc <target> <action> [args]` | **Yes**. Already has `toolbox` target; can add subcommands or use `qs ipc`. |
| **Master Shell IPC** | Yes | [`shell.qml`](file:///home/guru/Projects/my-rice/shell.qml#L166-L278) | QuickShell IPC: `quickshell ipc -p shell.qml call <target> <method>` | **Yes**. Houses `dashboard`, `notifcenter`, `wallpaper`, `aichat`, `mediahub`, `clipboard`, `toolbox`. |
| **Island IPC** | Yes | [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L1138-L1368) | QuickShell IPC to `IslandProduction.qml` target `island` | **Yes**. Houses `dnd`, `focusStart/Stop/Toggle`, `osd`, `nightlight`, `alert`. |
| **Design Tokens / Palette** | Yes | [`config/Theme.qml`](file:///home/guru/Projects/my-rice/config/Theme.qml) | QML Singleton `import qs.config; Theme.*` | **Yes**. Already imported via `ThemeData` ([L195](file:///home/guru/Projects/my-rice/components/Toolbox.qml#L195)). |
| **Wallpaper Engine** | Yes | [`scripts/set_wallpaper.py`](file:///home/guru/Projects/my-rice/scripts/set_wallpaper.py), [`scripts/gps_wallpaper.py`](file:///home/guru/Projects/my-rice/scripts/gps_wallpaper.py) | CLI: `gps-wallpaper next`, `gps-ipc shell wallpaper toggle` | **Yes**. Can be called as a reviewed action. |
| **Brightness Control** | Yes | [`config/Brightness.qml`](file:///home/guru/Projects/my-rice/config/Brightness.qml), `/usr/bin/brightnessctl` | QML Singleton `Brightness` or CLI `brightnessctl set <N>%` | **Yes**. Available via both QML and CLI. |
| **Audio Sinks / Volume** | Yes | [`scripts/audio-sinks.py`](file:///home/guru/Projects/my-rice/scripts/audio-sinks.py), `/usr/bin/wpctl` | CLI: `wpctl set-volume @DEFAULT_AUDIO_SINK@ <N>%` | **Yes**. Can be triggered directly or via Pipewire QML service. |
| **Sound FX Engine** | Yes | [`scripts/gps-sound`](file:///home/guru/Projects/my-rice/scripts/gps-sound), [`scripts/sound_engine.py`](file:///home/guru/Projects/my-rice/scripts/sound_engine.py) | CLI: `gps-sound <event>` (e.g. `action`, `notice`, `warn`) | **Yes**. Perfect for Toolbox action feedback and errors. |
| **Notification Server** | Yes | [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml), [`components/NotificationStore.js`](file:///home/guru/Projects/my-rice/components/NotificationStore.js) | CLI: `notify-send` or `gps-ipc notify <action>` | **Yes**. Island owns D-Bus notifications; Toolbox can query history and status. |
| **DND (Do Not Disturb)** | Yes | [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L1140-L1174) | CLI: `gps-ipc notify dnd [on\|off\|toggle]` | **Yes**. Reusable for Focus and Presets. |
| **Focus / Pomodoro** | Yes | [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L1284-L1323) | IPC: `gps-ipc island focusStart <work> <break> <count> <title>` | **Yes**. Directly callable from Toolbox Focus button and presets. |
| **Clipboard Engine** | Yes | [`scripts/gps-clipboard`](file:///home/guru/Projects/my-rice/scripts/gps-clipboard), `cliphist`, `wl-paste` | CLI: `gps-clipboard list/copy/clear`, state in `~/.local/state/gps/clipboard_pinned.json` | **Yes**. Toolbox can reuse clipboard store and copy operations. |
| **Media Hub Downloader** | Yes | [`scripts/media-hub-downloads.py`](file:///home/guru/Projects/my-rice/scripts/media-hub-downloads.py), [`components/MediaHubDownloads.qml`](file:///home/guru/Projects/my-rice/components/MediaHubDownloads.qml) | Python bridge over `yt-dlp` / `ffmpeg` via JSON IPC | **Architectural Model**. Demonstrates the safe QML Process + Python helper pattern. |
| **Screenshot (gps-shot)** | Yes | [`scripts/gps-shot`](file:///home/guru/Projects/my-rice/scripts/gps-shot) | CLI: `gps-shot [region\|window\|monitor]` | **Yes**. Reviewed desktop action ready to wire. |
| **Screen Record (gps-record)**| Yes | [`scripts/gps-record`](file:///home/guru/Projects/my-rice/scripts/gps-record) | CLI: `gps-record [start\|stop\|toggle\|status]` | **Yes**. Reviewed desktop action ready to wire. |
| **Color Picker (gps-picker)** | Yes | [`scripts/gps-picker`](file:///home/guru/Projects/my-rice/scripts/gps-picker) | CLI: `gps-picker` (calls `hyprpicker`) | **Yes**. Reviewed desktop action ready to wire. |
| **Session Diagnostics** | Yes | [`scripts/gps-doctor`](file:///home/guru/Projects/my-rice/scripts/gps-doctor) | CLI: `gps-doctor [--json]` | **Yes**. Can provide health metrics for the status strip. |
| **Session Lock Wrapper** | Yes | [`scripts/gps-lock`](file:///home/guru/Projects/my-rice/scripts/gps-lock) | CLI: `gps-lock` (wraps `hyprlock`) | **Yes**. Exactly what `lock_screen` should call. |
| **Hardware Device Watcher**| Yes | [`scripts/gps-device-watcher`](file:///home/guru/Projects/my-rice/scripts/gps-device-watcher) | Python daemon listening on D-Bus (UDisks2, BlueZ, NM) | **Yes**. Can feed connect/disconnect events to Device Bridge & Automations. |
| **Screen Time (awatcher)** | Yes | [`scripts/screen-time.py`](file:///home/guru/Projects/my-rice/scripts/screen-time.py), `~/.config/awatcher` | REST API: `http://127.0.0.1:5600/api/0` | **Yes**. Can enrich Activity & History or Dashboard with active app metrics. |
| **Pet Alert Feed** | Yes | [`scripts/pet-alert`](file:///home/guru/Projects/my-rice/scripts/pet-alert), [`pet/Pet.qml`](file:///home/guru/Projects/my-rice/pet/Pet.qml) | Feed: `/run/user/1000/pet/alerts.jsonl` | **Yes**. Can surface agent confirmations in Toolbox or Pet. |
| **AI Assistant (cat_talker)**| Yes | `/home/guru/ai-assistant`, [`scripts/ai-chat.py`](file:///home/guru/Projects/my-rice/scripts/ai-chat.py) | Python CLI: `/home/guru/ai-assistant/bin/assistant-control` or Ollama bridge | **Yes**. Available locally, callable via CLI script wrapper. |
| **Hermetic Test Suite** | Yes | [`tests/run_all.sh`](file:///home/guru/Projects/my-rice/tests/run_all.sh) | Runner: `./tests/run_all.sh` (89 tests) | **Yes**. Must add contract test for `ToolboxWindow` and backend. |

---

## 3. Real System Facts (Verified by Execution)

| Fact / Tool | System Fact / Status | Verification Command & Output Summary |
| :--- | :--- | :--- |
| **Hyprland Version** | **0.57.0** (commit `0aa6745f705f... clean`) | `hyprctl version` -> `Hyprland 0.57.0 built from branch v0.57.0` |
| **QuickShell Version** | **0.3.2** (rev `9b0f339b...`, AUR `quickshell-git`) | `quickshell --version` -> `Quickshell 0.3.2` |
| **Quickshell Modules** | Verified present: `Quickshell.Io`, `Quickshell.Hyprland`, `Quickshell.Bluetooth`, `Quickshell.Networking`, `Quickshell.Services.Mpris`, `Quickshell.Services.Notifications`, `Quickshell.Services.Pipewire`, `Quickshell.Services.SystemTray`, `Quickshell.Services.UPower`, `Quickshell.Wayland` | Verified across repo imports (`grep -rh "^import Quickshell" .`) |
| **Audio Stack** | `/usr/bin/wpctl` & `/usr/bin/pactl` available | `which wpctl pactl` -> Both present. Pipewire is primary sound server. |
| **Media Player Control**| `/usr/bin/playerctl` present; `mpv` present | `which playerctl mpv` -> Present. No external players active. |
| **Brightness Control** | `/usr/bin/brightnessctl` present | `which brightnessctl` -> `/usr/bin/brightnessctl` |
| **Power Management** | `/usr/bin/loginctl` & `/usr/bin/systemctl` present | `loginctl lock-session`, `systemctl suspend` available. |
| **Network Control** | `/usr/bin/nmcli` present | `which nmcli` -> `/usr/bin/nmcli` |
| **Bluetooth Control** | `/usr/bin/bluetoothctl` present | `which bluetoothctl` -> `/usr/bin/bluetoothctl` |
| **KDE Connect Engine** | `/usr/bin/kdeconnect-cli` & `/usr/bin/kdeconnectd` present; active on D-Bus user bus (PID 3030) | `busctl --user list \| grep kdeconnect` -> `org.kde.kdeconnect` running. |
| **Paired Phone Status**| **1 paired device**: `I2202` (id `2b1d17e9eb344e6686fe9fd613b3e669`) | `kdeconnect-cli -l` -> `1 device found (paired)`. `kdeconnect-cli --list-available` -> `0 devices found` (currently disconnected/asleep). |
| **Screen Mirroring** | `/usr/bin/scrcpy` present | `which scrcpy` -> `/usr/bin/scrcpy` |
| **Android ADB** | `/home/guru/Android/Sdk/platform-tools/adb` present | `adb devices` -> Daemon running; currently 0 devices attached. |
| **Scheduler Engine** | **`systemd --user` timers active**; `cron`/`crontab` **NOT** installed | `systemctl --user list-timers` lists 4 active timers; `which crontab` -> Not found. Systemd user timers are authoritative. |
| **Ollama Local LLM** | `/usr/bin/ollama` present; user service exists at `~/.config/systemd/user/ollama.service` (currently dead/inactive) | `systemctl --user status ollama` -> Inactive. |
| **State Storage Paths**| Config: `~/.config/gps/` (exists) & `~/.config/quickshell/`<br>Dynamic State: `~/.local/state/gps/` (exists: `notifications.json`, `dnd.json`, etc.)<br>Runtime: `/run/user/1000/gps/` (exists) | `ls -la ~/.local/state/gps` confirms JSON storage conventions across rice. |

---

## 4. Integration Map Table

| Feature / Button | Real Backend Target | Existing Code to Reuse | What Must Be Created New | Risk Level | Needs User Confirm? |
| :--- | :--- | :--- | :--- | :---: | :---: |
| **Status: HOST** | `uname -n` / `/etc/hostname`, `uname -s` | None | Read via Python backend or `Quickshell.env("HOSTNAME")` | Low | No |
| **Status: COMPOSITOR**| `Hyprland.focusedMonitor !== null` | `import Quickshell.Hyprland` | Wire property to `Hyprland` singleton | Low | No |
| **Status: DEVICE BRIDGE**| `kdeconnect-cli -l --json` or D-Bus query | [`scripts/gps-device-watcher`](file:///home/guru/Projects/my-rice/scripts/gps-device-watcher) | Query `org.kde.kdeconnect` on user bus | Low | No |
| **Status: INTEGRATION**| Checks if `ToolboxBackend` is live | `ToolboxWindow.qml` | Set `integrationAvailable: true` when backend loads | Low | No |
| **Quick Action: Lock Screen**| [`scripts/gps-lock`](file:///home/guru/Projects/my-rice/scripts/gps-lock) | [`scripts/gps-lock`](file:///home/guru/Projects/my-rice/scripts/gps-lock) | Whitelist entry `"lock_screen"` | Low | No |
| **Quick Action: Open Terminal**| `hyprctl dispatch exec kitty` | Default terminal config | Whitelist entry `"open_terminal"` | Low | No |
| **Quick Action: Dev Workspace**| `hyprctl dispatch workspace <N>` + app launch | [`dots/hypr/hyprland.lua`](file:///home/guru/Projects/my-rice/dots/hypr/hyprland.lua) | Workspace layout dispatcher script | Med | No |
| **Quick Action: Start Focus**| `gps-ipc island focusStart 1500 300 4 "Focus"`| [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L1284) | Whitelist entry `"focus_start"` routing to IPC | Low | No |
| **Quick Action: Launch scrcpy**| `scrcpy --stay-awake --turn-screen-off` | `/usr/bin/scrcpy` | Whitelist entry `"scrcpy_launch"` with device check | Med | No |
| **Quick Action: Audio Controls**| `gps-ipc mediahub open` or `pavucontrol` | [`scripts/gps-ipc`](file:///home/guru/Projects/my-rice/scripts/gps-ipc) | Route to Media Hub window or audio panel | Low | No |
| **Saved Space: Storage** | Atomic JSON: `~/.local/state/gps/toolbox/saved.json`| None (pattern from `media-hub-downloads.json`)| JSON read/write persistence module | Low | No |
| **Saved Space: Open Bookmark**| `xdg-open "<url>"` | `/usr/bin/xdg-open` | Safe URL validator (http/https only) | Low | No |
| **Saved Space: Copy Item** | `wl-copy` or QML `clipboard` | [`components/ClipboardService.js`](file:///home/guru/Projects/my-rice/components/ClipboardService.js)| QML clipboard helper | Low | No |
| **Automations: Execution** | `systemd-run --user --on-calendar=...` or systemd user timers | `systemctl --user` | Systemd timer generator / manager script | Med | Only Power |
| **Automations: State (Pause/On)**| `systemctl --user [enable\|disable\|stop] <unit>`| Systemd user service manager | Timer state toggle handler | Low | No |
| **Action: Suspend / Sleep** | `systemctl suspend` | `/usr/bin/systemctl` | Confirmation dialog + 30s grace window | High | **YES (Always)** |
| **Action: Power Off / Reboot** | `systemctl poweroff` / `reboot` | `/usr/bin/systemctl` | Confirmation dialog + 60s grace window | High | **YES (Always)** |
| **Action: Set Volume** | `wpctl set-volume @DEFAULT_AUDIO_SINK@ <N>%`| `/usr/bin/wpctl` | Whitelist entry `"set_volume"` with bounds 0-100 | Low | No |
| **Action: Set Brightness** | `brightnessctl set <N>%` | `/usr/bin/brightnessctl` | Whitelist entry `"set_brightness"` with bounds 1-100| Low | No |
| **Action: Enable DND** | `gps-ipc notify dnd on` | [`island/Island.qml`](file:///home/guru/Projects/my-rice/island/Island.qml#L1140) | Whitelist entry routing to Island IPC | Low | No |
| **Action: Send Notification** | `notify-send "<title>" "<msg>"` | `/usr/bin/notify-send` | Whitelist entry with sanitization | Low | No |
| **Routine Builder: Run** | Sequencer executing whitelisted actions | None | Step runner in helper script with conditional gates | Med | If steps confirm |
| **Device Bridge: Mirror** | `scrcpy --serial <id>` | `/usr/bin/scrcpy` | Subprocess launcher with active device detection | Low | No |
| **Device Bridge: Send File** | `kdeconnect-cli --device <id> --share <path>` | `/usr/bin/kdeconnect-cli` | File chooser dialog + KDE Connect CLI | Low | Yes (choose file)|
| **Device Bridge: Find Phone** | `kdeconnect-cli --device <id> --ring` | `/usr/bin/kdeconnect-cli` | Subprocess calling ring command | Low | No |
| **Device Bridge: Share URL** | `kdeconnect-cli --device <id> --share-text <url>`| `/usr/bin/kdeconnect-cli` | Subprocess sharing URL to device | Low | No |
| **Workspace Presets: Apply** | Hyprland dispatch rules / script | [`dots/hypr/hyprland.lua`](file:///home/guru/Projects/my-rice/dots/hypr/hyprland.lua) | Script dispatching workspaces, windows, & DND | Med | No |
| **Activity Journal Logging**| Append-only JSONL: `~/.local/state/gps/toolbox/history.jsonl`| [`scripts/pet-alert`](file:///home/guru/Projects/my-rice/scripts/pet-alert) logging pattern | Rotating JSONL writer with timestamp & outcome | Low | No |

---

## 5. Proposed Architecture & Safety Model

### 5.1 Architecture Overview: The Two-Tier Backend
To keep `Toolbox.qml` completely portable, clean, and free of subprocess vulnerabilities, we adopt the proven **Two-Tier Architecture** established by `MediaHubWindow` and `MediaHubDownloads`:

```
┌────────────────────────────────────────────────────────┐
│  Toolbox.qml (Pure Presentation & Interaction Layer)   │
│  - Receives models: items, automations, devices, etc.  │
│  - Emits request signals: actionRunRequested, etc.     │
└──────────────────────────┬─────────────────────────────┘
                           │ Properties & Signals
┌──────────────────────────▼─────────────────────────────┐
│  ToolboxBackend.qml (State & Controller Surface)       │
│  - Lives inside components/ToolboxWindow.qml           │
│  - Owns Quickshell.Io.Process and JSON file monitors   │
│  - Mediates between Toolbox.qml and host system        │
└──────────────────────────┬─────────────────────────────┘
                           │ JSON IPC / CLI Arguments
┌──────────────────────────▼─────────────────────────────┐
│  scripts/gps-toolbox (Python Backend Helper)           │
│  - Action Whitelist enforcement & argument validation  │
│  - KDE Connect D-Bus listener / cache                  │
│  - systemd user timer manager for Automations          │
│  - Atomic JSON persistence in ~/.local/state/gps/      │
└────────────────────────────────────────────────────────┘
```

1. **Presentation Component (`components/Toolbox.qml`)**:
   - Stays 100% UI and interaction logic.
   - Accepts public properties (`hostName`, `compositorState`, `devices`, `savedItems`, `automations`, `actionsData`, `presets`, `activityEvents`).
   - Emits signals on user intent.
2. **QML Controller Surface (`components/ToolboxBackend.qml`)**:
   - Instantiated inside `components/ToolboxWindow.qml`.
   - Imports `Quickshell.Io` and `Quickshell.Hyprland`.
   - Reads system facts live: host name from environment, compositor state from `Hyprland`, theme from `Theme`.
   - Connects to signals from `Toolbox.qml` and dispatches to `scripts/gps-toolbox`.
3. **Helper Daemon / CLI (`scripts/gps-toolbox`)**:
   - Python 3 helper following the strict conventions of `scripts/media-hub-downloads.py`.
   - Validates all input against a strict schema.
   - Manages state files in `~/.local/state/gps/toolbox/`.

---

### 5.2 Whitelist Security & Safe Execution Model

1. **Explicit Named Whitelist (`~/.config/gps/toolbox-actions.json`)**:
   - Arbitrary shell strings from the UI are strictly prohibited.
   - Every executable action must match a registered action ID mapped to fixed executable arrays:
     ```json
     {
       "actions": {
         "lock_screen": {
           "executable": ["${GPS_ROOT}/scripts/gps-lock"],
           "confirm": false,
           "destructive": false
         },
         "open_terminal": {
           "executable": ["hyprctl", "dispatch", "exec", "kitty"],
           "confirm": false,
           "destructive": false
         },
         "suspend": {
           "executable": ["systemctl", "suspend"],
           "confirm": true,
           "destructive": true,
           "grace": 30
         },
         "set_volume": {
           "executable": ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@"],
           "param_schema": {"level": "^([0-9]{1,2}|100)%?$"},
           "confirm": false
         }
       }
     }
     ```
2. **Zero Shell Interpolation**:
   - All executions use direct argument vector execution (`execv` via Python `subprocess.run(args, shell=False)` or `Quickshell.Io.Process { command: [...] }`).
   - Shell pipelines (`|`, `;`, `&&`) are never used inside dynamic action handlers.
3. **Confirmation and Grace Window for Destructive Actions**:
   - Power actions (`suspend`, `shutdown`, `reboot`) and actions marked with `confirm: true` always trigger `confirmDlg` with a mandatory countdown timer before dispatch.
   - Cancellation during the grace window instantly halts execution.
4. **Dry-Run / Test Mode**:
   - The "Test" button on automations and routines executes the actions with a `--dry-run` flag if supported, or checks return codes without executing side effects where simulated, logging the outcome to the Activity Journal.

---

### 5.3 Data Storage & Schema Design
Consistent with existing GPS state in `~/.local/state/gps/` (e.g. `notifications.json`, `dnd.json`, `media-hub-downloads.json`):

Directory: `~/.local/state/gps/toolbox/`
1. **`saved_space.json`**:
   ```json
   {
     "version": 1,
     "collections": ["Development", "Linux", "AI Tools", "Personal"],
     "items": [
       {
         "id": "s_1730798200_1",
         "type": "bookmark",
         "title": "Hyprland Wiki",
         "url": "https://wiki.hyprland.org",
         "content": "",
         "description": "Configuration reference",
         "collection": "Linux",
         "tags": ["linux", "wayland"],
         "pinned": true,
         "favorite": true,
         "created": 1730798200
       }
     ]
   }
   ```
2. **`automations.json`**: Definitions of user automations, triggers, enabled state, and associated systemd timer unit names.
3. **`presets.json`**: Workspace preset layouts, associated application classes, and focus modes.
4. **`history.jsonl`**: Append-only execution journal. Lines rotated at 5,000 entries or according to user retention setting (default 30 days).

---

## 6. Phased Implementation Plan

Each phase represents 30–90 minutes of bounded, verifiable work.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Phase 1   │────>│   Phase 2   │────>│   Phase 3   │────>│   Phase 4   │────>│   Phase 5   │
│ Wire Surface│     │ Saved Space │     │Quick Actions│     │Device Bridge│     │ Automations │
│ & Live Facts│     │ Persistence │     │ & Whitelist │     │& KDE Connect│     │ & Systemd   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

### Phase 1: Controller Wiring, Live System Facts & Status Strip
- **Objective**: Replace hardcoded defaults with live host, compositor, and theme facts. Connect `Toolbox.qml` signals to a new `ToolboxBackend.qml` controller.
- **Scope**:
  - Create `components/ToolboxBackend.qml`.
  - Wire `ToolboxWindow.qml` to bind `hostName`, `compositorName`, `compositorState` (from `Quickshell.Hyprland`), and set `integrationAvailable: true`.
  - Add hermetic contract tests for `ToolboxWindow` property bindings.
- **Verification Commands**:
  - `quickshell -p shell.qml` (via `gps-ipc toolbox toggle`)
  - Status strip displays real hostname, `"Hyprland"`, and `"Available"`.
  - `./tests/run_all.sh` passes.

### Phase 2: Saved Space Real Persistence (Bookmarks, Notes, Snippets)
- **Objective**: Wire Saved Space CRUD operations to atomic JSON storage in `~/.local/state/gps/toolbox/saved_space.json`.
- **Scope**:
  - Implement read/write in `ToolboxBackend.qml` (or Python helper).
  - Connect `savedItemSaved`, `savedItemDeleted`, and `openUrlRequested` (invoking `xdg-open`).
  - Wire copy operations to system clipboard.
  - Initial load populates with default clean bookmarks if file does not exist, preserving user additions across restarts.
- **Verification Commands**:
  - Click "+ Quick Capture" -> Add bookmark `https://github.com` -> Restart shell -> Item persists.
  - Click "Open" -> URL opens in Brave browser.
  - `./tests/run_all.sh` passes.

### Phase 3: Action Whitelist Engine & Quick Actions
- **Objective**: Wire Home Quick Actions and Action Library to the reviewed whitelist.
- **Scope**:
  - Implement `scripts/gps-toolbox action run <action_id> [params]`.
  - Define whitelist in `config/toolbox-actions.json` for: `lock_screen`, `open_terminal`, `focus_start`, `set_volume`, `set_brightness`, `dnd_enable`, `notify`.
  - Wire confirmation dialog for power actions (`suspend`, `shutdown`).
  - Connect `actionRunRequested` to log results into `history.jsonl` and feed `activityEvents`.
- **Verification Commands**:
  - Click "Lock Screen" -> Hyprlock engages.
  - Click "Open Terminal" -> Kitty opens.
  - Click "Start Focus Session" -> Island morphs into focus timer mode.
  - Activity & History journal records entries with timestamps.

### Phase 4: Device Bridge Integration (KDE Connect & scrcpy)
- **Objective**: Wire Device Bridge to live KDE Connect D-Bus status and `scrcpy`.
- **Scope**:
  - Backend queries `kdeconnect-cli -l --json` or `org.kde.kdeconnect` over D-Bus to populate `devices` array.
  - Honest empty state when no device is paired or reachable.
  - Connect "Launch Device Mirror" to `scrcpy` with `--turn-screen-off` / `--stay-awake`.
  - Connect "Find phone" to `kdeconnect-cli --ring`.
  - Connect "Send file" to file picker dialog.
- **Verification Commands**:
  - With phone disconnected: Device card honestly shows `I2202` as "Disconnected".
  - Actions disable gracefully when device is unreachable.
  - `./tests/run_all.sh` passes.

### Phase 5: Automations & Workspace Presets via Systemd User Timers
- **Objective**: Wire Automations to real `systemd --user` timers, and Presets to Hyprland layout dispatchers.
- **Scope**:
  - Implement schedule compiler in `scripts/gps-toolbox schedule <add|remove|list>`.
  - Generates transient or persistent `systemd` user units: `gps-auto-<id>.timer` and `gps-auto-<id>.service`.
  - Connect `automationStateChangeRequested` to `systemctl --user [enable|disable]`.
  - Implement Workspace Presets dispatcher using `hyprctl dispatch` for Coding, Study, and Presentation presets.
- **Verification Commands**:
  - Create 1-minute test automation -> `systemctl --user list-timers` confirms unit is scheduled.
  - Timer triggers -> Desktop notification fires -> Activity & History records "completed".
  - `./tests/run_all.sh` passes.

---

## 7. Risks & Unknowns

1. **Subprocess Concurrency & Shell Freezes**:
   - *Risk*: Running synchronous command calls inside QML main thread blocks the compositor UI.
   - *Mitigation*: Strictly utilize asynchronous `Quickshell.Io.Process` or `Quickshell.execDetached` with timeout guards, matching the pattern in `MediaHubDownloads.qml`.
2. **KDE Connect D-Bus Response Latency**:
   - *Risk*: `kdeconnect-cli` queries can hang or take >1.5s when devices are waking from sleep.
   - *Mitigation*: Run device polling on a background tick (e.g. every 15s) or listen to D-Bus signal changes, caching state in `ToolboxBackend`.
3. **Power Action Accidental Triggers**:
   - *Risk*: Automation with `suspend` running while user is actively presenting or compiling.
   - *Mitigation*: Enforce AC power / idle conditions and a mandatory 30s audible/visible cancel toast before sleep.
4. **Hyprland Workspace Application Discovery**:
   - *Risk*: Workspace presets attempting to launch hardcoded application paths that may differ across environments.
   - *Mitigation*: Use standard `.desktop` entry resolution or desktop environment defaults (`xdg-open`, default terminal, `$EDITOR`).

---

## 8. Confirmed Architectural Decisions

The user has reviewed and confirmed the following technical decisions:
1. **Toolbox Shortcut Keybind**: Assigned to `Super + T` in [`dots/hypr/hyprland.lua`](file:///home/guru/Projects/my-rice/dots/hypr/hyprland.lua) executing `scripts/gps-ipc toolbox toggle`.
2. **Automations Engine**: Approved use of `systemd --user` timers as the authoritative, non-root scheduler for background automations.
3. **Default Presets**:
   - Editor: VS Code (`code` / `com.visualstudio.code`)
   - Terminal: Kitty (`kitty`)
   - Browser: Brave Browser (`brave` / `brave-browser`)
4. **Device Bridge scrcpy Options**: Audio forwarding enabled by default when launching `scrcpy` (no `--no-audio` flag).

