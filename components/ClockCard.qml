import Quickshell
import QtQuick
import qs.config

Rectangle {
    id: root

    height: Theme.pillHeight
    width: clockRow.implicitWidth + 14
    radius: Theme.radiusPill
    color: Theme.card
    border.width: 1
    border.color: Theme.border

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Row {
        id: clockRow
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(sysClock.date, "ddd, dd MMM")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSizeDate
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "·"
            color: Theme.brandAccent
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(sysClock.date, "hh:mm")
            color: Theme.textMain
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeClock
            font.bold: true
            font.features: { "tnum": 1 }
        }
    }
}
