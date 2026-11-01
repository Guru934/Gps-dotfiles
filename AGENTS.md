# GPS Task T1 — Establish Shared AI Development Rules

## Purpose
This document provides the authoritative instruction system for all AI coding agents working on GPS (GitPCM Desktop Environment). It defines project structure, mandatory safety rules, testing procedures, and workflow requirements.

## Project Structure

### Core Components
- **shell.qml** - Main QuickShell instance managing Left Rail Dock, Dashboard drawer, Notification Center, Toast Banners, and Wallpaper Carousel. Operates as passive notification consumer to prevent D-Bus collision.

- **island/** - Tide Island QuickShell instance (separate process). Contains Island.qml and all state management.
  - `Island.qml` - Owns window, morphing pill, live data, and state priority
  - `states/` - Individual state files (Alert, Charge, Clip, Dnd, FaceLock, Launcher, Music, PetFx, Privacy, Workspace)

- **components/** - Reusable visual primitives and utility components
  - `ToolboxWindow.qml`, `MediaHubWindow.qml` - Standard window surfaces
  - `NotifCenter.qml` - Notification ownership belongs to Island process
  - `Dashboard.qml` - Home, Media, System, Tools panes
  - Various dashboard tabs (Focus, Media, NowPlaying, ScreenTime, Spectrum, etc.)

- **config/** - Runtime configuration and theme system
  - `Theme.qml` - Design tokens and palette transitions
  - `Brightness.qml`, other singletons

- **scripts/** - Automation and utility scripts
  - `run-gps.fish` - Process startup with `--no-duplicate`
  - `gps-ipc` - IPC and CLI routing layer
  - `gps-doctor` - Session diagnostics
  - `install.sh` - Safe idempotent installer
  - Theme hooks (gtk.py, qt.py, etc.)

- **dots/** - Hyprland configuration
  - `hypr/hyprland.lua` - Window manager rules
  - `hypr/hypridle.conf`, `hyprlock.conf`

- **tests/** - Hermetic test suite
  - `run_all.sh` - Test runner
  - All contract and reliability tests

- **packages/** - Dependency manifests
  - `required.txt` - Core dependencies
  - `optional.txt` - Optional features
  - `aur.txt` - AUR packages

## Mandatory Safety Rules

1. **Account Isolation**: Never modify the `guru` account or system configuration. Keep GPS development inside the `rice` account.

2. **Worktree Management**: Use a dedicated Git worktree for independent tasks. Never let two agents edit the same worktree simultaneously.

3. **Git Operations**: 
   - Never overwrite uncommitted changes
   - Never run destructive Git operations on changes you did not create
   - Never push to GitHub

4. **Process Management**: Never kill processes you did not start. Never automatically restart the real desktop session.

5. **Command Execution**: Never use sudo or pacman. Report commands for the user instead.

6. **Path Management**: Never hardcode usernames or home-directory paths. Use GPS_ROOT and appropriate XDG paths.

7. **QML Architecture**: Never use Qt.resolvedUrl for filesystem paths. Verify Hyprland Lua syntax using supported live validation.

8. **Architecture Preservation**: Preserve existing architecture unless explicitly authorized. Do not remove Tide Island or its dependencies.

## Testing Rules

- **Test Runner**: Always run `./tests/run_all.sh`
- **Hermetic Testing**: Tests use isolated temporary environments and must not modify the actual desktop
- **Work Sequence**: Audit → Plan → Implement → Test → Fix → Review → Commit
- **Atomic Commits**: Use one logical commit per completed task
- **Verification**: Never claim something works unless it was actually executed and verified

## Known Fragile Areas

- **Island Process**: Runs as separate Quickshell instance with its own configuration imported through symlink
- **Theme System**: Tokens must exist in Theme.qml
- **Notifications**: Ownership belongs to Island process
- **UWSM**: Process startup and environment propagation depend on UWSM
- **Multi-process Architecture**: GPS uses multiple processes with IPC communication

## Two-Agent Workflow

1. **Cline**: Implementation worker for bounded tasks
2. **Antigravity**: Handles complex architecture, difficult debugging, and independent review

3. **Concurrency Rules**: Never run both agents against the same working tree simultaneously
4. **Review Process**: A second agent must review completed changes without overwriting implementation

## Restrictions

- Do not modify application QML or runtime behavior
- Do not alter startup scripts
- Do not install software
- Do not change desktop configuration
- Do not create a commit until tests pass and final diff is reviewed
- Do not migrate or install GPS into guru or gpstest

## Testing Requirements

Add a hermetic test that:
- Fails if AGENTS.md is missing
- Verifies GEMINI.md and CLAUDE.md point to the canonical instructions
- Verifies Cline's instruction configuration exists and is readable

## Final Report

Provide:
1. Files created or modified
2. Actual instruction discovery mechanisms verified
3. Test results
4. Git status and diff
5. Any unsupported instruction mechanism
6. Proposed commit message