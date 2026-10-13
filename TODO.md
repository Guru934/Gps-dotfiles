# GPS Desktop — Immediate TODO

Use this as the short, frequently updated checklist. The full rationale, architecture, tool audit, phases, and AI collaboration rules are in `ROADMAP.md`.

## Current verified state

- [x] Separate `rice` user is running Hyprland/Wayland.
- [x] `rice` is not in `wheel`; sudo is denied.
- [x] Fish is the login shell.
- [x] QuickShell 0.3.2 is installed; the GPS prototype loads without the earlier Qt mismatch warning.
- [x] Caelestia still works in `guru`.
- [x] Starter GPS panel (brand, tagline, live clock/date) is committed locally: `140e10c`.
- [x] Initial QuickShell RSS measured at 183,716 KiB (~179 MiB); this is not whole-session RAM.
- [x] Research plan drafted using Awesome Hyprland, Hyprland rice examples, QuickShell, Rofi, and Caelestia references.

## Do these next — in order

- [ ] **Do not implement BatteryCard or more widgets yet.** Agree on the product and layout first.
- [ ] Capture/save 8–12 visual reference screenshots: 3 top panels, 3 Rofi-style launchers, 2 card/dashboard layouts, 1–2 power/quick-settings views.
- [ ] Create a 1920×1200 (16:10) rough wireframe for the top panel, launcher, dashboard, notifications, and power menu.
- [ ] Decide the visual tokens: background, surfaces, accent, text, font, icon style, spacing, corner radii, borders, motion.
- [ ] Audit installed tools only (no installs): Rofi, Fuzzel, wallpaper daemon, notifications, portal, polkit agent, lock/idle tools, brightness, NetworkManager.
- [ ] Test Rofi on Wayland if installed; compare with Fuzzel. Choose mature launcher first; custom GPS launcher remains optional until there is a concrete reason.
- [ ] Record a baseline with GPS stopped and running: whole-session memory, `qs` RSS, idle CPU, and visible behaviour.
- [ ] Add this plan to `~/Projects/my-rice/ROADMAP.md`, then commit it.
- [ ] Only after the design decision: split `shell.qml` into a small `components/` structure and establish theme tokens.

## Implementation rule for each future task

1. One task; one acceptance criterion.
2. Inspect the relevant current API/docs and package state.
3. Make the smallest scoped change under `/home/rice/Projects/my-rice`.
4. Test it, inspect `git diff`, run `git diff --check`.
5. Commit only after it works; update `ROADMAP.md`.
6. Never alter `guru`, grant sudo back to `rice`, install tools blindly, or add autostart before manual validation.
