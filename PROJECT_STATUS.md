# GPS Desktop — Project Status

**Current Milestone:** P5 — GPS Daily-Driver Readiness & Reliability
**Status:** Completed
**Branch:** `wip/media-hub-next-features`
**Hardware Baseline:** NVIDIA RTX 4050 Laptop GPU (6GB VRAM), 16GB RAM, 1920×1200 Display @ 1.5x scale (1280×800 logical)

## Phase Progress
- [x] **P4 — GPS Unified Visual Design System**: Completed.
  - Design tokens, reusable primitives, surface migration, Hyprland rules, and visual audit fully verified.
- [x] **P5.1 — Architecture & Reliability Audit**: Completed.
  - Complete runtime mapped (main Quickshell instance, island instance, IPC routers, persistence files, and background daemons).
  - Failure modes identified and prioritized (non-atomic writes, ungraceful SIGKILL, missing `--no-duplicate`, IPC method desynchronization).
  - Detailed report documented in `docs/reliability-audit-p5.md`.
- [x] **P5.2 — Session and Process Lifecycle**: Completed.
  - Implemented graceful process termination (`SIGTERM` -> 1.5s timeout -> `SIGKILL` fallback) in `scripts/run-gps.fish` and `scripts/switch-island.fish`.
  - Added `--no-duplicate` to master shell and Island production instances to prevent accidental duplicate instances.
  - Replaced hardcoded repository path strings in `pgrep` queries with dynamic user-scoped process patterns.
  - Added structured diagnostic logging with failure log tail capture.
  - Automated regression suite added in `tests/test_session_lifecycle.py` (6 tests passing).
- [x] **P5.3 — IPC Reliability**: Completed.
  - Re-architected `scripts/gps-ipc` with 3-second execution timeout guard (`GPS_IPC_TIMEOUT`) and structured error diagnostics (exit code 3 for dead instances, 124 for timeout).
  - Added direct first-class CLI routing for `pet` and `rail` subsystems.
  - Implemented `history(): string` and `focusToggle()` on `Island.qml`, enabling notification history querying.
  - Replaced hardcoded `tide-island` IPC paths in `NotifCenter.qml` with dynamic `gps-ipc` invocations.
  - Added `gps-ipc check [shell|island|settings|all]` and `gps-ipc status` diagnostic commands.
  - Added comprehensive failure, timeout, and routing test suite in `tests/test_gps_ipc_reliability.py` (10 tests passing).
- [x] **P5.4 — Settings and Persistence**: Completed.
  - Migrated `settings.qml` `writeFile` to atomic write pattern (`.tmp` file in same directory + `mv -f`).
  - Rewrote `AIChat.qml` model preference persister with atomic Python replacement that preserves existing `hypr`, `monitors`, and `island` sections.
  - Updated `Launcher.qml` usage frequency writer and `scripts/toolkit.sh` with safe directory creation and atomic replacement.
  - Added validation for non-array object shapes and corrupt JSON fallbacks in `settings.qml`.
  - Added automated persistence tests in `tests/test_settings_persistence.py` (5 tests passing).
- [x] **P5.5 — Graceful Dependency Handling**: Completed.
  - Verified and hardened fallback behavior across Audio (PipeWire), Network (NetworkManager), Bluetooth (BlueZ), Battery (UPower), Notifications, Wallpapers, Media playback, Downloads (yt-dlp, ffmpeg), and Pet companion.
  - Ensured UI elements surface actionable banners rather than silent hangs or blank dialogs.
  - Added automated dependency handling tests in `tests/test_dependency_handling.py` (9 tests passing).
- [x] **P5.6 — Integrated Reliability Verification**: Completed.
  - Live session verification in running Hyprland 0.57 environment: graceful recovery, panel toggling soak test, clean layer surfaces, and zero duplicate instances.
  - Full test suite passing: 340 Python tests, 74 Node assertions, qmllint with 0 errors, luac with 0 errors, shell/fish syntax clean, git diff --check clean.
  - Guru account and session security untouched. Unrelated worktree modifications preserved.
- [ ] **P5.4 — Settings and Persistence**: Pending.
- [ ] **P5.5 — Graceful Dependency Handling**: Pending.
- [ ] **P5.6 — Integrated Reliability Verification**: Pending.
