import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config

PanelWindow {
    id: root

    property var hub: null
    property bool open: false
    property string filter: "All"
    property string taskDraft: ""
    property var tasks: [
        { text: "Review shell.qml Phase 2 wiring", done: false },
        { text: "Check PipeWire volume telemetry", done: true },
        { text: "Commit notification drawer", done: false }
    ]
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
    function close() { root.open = false }
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

            Text { text: "ACTIVE NOTIFICATIONS"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2 }
            Column {
                width: parent.width
                spacing: 6
                NotificationCard { category: "POMODORO"; summary: "Focus session complete"; detail: "Time for a 5-min breather! 🍵"; action: "Start Break"; onActionClicked: if (root.hub) root.hub.toastVisible = true }
                NotificationCard { category: "GITHUB"; summary: "Phase 2 is ready for review"; detail: "notif-center changes are unstaged"; action: "View Diff" }
                NotificationCard { category: "PIPEWIRE"; summary: "Output device connected"; detail: "Default sink is ready"; action: "Dismiss" }
            }
        }
    }

    component NotificationCard: Rectangle {
        property string category: "SYSTEM"
        property string summary: ""
        property string detail: ""
        property string action: "Dismiss"
        signal actionClicked()
        width: parent ? parent.width : 320
        height: 62
        radius: 10
        color: Theme.card
        border.width: 1
        border.color: Theme.border
        Column {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { text: category; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }
            Text { text: summary; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
            Text { text: detail; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9; elide: Text.ElideRight; width: 190 }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: actionText.implicitWidth + 14; height: 24; radius: Theme.radiusPill
            color: Theme.brandAccent
            Text { id: actionText; anchors.centerIn: parent; text: action; color: Theme.brandAccentFg; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true }
            MouseArea { anchors.fill: parent; onClicked: actionClicked() }
        }
    }
}
