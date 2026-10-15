import Quickshell
import QtQuick
import qs.config

Rectangle {
    id: root

    property var hub: null
    readonly property bool horiz: root.hub !== null && root.hub.isHorizontal
    readonly property bool isSelected: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "clock"
    readonly property bool timerActive: root.hub !== null && root.hub.pomoRunning

    width: horiz ? (clockRow.implicitWidth + 16) : Theme.sideButtonSize
    height: horiz ? Theme.sideButtonSize : (clockCol.implicitHeight + 10)
    radius: Theme.radiusPill
    color: isSelected
        ? Theme.brandAccent
        : (clockMouse.containsMouse ? Theme.cardHover : Theme.card)
    border.width: 1
    border.color: (isSelected || timerActive) ? Theme.brandAccent : Theme.border

    Behavior on color { ColorAnimation { duration: 200 } }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Column {
        id: clockCol
        visible: !root.horiz
        anchors.centerIn: parent
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(sysClock.date, "hh")
            color: root.isSelected ? Theme.brandAccentFg : Theme.textMain
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(sysClock.date, "mm")
            color: root.isSelected ? Theme.brandAccentFg : Theme.brandAccent
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            visible: root.timerActive
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.hub ? root.hub.pomoShortText : ""
            color: root.isSelected ? Theme.brandAccentFg : Theme.statusGood
            font.family: Theme.fontMono
            font.pixelSize: 9
            font.bold: true
        }
    }

    Row {
        id: clockRow
        visible: root.horiz
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: Qt.formatTime(sysClock.date, "hh:mm")
            color: root.isSelected ? Theme.brandAccentFg : Theme.textMain
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            visible: root.timerActive
            text: "· " + (root.hub ? root.hub.pomoShortText : "")
            color: root.isSelected ? Theme.brandAccentFg : Theme.statusGood
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.bold: true
        }
    }

    MouseArea {
        id: clockMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.hub) root.hub.setTooltip(
            Qt.formatDate(sysClock.date, "ddd, dd MMM yyyy") + " · Click for Calendar & Pomodoro"
        )
        onExited: if (root.hub) root.hub.clearTooltip()
        onClicked: if (root.hub) root.hub.openPopup("clock")
    }
}
