# GPS Unified Visual Design System (P4)

The GPS Visual Design System establishes a single, canonical visual language across all Wayland shell surfaces, QuickShell components, and Hyprland compositor settings.

---

## 1. Core Principles

- **Dark, Elegant Surfaces**: Graphite/midnight base surfaces (`#0F131C`, `#181B25`) with deep atmospheric depth.
- **Teal / Cyan Accent Lighting**: Controlled, energetic glow (`#2DD4BF` / `#57F1DB`) with high contrast against dark foundations.
- **Translucent Layered Glass**: Physical layering rather than uniform opacity.
- **Subtle Hairline Borders**: 1px crisp outlines (`outlineSoft`, `borderAlpha: 0.25`) providing boundary definition without visual clutter.
- **Restrained Motion**: Snappy, intentional transitions (120ms fast, 220ms normal, 360ms slow) adhering to reduced-motion preferences.
- **Clean Hierarchy & Typography**: `Plus Jakarta Sans` for UI readability, `JetBrains Mono` for telemetry and metadata.

---

## 2. Visual Layering

GPS establishes five distinct elevation layers:

| Layer | Surface Token | Opacity / Treatment | Example Usage |
|:---|:---|:---|:---|
| **L1: Desktop** | Wallpaper / Root | Wallpaper + Compositor background | Workspace canvas |
| **L2: Floating Glass** | `Theme.surface` / `Theme.surfaceDeep` | `glassAlpha: 0.72` + MultiEffect / compositor blur | LeftRail dock, Island pill, Popup backgrounds |
| **L3: Elevated Panels & Cards** | `Theme.card` / `Theme.surfaceBase` | `glassAlphaElevated: 0.85`, 1px `Theme.outlineSoft` | Dashboard cards, Pet panel, Battery/Wifi cards |
| **L4: Interactive Controls** | `Theme.surfaceHigh` / `Theme.cardHover` | Distinct hover lift, `radiusSm` (8px) / `radiusPill` | Buttons, sliders, switches, list delegates |
| **L5: Active & Focus Elements**| `Theme.brandAccent` / `Theme.accentPrimary` | High-contrast accent fill with `Theme.onAccent` text | Active tab, connected devices, playing indicator |

---

## 3. Canonical Design Tokens (`Theme.qml`)

### Colors
- **Accents**:
  - `accentPrimary` / `brandAccent`: Primary teal/cyan brand accent (dynamically extracted or `#2DD4BF`).
  - `brandAccentFg` / `onAccent`: High-contrast dark text on accent surfaces (`#003731`).
  - `accentSecondary`: Secondary lilac/violet accent (`#DDB8FF`).
  - `accentTertiary`: Tertiary amber accent (`#FFD47B`).
- **Surfaces**:
  - `surfaceDeep`: Deepest panel and console background (`#0F131C`).
  - `surfaceBase`: Default card and drawer background (`#181B25`).
  - `surfaceHigh`: Elevated hover and active surface (`#262A34`).
  - `surfaceVariant`: Control track and neutral toggle background (`#31353F`).
  - `surface`: Floating glass panel surface with alpha (`#B30F131C`).
  - `card`: Elevated card container (`#CC1C1F29`).
  - `cardHover`: Hovered card container (`#E0262A34`).
  - `track`: Recessed well / telemetry container (`#0B1016`).
- **Outlines & Borders**:
  - `border`: Standard structural border (`#3C4A46`).
  - `outlineSoft` / `glassBorder`: Subtle hairline border (`#2F3A40`).
- **Text & Content**:
  - `textMain`: Primary readable text (`#DFE2EF`).
  - `textDim` / `textSecondary`: Secondary labels and captions (`#859490`).
  - `textMuted`: Muted metadata, unit labels, inactive glyphs (`#BACAC5`).
- **Semantic Status**:
  - `statusGood`: `#9CE5C0` (Success, charged, connected)
  - `statusWarn`: `#FFD47B` (Warning, battery low, pending)
  - `statusDanger`: `#FFB4AB` (Error, battery critical, danger)
  - `statusDangerBg`: `#3D1A26` / `statusDangerBorder`: `#FF4D6D` / `statusDangerFg`: `#FF5C77`

### Geometry Scale
- **Spacing**:
  - `spacingXs`: 4px
  - `spacingSm`: 8px
  - `spacingMd`: 12px
  - `spacingLg`: 16px
  - `spacingXl`: 24px
- **Corner Radii**:
  - `radiusXs`: 4px (badges, micro-indicators)
  - `radiusSm`: 8px (buttons, input fields, control rows)
  - `radiusMd`: 10px (compact cards, dialog buttons)
  - `radiusCard`: 14px (standard cards, popups)
  - `radiusDrawer`: 16px (large drawer panels)
  - `radiusPanel`: 18px (LeftRail capsules, full popups)
  - `radiusPill`: 999px (capsules, circular indicators, pills)
- **Border Widths**:
  - `borderWidth`: 1px (standard hairline)
  - `borderWidthThick`: 2px (focus and selection rings)
- **Component Heights**:
  - `controlHeightSm`: 24px (compact chips, mini-buttons)
  - `controlHeightMd`: 32px (standard buttons, inputs)
  - `controlHeightLg`: 40px (prominent buttons, cards)
  - `controlHeightXl`: 48px (primary action headers)
- **Standard Padding**:
  - `paddingSm`: 8px
  - `paddingMd`: 12px
  - `paddingLg`: 16px
  - `paddingXl`: 20px
- **Icon Sizes**:
  - `iconXs`: 12px
  - `iconSm`: 16px
  - `iconMd`: 20px
  - `iconLg`: 24px
  - `iconXl`: 32px

### Typography Scale
- `fontUi`: "Plus Jakarta Sans"
- `fontMono`: "JetBrains Mono"
- `fontSizeDisplay`: 22px (Bold)
- `fontSizeHeading`: 16px (SemiBold / Bold)
- `fontSizeSubheading`: 14px (SemiBold)
- `fontSizeBody`: 13px (Regular)
- `fontSizeSecondary`: 12px (Regular)
- `fontSizeCaption`: 10px (Regular / Medium)
- `fontSizeSmall`: 9px (Mono / Uppercase tracking)

### Motion & Effects
- `glassAlpha`: 0.72 | `glassAlphaElevated`: 0.85 | `glassAlphaSolid`: 0.95
- `borderAlpha`: 0.25 | `highlightAlpha`: 0.14 | `hoverAlpha`: 0.12
- `animFast`: 120ms | `animNormal`: 220ms | `animSlow`: 360ms | `animDuration`: 250ms
- `easingStandard`: Easing.OutCubic | `easingEmphasized`: Easing.OutQuint
