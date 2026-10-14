pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Typography (verified via fc-list)
    readonly property string fontUi: "Noto Sans"
    readonly property string fontMono: "JetBrainsMono Nerd Font Propo"

    // Core Surfaces & Borders
    readonly property color surface: "#E6161C2D"
    readonly property color card: "#1E2538"
    readonly property color cardHover: "#283149"
    readonly property color track: "#121622"
    readonly property color border: "#3A3A54"

    // Accents & Status Colors
    readonly property color brandAccent: "#EEB7D8"
    readonly property color brandAccentFg: "#242033"
    readonly property color statusGood: "#9CE5C0"
    readonly property color statusWarn: "#F5C17A"
    readonly property color statusDanger: "#F28FAD"

    // Semantic Text Hierarchy (plus legacy aliases)
    readonly property color textMain: "#F6F1FA"
    readonly property color textMuted: "#B9BBD0"
    readonly property color textPrimary: "#B9BBD0"
    readonly property color textOnAccent: "#F6F1FA"

    // Layout Metrics (1280x800 logical canvas)
    readonly property int panelWindowHeight: 50
    readonly property int panelBarHeight: 40
    readonly property int pillHeight: 28
    readonly property int radiusPanel: 13
    readonly property int radiusPill: 9
    readonly property int radiusCard: 10
    readonly property int radiusOverlay: 16
    readonly property int radiusEmblem: 6

    // Font Sizes
    readonly property int fontSizeGps: 12
    readonly property real letterSpacingGps: 1.2
    readonly property int fontSizeTagline: 12
    readonly property int fontSizeClock: 11
    readonly property int fontSizeDate: 11
    readonly property int fontSizeEmblem: 11
    readonly property int spacingLeftColumn: 3
    readonly property int spacingRightColumn: 2
}
