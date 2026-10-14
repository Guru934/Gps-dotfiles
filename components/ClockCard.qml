import Quickshell
import QtQuick
import qs.config

Item {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    implicitWidth: clockTexts.implicitWidth
    implicitHeight: clockTexts.implicitHeight

    Column {
        id: clockTexts
        anchors.fill: parent
        spacing: Theme.spacingRightColumn

        Text {
            anchors.right: parent.right
            text: Qt.formatTime(clock.date, "hh:mm")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeClock
            font.bold: true
        }

        Text {
            anchors.right: parent.right
            text: Qt.formatDate(clock.date, "ddd, dd MMM")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeDate
        }
    }
}