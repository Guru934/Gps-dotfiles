import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

Rectangle {
    id: root

    property var hub: null
    readonly property bool horiz: root.hub !== null && root.hub.isHorizontal === true

    width: horiz ? (wsRow.implicitWidth + 12) : Theme.sideButtonSize
    height: horiz ? Theme.sideButtonSize : (wsCol.implicitHeight + 12)
    radius: Theme.radiusPill
    color: Theme.card
    border.width: 1
    border.color: Theme.border

    Behavior on color { ColorAnimation { duration: 250 } }
    Behavior on border.color { ColorAnimation { duration: 250 } }

    readonly property int currentWs: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id
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
        visible: !root.horiz
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: [1, 2, 3, 4, 5]

            Rectangle {
                id: wsVItem
                required property int modelData
                readonly property bool isFocused: root.currentWs === wsVItem.modelData
                readonly property bool isOccupied: root.isWorkspaceOccupied(wsVItem.modelData)

                width: 28
                height: isFocused ? 28 : 22
                radius: 7
                color: isFocused ? Theme.brandAccent : (wsVHover.hovered ? Theme.cardHover : "transparent")

                Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                HoverHandler { id: wsVHover }

                Text {
                    anchors.centerIn: parent
                    text: wsVItem.modelData
                    color: wsVItem.isFocused
                        ? Theme.brandAccentFg
                        : (wsVItem.isOccupied ? Theme.textMain : Theme.textMuted)
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.bold: true
                }

                Rectangle {
                    visible: wsVItem.isOccupied && !wsVItem.isFocused
                    width: 3
                    height: 8
                    radius: 1.5
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

    Row {
        id: wsRow
        visible: root.horiz
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: [1, 2, 3, 4, 5]

            Rectangle {
                id: wsHItem
                required property int modelData
                readonly property bool isFocused: root.currentWs === wsHItem.modelData
                readonly property bool isOccupied: root.isWorkspaceOccupied(wsHItem.modelData)

                width: isFocused ? 28 : 22
                height: 26
                radius: 7
                color: isFocused ? Theme.brandAccent : (wsHHover.hovered ? Theme.cardHover : "transparent")

                HoverHandler { id: wsHHover }

                Text {
                    anchors.centerIn: parent
                    text: wsHItem.modelData
                    color: wsHItem.isFocused
                        ? Theme.brandAccentFg
                        : (wsHItem.isOccupied ? Theme.textMain : Theme.textMuted)
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function selectFromPos(xPos, yPos) {
            const ratio = root.horiz
                ? Math.max(0.0, Math.min(0.999, (xPos - 6) / Math.max(1, root.width - 12)))
                : Math.max(0.0, Math.min(0.999, (yPos - 6) / Math.max(1, root.height - 12)))
            const ws = Math.floor(ratio * 5) + 1
            root.switchTo(ws)
        }

        onPressed: mouse => selectFromPos(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (pressed) selectFromPos(mouse.x, mouse.y)
        }
        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.switchTo(root.currentWs - 1)
            else if (event.angleDelta.y < 0)
                root.switchTo(root.currentWs + 1)
        }
    }
}
