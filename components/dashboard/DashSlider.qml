import QtQuick
import qs.config

// Minimal horizontal slider. `value` is in [from, to]; dragging emits
// `moved` continuously so callers can apply live or debounce.
Item {
    id: root
    property real value: 0
    property real from: 0
    property real to: 1
    property bool interactive: true
    property color accent: Theme.accentPrimary

    signal moved(real value)

    implicitHeight: 22

    readonly property real fraction: root.to > root.from
        ? Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from)))
        : 0

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.surfaceVariant

        Rectangle {
            width: parent.width * root.fraction
            height: parent.height
            radius: parent.radius
            color: root.accent
        }
    }

    Rectangle {
        id: knob
        width: 12
        height: 12
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.width * root.fraction - width / 2))
        color: root.interactive ? Theme.textMain : Theme.textDim
        border.width: 2
        border.color: root.accent
        Behavior on x { enabled: !pointer.pressed; NumberAnimation { duration: 90 } }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function applyX(x) {
            const w = root.width
            const f = w > 0 ? Math.max(0, Math.min(1, x / w)) : 0
            const v = root.from + f * (root.to - root.from)
            root.value = v
            root.moved(v)
        }

        onPressed: (mouse) => applyX(mouse.x)
        onPositionChanged: (mouse) => {
            if (pressed) applyX(mouse.x)
        }
    }
}
