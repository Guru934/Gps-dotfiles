import QtQuick
import qs.config

// GPS Reusable Glass Surface (Layer 2)
// Provides a floating glass panel with subtle hairline outline and depth.
Rectangle {
    id: root

    property bool elevated: false
    property real cornerRadius: Theme.radiusPanel
    property real borderWidth: Theme.borderWidth
    property color borderColor: Theme.outlineSoft
    property color baseColor: elevated ? Theme.card : Theme.surface
    property bool highlight: true

    radius: cornerRadius
    color: baseColor
    border.width: borderWidth
    border.color: borderColor

    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

    // Subtle top-left hairline highlight for physical glass depth
    Rectangle {
        id: innerHighlight
        visible: root.highlight
        anchors.fill: parent
        anchors.margins: root.borderWidth
        radius: Math.max(0, root.radius - root.borderWidth)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, Theme.highlightAlpha * 0.4)
    }
}
