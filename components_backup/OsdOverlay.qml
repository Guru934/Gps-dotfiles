import Quickshell
import QtQuick
import qs.config

PanelWindow {
    id: root

    required property var hub
    visible: root.hub !== null && root.hub.osdVisible

    anchors {
        bottom: true
    }

    exclusionMode: ExclusionMode.Ignore
    margins {
        bottom: 44
    }

    implicitWidth: 230
    implicitHeight: 46
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 23
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        Row {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hub ? root.hub.osdIcon : "󰕾"
                color: Theme.brandAccent
                font.family: Theme.fontMono
                font.pixelSize: 16
            }

            Rectangle {
                width: 116
                height: 8
                radius: 4
                color: Theme.track
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * Math.min(1.0, Math.max(0.0, (root.hub ? root.hub.osdValue : 0) / 100.0))
                    height: parent.height
                    radius: 4
                    color: Theme.brandAccent
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (root.hub ? root.hub.osdValue : 0) + "%"
                color: Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 12
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }
    }
}
