import QtQuick
import qs.config

Item {
    id: root

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    property string dateText: Qt.formatDate(new Date(), "ddd, dd MMM")

    implicitWidth: clockTexts.implicitWidth
    implicitHeight: clockTexts.implicitHeight

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: {
            root.clockText = Qt.formatTime(new Date(), "hh:mm")
            root.dateText = Qt.formatDate(new Date(), "ddd, dd MMM")
        }
    }

    Column {
        id: clockTexts
        anchors.fill: parent
        spacing: Theme.spacingRightColumn

        Text {
            anchors.right: parent.right
            text: root.clockText
            color: Theme.textOnAccent
            font.pixelSize: Theme.fontSizeClock
            font.bold: true
        }

        Text {
            anchors.right: parent.right
            text: root.dateText
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeDate
        }
    }
}
