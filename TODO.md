# GPS Desktop — Immediate TODO

Use this as the frequently updated checklist. The full rationale, architecture, research, phased milestones and AI collaboration rules live in `ROADMAP.md`.

## Verified current state (2026-10-13)

- [x] Separate `rice` account runs Hyprland/Wayland; `rice` is not in `wheel` and sudo is denied.
- [x] Fish is the login shell.
- [x] QuickShell 0.3.2 loads GPS without the previous Qt mismatch warning; Caelestia still works in `guru`.
- [x] Starter `shell.qml` with GPS brand, tagline, and live clock/date committed as `140e10c`.
- [x] Component extractions complete: `BrandMark.qml` (`641bb75`), `ClockCard.qml` (`5865ca6`), `GpsPanel.qml` (`194df20`), theme singleton fix (`5fd2f59`).
- [x] Initial QuickShell RSS measurement: 183,716 KiB (~179 MiB, process only). Full-session memory baseline remains outstanding.
- [x] Local Git repository and roadmap/TODO commits exist; most recent known docs commit: `199783a`.
- [x] WIP battery-card experiment is preserved in `git stash` as `WIP: unreviewed GPS battery card experiment`; do not `stash pop` until design is agreed.
- [x] Display: `eDP-1`, physical 1920×1200, scale 1.5, 165 Hz. Design QML layouts on a 1280×800 logical canvas.
- [x] Available tools/commands: QuickShell, Kitty, Fish, Thunar, Fuzzel, `brightnessctl`, `playerctl`, `wpctl`, `grim`, `slurp`, `swappy`, `hypridle`.
- [x] Active services observed: PipeWire, WirePlumber, NetworkManager, UPower, power-profiles-daemon, `polkitd`, XDG portal and Hyprland portal.
- [x] No checked wallpaper or notification utility was found; no graphical Polkit authentication-agent process was found at audit time. `hypridle` was installed but not seen running.
- [x] Confirmed `hyprlauncher` and `dolphin` are absent. Changed `rice` Hyprland config to Fuzzel/Thunar, saved `hyprland.lua.bak-before-gps-tool-fix`, reloaded Hyprland, and verified `Super+R` and `Super+E` both work.
- [x] Display: `eDP-1`, physical 1920×1200, scale 1.5, 165 Hz. Design QML layouts on a 1280×800 logical canvas.

## Next actions — do these in order

- [ ] **Do not write more QML widgets yet.** Keep BatteryCard experiment stashed.
- [x] Verify `hyprlauncher` and `dolphin` are not installed; use installed Fuzzel and Thunar, with a rollback backup. Both shortcuts have been tested.
- [ ] Test Fuzzel’s filtering, keyboard behavior, styling, close/focus behavior and resource use. Rofi is not installed; consider it only after seeing a concrete need.
- [ ] Decide the long-term launcher based on visual fit, Wayland behavior, search/navigation, and resource use. Keep Fuzzel as the working baseline for now.
- [ ] Collect 8–12 visual references from the provided repositories and Rofi-style launchers; evaluate overall layout, not one-off screenshots.
- [ ] Agree on a 1280×800 logical-coordinate wireframe: top panel, center launcher overlay, dashboard/quick settings, notification treatment, and power menu.
- [ ] Define design tokens: color roles, typography, spacing, radii, borders, opacity/blur, icon style, motion and focus state.
- [ ] Decide missing utilities deliberately: one wallpaper tool, one notification daemon, one graphical Polkit agent, and a compatible locker/idle flow. Check repo/package compatibility before installing, only from `guru` after review.
- [ ] Capture a repeatable baseline with GPS stopped/running: whole-session memory, `qs` RSS, idle CPU and visual smoothness.
- [ ] Copy the updated audited `ROADMAP.md`/`TODO.md` from the latest downloads into `~/Projects/my-rice`, review the diff, then commit the updated plan.
- [ ] Only after design agreement: build one verified component per task. (Component extractions — `GpsPanel`, `ClockCard`, `BrandMark` — are complete; theme tokens already extracted.)

## Per-task engineering rule

1. One task with a clear acceptance criterion.
2. Read the current docs/API and inspect relevant files first.
3. Make the smallest change under `/home/rice/Projects/my-rice`.
4. Test it, inspect `git diff`, run `git diff --check`.
5. Commit only after it works; update the roadmap.
6. Never touch `guru` configuration, restore `rice` sudo, install packages blindly, or enable GPS autostart before manual testing.
