pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Unified palette source: ~/.config/quickshell/gps-theme.json is written by
// scripts/extract-theme.py whenever the wallpaper changes (run-gps startup,
// wallpaper carousel apply, Tools tab regenerate). The shell watches that
// file live and every mapped token follows it; anything missing falls back
// to the built-in design defaults so the shell always boots.
Singleton {
    id: root

    // Last successfully parsed live palette ({} until the file exists).
    property var live: ({})

    function applyLive(txt) {
        let j
        try { j = JSON.parse(txt) } catch (e) { return }
        const pick = k => (typeof j[k] === "string" && j[k] !== "") ? j[k] : undefined
        root.live = {
            surface: pick("surface"),
            card: pick("card"),
            cardHover: pick("cardHover"),
            track: pick("track"),
            border: pick("border"),
            brandAccent: pick("brandAccent"),
            brandAccentFg: pick("brandAccentFg"),
            textMain: pick("textMain"),
            textMuted: pick("textMuted")
        }
    }

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/quickshell/gps-theme.json"
        watchChanges: true
        onLoaded: root.applyLive(themeFile.text())
        onFileChanged: themeFile.reload()
    }

    readonly property string fontUi: "Plus Jakarta Sans"
    readonly property string fontMono: "JetBrains Mono"

    // Core tokens: live wallpaper palette when available, design defaults otherwise.
    readonly property color surface: root.live.surface !== undefined ? root.live.surface : "#B30F131C"
    readonly property color card: root.live.card !== undefined ? root.live.card : "#CC1C1F29"
    readonly property color cardHover: root.live.cardHover !== undefined ? root.live.cardHover : "#E0262A34"
    readonly property color border: root.live.border !== undefined ? root.live.border : "#3C4A46"
    readonly property color brandAccent: root.live.brandAccent !== undefined ? root.live.brandAccent : "#2DD4BF"
    readonly property color brandAccentFg: root.live.brandAccentFg !== undefined ? root.live.brandAccentFg : "#003731"
    readonly property color statusGood: "#9CE5C0"
    readonly property color statusWarn: "#FFD47B"
    readonly property color statusDanger: "#FFB4AB"
    readonly property color textMain: root.live.textMain !== undefined ? root.live.textMain : "#DFE2EF"
    readonly property color textMuted: root.live.textMuted !== undefined ? root.live.textMuted : "#BACAC5"

    readonly property int sidebarWindowWidth: 54
    readonly property int sidebarBarWidth: 54
    readonly property int sideButtonSize: 38
    readonly property int radiusPanel: 18
    readonly property int radiusPill: 999
    readonly property int radiusCard: 14

    // Dashboard v2 tokens (additive; existing tokens above are unchanged).
    // The accent + surface family follows the live wallpaper palette; semantic
    // status colors and secondary hues stay fixed by design.
    readonly property color surfaceDeep: root.live.track !== undefined ? root.live.track : "#0F131C"
    readonly property color surfaceBase: root.live.card !== undefined ? root.live.card : "#181B25"
    readonly property color surfaceHigh: root.live.cardHover !== undefined ? root.live.cardHover : "#262A34"
    readonly property color surfaceVariant: "#31353F"
    readonly property color outlineSoft: "#2F3A40"
    readonly property color accentPrimary: root.live.brandAccent !== undefined ? root.live.brandAccent : "#57F1DB"
    readonly property color accentPrimaryDim: Qt.darker(root.accentPrimary, 1.55)
    readonly property color onAccent: root.live.brandAccentFg !== undefined ? root.live.brandAccentFg : "#003731"
    readonly property color accentSecondary: "#DDB8FF"
    readonly property color accentSecondaryDim: "#62259B"
    readonly property color accentTertiary: "#FFD47B"
    readonly property color textDim: root.live.textMuted !== undefined ? root.live.textMuted : "#859490"
    readonly property int radiusDrawer: 16
    readonly property int radiusControl: 10
    readonly property int dashboardWidth: 440
}
