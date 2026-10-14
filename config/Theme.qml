pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property color surface: "#E6161C2D"
    readonly property color border: "#3A3A54"
    readonly property int radiusPanel: 22
    readonly property int radiusEmblem: 14
    readonly property color brandAccent: "#EEB7D8"
    readonly property color brandAccentFg: "#242033"
    readonly property color textPrimary: "#F6F1FA"
    readonly property color textOnAccent: "#F6F1FA"
    readonly property int fontSizeGps: 10
    readonly property real letterSpacingGps: 1.5
    readonly property int fontSizeTagline: 18
    readonly property int fontSizeClock: 22
    readonly property int fontSizeDate: 11
    readonly property int fontSizeEmblem: 24
    readonly property int spacingLeftColumn: 3
    readonly property int spacingRightColumn: 2
    readonly property color textSecondary: "#B9BBD0"
}