# GPS Desktop — Project Status

**Current Milestone:** P4 — GPS Unified Visual Design System
**Status:** In Progress
**Branch:** `wip/media-hub-next-features`
**Hardware Baseline:** NVIDIA RTX 4050 Laptop GPU (6GB VRAM), 16GB RAM, 1920×1200 Display @ 1.5x scale (1280×800 logical)

## Phase Progress
- [x] **P4.1 — Design Foundation**: Completed.
  - Canonical tokens for color, geometry, typography, effects, and motion added to `config/Theme.qml`.
  - Comprehensive design system documentation in `docs/design-system.md`.
  - Automated token verification suite created in `tests/test_design_tokens.py`.
- [x] **P4.2 — Reusable Visual Primitives**: Completed.
  - Core primitives created in `components/`: `GlassSurface`, `GlassCard`, `SectionHeader`, `IconButton`, `GpsButton`, `StatusIndicator`, `Separator`.
  - Comprehensive unit test coverage in `tests/test_reusable_components.py`.
- [x] **P4.3 — Major Surface Migration**: Completed.
  - LeftRail, Island, and Control Center aligned to canonical theme tokens and status danger/warn/success semantics.
  - Dashboard components (DashIcon, SysProbe, DashTabBar) updated and validated with qmllint.
  - Popup components (BatteryPopup, WifiPopup, BluetoothPopup, NotifCenter, NotifToast) unified with theme tokens.
  - Pet components (PetTheme, Pet.qml) and Settings Hub cleaned of QML syntax anomalies.
- [x] **P4.4 — Hyprland Visual Rules**: Completed.
  - Lua configuration in `dots/hypr/hyprland.lua` coordinated with canonical tokens (teal/cyan borders, deep shadows, balanced blur).
  - Explicit window rules and layer rules for GPS surfaces (`gps-rail-blur`, `gps-island-blur`, `gps-rofi-blur`).
  - Terminal text crispness exception (`kitty` opaque), video playback exception (`mpv`/`vlc` opaque, idle inhibit), and floating dialogs (`Media Hub`, `Toolbox`, `Settings Hub`, `Pet Companion`).
  - Automated tests in `tests/test_hyprland_rules.py`.
- [ ] **P4.5 — Final Visual Audit & Session Verification**: In Progress.
