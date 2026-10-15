import Quickshell
import QtQuick
import qs.config

PanelWindow {
    id: root

    required property var hub
    visible: root.hub !== null && root.hub.powerMenuOpen

    anchors {
        bottom: true
        left: true
    }

    exclusionMode: ExclusionMode.Ignore
    margins {
        bottom: 8
        left: 62
    }

    implicitWidth: 280
    implicitHeight: (root.hub && root.hub.pendingPowerAction !== "") ? 140 : 190
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusOverlay
        color: Theme.surface
        border.width: 1
        border.color: Theme.statusDanger

        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 10

            Text {
                text: (root.hub && root.hub.pendingPowerAction !== "")
                    ? "CONFIRM: " + root.hub.pendingPowerAction.toUpperCase() + "?"
                    : "󰐥 POWER MENU"
                color: Theme.statusDanger
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.1
            }

            Grid {
                visible: !root.hub || root.hub.pendingPowerAction === ""
                width: parent.width
                columns: 2
                spacing: 8

                Repeater {
                    model: [
                        { label: "Suspend", cmd: ["systemctl", "suspend"] },
                        { label: "Log out", cmd: ["hyprctl", "dispatch", "exit"] },
                        { label: "Restart", cmd: ["systemctl", "reboot"] },
                        { label: "Shut down", cmd: ["systemctl", "poweroff"] }
                    ]

                    Rectangle {
                        required property var modelData
                        width: (parent.width - 8) / 2
                        height: 34
                        radius: 8
                        color: pwrMouse.containsMouse ? Theme.cardHover : Theme.card
                        border.width: 1
                        border.color: pwrMouse.containsMouse ? Theme.statusDanger : Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: pwrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.hub) return
                                root.hub.pendingPowerAction = parent.modelData.label
                                root.hub.pendingPowerCmd = parent.modelData.cmd
                            }
                        }
                    }
                }
            }

            Row {
                visible: root.hub !== null && root.hub.pendingPowerAction !== ""
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 36
                    radius: 8
                    color: Theme.statusDanger

                    Text {
                        anchors.centerIn: parent
                        text: "Yes, " + (root.hub ? root.hub.pendingPowerAction : "")
                        color: Theme.brandAccentFg
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.hub) return
                            const cmd = root.hub.pendingPowerCmd
                            root.hub.pendingPowerAction = ""
                            root.hub.powerMenuOpen = false
                            Quickshell.execDetached(cmd)
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 36
                    radius: 8
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: "Back"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.hub) root.hub.pendingPowerAction = ""
                    }
                }
            }

            Rectangle {
                visible: !root.hub || root.hub.pendingPowerAction === ""
                width: parent.width
                height: 30
                radius: 8
                color: Theme.card
                border.width: 1
                border.color: Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.hub) root.hub.powerMenuOpen = false
                }
            }
        }
    }
}
