import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

Rectangle {
    id: root

    width: Theme.sideButtonSize
    height: wsCol.implicitHeight + 10
    radius: Theme.radiusPill
    color: Theme.card
    border.width: 1
    border.color: Theme.border

    readonly property int currentWs: (Hyprland.focusedWorkspace !== null)
        ? Hyprland.focusedWorkspace.id
        : 1

    function isWorkspaceOccupied(wsId) {
        const list = Hyprland.workspaces.values
        if (!list) return false
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === wsId) return true
        }
        return false
    }

    function switchTo(targetId) {
        const clamped = Math.max(1, Math.min(5, targetId))
        if (clamped !== root.currentWs) {
            Hyprland.dispatch("workspace " + clamped)
        }
    }

    Column {
        id: wsCol
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: [1, 2, 3, 4, 5]

            Rectangle {
                required property int modelData
                readonly property bool isFocused: root.currentWs === modelData
                readonly property bool isOccupied: root.isWorkspaceOccupied(modelData)

                width: 26
                height: isFocused ? 28 : 22
                radius: 6
                color: isFocused
                    ? Theme.brandAccent
                    : (wsHover.hovered ? Theme.cardHover : "transparent")

                Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 110 } }

                HoverHandler { id: wsHover }

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.isFocused
                        ? Theme.brandAccentFg
                        : (parent.isOccupied ? Theme.textMain : Theme.textMuted)
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.bold: parent.isFocused || parent.isOccupied
                }

                Rectangle {
                    visible: parent.isOccupied && !parent.isFocused
                    width: 2
                    height: 8
                    radius: 1
                    color: Theme.brandAccent
                    anchors {
                        left: parent.left
                        leftMargin: 2
                        verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function selectFromY(yPos) {
            const ratio = Math.max(0.0, Math.min(0.999, (yPos - 5) / Math.max(1, root.height - 10)))
            const ws = Math.floor(ratio * 5) + 1
            root.switchTo(ws)
        }

        onPressed: mouse => selectFromY(mouse.y)
        onPositionChanged: mouse => {
            if (pressed) selectFromY(mouse.y)
        }
        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.switchTo(root.currentWs - 1)
            else if (event.angleDelta.y < 0)
                root.switchTo(root.currentWs + 1)
        }
    }
}
