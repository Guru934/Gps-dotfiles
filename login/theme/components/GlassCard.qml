import QtQuick
import "../Theme.js" as Theme

Rectangle {
    id: root

    property color baseColor: Theme.palette.surface
    property color borderColor: Theme.palette.outlineSoft
    property real borderWidth: 1
    property real cornerRadius: 16

    color: baseColor
    radius: cornerRadius
    border.color: borderColor
    border.width: borderWidth

    // Subtle dark glow / border highlight
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        anchors.margins: 1
    }
}
