# Changelog

All notable changes to GPS Desktop are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- `README.md` — run, debug, git checkpoint and rollback instructions
- `CHANGELOG.md` — this file

## [0.1.0] - 2026-10-13

### Added
- Working starter panel (`shell.qml`) with GPS branding
- Live clock (12-hour format) and date (e.g., "Mon, 13 Oct")
- Brand mark (✦) with lavender-pink accent on graphite surface
- Tagline: "Your space. Your rules."
- Panel anchored top/left/right with 12px top margin, 16px side margins
- Transparent window background, `exclusiveZone: 0` (no reserved space)
- 1-second timer for clock/date updates

### Known Limitations
- No workspace indicator, battery, audio, or network status yet
- No launcher, dashboard, power menu, or notifications
- Font family not explicitly set (uses system default)
- Design tokens not centralized (hard-coded in `shell.qml`)
- Full-session memory baseline not measured (process RSS ~179 MiB)
- `exclusiveZone: 0` means panel does not reserve screen space — may overlap fullscreen windows
- No hot-reload verification for future theme singleton
- WIP battery card experiment preserved in git stash (not applied)

### Infrastructure
- Git repository initialized at `/home/rice/Projects/my-rice`
- QuickShell 0.3.2 verified loading without Qt mismatch warning
- Hyprland config updated for `rice` user: Fuzzel (Super+R), Thunar (Super+E)
- Backup of original Hyprland config saved as `hyprland.lua.bak-before-gps-tool-fix`

### Commit
- `140e10c` — Checkpoint working GPS prototype