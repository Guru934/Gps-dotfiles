pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Unified palette source: ~/.config/quickshell/gps-theme.json is written by
// scripts/set-wallpaper / extract-theme.py whenever the wallpaper changes.
// The shell watches that file live and smoothly transitions color tokens (~250ms).
// Anything missing falls back to safe design defaults so the shell always boots.
Singleton {
    id: root

    // Last successfully parsed live palette ({} until the file exists).
    property var live: ({})

    // Animation settings: 250ms transition by default, 0ms if reduced motion or animations disabled.
    property bool animationsEnabled: true
    readonly property bool reducedMotion: Quickshell.env("GPS_REDUCED_MOTION") === "1"
    readonly property int animDuration: (root.animationsEnabled && !root.reducedMotion) ? 250 : 0

    function applyLive(txt) {
        if (!txt || txt.trim() === "") return
        let j
        try {
            j = JSON.parse(txt)
        } catch (e) {
            // Keep previous colors if file is malformed or invalid
            return
        }
        if (!j || typeof j !== "object") return

        const pick = (k, fallback) => (typeof j[k] === "string" && j[k] !== "") ? j[k] : fallback
        const pickNum = (k, fallback) => (typeof j[k] === "number" && !isNaN(j[k])) ? j[k] : fallback
        root.live = {
            surface: pick("surface", root.live.surface),
            card: pick("card", root.live.card),
            cardHover: pick("cardHover", root.live.cardHover),
            track: pick("track", root.live.track),
            border: pick("border", root.live.border),
            brandAccent: pick("brandAccent", root.live.brandAccent),
            brandAccentFg: pick("brandAccentFg", root.live.brandAccentFg),
            textMain: pick("textMain", root.live.textMain),
            textMuted: pick("textMuted", root.live.textMuted),
            outlineSoft: pick("outlineSoft", root.live.outlineSoft),
            accentSecondary: pick("accentSecondary", root.live.accentSecondary),
            accentSecondaryDim: pick("accentSecondaryDim", root.live.accentSecondaryDim),
            accentTertiary: pick("accentTertiary", root.live.accentTertiary),
            leftLuminance: pickNum("leftLuminance", root.live.leftLuminance !== undefined ? root.live.leftLuminance : 0.20)
        }
    }

    function applySettings(txt) {
        if (!txt || txt.trim() === "") return
        try {
            const cfg = JSON.parse(txt)
            if (cfg && cfg.hypr && typeof cfg.hypr["animations:enabled"] === "boolean") {
                root.animationsEnabled = cfg.hypr["animations:enabled"]
            } else if (cfg && typeof cfg["animations:enabled"] === "boolean") {
                root.animationsEnabled = cfg["animations:enabled"]
            }
        } catch (e) {
            return
        }
    }

    FileView {
        id: themeFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/gps-theme.json"
        watchChanges: true
        onLoaded: root.applyLive(themeFile.text())
        onFileChanged: themeFile.reload()
    }

    FileView {
        id: riceSettingsFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/rice-settings.json"
        watchChanges: true
        onLoaded: root.applySettings(riceSettingsFile.text())
        onFileChanged: riceSettingsFile.reload()
    }

    // Preferred typography families
    readonly property string fontSansPreferred: "Plus Jakarta Sans"
    readonly property string fontMonoPreferred: "JetBrains Mono"
    readonly property string fontIconPreferred: "Material Symbols Rounded"

    // Functional installed fallbacks
    readonly property string fontSansFallback: "Noto Sans"
    readonly property string fontMonoFallback: "JetBrainsMono Nerd Font"
    readonly property string fontIconFallback: "Material Symbols Rounded"

    function resolveFont(preferred, fallbacks) {
        if (typeof Qt !== "undefined" && Qt.fontFamilies) {
            const list = Qt.fontFamilies()
            if (list.indexOf(preferred) >= 0) return preferred
            for (let i = 0; i < fallbacks.length; i++) {
                if (list.indexOf(fallbacks[i]) >= 0) return fallbacks[i]
            }
        }
        return fallbacks.length > 0 ? fallbacks[0] : preferred
    }

    readonly property string fontSans: root.resolveFont(root.fontSansPreferred, [root.fontSansFallback, "DejaVu Sans", "sans-serif"])
    readonly property string fontMono: root.resolveFont(root.fontMonoPreferred, [root.fontMonoFallback, "Noto Sans Mono", "monospace"])
    readonly property string fontIcon: root.resolveFont(root.fontIconPreferred, [root.fontIconFallback, "Material Symbols Outlined", "sans-serif"])

    // Preserved alias for backwards compatibility
    readonly property string fontUi: root.fontSans

    // Central logical-pixel scale for GPS surfaces. Change this one value to
    // adjust the shell without touching the compositor or Qt scale.
    readonly property real uiScale: 1.15

    function scaled(value) {
        return Math.round(value * root.uiScale)
    }

    // Core tokens: live wallpaper palette when available, design defaults otherwise.
    property color surface: root.live.surface !== undefined ? root.live.surface : "#B30F131C"
    Behavior on surface { ColorAnimation { duration: root.animDuration } }

    property color card: root.live.card !== undefined ? root.live.card : "#CC1C1F29"
    Behavior on card { ColorAnimation { duration: root.animDuration } }

    property color cardHover: root.live.cardHover !== undefined ? root.live.cardHover : "#E0262A34"
    Behavior on cardHover { ColorAnimation { duration: root.animDuration } }

    property color track: root.live.track !== undefined ? root.live.track : "#0B1016"
    Behavior on track { ColorAnimation { duration: root.animDuration } }

    property color border: root.live.border !== undefined ? root.live.border : "#3C4A46"
    Behavior on border { ColorAnimation { duration: root.animDuration } }

    property color brandAccent: root.live.brandAccent !== undefined ? root.live.brandAccent : "#2DD4BF"
    Behavior on brandAccent { ColorAnimation { duration: root.animDuration } }

    property color brandAccentFg: root.live.brandAccentFg !== undefined ? root.live.brandAccentFg : "#003731"
    Behavior on brandAccentFg { ColorAnimation { duration: root.animDuration } }

    readonly property color statusGood: "#9CE5C0"
    readonly property color statusWarn: "#FFD47B"
    readonly property color statusDanger: "#FFB4AB"

    property color textMain: root.live.textMain !== undefined ? root.live.textMain : "#DFE2EF"
    Behavior on textMain { ColorAnimation { duration: root.animDuration } }

    property color textMuted: root.live.textMuted !== undefined ? root.live.textMuted : "#BACAC5"
    Behavior on textMuted { ColorAnimation { duration: root.animDuration } }

    // Left wallpaper strip relative luminance (0.0 = black, 1.0 = white, 0.20 default fallback)
    property real leftLuminance: (root.live.leftLuminance !== undefined && typeof root.live.leftLuminance === "number") ? root.live.leftLuminance : 0.20
    Behavior on leftLuminance { NumberAnimation { duration: root.animDuration } }

    readonly property int sidebarWindowWidth: root.scaled(54)
    readonly property int sidebarBarWidth: root.scaled(54)
    readonly property int sidebarRailWidth: root.scaled(50)
    readonly property int sideButtonSize: root.scaled(38)
    readonly property int railControlSize: root.scaled(36)
    readonly property int railIconSize: root.scaled(19)
    readonly property int radiusPanel: root.scaled(18)
    readonly property int radiusPill: 999
    readonly property int radiusCard: root.scaled(14)

    // Dashboard v2 & additive tokens
    property color surfaceDeep: root.live.track !== undefined ? root.live.track : "#0F131C"
    Behavior on surfaceDeep { ColorAnimation { duration: root.animDuration } }

    property color surfaceBase: root.live.card !== undefined ? root.live.card : "#181B25"
    Behavior on surfaceBase { ColorAnimation { duration: root.animDuration } }

    property color surfaceHigh: root.live.cardHover !== undefined ? root.live.cardHover : "#262A34"
    Behavior on surfaceHigh { ColorAnimation { duration: root.animDuration } }

    readonly property color surfaceVariant: "#31353F"

    property color outlineSoft: root.live.outlineSoft !== undefined ? root.live.outlineSoft : (root.live.border !== undefined ? root.live.border : "#2F3A40")
    Behavior on outlineSoft { ColorAnimation { duration: root.animDuration } }

    property color accentPrimary: root.live.brandAccent !== undefined ? root.live.brandAccent : "#57F1DB"
    Behavior on accentPrimary { ColorAnimation { duration: root.animDuration } }

    property color accentPrimaryDim: Qt.darker(root.accentPrimary, 1.55)
    Behavior on accentPrimaryDim { ColorAnimation { duration: root.animDuration } }

    property color onAccent: root.live.brandAccentFg !== undefined ? root.live.brandAccentFg : "#003731"
    Behavior on onAccent { ColorAnimation { duration: root.animDuration } }

    readonly property color accentSecondary: "#DDB8FF"
    readonly property color accentSecondaryDim: "#62259B"
    readonly property color accentTertiary: "#FFD47B"

    property color textDim: root.live.textMuted !== undefined ? root.live.textMuted : "#859490"
    Behavior on textDim { ColorAnimation { duration: root.animDuration } }

    readonly property int radiusDrawer: root.scaled(16)
    readonly property int radiusControl: root.scaled(10)
    readonly property int dashboardWidth: root.scaled(480)

    // Dashboard-only content rhythm. These tokens keep the global UI scale
    // unchanged while giving the console panes room for readable telemetry.
    readonly property int dashboardFramePadding: root.scaled(18)
    readonly property int dashboardCardPadding: root.scaled(14)
    readonly property int dashboardSectionGap: root.scaled(14)
    readonly property int dashboardSpacingSm: root.scaled(8)
    readonly property int dashboardSpacingMd: root.scaled(12)
    readonly property int dashboardControlHeight: root.scaled(40)
    readonly property int dashboardTextCaption: root.scaled(9)
    readonly property int dashboardTextSmall: root.scaled(10)
    readonly property int dashboardTextBody: root.scaled(12)
    readonly property int dashboardTextHeading: root.scaled(15)
    readonly property int dashboardTextTitle: root.scaled(18)

    function dashboardText(baseSize) {
        return Math.round(baseSize * root.uiScale * 1.08)
    }

    // Surface-level geometry tokens for layouts that previously used local
    // pixel constants. Screen and edge bounds are still applied by each view.
    readonly property int powerPopupWidth: root.scaled(240)
    readonly property int systemPopupWidth: root.scaled(330)
    readonly property int trayPopupWidth: root.scaled(280)
    readonly property int notificationCenterWidth: root.scaled(380)
    readonly property int notificationCenterMaxHeight: root.scaled(640)
    readonly property int islandPanelWidth: root.scaled(560)
    readonly property int islandPanelHeight: root.scaled(580)
    readonly property int islandControlWidthExpanded: root.scaled(460)
    readonly property int islandControlWidthCompact: root.scaled(180)
    readonly property int islandControlHeightCompact: root.scaled(36)
    readonly property int islandControlMaxHeight: root.scaled(560)
    readonly property int islandLauncherWidth: root.scaled(520)
    readonly property int islandLauncherSearchHeight: root.scaled(44)

    // ──────────────── Canonical Design Tokens ────────────────
    // Semantic aliases
    readonly property color textSecondary: root.textDim
    readonly property color surfaceActive: root.cardHover
    readonly property color glassBorder: root.outlineSoft

    // Status state surfaces & borders
    readonly property color statusDangerBg: "#3D1A26"
    readonly property color statusDangerBorder: "#FF4D6D"
    readonly property color statusDangerFg: "#FF5C77"
    readonly property color statusSuccessBg: "#163328"
    readonly property color statusSuccessFg: "#9CE5C0"
    readonly property color statusWarnBg: "#3D2E14"
    readonly property color statusWarnFg: "#FFD47B"

    // Geometry — Spacing Scale
    readonly property int spacingXs: root.scaled(4)
    readonly property int spacingSm: root.scaled(8)
    readonly property int spacingMd: root.scaled(12)
    readonly property int spacingLg: root.scaled(16)
    readonly property int spacingXl: root.scaled(24)

    // Geometry — Corner Radius Scale
    readonly property int radiusXs: root.scaled(4)
    readonly property int radiusSm: root.scaled(8)
    readonly property int radiusMd: root.scaled(10)
    readonly property int radiusLg: root.scaled(14)
    readonly property int radiusXl: root.scaled(18)

    // Geometry — Border Widths
    readonly property int borderWidth: 1
    readonly property int borderWidthThick: 2

    // Geometry — Component Heights
    readonly property int controlHeightSm: root.scaled(24)
    readonly property int controlHeightMd: root.scaled(32)
    readonly property int controlHeightLg: root.scaled(40)
    readonly property int controlHeightXl: root.scaled(48)

    // Geometry — Padding Scale
    readonly property int paddingSm: root.scaled(8)
    readonly property int paddingMd: root.scaled(12)
    readonly property int paddingLg: root.scaled(16)
    readonly property int paddingXl: root.scaled(20)

    // Geometry — Icon Sizes
    readonly property int iconXs: root.scaled(12)
    readonly property int iconSm: root.scaled(16)
    readonly property int iconMd: root.scaled(20)
    readonly property int iconLg: root.scaled(24)
    readonly property int iconXl: root.scaled(32)

    // Typography Scale
    readonly property int fontSizeDisplay: root.scaled(22)
    readonly property int fontSizeHeading: root.scaled(16)
    readonly property int fontSizeSubheading: root.scaled(14)
    readonly property int fontSizeBody: root.scaled(13)
    readonly property int fontSizeSecondary: root.scaled(12)
    readonly property int fontSizeCaption: root.scaled(10)
    readonly property int fontSizeSmall: root.scaled(9)

    // Effects — Glass, Blur, Opacity, Shadow
    readonly property real glassAlpha: 0.72
    readonly property real glassAlphaElevated: 0.85
    readonly property real glassAlphaSolid: 0.95
    readonly property real borderAlpha: 0.25
    readonly property real highlightAlpha: 0.14
    readonly property real hoverAlpha: 0.12
    readonly property color shadowColor: "#80000000"
    readonly property int shadowRadius: 16
    readonly property int blurRadius: 16
    readonly property int blurPasses: 2

    // Motion — Durations and Easing
    readonly property int animFast: (root.animationsEnabled && !root.reducedMotion) ? 120 : 0
    readonly property int animNormal: (root.animationsEnabled && !root.reducedMotion) ? 220 : 0
    readonly property int animSlow: (root.animationsEnabled && !root.reducedMotion) ? 360 : 0
    readonly property int easingStandard: Easing.OutCubic
    readonly property int easingEmphasized: Easing.OutQuint
}
