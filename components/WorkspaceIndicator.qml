import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

Rectangle {
    id: root

    property var hub: null
    property var rail: null
    property int workspaceCount: 5

    width: Theme.railControlSize
    height: wsCol.implicitHeight + Theme.spacingMd
    radius: 14
    color: Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.40)
    border.width: 1
    border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)

    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

    readonly property int currentWs: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id
        ? Hyprland.focusedWorkspace.id
        : 1

    function isWorkspaceOccupied(wsId) {
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        if (!list) return false
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === wsId) {
                return list[i].windows !== undefined ? list[i].windows > 0 : true
            }
        }
        return false
    }

    function workspaceName(wsId) {
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        if (list) {
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === wsId && list[i].name) return list[i].name
            }
        }
        return "" + wsId
    }

    function switchTo(targetId) {
        const clamped = Math.max(1, Math.min(root.workspaceCount, targetId))
        if (clamped !== root.currentWs) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + clamped + " })")
        }
    }

    property real lastWheelTime: 0
    function handleWheel(deltaY) {
        const now = Date.now()
        if (now - lastWheelTime < 120) return
        lastWheelTime = now
        if (deltaY > 0) {
            if (root.currentWs > 1) {
                root.switchTo(root.currentWs - 1)
            }
        } else if (deltaY < 0) {
            if (root.currentWs < root.workspaceCount) {
                root.switchTo(root.currentWs + 1)
            }
        }
    }

    Column {
        id: wsCol
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        Repeater {
            model: root.workspaceCount

            Item {
                id: dotItem
                required property int index
                readonly property int wsId: dotItem.index + 1
                readonly property bool isActive: root.currentWs === dotItem.wsId
                readonly property bool isOccupied: root.isWorkspaceOccupied(dotItem.wsId)


                width: Theme.railControlSize
                height: Theme.railControlSize

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: dotItem.isActive
                        ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.16)
                        : (workspaceHover.containsMouse ? Theme.surfaceVariant : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Rectangle {
                    id: dotPill
                    anchors.centerIn: parent
                    width: dotItem.isActive ? 6 : 5
                    height: dotItem.isActive ? 16 : 5
                    radius: 3
                    color: dotItem.isActive
                        ? Theme.brandAccent
                        : (dotItem.isOccupied
                            ? Theme.textMain
                            : Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.35))

                    Behavior on height {
                        enabled: Theme.animationsEnabled && !Theme.reducedMotion
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on width {
                        enabled: Theme.animationsEnabled && !Theme.reducedMotion
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                }

                MouseArea {
                    id: workspaceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        if (root.hub) {
                            const name = root.workspaceName(dotItem.wsId)
                            const text = "Workspace " + dotItem.wsId + (name !== ("" + dotItem.wsId) ? (" · " + name) : "")
                            if (root.rail && root.rail.showRailTooltip) root.rail.showRailTooltip(text, dotItem)
                        }
                    }
                    onExited: if (root.rail && root.rail.hideRailTooltip) root.rail.hideRailTooltip()
                    onClicked: root.switchTo(dotItem.wsId)
                    onWheel: event => root.handleWheel(event.angleDelta.y)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onWheel: event => root.handleWheel(event.angleDelta.y)
    }
}
