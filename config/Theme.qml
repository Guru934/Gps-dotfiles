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
            outlineSoft: pick("outlineSoft", root.live.outlineSoft)
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

    readonly property string fontUi: "Plus Jakarta Sans"
    readonly property string fontMono: "JetBrains Mono"

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

    readonly property int sidebarWindowWidth: 54
    readonly property int sidebarBarWidth: 54
    readonly property int sideButtonSize: 38
    readonly property int radiusPanel: 18
    readonly property int radiusPill: 999
    readonly property int radiusCard: 14

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

    readonly property int radiusDrawer: 16
    readonly property int radiusControl: 10
    readonly property int dashboardWidth: 440
}
