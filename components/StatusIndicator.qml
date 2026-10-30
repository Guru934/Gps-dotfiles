import QtQuick
import QtQuick.Layouts
import qs.config

// GPS Reusable Status Indicator
// Provides consistent status dots, optional labels, and subtle pulse feedback.
RowLayout {
    id: root

    property string status: "good" // "good" | "warn" | "danger" | "info" | "muted"
    property string label: ""
    property real dotSize: 8
    property bool pulse: false
    property color customColor: "transparent"

    spacing: Theme.spacingSm

    readonly property color statusColor: {
        if (customColor !== "transparent" && customColor.a > 0) return customColor
        switch (status) {
        case "good": return Theme.statusGood
        case "warn": return Theme.statusWarn
        case "danger": return Theme.statusDanger
        case "info": return Theme.brandAccent
        case "muted":
        default:
            return Theme.textMuted
        }
    }

    Item {
        implicitWidth: root.dotSize + (root.pulse ? 4 : 0)
        implicitHeight: root.dotSize + (root.pulse ? 4 : 0)
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            id: pulseHalo
            visible: root.pulse
            anchors.centerIn: parent
            width: root.dotSize + 4
            height: root.dotSize + 4
            radius: width / 2
            color: root.statusColor
            opacity: 0.35

            SequentialAnimation on opacity {
                running: root.pulse
                loops: Animation.Infinite
                NumberAnimation { from: 0.45; to: 0.10; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.10; to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
            }
        }

        Rectangle {
            id: dot
            anchors.centerIn: parent
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: root.statusColor

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }
    }

    Text {
        visible: root.label !== ""
        text: root.label
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fontSizeSecondary
        Layout.alignment: Qt.AlignVCenter
    }
}
