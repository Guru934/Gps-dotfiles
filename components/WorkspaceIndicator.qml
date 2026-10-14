import Quickshell.Hyprland
import QtQuick
import qs.config

Rectangle {
    id: root

    height: Theme.pillHeight
    width: wsRow.implicitWidth + 10
    radius: Theme.radiusPill
    color: Theme.card
    border.width: 1
    border.color: Theme.border

    function isWorkspaceOccupied(wsId) {
        const list = Hyprland.workspaces.values
        if (!list) return false
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === wsId) return true
        }
        return false
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: [1, 2, 3, 4, 5]

            Rectangle {
                required property int modelData
                readonly property bool isFocused: Hyprland.focusedWorkspace !== null
                    && Hyprland.focusedWorkspace.id === modelData
                readonly property bool isOccupied: root.isWorkspaceOccupied(modelData)

                width: isFocused ? 30 : 22
                height: 22
                radius: 6
                color: isFocused
                    ? Theme.brandAccent
                    : (wsMouse.containsMouse ? Theme.cardHover : "transparent")

                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (parent.isOccupied && !parent.isFocused) ? -2 : 0
                    text: parent.modelData
                    color: parent.isFocused
                        ? Theme.brandAccentFg
                        : (parent.isOccupied ? Theme.textMain : Theme.textMuted)
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.bold: parent.isFocused || parent.isOccupied
                }

                // Sleek 8x2px underline bar that never collides with the digit
                Rectangle {
                    visible: parent.isOccupied && !parent.isFocused
                    width: 8
                    height: 2
                    radius: 1
                    color: Theme.brandAccent
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 2
                        horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + parent.modelData)
                    onWheel: event => {
                        if (event.angleDelta.y > 0)
                            Hyprland.dispatch("workspace e-1")
                        else if (event.angleDelta.y < 0)
                            Hyprland.dispatch("workspace e+1")
                    }
                }
            }
        }
    }
}
