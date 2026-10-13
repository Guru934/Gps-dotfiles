
import Quickshell
import QtQuick
import qs.config as Config

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
        radius: Config.Theme.radiusPanel
        color: Config.Theme.surface
        border.width: 1
        border.color: Config.Theme.border

        Rectangle {
            id: emblem
            width: 44
            height: 44
            radius: Config.Theme.radiusEmblem
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 18
            color: Config.Theme.brandAccent

            Text {
                anchors.centerIn: parent
                text: "✦"
                color: Config.Theme.brandAccentFg
                font.pixelSize: Config.Theme.fontSizeEmblem
            }
        }

        Column {
            anchors.left: emblem.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.Theme.spacingLeftColumn

            Text {
                text: "GPS"
                color: Config.Theme.textPrimary
                font.pixelSize: Config.Theme.fontSizeGps
                font.bold: true
                font.letterSpacing: Config.Theme.letterSpacingGps
            }

            Text {
                text: "Your space. Your rules."
                color: Config.Theme.textOnAccent
                font.pixelSize: Config.Theme.fontSizeTagline
                font.bold: true
            }
        }

        Column {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.Theme.spacingRightColumn

            Text {
                anchors.right: parent.right
                text: root.clockText
                color: Config.Theme.textOnAccent
                font.pixelSize: Config.Theme.fontSizeClock
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                text: root.dateText
                color: Config.Theme.textPrimary
                font.pixelSize: Config.Theme.fontSizeDate
            }
        }
    }
}
