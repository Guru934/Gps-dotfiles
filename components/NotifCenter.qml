import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.config

PanelWindow {
    id: root

    property var hub: null
    property bool open: false
    property string filter: "All"
    property string taskDraft: ""
    property var tasks: []

    // Live notification history + DND state from Tide Island (the single
    // notification daemon). Polled while the center is open - never faked.
    property var islandItems: []
    property bool islandFocus: false
    readonly property string repoRoot: (root.hub && root.hub.repoRoot)
        ? root.hub.repoRoot
        : (Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice"))
    readonly property string ipcScript: root.repoRoot + "/scripts/gps-ipc"

    readonly property string notifHistoryPath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
        return stateHome + "/gps/notifications.json"
    }

    FileView {
        path: root.notifHistoryPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = text()
                if (textData && textData.trim().length > 0) {
                    const parsed = JSON.parse(textData)
                    if (parsed && Array.isArray(parsed.entries)) {
                        root.islandItems = parsed.entries.slice(0, 30)
                    }
                }
            } catch (e) {}
        }
    }

    function parseIslandHistory(raw) {
        try {
            const d = JSON.parse(raw)
            root.islandFocus = !!d.focus
            root.islandItems = (d.items || []).slice(0, 30)
        } catch (e) {}
    }
    function refreshIsland() {
        if (!islandHistoryProc.running) islandHistoryProc.running = true
    }
    function toggleIslandFocus() {
        Quickshell.execDetached([root.ipcScript, "island", "focusToggle"])
        islandSyncTimer.restart()
    }
    function openIslandCenter() {
        Quickshell.execDetached([root.ipcScript, "island", "control", "open"])
    }
    function timeAgo(ts) {
        if (!ts) return ""
        const s = Math.max(0, Math.floor((Date.now() - ts) / 1000))
        if (s < 60) return s + "s ago"
        if (s < 3600) return Math.floor(s / 60) + "m ago"
        if (s < 86400) return Math.floor(s / 3600) + "h ago"
        return Math.floor(s / 86400) + "d ago"
    }

    Process {
        id: islandHistoryProc
        command: [root.ipcScript, "island", "history"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseIslandHistory(text)
        }
    }
    Timer {
        id: islandSyncTimer
        interval: 700
        repeat: false
        onTriggered: root.refreshIsland()
    }
    Timer {
        interval: 3000
        repeat: true
        running: root.open
        onTriggered: root.refreshIsland()
    }
    onOpenChanged: if (root.open) root.refreshIsland()
    readonly property var weekDays: {
        const today = new Date()
        const mondayOffset = (today.getDay() + 6) % 7
        const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - mondayOffset)
        const result = []
        for (let i = 0; i < 7; i++) {
            const day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
            result.push({
                label: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][i],
                number: day.getDate(),
                today: day.toDateString() === today.toDateString()
            })
        }
        return result
    }
    readonly property var visibleTasks: {
        if (root.filter === "Pending") return root.tasks.filter(task => !task.done)
        if (root.filter === "Done") return root.tasks.filter(task => task.done)
        return root.tasks
    }

    function toggle() { root.open = !root.open }
    function close() {
        taskInput.focus = false
        root.open = false
    }
    function addTask() {
        const value = root.taskDraft.trim()
        if (!value) return
        root.tasks = root.tasks.concat([{ text: value, done: false }])
        root.taskDraft = ""
    }
    function toggleTask(taskText) {
        const next = root.tasks.slice()
        const index = next.findIndex(task => task.text === taskText)
        if (index < 0) return
        const task = next[index]
        next[index] = { text: task.text, done: !task.done }
        root.tasks = next
    }

    Timer {
        id: autoCloseTimer
        interval: 350
        repeat: false
        onTriggered: root.close()
    }

    anchors { top: true; bottom: true; left: true }
    margins { left: 60 }
    implicitWidth: 360
    color: "transparent"
    visible: root.open
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut { sequence: "Super+N"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.open; onActivated: root.close() }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        onVisibleChanged: {
            if (!visible) taskInput.focus = false
        }

        MouseArea {
            anchors.fill: parent
            z: 20
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: autoCloseTimer.stop()
            onExited: autoCloseTimer.start()
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Row {
                width: parent.width
                spacing: 8
                Text { text: "NOTIFICATION CENTER"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 13; font.bold: true }
                Item { width: parent.width - 170; height: 1 }
                Text { text: "ESC"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
            }

            Row {
                width: parent.width
                spacing: 5
                Repeater {
                    model: root.weekDays
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 30) / 7
                        height: 54
                        radius: Theme.radiusPill
                        color: modelData.today ? Theme.brandAccent : Theme.card
                        border.width: 1
                        border.color: modelData.today ? Theme.brandAccent : Theme.border
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: modelData.today ? Theme.brandAccentFg : Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.number; color: modelData.today ? Theme.brandAccentFg : Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 15; font.bold: true }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 6
                Repeater {
                    model: ["All", "Pending", "Done"]
                    delegate: Rectangle {
                        required property string modelData
                        width: filterText.implicitWidth + 18
                        height: 26
                        radius: Theme.radiusPill
                        color: root.filter === modelData ? Theme.brandAccent : Theme.card
                        Text { id: filterText; anchors.centerIn: parent; text: modelData; color: root.filter === modelData ? Theme.brandAccentFg : Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.filter = modelData }
                    }
                }
            }

            Row {
                width: parent.width
                height: 34
                spacing: 6
                Rectangle {
                    width: parent.width - addButton.width - 6
                    height: parent.height
                    radius: 9
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border
                    TextInput {
                        id: taskInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        text: root.taskDraft
                        onTextChanged: root.taskDraft = text
                        Keys.onReturnPressed: root.addTask()
                    }
                    Text {
                        anchors.fill: taskInput
                        verticalAlignment: Text.AlignVCenter
                        text: "Add an objective…"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        visible: taskInput.text.length === 0 && !taskInput.activeFocus
                    }
                }
                Rectangle {
                    id: addButton
                    width: 34; height: 34; radius: 9
                    color: Theme.brandAccent
                    Text { anchors.centerIn: parent; text: "+"; color: Theme.brandAccentFg; font.pixelSize: 20 }
                    MouseArea { anchors.fill: parent; onClicked: root.addTask() }
                }
            }

            Text { text: "DAILY OBJECTIVES"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2 }
            ListView {
                id: taskList
                width: parent.width
                height: 112
                spacing: 6
                clip: true
                model: root.visibleTasks
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: taskList.width
                    height: 32
                    radius: 8
                    color: Theme.card
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 8
                        Rectangle { width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter; radius: 5; color: modelData.done ? Theme.brandAccent : "transparent"; border.width: 1; border.color: modelData.done ? Theme.brandAccent : Theme.textMuted; Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"; color: Theme.brandAccentFg; font.pixelSize: 11; font.bold: true } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; color: modelData.done ? Theme.textMuted : Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.strikeout: modelData.done; elide: Text.ElideRight; width: parent.width - 34 }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.toggleTask(modelData.text) }
                }
            }
            Text {
                visible: root.visibleTasks.length === 0
                text: "No objectives yet — add one above."
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 9
            }

            Text { text: "FOCUS MODE (DO NOT DISTURB)"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2 }
            Row {
                width: parent.width
                height: 34
                spacing: 6
                Rectangle {
                    width: parent.width - islandCenterButton.width - 6
                    height: parent.height
                    radius: 9
                    color: root.islandFocus ? Theme.brandAccent : Theme.card
                    border.width: 1
                    border.color: root.islandFocus ? Theme.brandAccent : Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: root.islandFocus ? "Notifications paused — click to resume" : "Notifications active — click to pause"
                        color: root.islandFocus ? Theme.brandAccentFg : Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        font.bold: true
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleIslandFocus() }
                }
                Rectangle {
                    id: islandCenterButton
                    width: 102
                    height: parent.height
                    radius: 9
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border
                    Text { anchors.centerIn: parent; text: "Open Center"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openIslandCenter() }
                }
            }

            Text { text: "RECENT NOTIFICATIONS"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2 }
            ListView {
                id: islandList
                width: parent.width
                height: 132
                spacing: 6
                clip: true
                model: root.islandItems
                delegate: NotificationCard {
                    app: modelData.app || "NOTIFICATION"
                    summary: modelData.summary
                    detail: modelData.body
                    when: root.timeAgo(modelData.ts)
                }
            }
            Text {
                visible: root.islandItems.length === 0
                text: "No notifications yet — real ones from any app appear here."
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 9
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }
    }

    component NotificationCard: Rectangle {
        property string app: "NOTIFICATION"
        property string summary: ""
        property string detail: ""
        property string when: ""
        width: parent ? parent.width : 320
        height: 58
        radius: 10
        color: Theme.card
        border.width: 1
        border.color: Theme.border
        Column {
            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Row {
                spacing: 6
                Text { text: app; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }
                Text { text: when; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 }
            }
            Text { text: summary; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true; width: parent.width; elide: Text.ElideRight }
            Text { visible: detail !== ""; text: detail; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9; width: parent.width; elide: Text.ElideRight }
        }
    }
}
