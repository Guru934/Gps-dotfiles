# GPS Desktop — Project Plan & TODO

> **Project:** GPS Desktop, a custom CachyOS + Hyprland desktop shell built with QuickShell / Qt Quick (QML).
> **Workspace:** `/home/rice/Projects/my-rice`
> **Status:** Planning / prototype stage. Working starter panel exists and is checkpointed in local Git as `140e10c`.
> **Brand:** GPS (provisional; user selected it instead of “Sekai”).
> **Primary requirement:** develop in the unprivileged `rice` account while keeping the `guru` daily-driver desktop untouched.

## 1. Product vision

Build a cohesive, polished, keyboard-friendly Wayland desktop experience that feels like a carefully designed product rather than a pile of unrelated widgets. Combine a modern card/dashboard aesthetic with a Rofi-like launcher workflow. Make it useful every day first, beautiful second, and elaborate only where the result adds real utility.

### Design direction (initial hypothesis, not frozen)
- Dark graphite / midnight surfaces.
- Lavender-pink accent, restrained highlights, readable contrast.
- Rounded cards and balanced negative space; avoid turning the entire screen into cards.
- Smooth, short transitions. No always-moving animations just for decoration.
- Clear information hierarchy and consistent iconography / typography.
- 16:10 canvas first (the laptop's 1920×1200 WUXGA panel), but layouts must adapt to monitor dimensions and scaling.

### Interaction principles
- Keyboard-first for search, app launch, switching, and power actions.
- Mouse/touchpad-friendly controls in dashboard cards.
- Escape closes overlays, focus goes to the intended control, click-away behaviour is deliberate.
- Use real system state. No fake battery, network, audio, or workspace indicators.
- Degrade gracefully when a service/API is unavailable.

## 2. Research and useful references

Research was performed on the provided GitHub projects and related upstream references on 2026-10-13.

- [Awesome Hyprland](https://github.com/hyprland-community/awesome-hyprland): a broad, categorized index of compatible tools. It separates status bars/shells from notifications, launchers, wallpaper tools, display tools, screenshot, locking/idle, and other utilities. Treat it as a shortlist, not a list to install wholesale.
- [Hyprland rice topic](https://github.com/topics/hyprland-rice): useful for screenshots, color/layout ideas, and discovering public setups. The topic page is a discovery feed, not an installation recipe. Inspect each project's dependencies, update activity, licensing, and Hyprland/Qt compatibility before borrowing anything.
- [Rofi](https://github.com/davatorium/rofi): upstream documentation describes Rofi as an application launcher, window switcher, and dmenu replacement. It has keyboard navigation, type-to-filter and fuzzy matching, run/drun/window/SSH/file-browser/script modes. Upstream supports Wayland since 2025. This is a strong functional and visual reference for the launch experience, but it is a launcher—not a full shell/UI toolkit.
- [QuickShell](https://quickshell.outfoxxed.me/): primary implementation reference for QML panels, widgets, services, and integration with desktop state.
- [Caelestia shell](https://github.com/caelestia-dots/shell): helpful real-world example of a larger QuickShell project and modular shell. Its source warns users not to modify package-managed files and documents a manual config checkout approach. Use it for architecture inspiration only, not wholesale copying.
- [Awesome Hyprland shell list](https://github.com/hyprland-community/awesome-hyprland): lists QuickShell alongside Waybar, AGS, Eww, Fabric, Ignis and other alternatives. Since QuickShell is already installed and the prototype runs, do not change frameworks without a concrete limitation.
- [Rofi source/documentation](https://github.com/davatorium/rofi): upstream has Wayland mode. Test the installed package and theme first. If Rofi's interaction and theming meet the need, reuse Rofi instead of rebuilding fuzzy search, desktop-entry indexing, window switching, and launcher keyboard semantics from scratch.
- [Fuzzel](https://codeberg.org/dnkl/fuzzel): already seen on the initial `rice` setup screen as an installed launcher. It is a reasonable fallback for a lightweight drun-style launcher if Rofi behaves poorly on this Wayland setup.
- Existing local tool context: QuickShell 0.3.2, Hyprland 0.56.2, Kitty, Fish, Thunar, Fuzzel, PipeWire, and UPower were verified in the session. UPower exposes battery and AC devices. Do a real package/service audit before planning additional installs.
- Avoid blindly following dotfiles install scripts. They may replace configs, alter system packages, add autostart rules, or assume another distribution.

### Key conclusion
Do not recreate all the pieces already solved by proven utilities. GPS should own the visual identity, QML panel, dashboard/control center, and selected custom interactions. Prefer reliable existing tools for commodity jobs until there is a strong reason to replace them.

## 3. Architecture proposal

### Layers
1. **Hyprland integration** — only required keybinds, window/layer rules, output behaviour and eventually one controlled autostart entry. Change only after manual tests, and only in `/home/rice/.config/hypr/`.
2. **GPS shell process (QuickShell/QML)** — panel, overlay surfaces, dashboard, cards, animations and display layout.
3. **Reusable UI components** — Card, IconLabel, StatusPill, SliderRow, SectionHeader, OverlayFrame.
4. **Services/adapters** — live adapters for UPower, PipeWire, NetworkManager, MPRIS, Hyprland IPC, notifications. Each adapter should have explicit loading/error states.
5. **External utilities** — launcher, wallpaper tool, notification daemon, screenshot tool, locker/idle handler. Use one suitable utility per job; avoid overlapping daemons.
6. **Assets/design tokens** — palette, spacing, radii, typography, icon choices, wallpapers and optional artwork.

### Proposed code structure (evolve only as justified)
```text
my-rice/
├── shell.qml                 # entry point / top-level panel
├── ROADMAP.md                # this plan and checklist
├── README.md                 # run/debug instructions
├── CHANGELOG.md              # verified notable changes
├── components/
│   ├── GpsPanel.qml
│   ├── BrandMark.qml
│   ├── ClockCard.qml
│   ├── BatteryStatus.qml
│   ├── AudioStatus.qml
│   ├── NetworkStatus.qml
│   ├── WorkspaceIndicator.qml
│   ├── AppLauncher.qml       # only if custom launcher decision is justified
│   ├── Dashboard.qml
│   └── PowerMenu.qml
├── services/
│   ├── PowerService.qml
│   ├── AudioService.qml
│   ├── NetworkService.qml
│   └── WindowService.qml
├── config/
│   └── Theme.qml             # tokens; use singleton only after project setup supports it
├── assets/
│   ├── icons/
│   ├── wallpapers/
│   └── fonts/                # reference installed fonts; do not commit copyrighted font files
├── scripts/
│   ├── run-gps.fish
│   └── measure-memory.fish
└── docs/
    ├── design-brief.md
    └── dependency-audit.md
```
Do not create every file immediately. Start by writing the design brief and splitting out only the first stable component when the current QML grows.

## 4. Tooling and dependencies

### Already available / verified
- QuickShell 0.3.2, rebuilt/updated; GPS prototype loads without the earlier Qt mismatch warning.
- Hyprland 0.56.2.
- Kitty 0.49.2.
- Fish 4.9.3 (configured as login shell).
- Git (local repository initialised).
- Fuzzel and Thunar.
- PipeWire.
- UPower installed; system exposes battery and AC adapter devices.
- `paru` available to the administrator account `guru`, but `rice` is deliberately non-admin.

### Do not install yet; audit first
- Rofi: check `pacman -Q rofi`, `command -v rofi`, then test Wayland `drun` and `window` behaviour if installed.
- Wallpaper: identify installed Hyprpaper/swww/swaybg/wpaperd/Waypaper, select one only after checking existing startup config.
- Notifications: inspect existing mako/dunst/SwayNotificationCenter and service state.
- Desktop portal: confirm the Hyprland-compatible xdg-desktop-portal backend before changing it.
- Polkit agent: determine whether an agent already starts and whether administrative GUI prompts work in `rice`.
- Lock/idle: inspect current hyprlock/hypridle or alternatives before configuring.
- Brightness: identify `brightnessctl`/`ddcutil` and permission/device support before adding a UI control.
- Audio: use PipeWire native interfaces/verified QuickShell modules; avoid repeated shell polling if a live API is available.
- Network: inspect NetworkManager and available D-Bus/API before choosing the adapter.
- Fonts/icons: inspect what is installed; add a single consistent family/icon set only after mockups.
- Build/dev tools: use what exists; install system-wide packages only from `guru` after a reviewed transaction and only when actually needed.

### Package-management safety rules
- `rice` must remain out of `wheel` and must not acquire sudo.
- All package changes are machine-wide and can affect Caelestia in `guru`; review every transaction.
- Never install an alternate QuickShell provider/fork as a side effect of rebuilding. Preserve the verified `quickshell-git` provider.
- Do not execute external dotfiles installers. Review PKGBUILDs/scripts before running them.
- Keep changes confined to `/home/rice` except deliberate system-level dependency operations.

## 5. Phased roadmap

Status: `[x]` verified; `[~]` active; `[ ]` TODO; `[!]` decision/blocker.

### Phase 0 — Isolation and working baseline
- [x] Create `rice` sandbox account and confirm Wayland/Hyprland.
- [x] Ensure `rice` is not in `wheel`; verify `sudo` denied.
- [x] Configure Fish as the login shell.
- [x] Create `/home/rice/Projects/my-rice/`.
- [x] Install/verify QuickShell 0.3.2; test Caelestia still works in `guru`.
- [x] Build a starter GPS panel with clock/date/brand.
- [x] Initialise Git and commit known-good starter: `140e10c`.
- [x] Confirm QuickShell loads the starter under 0.3.2 without the previous Qt mismatch warning.
- [x] Record initial QuickShell RSS: 183,716 KiB (~179 MiB).
- [ ] Measure whole-session idle RAM/CPU consistently, with and without GPS; record baseline methodology.
- [ ] Ensure `.gitignore` ignores local logs/build output and commit planning docs.
- [ ] Verify fresh-login start/stop workflow; GPS must remain manually launched during development.

### Phase 1 — Define product and visual design (do before adding widgets)
- [ ] Collect 8–12 screenshots/reference examples from the supplied repositories plus Rofi-style launchers.
- [ ] Choose a main visual direction: dark graphite with lavender/pink accents; document an alternative palette.
- [ ] Sketch 1920×1200 layout for panel, launcher, dashboard/quick settings, notification, and power menu.
- [ ] Define design tokens for colour, typography, spacing, radii, borders, surfaces, hover/focus, shadows/blur, and animation.
- [ ] Decide what belongs on the panel versus hidden in dashboard; avoid permanent clutter.
- [ ] Define keyboard/mouse behaviours: Escape, focus restore, click-away, global shortcuts, multi-monitor behaviour.
- [ ] Write explicit MVP goals and non-goals before implementation.

### Phase 2 — Development workflow and modular foundation
- [ ] Write a short README with current status, run commands, log locations and rollback instructions.
- [ ] Convert this document into a maintained roadmap/TODO in Git.
- [ ] Add CHANGELOG and a small `run-gps.fish` dev script with logs; no autostart or config modification.
- [ ] Define a small, consistent commit workflow: inspect diff, `git diff --check`, run manual test, commit.
- [ ] Split code only when helpful: `GpsPanel`, `ClockCard`, common `Theme` tokens, then service adapters.
- [ ] Ensure each module has loading/unavailable/error states and no made-up values.

### Phase 3 — MVP status panel
- [ ] Make top panel responsive with no overlaps on 1920×1200 and under font scaling.
- [ ] Keep a clock/date component with local-time formatting.
- [ ] Add workspace indicator based on real Hyprland state.
- [ ] Add a focus/title indicator only if the layout remains clean.
- [ ] Add a battery status widget from a verified QuickShell/UPower API; show charge and charging/AC state.
- [ ] Add audio mute/volume using a verified PipeWire-aware API.
- [ ] Add truthful network state using verified NetworkManager/API signals.
- [ ] Add mouse tooltips and proper keyboard/focus behaviour where relevant.
- [ ] Test AC connect/disconnect, mute/volume, Wi-Fi state and reload/crash behaviour.
- [ ] Measure RSS, whole-session RAM and idle CPU after each addition.

### Phase 4 — Rofi-style launcher
- [ ] Audit whether Rofi is installed and inspect package/version.
- [ ] Test existing Rofi in Wayland mode; verify application launch, keyboard selection, fuzzy filter, window mode and theme.
- [ ] Compare Rofi versus existing Fuzzel based on user-visible test, not internet reputation.
- [ ] Prefer using and theming Rofi if it satisfies functionality and aesthetics.
- [ ] Build a custom QuickShell launcher only if it provides clear value: rich app cards, custom GPS integration, search providers or integrated dashboard.
- [ ] For a custom launcher, use desktop-entry metadata and safe process APIs; never concatenate untrusted app data into shell strings.
- [ ] Add the Hyprland shortcut only after reliable manual testing; preserve escape/focus/launcher close behaviour.

### Phase 5 — Dashboard / quick settings
- [ ] Build reusable cards, section headers, status pills, icon labels, sliders, focus and hover states.
- [ ] Create an overlay dashboard that is hidden by default and opened via shortcut/button.
- [ ] Add volume/mute control.
- [ ] Add media controls using MPRIS if useful.
- [ ] Add network controls/details only with a reliable backend.
- [ ] Add brightness control only when device/API/permissions are verified.
- [ ] Add power profile status/control if it is supported and useful on this hardware.
- [ ] Test click-away, Escape, focus, multi-monitor placement, fullscreen app interaction.

### Phase 6 — Separate desktop utilities and polish
- [ ] Choose one wallpaper utility and make wallpaper changing reversible.
- [ ] Choose one notification daemon and test actions/urgency rendering.
- [ ] Choose one OSD utility for volume/brightness if needed; avoid duplicate OSDs.
- [ ] Select/verify screen lock and idle/suspend handling without changing `guru`.
- [ ] Build a safe power menu with explicit confirmation for shutdown/reboot.
- [ ] Add screenshot workflow (capture, preview, save/copy) only after the core shell works.
- [ ] Choose fonts/icon set after visual references; verify glyph coverage.
- [ ] Add subtle motion, avoid excessive blur, provide a low-motion/no-effects fallback.
- [ ] Test display scaling, animations, fullscreen behaviour, screen-edge placement and multi-monitor use.

### Phase 7 — Laptop integration and efficiency
- [ ] Identify which GPU renders the `rice` session and check dGPU idle state.
- [ ] Profile memory/CPU before and after each feature using a repeatable measurement procedure.
- [ ] Count the whole GPS stack, not just `qs`, when assessing the 600–900 MiB goal.
- [ ] Profile frame pacing with the 165 Hz panel; avoid busy JS timers and permanent animations.
- [ ] Test AC/battery transition, suspend/resume, Wi-Fi reconnect and monitor events.
- [ ] Keep current NVIDIA dynamic power-management configuration unchanged unless a measured issue demands change.
- [ ] Document actual results and known limits; no assumptions about resource use.

### Phase 8 — Autostart, recovery and daily-use hardening
- [ ] Keep manual launch only until MVP is reliable.
- [ ] Add a user-local single-instance launcher script with logs.
- [ ] Test crashes/restarts and reload behaviour.
- [ ] Add a user-only autostart method after restart and login tests pass.
- [ ] Document emergency disable procedure from TTY/another session.
- [ ] Test fallback desktop and preserve ability to switch back.
- [ ] Re-audit symlinks and ensure `guru` is unchanged.

### Phase 9 — Release candidate
- [ ] Full login/logout test.
- [ ] Test app launch/window switching/keyboard navigation, audio, power, network, notifications, lock and power menu.
- [ ] Audit package set and remove unnecessary dependencies.
- [ ] Review provenance/licences for source snippets and artwork.
- [ ] Confirm idle CPU/RAM/frame stability targets using measured data.
- [ ] Tag a release candidate in Git and document how to install/disable it.

## 6. Daily session protocol (30–90 minutes)

1. Pick **one** TODO with a clear acceptance criterion.
2. Read the current roadmap, `git status`, relevant QML/API docs and only the files needed.
3. Ask an AI to propose a minimal approach first, not rewrite the project.
4. Ask AI to implement only the agreed scope. Require any uncertain API usage to be verified against current docs/local QML modules.
5. Inspect all changed files and `git diff`; reject changes to unrelated configs, dependencies, autostart, or `guru`.
6. Run the exact test and check terminal/log output.
7. Run `git diff --check`; commit only after the feature works.
8. Update this roadmap and choose the next TODO.

## 7. AI collaboration brief

When using another AI, provide:
- This `ROADMAP.md`, `git status --short`, current QuickShell version, and only the relevant source files.
- Constraint: work in `/home/rice/Projects/my-rice`; do not touch `guru`, shared desktop config, system packages, sudo, or wheel membership.
- Do not add autostart unless explicitly tasked.
- Do not paste long generated code directly into the terminal where quoting/heredocs may be mishandled; prefer deliberate file editing and review.
- Request: plan → minimal implementation diff → exact verification steps → risks/rollback.
- Reject architecture rewrites, new frameworks, duplicate daemons, fake status values, shell-string command construction, unreviewed package installs, and unlicensed assets.

## 8. Immediate TODO (next session)

1. [ ] **Pause feature coding** until the product direction is agreed.
2. [ ] Capture/pick visual references: card-style dashboard + Rofi-inspired launcher.
3. [ ] Audit current relevant tools: `rofi`, Fuzzel, wallpaper, notification, portal, polkit, lock/idle, brightness, NetworkManager/MPRIS.
4. [ ] Draft one 1920×1200 wireframe and design tokens.
5. [ ] Commit this roadmap.
6. [ ] Only then modularize the current `shell.qml` and implement the MVP in small steps.
