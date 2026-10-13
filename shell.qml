
import Quickshell
import QtQuick

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
        radius: 22
        color: "#E6161C2D"
        border.width: 1
        border.color: "#3A3A54"

        Rectangle {
            id: emblem
            width: 44
            height: 44
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 18
            color: "#EEB7D8"

            Text {
                anchors.centerIn: parent
                text: "✦"
                color: "#242033"
                font.pixelSize: 24
            }
        }

        Column {
            anchors.left: emblem.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                text: "GPS"
                color: "#B9BBD0"
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
            }

            Text {
                text: "Your space. Your rules."
                color: "#F6F1FA"
                font.pixelSize: 18
                font.bold: true
            }
        }

        Column {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.right: parent.right
                text: root.clockText
                color: "#F6F1FA"
                font.pixelSize: 22
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                text: root.dateText
                color: "#B9BBD0"
                font.pixelSize: 11
            }
        }
    }
}
