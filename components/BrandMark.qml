import Quickshell
import QtQuick
import qs.config

Rectangle {
    id: root

    width: Theme.sideButtonSize
    height: Theme.sideButtonSize
    radius: Theme.radiusPill
    color: brandMouse.containsMouse ? Theme.cardHover : Theme.brandAccent
    border.width: 1
    border.color: Theme.brandAccent

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: "✦"
        color: brandMouse.containsMouse ? Theme.brandAccent : Theme.brandAccentFg
        font.family: Theme.fontUi
        font.pixelSize: 16
        font.bold: true
    }

    MouseArea {
        id: brandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "rofi", "-show", "drun"])
    }
}
