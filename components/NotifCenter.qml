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

    function saveDndState() {
        const raw = JSON.stringify(root.dndState || {}, null, 2)
        const script = 'd="$(dirname "$1")" && mkdir -m 0700 -p "$d" && tmp="${d}/.$(basename "$1").tmp.$$" && (umask 077 && printf "%s\\n" "$2" > "$tmp") && chmod 0600 "$tmp" && mv -f "$tmp" "$1"'
        Quickshell.execDetached(["sh", "-c", script, "sh", root.notifDndPath, raw])
    }

    function saveNotifSettings() {
        const raw = JSON.stringify({
            version: 1,
            entries: root.islandItems,
            settings: root.notifSettings || { storeBody: true, mutedApps: [] }
        }, null, 2)
        const script = 'd="$(dirname "$1")" && mkdir -m 0700 -p "$d" && tmp="${d}/.$(basename "$1").tmp.$$" && (umask 077 && printf "%s\\n" "$2" > "$tmp") && chmod 0600 "$tmp" && mv -f "$tmp" "$1"'
        Quickshell.execDetached(["sh", "-c", script, "sh", root.notifHistoryPath, raw])
    }

    function toggleDnd() {
        Quickshell.execDetached([root.ipcScript, "notify", "dnd", "toggle"])
    }

    function snoozeDnd(minutes) {
        Quickshell.execDetached([root.ipcScript, "notify", "snooze", "" + minutes])
    }

    function setDndManual(on) {
        Quickshell.execDetached([root.ipcScript, "notify", "dnd", on ? "on" : "off"])
    }

    function getMinutesUntilTomorrowMorning() {
        const now = new Date()
        const morning = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 7, 0, 0)
        return Math.max(1, Math.floor((morning.getTime() - now.getTime()) / 60000))
    }

    function toggleAllowCritical() {
        if (!root.dndState) root.dndState = { mode: "off", allowCritical: true, schedule: { enabled: false, from: "22:00", to: "07:00", days: [1,2,3,4,5,6,7] } }
        root.dndState.allowCritical = !root.dndState.allowCritical
        root.saveDndState()
    }

    function toggleStoreBody() {
        const curr = (root.notifSettings && root.notifSettings.storeBody !== false)
        Quickshell.execDetached([root.ipcScript, "notify", "store-body", curr ? "off" : "on"])
        if (!root.notifSettings) root.notifSettings = { storeBody: true, mutedApps: [] }
        root.notifSettings.storeBody = !curr
        root.saveNotifSettings()
    }

    function toggleScheduleEnabled() {
        if (!root.dndState) root.dndState = { mode: "off", allowCritical: true, schedule: { enabled: false, from: "22:00", to: "07:00", days: [1,2,3,4,5,6,7] } }
        if (!root.dndState.schedule) root.dndState.schedule = { enabled: false, from: "22:00", to: "07:00", days: [1,2,3,4,5,6,7] }
        root.dndState.schedule.enabled = !root.dndState.schedule.enabled
        root.dndState.mode = root.dndState.schedule.enabled ? "schedule" : "off"
        root.saveDndState()
    }

    function toggleScheduleDay(dayNum) {
        if (!root.dndState || !root.dndState.schedule) return
        if (!Array.isArray(root.dndState.schedule.days)) root.dndState.schedule.days = [1,2,3,4,5,6,7]
        const days = root.dndState.schedule.days.slice()
        const idx = days.indexOf(dayNum)
        if (idx >= 0) {
            days.splice(idx, 1)
        } else {
            days.push(dayNum)
        }
        root.dndState.schedule.days = days.sort()
        root.saveDndState()
    }

    function updateScheduleTimes(fromTime, toTime) {
        if (!root.dndState || !root.dndState.schedule) return
        if (fromTime) root.dndState.schedule.from = fromTime
        if (toTime) root.dndState.schedule.to = toTime
        root.saveDndState()
    }

    function toggleMuteApp(appName) {
        if (!root.notifSettings) root.notifSettings = { storeBody: true, mutedApps: [] }
        if (!Array.isArray(root.notifSettings.mutedApps)) root.notifSettings.mutedApps = []
        const muted = root.notifSettings.mutedApps.slice()
        const idx = muted.indexOf(appName)
        if (idx >= 0) {
            muted.splice(idx, 1)
        } else {
            muted.push(appName)
        }
        root.notifSettings.mutedApps = muted
        root.saveNotifSettings()
    }

    function clearNotificationHistory() {
        Quickshell.execDetached([root.ipcScript, "notify", "clear"])
        root.confirmClearHistory = false
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
                    if (parsed && parsed.settings) {
                        root.notifSettings = parsed.settings
                    }
                }
            } catch (e) {}
        }
    }

    property var notifSettings: ({ storeBody: true, mutedApps: [] })
    property bool confirmClearHistory: false
    property string scheduleFromDraft: ""
    property string scheduleToDraft: ""

    readonly property var allKnownApps: {
        const apps = root.appNames.slice()
        if (root.notifSettings && Array.isArray(root.notifSettings.mutedApps)) {
            for (let i = 0; i < root.notifSettings.mutedApps.length; i++) {
                const m = root.notifSettings.mutedApps[i]
                if (!apps.includes(m)) apps.push(m)
            }
        }
        return apps.sort()
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
            if (root.hub) root.hub.closeDashboard()
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
    readonly property int maxDrawerHeight: 640
    readonly property int calculatedContentHeight: Math.min(root.maxDrawerHeight, Math.max(320, mainCol.implicitHeight + 36))

    anchors { top: true; left: true }
    margins {
        left: 60
        top: 20
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
        color: Theme.surfaceDeep
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
                    visible: Number(root.currentSection) === 0 && root.activeEntries.length > 0 && !root.undoActive
                    radius: 6
                    color: clearMa.containsMouse ? Theme.surfaceHigh : "transparent"
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
                    color: escMa.containsMouse ? Theme.surfaceHigh : "transparent"
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
                            color: Number(root.currentSection) === index ? Theme.brandAccent : (tabMa.containsMouse ? Theme.surfaceHigh : "transparent")

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !Theme.reducedMotion
                                ColorAnimation { duration: Theme.animDuration }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: modelData.label
                                    color: Number(root.currentSection) === index ? Theme.brandAccentFg : (tabMa.containsMouse ? Theme.textMain : Theme.textMuted)
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    visible: modelData.badge !== ""
                                    radius: 6
                                    color: Number(root.currentSection) === index ? Qt.rgba(0,0,0,0.2) : Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.2)
                                    implicitWidth: tabBadgeText.implicitWidth + 8
                                    implicitHeight: 14
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: tabBadgeText
                                        anchors.centerIn: parent
                                        text: modelData.badge
                                        color: Number(root.currentSection) === index ? Theme.brandAccentFg : Theme.brandAccent
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
                visible: Number(root.currentSection) === 0
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

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                text: root.searchQuery
                                onTextChanged: root.searchQuery = text
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.searchQuery === "" && !searchInput.activeFocus
                                text: "Search notifications…"
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                            }
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

                // Filter chips: All, Unread, + apps (scrollable with fade edges)
                Item {
                    width: parent.width
                    height: 26

                    Flickable {
                        id: chipsFlickable
                        anchors.fill: parent
                        contentWidth: chipsRow.implicitWidth
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        WheelHandler {
                            orientation: Qt.Vertical
                            onWheel: event => {
                                chipsFlickable.contentX = Math.max(0, Math.min(chipsFlickable.contentWidth - chipsFlickable.width, chipsFlickable.contentX - event.angleDelta.y))
                            }
                        }

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

                // Left fade edge
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 16
                        visible: chipsFlickable.contentX > 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.surfaceDeep }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Right fade edge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 16
                        visible: chipsFlickable.contentWidth > chipsFlickable.width && (chipsFlickable.contentX < chipsFlickable.contentWidth - chipsFlickable.width - 2)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Theme.surfaceDeep }
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
                        width: parent.width - 12
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
                visible: Number(root.currentSection) === 1
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
                                color: prevMoMa.containsMouse ? Theme.surfaceHigh : "transparent"
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
                                color: nextMoMa.containsMouse ? Theme.surfaceHigh : "transparent"
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
                                color: todayBtnMa.containsMouse ? Theme.surfaceHigh : "transparent"
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
                                    color: modelData.isSelected ? Theme.brandAccent : (dayMa.containsMouse ? Theme.surfaceHigh : "transparent")
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
                        color: carryMa.containsMouse ? Qt.rgba(Theme.statusWarn.r, Theme.statusWarn.g, Theme.statusWarn.b, 0.25) : Qt.rgba(Theme.statusWarn.r, Theme.statusWarn.g, Theme.statusWarn.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.statusWarn.r, Theme.statusWarn.g, Theme.statusWarn.b, 0.40)
                        implicitWidth: carryText.implicitWidth + 10
                        implicitHeight: 20

                        Row {
                            id: carryText
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: "󰁔"; color: Theme.statusWarn; font.family: Theme.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Carry (" + root.carriedPendingCount + ") to today"; color: Theme.statusWarn; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
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
                                        color: delTaskMa.containsMouse ? Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.2) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            color: delTaskMa.containsMouse ? Theme.statusDanger : Theme.textMuted
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

            // SECTION 2: MODES
            Flickable {
                visible: Number(root.currentSection) === 2
                width: parent.width
                height: Math.max(160, Math.min(460, root.maxDrawerHeight - 120))
                contentHeight: modesCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: modesCol
                    width: parent.width
                    spacing: 12

                    // Big DND Switch Card
                    Rectangle {
                        width: parent.width
                        implicitHeight: dndCardRow.implicitHeight + 20
                        radius: 10
                        color: Theme.card
                        border.width: 1
                        border.color: root.dndActive ? Theme.brandAccent : Theme.border

                        Behavior on border.color {
                            enabled: Theme.animationsEnabled && !Theme.reducedMotion
                            ColorAnimation { duration: Theme.animDuration }
                        }

                        RowLayout {
                            id: dndCardRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 10

                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                color: root.dndActive ? Theme.brandAccent : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.4)

                                Behavior on color {
                                    enabled: Theme.animationsEnabled && !Theme.reducedMotion
                                    ColorAnimation { duration: Theme.animDuration }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.dndActive ? "󰂛" : "󰂚"
                                    color: root.dndActive ? Theme.brandAccentFg : Theme.textMain
                                    font.family: Theme.fontMono
                                    font.pixelSize: 18
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Do Not Disturb"
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Text {
                                    text: root.dndActive ? "Popups and alert banners are silenced" : "Banner notifications and popups active"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                }
                            }

                            ToggleSwitch {
                                checked: root.dndActive
                                onToggled: root.toggleDnd()
                            }
                        }
                    }

                    // Duration Chips
                    Column {
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "QUICK DURATION"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Grid {
                            width: parent.width
                            columns: 2
                            spacing: 6

                            // 30 min chip
                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 30
                                radius: 8
                                color: dnd30Ma.containsMouse ? Theme.surfaceHigh : Theme.card
                                border.width: 1
                                border.color: (root.dndActive && root.dndState && root.dndState.mode === "snooze") ? Theme.brandAccent : Theme.border

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { text: "󰥔"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "30 min"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                }

                                MouseArea {
                                    id: dnd30Ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.snoozeDnd(30)
                                }
                            }

                            // 1 hour chip
                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 30
                                radius: 8
                                color: dnd60Ma.containsMouse ? Theme.surfaceHigh : Theme.card
                                border.width: 1
                                border.color: Theme.border

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { text: "󰥔"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "1 hour"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                }

                                MouseArea {
                                    id: dnd60Ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.snoozeDnd(60)
                                }
                            }

                            // Until tomorrow morning chip
                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 30
                                radius: 8
                                color: dndMornMa.containsMouse ? Theme.surfaceHigh : Theme.card
                                border.width: 1
                                border.color: Theme.border

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { text: "󰖔"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Until tomorrow"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                }

                                MouseArea {
                                    id: dndMornMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.snoozeDnd(root.getMinutesUntilTomorrowMorning())
                                }
                            }

                            // Until I turn it off chip
                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 30
                                radius: 8
                                color: dndIndefMa.containsMouse ? Theme.surfaceHigh : Theme.card
                                border.width: 1
                                border.color: (root.dndActive && root.dndState && root.dndState.mode === "dnd") ? Theme.brandAccent : Theme.border

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { text: "󰂛"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Until I turn it off"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                }

                                MouseArea {
                                    id: dndIndefMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setDndManual(true)
                                }
                            }
                        }
                    }

                    // Schedule Editor Card
                    Column {
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "SCHEDULED DO NOT DISTURB"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Rectangle {
                            width: parent.width
                            implicitHeight: schedCol.implicitHeight + 20
                            radius: 10
                            color: Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Column {
                                id: schedCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                spacing: 10

                                RowLayout {
                                    width: parent.width

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { text: "Enable Schedule"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
                                        Text { text: "Automatically silence notifications during set hours"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9 }
                                    }

                                    ToggleSwitch {
                                        checked: !!(root.dndState && root.dndState.schedule && root.dndState.schedule.enabled)
                                        onToggled: root.toggleScheduleEnabled()
                                    }
                                }

                                // From / To Time Pickers
                                RowLayout {
                                    width: parent.width
                                    spacing: 10

                                    Row {
                                        spacing: 6
                                        Text { text: "From"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle {
                                            width: 54
                                            height: 24
                                            radius: 6
                                            color: Theme.surfaceHigh
                                            border.width: 1
                                            border.color: Theme.border

                                            TextInput {
                                                anchors.fill: parent
                                                horizontalAlignment: TextInput.AlignHCenter
                                                verticalAlignment: TextInput.AlignVCenter
                                                color: Theme.textMain
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                maximumLength: 5
                                                text: (root.dndState && root.dndState.schedule && root.dndState.schedule.from) ? root.dndState.schedule.from : "22:00"
                                                onEditingFinished: root.updateScheduleTimes(text, null)
                                            }
                                        }
                                    }

                                    Row {
                                        spacing: 6
                                        Text { text: "To"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle {
                                            width: 54
                                            height: 24
                                            radius: 6
                                            color: Theme.surfaceHigh
                                            border.width: 1
                                            border.color: Theme.border

                                            TextInput {
                                                anchors.fill: parent
                                                horizontalAlignment: TextInput.AlignHCenter
                                                verticalAlignment: TextInput.AlignVCenter
                                                color: Theme.textMain
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                maximumLength: 5
                                                text: (root.dndState && root.dndState.schedule && root.dndState.schedule.to) ? root.dndState.schedule.to : "07:00"
                                                onEditingFinished: root.updateScheduleTimes(null, text)
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true; height: 1 }
                                }

                                // Days selector row (Mo, Tu, We, Th, Fr, Sa, Su)
                                Row {
                                    width: parent.width
                                    spacing: 4

                                    Repeater {
                                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                        delegate: Rectangle {
                                            required property string modelData
                                            required property int index
                                            readonly property int dayNum: index + 1
                                            readonly property bool isDayActive: !!(root.dndState && root.dndState.schedule && Array.isArray(root.dndState.schedule.days) && root.dndState.schedule.days.includes(dayNum))

                                            width: (parent.width - 24) / 7
                                            height: 24
                                            radius: 6
                                            color: isDayActive ? Theme.brandAccent : Theme.surfaceHigh
                                            border.width: 1
                                            border.color: isDayActive ? Theme.brandAccent : Theme.border

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: isDayActive ? Theme.brandAccentFg : Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                                font.bold: true
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleScheduleDay(dayNum)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Alerts & History Settings Card
                    Column {
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "SETTINGS & PRIVACY"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Rectangle {
                            width: parent.width
                            implicitHeight: privacyCol.implicitHeight + 20
                            radius: 10
                            color: Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Column {
                                id: privacyCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                spacing: 10

                                // Allow critical alerts toggle
                                RowLayout {
                                    width: parent.width

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { text: "Allow critical alerts"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
                                        Text { text: "Urgent notifications bypass Do Not Disturb"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9 }
                                    }

                                    ToggleSwitch {
                                        checked: root.dndState ? (root.dndState.allowCritical !== false) : true
                                        onToggled: root.toggleAllowCritical()
                                    }
                                }

                                Rectangle { width: parent.width; height: 1; color: Theme.border }

                                // Store notification body toggle
                                RowLayout {
                                    width: parent.width

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { text: "Store notification body text"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
                                        Text { text: "Preserve message content in disk history"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9 }
                                    }

                                    ToggleSwitch {
                                        checked: root.notifSettings ? (root.notifSettings.storeBody !== false) : true
                                        onToggled: root.toggleStoreBody()
                                    }
                                }
                            }
                        }
                    }

                    // Per-App Mute List
                    Column {
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "MUTED APPLICATIONS"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Rectangle {
                            width: parent.width
                            implicitHeight: appMuteCol.implicitHeight + 16
                            radius: 10
                            color: Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Column {
                                id: appMuteCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 8

                                Text {
                                    visible: root.allKnownApps.length === 0
                                    text: "No applications registered yet"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                }

                                Repeater {
                                    model: root.allKnownApps
                                    delegate: RowLayout {
                                        required property string modelData
                                        readonly property bool isMuted: !!(root.notifSettings && Array.isArray(root.notifSettings.mutedApps) && root.notifSettings.mutedApps.includes(modelData))

                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            text: modelData
                                            color: Theme.textMain
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: isMuted ? "Muted" : "Active"
                                            color: isMuted ? Theme.statusWarn : Theme.textMuted
                                            font.family: Theme.fontUi
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        ToggleSwitch {
                                            checked: isMuted
                                            onToggled: root.toggleMuteApp(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Clear History with Confirmation
                    Column {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            visible: !root.confirmClearHistory
                            width: parent.width
                            height: 32
                            radius: 8
                            color: clearHistMa.containsMouse ? Theme.surfaceHigh : Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "󰆴"; color: Theme.statusWarn; font.family: Theme.fontMono; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Clear notification history"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            }

                            MouseArea {
                                id: clearHistMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmClearHistory = true
                            }
                        }

                        // Confirmation Box
                        Rectangle {
                            visible: root.confirmClearHistory
                            width: parent.width
                            implicitHeight: confirmCol.implicitHeight + 16
                            radius: 8
                            color: Qt.rgba(Theme.statusWarn.r, Theme.statusWarn.g, Theme.statusWarn.b, 0.12)
                            border.width: 1
                            border.color: Theme.statusWarn

                            Column {
                                id: confirmCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 8

                                Text {
                                    text: "Permanently delete all stored notifications?"
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Row {
                                    spacing: 8

                                    Rectangle {
                                        width: 70
                                        height: 24
                                        radius: 5
                                        color: Theme.surfaceHigh
                                        border.width: 1
                                        border.color: Theme.border
                                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.confirmClearHistory = false
                                        }
                                    }

                                    Rectangle {
                                        width: 90
                                        height: 24
                                        radius: 5
                                        color: Theme.statusWarn
                                        Text { anchors.centerIn: parent; text: "Clear All"; color: Theme.brandAccentFg; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.clearNotificationHistory()
                                        }
                                    }
                                }
                            }
                        }
                    }
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
                color: groupClearMa.containsMouse ? Theme.surfaceHigh : "transparent"
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

            // Gutter clearance so clear button is never clipped by the scrollbar
            Item { Layout.preferredWidth: 4 }
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
                    color: dismissCardMa.containsMouse ? Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: dismissCardMa.containsMouse ? Theme.statusDanger : Theme.textMuted
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
                        color: actMa.containsMouse ? Theme.surfaceHigh : Theme.card
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

    // ToggleSwitch Component
    component ToggleSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()

        width: 38
        height: 22
        radius: 11
        color: checked ? Theme.brandAccent : Theme.surfaceHigh
        border.width: 1
        border.color: checked ? Theme.brandAccent : Theme.border

        Behavior on color {
            enabled: Theme.animationsEnabled && !Theme.reducedMotion
            ColorAnimation { duration: Theme.animDuration }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? (sw.width - width - 3) : 3
            color: sw.checked ? Theme.brandAccentFg : Theme.textMuted

            Behavior on x {
                enabled: Theme.animationsEnabled && !Theme.reducedMotion
                NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }
}
