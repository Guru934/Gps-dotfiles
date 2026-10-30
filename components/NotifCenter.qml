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

            // SECTION 1: PLANNER (Stub for U2 commit)
            Column {
                visible: root.currentSection === 1
                width: parent.width
                spacing: 10

                Text {
                    text: "PLANNER CALENDAR & TASKS"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.bold: true
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
