import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.config
import "NotifCenterLogic.js" as NotifCenterLogic
import "PlannerLogic.js" as PlannerLogic

PanelWindow {
    id: root

    property var hub: null
    property bool open: false
    property int currentSection: 0 // 0: Inbox, 1: Planner, 2: Modes
    property string searchQuery: ""
    property string activeAppFilter: "All"
    property bool unreadOnly: false
    property var expandedCardMap: ({})

    // Undo state for "Clear all"
    property bool undoActive: false
    property int undoSeconds: 5
    property var stashBeforeClear: []

    // Live notification history + DND state
    property var islandItems: []
    property bool dndActive: false
    property var dndState: null
    readonly property int unreadCount: NotifCenterLogic.getUnreadCount(root.islandItems)
    readonly property var appNames: NotifCenterLogic.getAppNames(root.islandItems)

    readonly property string repoRoot: (root.hub && root.hub.repoRoot)
        ? root.hub.repoRoot
        : (Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice"))
    readonly property string ipcScript: root.repoRoot + "/scripts/gps-ipc"

    readonly property string notifHistoryPath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
        return stateHome + "/gps/notifications.json"
    }

    readonly property string notifDndPath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
        return stateHome + "/gps/dnd.json"
    }

    readonly property string plannerPath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
        return stateHome + "/gps/planner.json"
    }

    // Planner State
    property var plannerTasks: []
    property int selectedYear: new Date().getFullYear()
    property int selectedMonthIndex: new Date().getMonth()
    property string selectedDateKey: PlannerLogic.formatDateKey(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())
    readonly property string todayKey: PlannerLogic.formatDateKey(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())
    property string taskFilterMode: "All" // "All", "Pending", "Done"
    property string taskDraftText: ""
    property string taskDraftTime: ""
    property string editingTaskId: ""
    property string editingTaskDraft: ""

    readonly property var taskDotsMap: PlannerLogic.getTaskDotsMap(root.plannerTasks)
    readonly property var monthCells: PlannerLogic.getMonthDays(root.selectedYear, root.selectedMonthIndex, root.selectedDateKey, Date.now())
    readonly property var selectedDayTasks: PlannerLogic.filterTasks(root.plannerTasks, root.selectedDateKey, root.taskFilterMode)
    readonly property int carriedPendingCount: {
        let count = 0
        for (let i = 0; i < root.plannerTasks.length; i++) {
            const t = root.plannerTasks[i]
            if (!t.done && t.dateKey < root.todayKey) count++
        }
        return count
    }

    FileView {
        path: root.plannerPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = text()
                root.plannerTasks = PlannerLogic.deserialize(textData)
            } catch (e) {
                root.plannerTasks = []
            }
        }
    }

    function savePlanner() {
        const raw = PlannerLogic.serialize(root.plannerTasks)
        const script = 'd="$(dirname "$1")" && mkdir -m 0700 -p "$d" && tmp="${d}/.$(basename "$1").tmp.$$" && (umask 077 && printf "%s\\n" "$2" > "$tmp") && chmod 0600 "$tmp" && mv -f "$tmp" "$1"'
        Quickshell.execDetached(["sh", "-c", script, "sh", root.plannerPath, raw])
    }

    function checkReminders() {
        const due = PlannerLogic.getDueReminders(root.plannerTasks, Date.now())
        if (due.length === 0) return
        for (let i = 0; i < due.length; i++) {
            const t = due[i]
            Quickshell.execDetached(["notify-send", "-a", "Planner", "Task Reminder", t.text])
        }
        const dueIds = due.map(d => d.id)
        root.plannerTasks = PlannerLogic.markRemindersSent(root.plannerTasks, dueIds)
        root.savePlanner()
    }

    Timer {
        id: reminderTimer
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.checkReminders()
    }

    function prevMonth() {
        if (root.selectedMonthIndex === 0) {
            root.selectedYear--
            root.selectedMonthIndex = 11
        } else {
            root.selectedMonthIndex--
        }
    }

    function nextMonth() {
        if (root.selectedMonthIndex === 11) {
            root.selectedYear++
            root.selectedMonthIndex = 0
        } else {
            root.selectedMonthIndex++
        }
    }

    function jumpToday() {
        const d = new Date()
        root.selectedYear = d.getFullYear()
        root.selectedMonthIndex = d.getMonth()
        root.selectedDateKey = PlannerLogic.formatDateKey(d.getFullYear(), d.getMonth(), d.getDate())
    }

    function selectDate(key, yr, mo) {
        root.selectedDateKey = key
        root.selectedYear = yr
        root.selectedMonthIndex = mo
    }

    function addPlannerTask() {
        const t = PlannerLogic.createTask(root.taskDraftText, root.taskDraftTime, root.selectedDateKey)
        if (!t) return
        root.plannerTasks = PlannerLogic.addTask(root.plannerTasks, t)
        root.taskDraftText = ""
        root.taskDraftTime = ""
        root.savePlanner()
        root.checkReminders()
    }

    function toggleTask(id) {
        root.plannerTasks = PlannerLogic.toggleTaskDone(root.plannerTasks, id)
        root.savePlanner()
    }

    function deleteTask(id) {
        root.plannerTasks = PlannerLogic.deleteTask(root.plannerTasks, id)
        root.savePlanner()
    }

    function carryUnfinished() {
        const res = PlannerLogic.carryUnfinishedToToday(root.plannerTasks, root.todayKey)
        if (res.carriedCount > 0) {
            root.plannerTasks = res.updatedTasks
            root.savePlanner()
        }
    }

    function startEditTask(task) {
        root.editingTaskId = task.id
        root.editingTaskDraft = task.text
    }

    function commitEditTask() {
        if (!root.editingTaskId) return
        root.plannerTasks = PlannerLogic.editTask(root.plannerTasks, root.editingTaskId, { text: root.editingTaskDraft })
        root.editingTaskId = ""
        root.editingTaskDraft = ""
        root.savePlanner()
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
                        root.islandItems = parsed.entries
                    }
                }
            } catch (e) {}
        }
    }

    FileView {
        path: root.notifDndPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = text()
                if (textData && textData.trim().length > 0) {
                    const parsed = JSON.parse(textData)
                    root.dndState = parsed
                    root.dndActive = parsed.mode === "dnd" || parsed.mode === "snooze" || (parsed.schedule && parsed.schedule.enabled)
                }
            } catch (e) {}
        }
    }

    function timeAgo(ts) {
        return NotifCenterLogic.timeAgo(ts, Date.now())
    }

    function toggle() { root.open = !root.open }
    function close() { root.open = false }

    function refreshIsland() {
        if (!islandHistoryProc.running) islandHistoryProc.running = true
    }

    function dismissNotif(id) {
        Quickshell.execDetached([root.ipcScript, "notify", "dismiss", "" + id])
    }

    function invokeAction(id, actionKey) {
        Quickshell.execDetached([root.ipcScript, "notify", "action", "" + id, actionKey])
    }

    function markRead(id) {
        Quickshell.execDetached([root.ipcScript, "notify", "markread", "" + id])
    }

    function startUndoClear() {
        root.stashBeforeClear = root.islandItems.slice()
        root.undoActive = true
        root.undoSeconds = 5
        undoCountdownTimer.restart()
    }

    function cancelUndo() {
        root.undoActive = false
        undoCountdownTimer.stop()
        root.stashBeforeClear = []
    }

    function commitClear() {
        root.undoActive = false
        undoCountdownTimer.stop()
        root.stashBeforeClear = []
        Quickshell.execDetached([root.ipcScript, "notify", "clear"])
    }

    function clearGroup(groupName) {
        const remaining = NotifCenterLogic.clearGroupFromEntries(root.islandItems, groupName, Date.now())
        // Dismiss IDs that were removed
        const toRemove = root.islandItems.filter(e => !remaining.some(r => r.id === e.id))
        for (let i = 0; i < toRemove.length; i++) {
            root.dismissNotif(toRemove[i].id)
        }
    }

    function toggleExpandCard(id) {
        const copy = Object.assign({}, root.expandedCardMap)
        copy[id] = !copy[id]
        root.expandedCardMap = copy
    }

    Process {
        id: islandHistoryProc
        command: [root.ipcScript, "island", "history"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d && Array.isArray(d.items)) {
                        root.islandItems = d.items
                    }
                    if (d && typeof d.dnd !== "undefined") {
                        root.dndActive = !!d.dnd
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: undoCountdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.undoSeconds > 1) {
                root.undoSeconds--
            } else {
                root.commitClear()
            }
        }
    }

    Timer {
        id: markReadOnOpenTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.open && root.unreadCount > 0) {
                root.markRead(0)
            }
        }
    }

    onOpenChanged: {
        if (root.open) {
            root.refreshIsland()
            markReadOnOpenTimer.restart()
        } else {
            markReadOnOpenTimer.stop()
        }
    }

    readonly property var activeEntries: root.undoActive ? [] : root.islandItems

    readonly property var filteredEntries: NotifCenterLogic.filterEntries(root.activeEntries, {
        query: root.searchQuery,
        appFilter: root.activeAppFilter,
        unreadOnly: root.unreadOnly
    })

    readonly property var groupedEntries: NotifCenterLogic.groupEntriesByDay(root.filteredEntries, Date.now())

    // 80% of 800 logical screen height is 640px
    readonly property int maxDrawerHeight: Math.min(640, Math.floor(Screen.height * 0.80))
    readonly property int calculatedContentHeight: Math.min(root.maxDrawerHeight, Math.max(320, mainCol.implicitHeight + 36))

    anchors { top: true; left: true }
    margins {
        left: 60
        top: Math.max(20, Math.floor((Screen.height - root.calculatedContentHeight) / 2))
    }
    implicitWidth: 380
    implicitHeight: root.calculatedContentHeight
    color: "transparent"
    visible: root.open
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut { sequence: "Super+N"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.open; onActivated: root.close() }
    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; enabled: root.open; onActivated: root.currentSection = 0 }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; enabled: root.open; onActivated: root.currentSection = 1 }
    Shortcut { sequence: "3"; context: Qt.ApplicationShortcut; enabled: root.open; onActivated: root.currentSection = 2 }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        Column {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // Header: Title, unread count badge, clear all, ESC
            RowLayout {
                width: parent.width
                spacing: 8

                Text {
                    text: "NOTIFICATIONS"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.bold: true
                }

                Rectangle {
                    visible: root.unreadCount > 0
                    radius: 6
                    color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.40)
                    implicitWidth: unreadText.implicitWidth + 10
                    implicitHeight: 18

                    Text {
                        id: unreadText
                        anchors.centerIn: parent
                        text: root.unreadCount + " unread"
                        color: Theme.brandAccent
                        font.family: Theme.fontUi
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true; height: 1 }

                // Clear all button (only shown in Inbox tab when entries exist)
                Rectangle {
                    visible: root.currentSection === 0 && root.activeEntries.length > 0 && !root.undoActive
                    radius: 6
                    color: clearMa.containsMouse ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: clearMa.containsMouse ? Theme.border : "transparent"
                    implicitWidth: clearRow.implicitWidth + 12
                    implicitHeight: 22

                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: "󰆴"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Clear all"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startUndoClear()
                    }
                }

                // Esc indicator / close button
                Rectangle {
                    width: 22
                    height: 22
                    radius: 6
                    color: escMa.containsMouse ? Theme.surfaceAlt : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.textMuted; font.pixelSize: 11 }
                    MouseArea {
                        id: escMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // Segmented switch (Inbox / Planner / Modes)
            Rectangle {
                width: parent.width
                height: 32
                radius: Theme.radiusPill
                color: Theme.card
                border.width: 1
                border.color: Theme.border

                Row {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: [
                            { label: "Inbox", badge: root.unreadCount > 0 ? ("" + root.unreadCount) : "" },
                            { label: "Planner", badge: "" },
                            { label: "Modes", badge: root.dndActive ? "󰂛" : "" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            width: (parent.width - 4) / 3
                            height: parent.height
                            radius: Theme.radiusPill
                            color: root.currentSection === index ? Theme.brandAccent : (tabMa.containsMouse ? Theme.surfaceAlt : "transparent")

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !Theme.reducedMotion
                                ColorAnimation { duration: Theme.animDuration }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: modelData.label
                                    color: root.currentSection === index ? Theme.brandAccentFg : (tabMa.containsMouse ? Theme.textMain : Theme.textMuted)
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    visible: modelData.badge !== ""
                                    radius: 6
                                    color: root.currentSection === index ? Qt.rgba(0,0,0,0.2) : Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.2)
                                    implicitWidth: tabBadgeText.implicitWidth + 8
                                    implicitHeight: 14
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: tabBadgeText
                                        anchors.centerIn: parent
                                        text: modelData.badge
                                        color: root.currentSection === index ? Theme.brandAccentFg : Theme.brandAccent
                                        font.family: Theme.fontMono
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentSection = index
                            }
                        }
                    }
                }
            }

            // Undo Banner
            Rectangle {
                visible: root.undoActive
                width: parent.width
                height: 38
                radius: 8
                color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.15)
                border.width: 1
                border.color: Theme.brandAccent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "Cleared all notifications"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Rectangle {
                        radius: 6
                        color: Theme.brandAccent
                        implicitWidth: undoBtnText.implicitWidth + 14
                        implicitHeight: 24

                        Text {
                            id: undoBtnText
                            anchors.centerIn: parent
                            text: "Undo (" + root.undoSeconds + "s)"
                            color: Theme.brandAccentFg
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelUndo()
                        }
                    }
                }
            }

            // SECTION 0: INBOX
            Column {
                visible: root.currentSection === 0
                width: parent.width
                spacing: 10

                // Search Bar
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: Theme.card
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.brandAccent : Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: "󰍉"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            text: root.searchQuery
                            onTextChanged: root.searchQuery = text
                        }

                        Text {
                            visible: root.searchQuery === "" && !searchInput.activeFocus
                            text: "Search notifications…"
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                        }

                        Text {
                            visible: root.searchQuery !== ""
                            text: "✕"
                            color: Theme.textMuted
                            font.pixelSize: 10
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.searchQuery = ""
                                    searchInput.text = ""
                                }
                            }
                        }
                    }
                }

                // Filter chips: All, Unread, + apps
                Flickable {
                    width: parent.width
                    height: 26
                    contentWidth: chipsRow.implicitWidth
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: chipsRow
                        spacing: 6

                        // "All" chip
                        Rectangle {
                            height: 24
                            radius: Theme.radiusPill
                            implicitWidth: chipAllText.implicitWidth + 16
                            color: (root.activeAppFilter === "All" && !root.unreadOnly) ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: (root.activeAppFilter === "All" && !root.unreadOnly) ? Theme.brandAccent : Theme.border

                            Text {
                                id: chipAllText
                                anchors.centerIn: parent
                                text: "All"
                                color: (root.activeAppFilter === "All" && !root.unreadOnly) ? Theme.brandAccentFg : Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeAppFilter = "All"
                                    root.unreadOnly = false
                                }
                            }
                        }

                        // "Unread" chip
                        Rectangle {
                            height: 24
                            radius: Theme.radiusPill
                            implicitWidth: chipUnreadText.implicitWidth + 16
                            color: root.unreadOnly ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: root.unreadOnly ? Theme.brandAccent : Theme.border

                            Text {
                                id: chipUnreadText
                                anchors.centerIn: parent
                                text: "Unread" + (root.unreadCount > 0 ? (" (" + root.unreadCount + ")") : "")
                                color: root.unreadOnly ? Theme.brandAccentFg : Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.unreadOnly = !root.unreadOnly
                                    if (root.unreadOnly) root.activeAppFilter = "All"
                                }
                            }
                        }

                        // Per-app chips
                        Repeater {
                            model: root.appNames
                            delegate: Rectangle {
                                required property string modelData
                                height: 24
                                radius: Theme.radiusPill
                                implicitWidth: appChipText.implicitWidth + 16
                                color: (root.activeAppFilter === modelData && !root.unreadOnly) ? Theme.brandAccent : Theme.card
                                border.width: 1
                                border.color: (root.activeAppFilter === modelData && !root.unreadOnly) ? Theme.brandAccent : Theme.border

                                Text {
                                    id: appChipText
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: (root.activeAppFilter === modelData && !root.unreadOnly) ? Theme.brandAccentFg : Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.unreadOnly = false
                                        root.activeAppFilter = (root.activeAppFilter === modelData) ? "All" : modelData
                                    }
                                }
                            }
                        }
                    }
                }

                // Scrollable Notifications Feed
                Flickable {
                    id: inboxFlickable
                    width: parent.width
                    height: Math.max(120, Math.min(380, root.maxDrawerHeight - 210))
                    contentHeight: inboxFeedCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Column {
                        id: inboxFeedCol
                        width: parent.width
                        spacing: 12

                        // Friendly Empty State
                        Column {
                            visible: root.filteredEntries.length === 0
                            width: parent.width
                            spacing: 8
                            topPadding: 32
                            bottomPadding: 32

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰂚"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 36
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.searchQuery ? "No matching notifications" : "All caught up"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.searchQuery ? "Try a different search term" : "No new notifications right now."
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                            }
                        }

                        // TODAY GROUP
                        GroupSection {
                            title: "TODAY"
                            groupName: "today"
                            entries: root.groupedEntries.today
                            visible: entries.length > 0
                        }

                        // YESTERDAY GROUP
                        GroupSection {
                            title: "YESTERDAY"
                            groupName: "yesterday"
                            entries: root.groupedEntries.yesterday
                            visible: entries.length > 0
                        }

                        // EARLIER GROUP
                        GroupSection {
                            title: "EARLIER"
                            groupName: "earlier"
                            entries: root.groupedEntries.earlier
                            visible: entries.length > 0
                        }
                    }
                }
            }

            // SECTION 1: PLANNER
            Column {
                visible: root.currentSection === 1
                width: parent.width
                spacing: 10

                // Calendar Month Card
                Rectangle {
                    width: parent.width
                    implicitHeight: calCol.implicitHeight + 16
                    radius: 10
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        id: calCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        spacing: 8

                        // Month Navigation Header
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 4
                                color: prevMoMa.containsMouse ? Theme.surfaceAlt : "transparent"
                                Text { anchors.centerIn: parent; text: "󰅁"; color: Theme.textMain; font.family: Theme.fontMono; font.pixelSize: 13 }
                                MouseArea {
                                    id: prevMoMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.prevMonth()
                                }
                            }

                            Text {
                                text: {
                                    const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
                                    return (months[root.selectedMonthIndex] || "") + " " + root.selectedYear
                                }
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 4
                                color: nextMoMa.containsMouse ? Theme.surfaceAlt : "transparent"
                                Text { anchors.centerIn: parent; text: "󰅂"; color: Theme.textMain; font.family: Theme.fontMono; font.pixelSize: 13 }
                                MouseArea {
                                    id: nextMoMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.nextMonth()
                                }
                            }

                            Item { Layout.fillWidth: true; height: 1 }

                            // Today button
                            Rectangle {
                                radius: 4
                                color: todayBtnMa.containsMouse ? Theme.surfaceAlt : "transparent"
                                border.width: 1
                                border.color: Theme.border
                                implicitWidth: todayBtnText.implicitWidth + 10
                                implicitHeight: 20

                                Text {
                                    id: todayBtnText
                                    anchors.centerIn: parent
                                    text: "Today"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    id: todayBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.jumpToday()
                                }
                            }
                        }

                        // Day of week headers (Monday first)
                        Row {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                delegate: Item {
                                    required property string modelData
                                    width: (parent.width - 12) / 7
                                    height: 16
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // Grid of month days
                        Grid {
                            width: parent.width
                            columns: 7
                            spacing: 2

                            Repeater {
                                model: root.monthCells
                                delegate: Rectangle {
                                    required property var modelData
                                    width: (parent.width - 12) / 7
                                    height: 24
                                    radius: 6
                                    color: modelData.isSelected ? Theme.brandAccent : (dayMa.containsMouse ? Theme.surfaceAlt : "transparent")
                                    border.width: modelData.isToday ? 1.5 : 0
                                    border.color: Theme.brandAccent

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "" + modelData.dayNumber
                                            color: modelData.isSelected ? Theme.brandAccentFg : (modelData.isOtherMonth ? Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.45) : Theme.textMain)
                                            font.family: Theme.fontUi
                                            font.pixelSize: 10
                                            font.bold: modelData.isSelected || modelData.isToday || !modelData.isOtherMonth
                                        }

                                        // Task dot indicator
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            readonly property var dotsInfo: root.taskDotsMap[modelData.dateKey]
                                            visible: !!dotsInfo && dotsInfo.total > 0
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: {
                                                if (modelData.isSelected) return Theme.brandAccentFg
                                                if (dotsInfo && dotsInfo.pending > 0) return Theme.brandAccent
                                                return Theme.textMuted
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: dayMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectDate(modelData.dateKey, modelData.year, modelData.monthIndex)
                                    }
                                }
                            }
                        }
                    }
                }

                // Selected Day Header & Actions
                RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: {
                            const parsed = PlannerLogic.parseDateKey(root.selectedDateKey)
                            if (!parsed) return root.selectedDateKey
                            const d = new Date(parsed.year, parsed.monthIndex, parsed.day)
                            const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                            const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                            return (days[d.getDay()] || "") + ", " + (months[d.getMonth()] || "") + " " + d.getDate()
                        }
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Rectangle {
                        radius: 4
                        color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.15)
                        implicitWidth: dayTaskCountText.implicitWidth + 8
                        implicitHeight: 16

                        Text {
                            id: dayTaskCountText
                            anchors.centerIn: parent
                            text: root.selectedDayTasks.length + " tasks"
                            color: Theme.brandAccent
                            font.family: Theme.fontUi
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    // Carry unfinished to today button
                    Rectangle {
                        visible: root.carriedPendingCount > 0
                        radius: 5
                        color: carryMa.containsMouse ? Qt.rgba(Theme.accentWarning.r, Theme.accentWarning.g, Theme.accentWarning.b, 0.25) : Qt.rgba(Theme.accentWarning.r, Theme.accentWarning.g, Theme.accentWarning.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.accentWarning.r, Theme.accentWarning.g, Theme.accentWarning.b, 0.40)
                        implicitWidth: carryText.implicitWidth + 10
                        implicitHeight: 20

                        Row {
                            id: carryText
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: "󰁔"; color: Theme.accentWarning; font.family: Theme.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Carry (" + root.carriedPendingCount + ") to today"; color: Theme.accentWarning; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        }

                        MouseArea {
                            id: carryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.carryUnfinished()
                        }
                    }
                }

                // Filter pills: All | Pending | Done
                Row {
                    spacing: 6
                    Repeater {
                        model: ["All", "Pending", "Done"]
                        delegate: Rectangle {
                            required property string modelData
                            height: 22
                            radius: Theme.radiusPill
                            implicitWidth: filterPillText.implicitWidth + 14
                            color: root.taskFilterMode === modelData ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: root.taskFilterMode === modelData ? Theme.brandAccent : Theme.border

                            Text {
                                id: filterPillText
                                anchors.centerIn: parent
                                text: modelData
                                color: root.taskFilterMode === modelData ? Theme.brandAccentFg : Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 9
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.taskFilterMode = modelData
                            }
                        }
                    }
                }

                // Add Task Row
                RowLayout {
                    width: parent.width
                    height: 32
                    spacing: 6

                    // Text Input
                    Rectangle {
                        Layout.fillWidth: true
                        height: parent.height
                        radius: 7
                        color: Theme.card
                        border.width: 1
                        border.color: taskTextInput.activeFocus ? Theme.brandAccent : Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            TextInput {
                                id: taskTextInput
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                text: root.taskDraftText
                                onTextChanged: root.taskDraftText = text
                                Keys.onReturnPressed: root.addPlannerTask()
                            }

                            Text {
                                visible: root.taskDraftText === "" && !taskTextInput.activeFocus
                                text: "Add a task for this day…"
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                            }
                        }
                    }

                    // Optional Time Input
                    Rectangle {
                        width: 54
                        height: parent.height
                        radius: 7
                        color: Theme.card
                        border.width: 1
                        border.color: timeTextInput.activeFocus ? Theme.brandAccent : Theme.border

                        TextInput {
                            id: timeTextInput
                            anchors.fill: parent
                            anchors.margins: 4
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textMain
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            maximumLength: 5
                            text: root.taskDraftTime
                            onTextChanged: root.taskDraftTime = text
                            Keys.onReturnPressed: root.addPlannerTask()
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.taskDraftTime === "" && !timeTextInput.activeFocus
                            text: "HH:MM"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                        }
                    }

                    // Add Button
                    Rectangle {
                        width: 32
                        height: parent.height
                        radius: 7
                        color: Theme.brandAccent

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Theme.brandAccentFg
                            font.pixelSize: 18
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addPlannerTask()
                        }
                    }
                }

                // Tasks List
                Flickable {
                    width: parent.width
                    height: Math.max(100, Math.min(220, root.maxDrawerHeight - 400))
                    contentHeight: tasksCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: tasksCol
                        width: parent.width
                        spacing: 6

                        // Friendly empty state
                        Text {
                            visible: root.selectedDayTasks.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 16
                            bottomPadding: 16
                            text: "No tasks for this day. Add one above!"
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                        }

                        Repeater {
                            model: root.selectedDayTasks
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                implicitHeight: 34
                                radius: 8
                                color: Theme.card
                                border.width: 1
                                border.color: Theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Checkbox
                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 4
                                        color: modelData.done ? Theme.brandAccent : "transparent"
                                        border.width: 1
                                        border.color: modelData.done ? Theme.brandAccent : Theme.textMuted

                                        Text {
                                            anchors.centerIn: parent
                                            visible: modelData.done
                                            text: "✓"
                                            color: Theme.brandAccentFg
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleTask(modelData.id)
                                        }
                                    }

                                    // Task Text or Edit Input
                                    Item {
                                        Layout.fillWidth: true
                                        height: parent.height

                                        Text {
                                            visible: root.editingTaskId !== modelData.id
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width
                                            text: modelData.text
                                            color: modelData.done ? Theme.textMuted : Theme.textMain
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                            font.strikeout: modelData.done
                                            elide: Text.ElideRight

                                            MouseArea {
                                                anchors.fill: parent
                                                onDoubleClicked: root.startEditTask(modelData)
                                            }
                                        }

                                        TextInput {
                                            visible: root.editingTaskId === modelData.id
                                            anchors.fill: parent
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.textMain
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                            text: root.editingTaskDraft
                                            onTextChanged: root.editingTaskDraft = text
                                            Keys.onReturnPressed: root.commitEditTask()
                                            Keys.onEscapePressed: root.editingTaskId = ""
                                        }
                                    }

                                    // Time Badge
                                    Rectangle {
                                        visible: !!modelData.time
                                        radius: 4
                                        color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.12)
                                        implicitWidth: timeBadgeRow.implicitWidth + 8
                                        implicitHeight: 18

                                        Row {
                                            id: timeBadgeRow
                                            anchors.centerIn: parent
                                            spacing: 3
                                            Text { text: "󰥔"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: modelData.time || ""; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }

                                    // Delete button
                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 4
                                        color: delTaskMa.containsMouse ? Qt.rgba(Theme.accentWarning.r, Theme.accentWarning.g, Theme.accentWarning.b, 0.2) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            color: delTaskMa.containsMouse ? Theme.accentWarning : Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                        }

                                        MouseArea {
                                            id: delTaskMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.deleteTask(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // SECTION 2: MODES (Stub for U3 commit)
            Column {
                visible: root.currentSection === 2
                width: parent.width
                spacing: 10

                Text {
                    text: "MODES & DO NOT DISTURB"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // Component for grouped notification section (Today / Yesterday / Earlier)
    component GroupSection: Column {
        id: groupRoot
        property string title: ""
        property string groupName: ""
        property var entries: []
        width: parent ? parent.width : 340
        spacing: 6

        RowLayout {
            width: parent.width

            Text {
                text: groupRoot.title + " (" + groupRoot.entries.length + ")"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.1
            }

            Item { Layout.fillWidth: true; height: 1 }

            Rectangle {
                radius: 4
                color: groupClearMa.containsMouse ? Theme.surfaceAlt : "transparent"
                implicitWidth: groupClearText.implicitWidth + 8
                implicitHeight: 18

                Text {
                    id: groupClearText
                    anchors.centerIn: parent
                    text: "Clear"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: 9
                    font.bold: true
                }

                MouseArea {
                    id: groupClearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearGroup(groupRoot.groupName)
                }
            }
        }

        Repeater {
            model: groupRoot.entries
            delegate: NotificationCardItem {
                required property var modelData
                entry: modelData
                formattedTime: root.timeAgo(modelData.ts)
            }
        }
    }

    // Interactive Notification Card Delegate
    component NotificationCardItem: Rectangle {
        id: cardItem
        property var entry: null
        property string formattedTime: ""
        readonly property bool isExpanded: !!root.expandedCardMap[entry ? entry.id : 0]

        width: parent ? parent.width : 340
        implicitHeight: cardCol.implicitHeight + 16
        radius: 10
        color: Theme.card
        border.width: 1
        border.color: cardMouse.containsMouse ? Theme.brandAccent : Theme.border

        Behavior on border.color {
            enabled: Theme.animationsEnabled && !Theme.reducedMotion
            ColorAnimation { duration: 120 }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (entry) {
                    root.markRead(entry.id)
                    root.toggleExpandCard(entry.id)
                }
            }
        }

        Column {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 4

            // Top row: icon/app, time, unread indicator, dismiss
            RowLayout {
                width: parent.width
                spacing: 6

                // App icon or glyph
                Rectangle {
                    width: 16
                    height: 16
                    radius: 4
                    color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: (entry && entry.appName && entry.appName.length > 0) ? entry.appName.charAt(0).toUpperCase() : "󰂚"
                        color: Theme.brandAccent
                        font.family: Theme.fontUi
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Text {
                    text: entry ? (entry.appName || entry.app || "Notification") : ""
                    color: Theme.brandAccent
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    font.bold: true
                    Layout.maximumWidth: 160
                    elide: Text.ElideRight
                }

                Text {
                    text: cardItem.formattedTime
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 8
                }

                // Unread dot
                Rectangle {
                    visible: entry && !entry.read
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.brandAccent
                }

                Item { Layout.fillWidth: true; height: 1 }

                // Dismiss button ✕
                Rectangle {
                    width: 18
                    height: 18
                    radius: 4
                    color: dismissCardMa.containsMouse ? Qt.rgba(Theme.accentWarning.r, Theme.accentWarning.g, Theme.accentWarning.b, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: dismissCardMa.containsMouse ? Theme.accentWarning : Theme.textMuted
                        font.pixelSize: 9
                    }

                    MouseArea {
                        id: dismissCardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (entry) root.dismissNotif(entry.id)
                        }
                    }
                }
            }

            // Summary
            Text {
                width: parent.width
                text: entry ? (entry.summary || "") : ""
                color: Theme.textMain
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.bold: true
                wrapMode: Text.WordWrap
                maximumLineCount: cardItem.isExpanded ? 10 : 2
                elide: Text.ElideRight
            }

            // Expandable Body
            Text {
                visible: entry && entry.body && entry.body.length > 0
                width: parent.width
                text: entry ? entry.body : ""
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                maximumLineCount: cardItem.isExpanded ? 20 : 1
                elide: Text.ElideRight
            }

            // Action Buttons
            Row {
                visible: entry && Array.isArray(entry.actions) && entry.actions.length > 0
                spacing: 6
                topPadding: 2

                Repeater {
                    model: entry ? (entry.actions || []) : []
                    delegate: Rectangle {
                        required property var modelData
                        height: 22
                        radius: 5
                        implicitWidth: actionBtnText.implicitWidth + 14
                        color: actMa.containsMouse ? Theme.surfaceAlt : Theme.cardAlt
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: actionBtnText
                            anchors.centerIn: parent
                            text: modelData.text || modelData.identifier
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (entry) root.invokeAction(entry.id, modelData.identifier)
                            }
                        }
                    }
                }
            }
        }
    }
}
