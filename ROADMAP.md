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

- [ ] **P5 — GPS Daily-Driver Readiness & Reliability**
  - [x] **P5.1 — Architecture and reliability audit**
    - Map runtime: main shell, island, IPC handlers, background processes, external dependencies
    - Prioritized reliability audit report (`docs/reliability-audit-p5.md`)
  - [ ] **P5.2 — Session and process lifecycle**
    - Prevent duplicate shell launches, graceful termination, dynamic path detection, startup logging
  - [ ] **P5.3 — IPC reliability**
    - Predictable arguments/responses, timeouts, missing targets handling, clipboard/history harmonization
  - [ ] **P5.4 — Settings and persistence**
    - Atomic configuration writes, malformed JSON recovery, safe defaults
  - [ ] **P5.5 — Graceful dependency handling**
    - Clean UI fallbacks when audio, network, bluetooth, battery, or tools are unavailable
  - [ ] **P5.6 — Integrated reliability verification**
    - Real-session verification, panel toggle soak tests, automated regression runs
