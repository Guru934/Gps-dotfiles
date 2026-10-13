# GPS Desktop — First Wireframe (Proposal)

**Status:** draft for discussion, not implementation instructions.

## Display coordinate system

- Physical panel: 1920×1200, 165 Hz.
- Hyprland scale: 1.5.
- Primary QML design canvas: **1280×800 logical pixels** (`1920 / 1.5 = 1280`; `1200 / 1.5 = 800`).
- All dimensions below are starting estimates. QML anchors/layouts should adapt to actual available geometry rather than hardcoding every position.

## Visual direction

- Brand: **GPS** (working name).
- Mood: dark graphite / midnight, pale text, restrained lavender-pink accent, muted blue-grey secondary text.
- Rounded cards with consistent radii; no excessive blur, glow, or permanent animation.
- High information clarity; the desktop should stay useful in real work, not look like a screenshot-only theme.

## Screen A — everyday desktop (1280×800 logical)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│  ✦ GPS   [ 1 ][ 2 ][ 3 ][ 4 ]      active window / breathing room   ◉  18:42 │  ← top panel, ~48–56 px
│                                                            network audio batt │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                                                                              │
│                         WORKSPACE / APPLICATIONS                             │
│                       desktop remains uncluttered                            │
│                                                                              │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Panel responsibilities

- Left: GPS mark and real Hyprland workspace state.
- Middle: leave free initially; optionally show active-window title only if it helps.
- Right: notification affordance, audio, network, battery/power and clock/date. Avoid duplicate icons for controls that the user never touches.
- Keep the panel compact; decide whether it reserves screen space after manual testing.

## Screen B — launcher overlay (invoked by shortcut; hidden by default)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                   ┌────────────────────────────────────┐                     │
│                   │ GPS / SEARCH                       │                     │
│                   │  > Search apps, windows, actions…  │                     │
│                   ├────────────────────────────────────┤                     │
│                   │  ✦  App result                     │                     │
│                   │  ◈  App result                     │                     │
│                   │  ◉  App result                     │                     │
│                   │  …                                 │                     │
│                   ├────────────────────────────────────┤                     │
│                   │ ↑↓ navigate   ↵ open   Esc close   │                     │
│                   └────────────────────────────────────┘                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

Fuzzel is installed and now mapped to Super+R in the rice-only Hyprland config; Thunar is mapped to Super+E. Both shortcuts were reloaded and tested. First evaluate Fuzzel styling, filtering, keyboard navigation, focus restoration and resource use. Rofi is not installed; consider installing it only if a controlled comparison is worth the dependency. Do not build a custom search engine just for branding. The final launcher may remain an external app with a GPS theme; a native QML launcher is optional.

## Screen C — quick settings / dashboard (toggle overlay)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ GPS CONTROL CENTER                                    Tue 13 Oct · 18:42     │
│                                                                              │
│ ┌───────────────────┐ ┌───────────────────┐ ┌─────────────────────────────┐ │
│ │ AUDIO             │ │ NETWORK           │ │ POWER                       │ │
│ │ volume + mute     │ │ connected state   │ │ battery + AC + power mode   │ │
│ │ output selector   │ │ details / toggle* │ │                             │ │
│ └───────────────────┘ └───────────────────┘ └─────────────────────────────┘ │
│                                                                              │
│ ┌─────────────────────────────┐ ┌────────────────────────────────────────┐ │
│ │ MEDIA                       │ │ BRIGHTNESS                             │ │
│ │ title / controls / progress │ │ slider only if API + permission work  │ │
│ └─────────────────────────────┘ └────────────────────────────────────────┘ │
│                                                                              │
│ [wallpaper] [screenshot] [settings]                         [power menu]     │
└──────────────────────────────────────────────────────────────────────────────┘
```

`*`Network toggle/actions depend on a reliable backend; do not fake state or assume the user has permission. The dashboard is closed by default and must not compete with full-screen applications.

## Screen D — power menu

```text
                    ┌───────────────────────────────┐
                    │ POWER                         │
                    │ Lock      Suspend             │
                    │ Log out   Restart             │
                    │ Shut down                     │
                    │                      Cancel   │
                    └───────────────────────────────┘
```

Destructive actions require deliberate selection and a confirmation step. Locking and suspend behaviour must be tested independently before the menu is wired up.

## Interaction requirements

- Launcher is keyboard-first, predictable, and dismisses with Escape. Focus returns to the previous app when closed.
- Dashboard opens through a deliberate shortcut/panel click; click-away behaviour is tested.
- All interactive controls have focused/hover/disabled states and readable contrast.
- Workspace state, battery, network, audio and media reflect live system state; each supports unavailable/loading states.
- Multi-monitor behaviour should be designed for future extension, even though only `eDP-1` is currently reported.
- Autostart remains off during development. GPS is launched manually until recovery behaviour is tested.

## Decisions not made yet

- Rofi vs Fuzzel vs Hyprlauncher vs a future custom launcher.
- Whether top panel reserves screen space.
- Final typeface, icon set, exact colors and motion durations.
- Wallpaper, notifications, graphical Polkit authentication agent and locker/idle utility.
- Whether a dock adds enough value to justify another component/process.
