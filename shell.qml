
import Quickshell
import QtQuick
import qs.config
import qs.components

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 94
    color: "transparent"
    exclusiveZone: 0

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    property string dateText: Qt.formatDate(new Date(), "ddd, dd MMM")

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: {
            root.clockText = Qt.formatTime(new Date(), "hh:mm")
            root.dateText = Qt.formatDate(new Date(), "ddd, dd MMM")
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 12
            leftMargin: 16
            rightMargin: 16
        }

        height: 70
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        BrandMark {
            id: brandMark
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 18
        }

        Column {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
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
}
