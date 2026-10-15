pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string fontUi: "Noto Sans"
    readonly property string fontMono: "JetBrainsMono Nerd Font Propo"

    readonly property color surface: "#E6161C2D"
    readonly property color card: "#1E2538"
    readonly property color cardHover: "#283149"
    readonly property color track: "#121622"
    readonly property color border: "#3A3A54"

    readonly property color brandAccent: "#EEB7D8"
    readonly property color brandAccentFg: "#242033"
    readonly property color statusGood: "#9CE5C0"
    readonly property color statusWarn: "#F5C17A"
    readonly property color statusDanger: "#F28FAD"

    readonly property color textMain: "#F6F1FA"
    readonly property color textMuted: "#B9BBD0"
    readonly property color textPrimary: "#B9BBD0"
    readonly property color textOnAccent: "#F6F1FA"

    // Left Vertical Dock Metrics
    readonly property int sidebarWindowWidth: 58
    readonly property int sidebarBarWidth: 46
    readonly property int sideButtonSize: 34
    readonly property int radiusPanel: 14
    readonly property int radiusPill: 9
    readonly property int radiusCard: 10
    readonly property int radiusOverlay: 16
    readonly property int radiusEmblem: 8
}
