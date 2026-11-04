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

    property bool completed: false
    Component.onCompleted: root.completed = true

    // Event epoch counter incremented whenever Hyprland reports workspace/window changes.
    // This enables purely event-driven property updates without any polling or timers.
    property int dataEpoch: 0
    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) {
            root.dataEpoch++
        }
        function onFocusedWorkspaceChanged() {
            root.dataEpoch++
        }
        function onActiveToplevelChanged() {
            root.dataEpoch++
        }
    }

    readonly property int currentWs: {
        const _ = root.dataEpoch
        return (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id)
            ? Hyprland.focusedWorkspace.id
            : 1
    }

    readonly property int targetIndex: Math.max(0, Math.min(root.workspaceCount - 1, root.currentWs - 1))

    function isWorkspaceOccupied(wsId) {
        const _ = root.dataEpoch
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        if (list) {
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === wsId) {
                    if (list[i].toplevels && list[i].toplevels.values) {
                        return list[i].toplevels.values.length > 0
                    }
                    if (list[i].lastIpcObject && list[i].lastIpcObject.windows !== undefined) {
                        return list[i].lastIpcObject.windows > 0
                    }
                    if (list[i].windows !== undefined) {
                        return list[i].windows > 0
                    }
                    return true
                }
            }
        }
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
        if (toplevels) {
            for (let j = 0; j < toplevels.length; j++) {
                const tl = toplevels[j]
                if (tl && tl.workspace && tl.workspace.id === wsId) {
                    return true
                }
            }
        }
        return false
    }

    function isWorkspaceUrgent(wsId) {
        const _ = root.dataEpoch
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        if (list) {
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === wsId && list[i].urgent) {
                    return true
                }
            }
        }
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
        if (toplevels) {
            for (let j = 0; j < toplevels.length; j++) {
                const tl = toplevels[j]
                if (tl && tl.urgent && tl.workspace && tl.workspace.id === wsId) {
                    return true
                }
            }
        }
        return false
    }

    function workspaceName(wsId) {
        const _ = root.dataEpoch
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        if (list) {
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === wsId && list[i].name) return list[i].name
            }
        }
        return "" + wsId
    }

    function workspaceTooltipText(wsId) {
        const _ = root.dataEpoch
        const name = root.workspaceName(wsId)
        const apps = []
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
        if (toplevels) {
            for (let i = 0; i < toplevels.length; i++) {
                const tl = toplevels[i]
                if (tl && tl.workspace && tl.workspace.id === wsId) {
                    let app = ""
                    if (tl.wayland && tl.wayland.appId) {
                        app = tl.wayland.appId
                    } else if (tl.lastIpcObject && (tl.lastIpcObject.initialClass || tl.lastIpcObject.class)) {
                        app = tl.lastIpcObject.initialClass || tl.lastIpcObject.class
                    } else if (tl.title) {
                        app = tl.title
                    }
                    if (app) {
                        const parts = app.split(".")
                        let base = parts[parts.length - 1]
                        if (base.length > 0) {
                            base = base.charAt(0).toUpperCase() + base.slice(1)
                        }
                        if (apps.indexOf(base) === -1) {
                            apps.push(base)
                        }
                    }
                }
            }
        }
        const label = (name !== "" && name !== ("" + wsId))
            ? ("Workspace " + wsId + " (" + name + ")")
            : ("Workspace " + wsId)

        if (apps.length > 0) {
            return label + " · " + apps.join(", ")
        }
        return label + " · Empty"
    }

    function switchTo(targetId) {
        const clamped = Math.max(1, Math.min(root.workspaceCount, targetId))
        if (clamped !== root.currentWs) {
            if (Hyprland.usingLua) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + clamped + " })")
            } else {
                Hyprland.dispatch("workspace " + clamped)
            }
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

    readonly property int slotSize: Theme.railControlSize

    // Active morphing pill with soft neon glow that smoothly glides between workspaces
    Item {
        id: activeIndicator
        width: 24
        height: 28
        anchors.horizontalCenter: parent.horizontalCenter
        z: 1

        y: wsCol.y + root.targetIndex * (root.slotSize + wsCol.spacing) + (root.slotSize - height) / 2

        Behavior on y {
            enabled: root.completed && Theme.animationsEnabled && !Theme.reducedMotion
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
                easing.overshoot: 1.25
            }
        }

        // Soft outer glow
        Rectangle {
            id: activeGlow
            anchors.centerIn: parent
            width: parent.width + 6
            height: parent.height + 6
            radius: 12
            color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.32)
            z: 0

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }

        // Solid rounded pill
        Rectangle {
            id: activePill
            anchors.fill: parent
            radius: 9
            color: Theme.brandAccent
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.30)
            z: 1

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }

            Text {
                anchors.centerIn: parent
                text: "" + root.currentWs
                color: Theme.brandAccentFg
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
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
                readonly property bool isUrgent: root.isWorkspaceUrgent(dotItem.wsId)

                width: root.slotSize
                height: root.slotSize

                // Slot background on hover
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: (workspaceHover.containsMouse && !dotItem.isActive)
                        ? Theme.surfaceVariant
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Urgent pulse ring
                Rectangle {
                    id: urgentRing
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 9
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.statusWarn
                    visible: dotItem.isUrgent && !dotItem.isActive
                    opacity: 0.8

                    SequentialAnimation on opacity {
                        running: dotItem.isUrgent && !dotItem.isActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 0.15; duration: 550; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.15; to: 0.8; duration: 550; easing.type: Easing.InOutQuad }
                    }
                    SequentialAnimation on scale {
                        running: dotItem.isUrgent && !dotItem.isActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.9; to: 1.35; duration: 550; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.35; to: 0.9; duration: 550; easing.type: Easing.InOutQuad }
                    }
                }

                // Workspace shape (hollow diamond for empty, filled accent diamond for occupied)
                Rectangle {
                    id: dotShape
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    rotation: 45
                    radius: 1.5

                    // Diamond fills with accent when occupied, transparent when empty
                    color: dotItem.isOccupied ? Theme.brandAccent : "transparent"
                    border.width: dotItem.isOccupied ? 0 : 1.5
                    border.color: dotItem.isOccupied
                        ? "transparent"
                        : (workspaceHover.containsMouse
                            ? Theme.textMain
                            : Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.40))

                    // Smoothly fade out when this workspace is active (covered by active pill)
                    opacity: dotItem.isActive ? 0.0 : 1.0

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                    // Gentle pulse when urgent
                    SequentialAnimation {
                        running: dotItem.isUrgent && !dotItem.isActive
                        loops: Animation.Infinite
                        ParallelAnimation {
                            NumberAnimation { target: dotShape; property: "scale"; to: 1.35; duration: 450; easing.type: Easing.InOutQuad }
                            ColorAnimation { target: dotShape; property: "color"; to: Theme.statusWarn; duration: 450 }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: dotShape; property: "scale"; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
                            ColorAnimation { target: dotShape; property: "color"; to: dotItem.isOccupied ? Theme.brandAccent : "transparent"; duration: 450 }
                        }
                    }
                }

                MouseArea {
                    id: workspaceHover
                    anchors.fill: parent
                    z: 2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        const text = root.workspaceTooltipText(dotItem.wsId)
                        if (root.rail && root.rail.showRailTooltip) {
                            root.rail.showRailTooltip(text, dotItem)
                        }
                    }
                    onExited: {
                        if (root.rail && root.rail.hideRailTooltip) {
                            root.rail.hideRailTooltip()
                        }
                    }
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
