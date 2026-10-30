import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.config
import "ClipboardService.js" as CS

PanelWindow {
    id: root

    property var hub: null
    property bool isOpen: false
    property var rawItems: []
    property var items: []
    property int selectedIndex: 0
    property string searchQuery: ""
    property bool isHistoryPaused: false
    property bool confirmWipe: false
    property int itemCount: items.length

    readonly property string repoRoot: (root.hub && root.hub.repoRoot)
        ? root.hub.repoRoot
        : (Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice"))
    readonly property string clipScript: root.repoRoot + "/scripts/gps-clipboard"
    readonly property string ipcScript: root.repoRoot + "/scripts/gps-ipc"

    function open() {
        root.confirmWipe = false
        root.searchQuery = ""
        root.selectedIndex = 0
        root.isOpen = true
        Quickshell.execDetached([root.ipcScript, "island", "externalInteraction", "true"])
        refresh()
    }

    function close() {
        root.isOpen = false
        root.confirmWipe = false
        Quickshell.execDetached([root.ipcScript, "island", "externalInteraction", "false"])
    }

    function toggle() {
        if (root.isOpen) close()
        else open()
    }

    function refresh() {
        if (!listProc.running) listProc.running = true
    }

    function copySelected() {
        if (root.items.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= root.items.length) {
            close()
            return
        }
        const item = root.items[root.selectedIndex]
        if (!item || !item.id) return

        copyProc.command = [root.clipScript, "copy", String(item.id)]
        copyProc.running = true

        // Notify Island to flash copied confirmation toast
        Quickshell.execDetached([root.ipcScript, "island", "copied", item.kind, item.preview.slice(0, 100)])
        close()
    }

    function deleteSelected() {
        if (root.items.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= root.items.length) return
        const item = root.items[root.selectedIndex]
        if (!item || !item.id) return

        deleteProc.command = [root.clipScript, "delete", String(item.id)]
        deleteProc.running = true
    }

    function togglePinSelected() {
        if (root.items.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= root.items.length) return
        const item = root.items[root.selectedIndex]
        if (!item || !item.id) return

        pinProc.command = [root.clipScript, "pin", String(item.id)]
        pinProc.running = true
    }

    function togglePause() {
        pauseProc.command = [root.clipScript, "pause", "toggle"]
        pauseProc.running = true
    }

    function triggerWipe() {
        if (!root.confirmWipe) {
            root.confirmWipe = true
            wipeConfirmTimer.restart()
            return
        }
        root.confirmWipe = false
        wipeProc.running = true
    }

    onIsOpenChanged: {
        // Inform Island to suspend Control Center hover expansion while picker is active
        Quickshell.execDetached([root.ipcScript, "island", "externalInteraction", root.isOpen ? "true" : "false"])
        if (root.isOpen) {
            refresh()
            searchField.forceActiveFocus()
        }
    }

    onSearchQueryChanged: {
        root.items = CS.filterItems(root.rawItems, root.searchQuery)
        root.selectedIndex = 0
    }

    // Background processes for data operations
    Process {
        id: listProc
        command: [root.clipScript, "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.items)) {
                        root.rawItems = res.items
                        root.items = CS.filterItems(res.items, root.searchQuery)
                        root.isHistoryPaused = Boolean(res.paused)
                        root.itemCount = res.count || res.items.length
                        if (root.selectedIndex >= root.items.length) {
                            root.selectedIndex = Math.max(0, root.items.length - 1)
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: copyProc
        command: [root.clipScript, "copy", "0"]
    }

    Process {
        id: deleteProc
        command: [root.clipScript, "delete", "0"]
        onExited: root.refresh()
    }

    Process {
        id: pinProc
        command: [root.clipScript, "pin", "0"]
        onExited: root.refresh()
    }

    Process {
        id: pauseProc
        command: [root.clipScript, "pause", "toggle"]
        onExited: root.refresh()
    }

    Process {
        id: wipeProc
        command: [root.clipScript, "clear"]
        onExited: root.refresh()
    }

    Timer {
        id: wipeConfirmTimer
        interval: 3500
        onTriggered: root.confirmWipe = false
    }

    // Panel Window Configuration
    WlrLayershell.namespace: "gps-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Center surface on screen
    anchors {}
    color: "transparent"
    visible: root.isOpen

    implicitWidth: 480
    implicitHeight: 460

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "CLIPBOARD"
                    color: Theme.textMain
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.2
                }

                Rectangle {
                    implicitWidth: countText.implicitWidth + 10
                    implicitHeight: 18
                    radius: 9
                    color: Theme.surfaceDeep
                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: String(root.itemCount)
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Pause History Button
                Rectangle {
                    implicitWidth: pauseLabel.implicitWidth + 14
                    implicitHeight: 24
                    radius: 6
                    color: root.isHistoryPaused ? Qt.rgba(Theme.statusWarn.r, Theme.statusWarn.g, Theme.statusWarn.b, 0.2) : Theme.card
                    border.width: 1
                    border.color: root.isHistoryPaused ? Theme.statusWarn : Theme.border
                    Text {
                        id: pauseLabel
                        anchors.centerIn: parent
                        text: root.isHistoryPaused ? "PAUSED" : "ACTIVE"
                        color: root.isHistoryPaused ? Theme.statusWarn : Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePause()
                    }
                }

                // Clear / Wipe Button
                Rectangle {
                    implicitWidth: wipeLabel.implicitWidth + 14
                    implicitHeight: 24
                    radius: 6
                    color: root.confirmWipe ? Theme.statusDanger : Theme.card
                    border.width: 1
                    border.color: root.confirmWipe ? Theme.statusDanger : Theme.border
                    Text {
                        id: wipeLabel
                        anchors.centerIn: parent
                        text: root.confirmWipe ? "CONFIRM CLEAR?" : "CLEAR ALL"
                        color: root.confirmWipe ? "#ffffff" : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.triggerWipe()
                    }
                }

                // Close Button
                Rectangle {
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: 6
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.textMuted
                        font.pixelSize: 15
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 8
                color: Theme.card
                border.width: 1
                border.color: searchField.activeFocus ? Theme.brandAccent : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: "⌕"
                        color: Theme.textMuted
                        font.pixelSize: 14
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.searchQuery
                        onTextChanged: root.searchQuery = text

                        Keys.onUpPressed: event => {
                            event.accepted = true
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            listView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                        }
                        Keys.onDownPressed: event => {
                            event.accepted = true
                            root.selectedIndex = Math.min(root.items.length - 1, root.selectedIndex + 1)
                            listView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                        }
                        Keys.onReturnPressed: root.copySelected()
                        Keys.onEscapePressed: root.close()
                        Keys.onDeletePressed: root.deleteSelected()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                                event.accepted = true
                                root.togglePinSelected()
                            }
                        }
                    }

                    Text {
                        visible: searchField.text.length === 0 && !searchField.activeFocus
                        text: "Search clipboard (Up/Down navigate, Enter copy, Del remove, Ctrl+P pin)"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: searchField.text.length > 0
                        text: "×"
                        color: Theme.textMuted
                        font.pixelSize: 13
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.searchQuery = ""
                        }
                    }
                }
            }

            // Empty State
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.items.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "📋"
                        font.pixelSize: 32
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.searchQuery.length > 0 ? "No matches found" : "Clipboard is empty"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.searchQuery.length > 0 ? "Try another search term" : "Copied text and images will appear here"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                    }
                }
            }

            // Entries List
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.items.length > 0
                clip: true
                spacing: 4
                model: root.items

                delegate: Rectangle {
                    id: rowDelegate
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedIndex === index
                    readonly property bool isPinned: Boolean(modelData.pinned)
                    readonly property bool isHovered: rowMouse.containsMouse

                    width: listView.width
                    height: 52
                    radius: 8
                    color: isSelected
                        ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.20)
                        : (isHovered ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.12) : Theme.card)
                    border.width: isSelected || isPinned || isHovered ? 1 : 0
                    border.color: isSelected
                        ? Theme.brandAccent
                        : (isPinned ? Theme.brandAccent : (isHovered ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.60) : "transparent"))

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !Theme.reducedMotion
                        ColorAnimation { duration: 100 }
                    }
                    Behavior on border.color {
                        enabled: Theme.animationsEnabled && !Theme.reducedMotion
                        ColorAnimation { duration: 100 }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedIndex = index
                            root.copySelected()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        // Type Icon / Indicator
                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 6
                            color: modelData.kind === "color" && modelData.colorHex
                                ? modelData.colorHex
                                : Theme.surfaceDeep
                            border.width: 1
                            border.color: Theme.border

                            // Text for icons
                            Text {
                                anchors.centerIn: parent
                                visible: modelData.kind !== "color" && !modelData.isImage
                                text: {
                                    if (modelData.kind === "url") return "🔗"
                                    if (modelData.kind === "path") return "📁"
                                    return "📄"
                                }
                                font.pixelSize: 14
                            }

                            // Image thumbnail if decoded, or image badge
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                visible: modelData.isImage && modelData.thumbPath
                                source: modelData.thumbPath ? "file://" + modelData.thumbPath : ""
                                fillMode: Image.PreserveAspectCrop
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: modelData.isImage && !modelData.thumbPath
                                text: "🖼"
                                font.pixelSize: 14
                            }
                        }

                        // Preview Column
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: {
                                        if (modelData.kind === "image") {
                                            return modelData.imageInfo
                                                ? modelData.imageInfo.format + " Image (" + modelData.imageInfo.sizeStr + ")"
                                                : "Image"
                                        }
                                        if (modelData.kind === "url") return "Link"
                                        if (modelData.kind === "color") return "Color: " + modelData.preview
                                        if (modelData.kind === "path") return "File Path"
                                        return "Text"
                                    }
                                    color: modelData.kind === "url" ? Theme.brandAccent : Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    font.bold: true
                                }

                                Text {
                                    visible: isPinned
                                    text: "📌 PINNED"
                                    color: Theme.brandAccent
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.preview
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Pin Button
                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: 4
                            color: isPinned ? Theme.brandAccent : Theme.surfaceDeep
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: "📌"
                                font.pixelSize: 11
                                opacity: isPinned ? 1.0 : 0.4
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedIndex = index
                                    root.togglePinSelected()
                                }
                            }
                        }
                    }
                }
            }

            // Keyboard footer tip
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Enter: Copy · Del: Remove · Ctrl+P: Pin · Esc: Close"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 8
            }
        }
    }
}
