# GPS Desktop — Project Status

**Current Milestone:** P5 — GPS Daily-Driver Readiness & Reliability
**Status:** In Progress
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
- [ ] **P5.3 — IPC Reliability**: In Progress.
- [ ] **P5.4 — Settings and Persistence**: Pending.
- [ ] **P5.5 — Graceful Dependency Handling**: Pending.
- [ ] **P5.6 — Integrated Reliability Verification**: Pending.
