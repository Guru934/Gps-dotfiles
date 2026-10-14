import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

PanelWindow {
    id: root

    property var hub: null

    // Only visible when the focused workspace has no active window
    visible: Hyprland.activeToplevel === null
        && (!root.hub || (!root.hub.dashboardOpen && !root.hub.powerMenuOpen))

    anchors {
        bottom: true
        left: true
    }

    exclusionMode: ExclusionMode.Ignore
    margins {
        bottom: 24
        left: 24
    }

    implicitWidth: 270
    implicitHeight: 64
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Row {
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 12

            Rectangle {
                width: 38
                height: 38
                radius: 10
                color: Theme.brandAccent
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "✦"
                    color: Theme.brandAccentFg
                    font.family: Theme.fontUi
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "GPS DESKTOP"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: "Your space. Your rules."
                    color: Theme.brandAccent
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }
    }
}
