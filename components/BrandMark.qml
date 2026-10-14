import Quickshell
import QtQuick
import qs.config

Rectangle {
    id: root

    property bool showTagline: false
    property bool interactive: true

    height: Theme.pillHeight
    width: brandRow.implicitWidth + 14
    radius: Theme.radiusPill
    color: (root.interactive && brandMouse.containsMouse) ? Theme.cardHover : Theme.card
    border.width: 1
    border.color: (root.interactive && brandMouse.containsMouse) ? Theme.brandAccent : Theme.border

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: brandRow
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            width: 18
            height: 18
            radius: Theme.radiusEmblem
            color: Theme.brandAccent
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "✦"
                color: Theme.brandAccentFg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSizeEmblem
                font.bold: true
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "GPS"
            color: Theme.textMain
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSizeGps
            font.bold: true
            font.letterSpacing: Theme.letterSpacingGps
        }

        Text {
            visible: root.showTagline
            anchors.verticalCenter: parent.verticalCenter
            text: "· Your space. Your rules."
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSizeTagline
        }
    }

    MouseArea {
        id: brandMouse
        enabled: root.interactive
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["fuzzel"])
    }
}
