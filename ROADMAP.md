# GPS Desktop Roadmap

## Milestones

- [x] **P1 — Foundation & Core Shell**
  - LeftRail dock with split/unified layouts
  - Tide Island top status pill and state router
  - HUD Dashboard with Home, Media, System, Tools panes
  - Dynamic wallpaper palette extraction (extract-theme / set-wallpaper)

- [x] **P2 — Media Hub, Toolbox & System Services**
  - Full-featured Media Hub (Music, Radio, Wallhaven, AniList, Manga, Downloads)
  - Standalone GPS Toolbox utility suite
  - Popups: Wi-Fi, Bluetooth, Battery, Notification Center, transient toasts
  - Pet Companion and alert daemon integration

- [x] **P3 — Session Lock & Idle Management**
  - Unified `gps-lock` and `gps-idle` CLI wrappers
  - GPS-styled `hyprlock.conf` with dynamic palette
  - Managed `hypridle.conf` with clean DPMS and lock policies
  - SDDM login theme integration

- [x] **P4 — GPS Unified Visual Design System**
  - [x] **P4.1 — Design foundation**
    - Audit existing desktop surfaces and identify styling fragmentation
    - Establish canonical design tokens in `Theme.qml` (colors, geometry, typography, effects, motion)
    - Add automated token regression tests (`test_design_tokens.py`)
    - Document design system principles and specifications (`docs/design-system.md`)
  - [x] **P4.2 — Reusable components**
    - Implement shared primitives: `GlassSurface`, `GlassCard`, `SectionHeader`, `IconButton`, `GpsButton`, `StatusIndicator`, `Separator`
    - Automated tests for visual primitives (`test_reusable_components.py`)
  - [x] **P4.3 — Major surface migration**
    - LeftRail & Island unified styling (tokens, power dialog, status indicators)
    - Control Center & Dashboard consolidation (DashIcon, SysProbe, DashTabBar, tile styling)
    - Popups (Battery, Wi-Fi, Bluetooth, NotifCenter, NotifToast)
    - Pet panels and Settings Hub IPC syntax fixes
  - [x] **P4.4 — Hyprland visual rules**
    - Coordinated `dots/hypr/hyprland.lua` window/layer rules with GPS design tokens
    - Enforced crispness exceptions for terminals, video playback, overlays
    - Validated performance and compositor harmony with regression tests (`test_hyprland_rules.py`)
  - [x] **P4.5 — Final visual audit & verification**
    - Comprehensive review across all surfaces
    - Verified 1920x1200 / 1.5x scale (1280x800 logical coords)
    - 100% pass across Python test suite (310 tests), Node test suite (74 tests), qmllint, luac, and git diff --check

- [x] **P5 — GPS Daily-Driver Readiness & Reliability**
  - [x] **P5.1 — Architecture and reliability audit**
    - Map runtime: main shell, island, IPC handlers, background processes, external dependencies
    - Prioritized reliability audit report (`docs/reliability-audit-p5.md`)
  - [x] **P5.2 — Session and process lifecycle**
    - Prevent duplicate shell launches (`--no-duplicate`), graceful SIGTERM termination with fallback
    - Dynamic user/process detection without hardcoded paths, actionable diagnostics logging
    - Automated lifecycle safety tests (`tests/test_session_lifecycle.py`)
  - [x] **P5.3 — IPC reliability**
    - Predictable arguments/responses, 3s execution timeouts, structured failure exit codes
    - Target routing for `pet`, `rail`, `mediahub`, `toolbox`, `island`, `clipboard`, `settings`
    - Harmonized `Island.qml` contract (`history`, `focusToggle`, `clipboard`, `clip`)
    - Added health checks (`gps-ipc check`) and system status command (`gps-ipc status`)
    - Automated failure and contract test suite (`tests/test_gps_ipc_reliability.py`)
  - [x] **P5.4 — Settings and persistence**
    - Enforced atomic writes via temp file + replace in `settings.qml`, `AIChat.qml`, and `Launcher.qml`
    - Preserved existing configuration sections during targeted updates
    - Fault-tolerant JSON handling with safe fallbacks on malformed settings
    - Automated persistence and atomic write test suite (`tests/test_settings_persistence.py`)
  - [x] **P5.5 — Graceful dependency handling**
    - Verified clean UI fallbacks across all 9 subsystems (Audio, Network, Bluetooth, Battery, Notifications, Wallpapers, Media, Downloads, Pet)
    - Actionable error banners in popups and drawers when external daemons are missing
    - Automated external service dependency test suite (`tests/test_dependency_handling.py`)
  - [x] **P5.6 — Integrated reliability verification**
    - Live-session soak test across both QuickShell instances with panel toggling and recovery
    - Zero duplicate processes or orphan layers verified with Hyprland 0.57
    - 100% pass across Python test suite (340 tests), Node test suite (74 tests), qmllint, luac, shell/fish checks, git diff --check
    - Real-session verification, panel toggle soak tests, automated regression runs

- [x] **PK1 — GPS Packaging, Installation & Recovery**
  - [x] **K1 — Location-Independent Architecture**: Replaced hardcoded repository paths with dynamic resolution (`$GPS_ROOT`), relative imports, and symlink derivation (`tests/test_location_independence.py`).
  - [x] **K2 — Declarative Package Manifests & Inspector**: Formalized `packages/required.txt`, `packages/optional.txt`, `packages/aur.txt`, and implemented read-only `scripts/gps-deps` (`tests/test_gps_deps.py`).
  - [x] **K3 — Safe Idempotent Installer & Recovery**: Built `install.sh` and `scripts/installer.py` featuring advisory file lock, durable transaction journal, pre-apply backup with SHA-256 verification, atomic symlinks, template preservation, signal interception rollback, and safe restartable uninstaller (`tests/test_installer.py`).
  - [x] **K4 — Packaging Documentation**: Comprehensive canonical manual (`docs/installation.md`), expanded manifest guide (`packages/README.md`), navigable root reference (`README.md`), troubleshooting matrix, and clean-account trial instructions.
