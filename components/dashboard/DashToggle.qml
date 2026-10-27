import QtQuick
import qs.config

// Compact pill switch. State is owned by the caller: the signal is emitted
// after the local `checked` flips, callers may also bind `checked` directly.
Item {
    id: root
    property bool checked: false
    property color accent: Theme.accentPrimary

    signal toggled(bool checked)

    implicitWidth: 44
    implicitHeight: 24

    function toggle() {
        root.checked = !root.checked
        root.toggled(root.checked)
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.accent : Theme.surfaceVariant
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            id: knob
            width: 18
            height: 18
            radius: 9
            y: 3
            x: root.checked ? track.width - width - 3 : 3
            color: root.checked ? Theme.onAccent : Theme.textDim
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }
}
