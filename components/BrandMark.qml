import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root

    width: 32
    height: 32
    radius: Theme.radiusPill
    color: brandMouse.containsMouse ? Theme.cardHover : Theme.brandAccent
    border.width: 1
    border.color: Theme.brandAccent

    Behavior on color { ColorAnimation { duration: 120 } }

    Image {
        anchors.centerIn: parent
        width: 20
        height: 20
        Layout.alignment: Qt.AlignHCenter
        source: Qt.resolvedUrl("../assets/rice-logo.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        scale: brandMouse.containsMouse ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    }

    MouseArea {
        id: brandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "rofi", "-show", "drun"])
    }
}
