import QtQuick
import qs.config

// GPS Reusable Glass Card (Layer 3)
// Provides an elevated card surface with optional hover, selection, and click states.
Rectangle {
    id: root

    property bool interactive: false
    property bool selected: false
    property bool accentBorder: false
    property real cornerRadius: Theme.radiusCard
    property real borderWidth: Theme.borderWidth
    property color baseColor: Theme.card
    property color hoverColor: Theme.cardHover
    property color activeColor: Theme.surfaceHigh
    property color accentColor: Theme.brandAccent

    readonly property bool hovered: interactive && mouseArea.containsMouse
    readonly property bool pressed: interactive && mouseArea.pressed

    signal clicked()

    radius: cornerRadius
    border.width: borderWidth
    border.color: selected
        ? accentColor
        : (accentBorder
            ? (hovered ? Qt.alpha(accentColor, 0.6) : Qt.alpha(accentColor, 0.3))
            : (hovered ? Qt.lighter(Theme.outlineSoft, 1.25) : Theme.outlineSoft))

    color: pressed
        ? activeColor
        : (hovered ? hoverColor : baseColor)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
