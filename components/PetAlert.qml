import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config

// Small, non-focus-stealing permission indicator. The reader starts at the
// current end of the JSONL file, so old requests never reappear after restart.
Scope {
    id: root

    property var alerts: []
    property real now: Date.now() / 1000
    property int expireSeconds: 900
    readonly property string dirPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pet"

    function validAsk(o) {
        return o && o.type === "ask" && typeof o.id === "string" && o.id !== ""
            && typeof o.ts === "number" && o.ts <= root.now + 60
            && root.now - o.ts <= root.expireSeconds
    }

    function handle(line) {
        let o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o.type === "ask" && root.validAsk(o)) {
            root.alerts = [o].concat(root.alerts.filter(a => a.id !== o.id)).slice(0, 4)
        } else if (o.type === "clear") {
            root.alerts = root.alerts.filter(a => !((o.id && a.id === o.id)
                || (!o.id && o.session && a.session === o.session && a.tool === o.tool)))
        }
    }

    function remove(id) { root.alerts = root.alerts.filter(a => a.id !== id) }
    function label(tool) { return tool === "opencode" ? "OpenCode" : tool === "codex" ? "Codex" : (tool || "Agent") }
    function project(cwd) {
        const parts = (cwd || "").split("/").filter(x => x !== "")
        return parts.length ? parts[parts.length - 1] : ""
    }
    function waited(ts) {
        const seconds = Math.max(0, Math.floor(root.now - ts))
        return seconds < 60 ? seconds + "s" : Math.floor(seconds / 60) + "m"
    }
    function jump(alert) {
        if (typeof alert.addr === "string" && alert.addr !== "")
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + alert.addr])
        root.remove(alert.id)
    }

    Process {
        id: feed
        running: true
        command: ["sh", "-c", "d=$1; mkdir -p -- \"$d\"; touch -- \"$d/alerts.jsonl\"; exec tail -n0 -F -- \"$d/alerts.jsonl\" 2>/dev/null", "pet-alert", root.dirPath]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: feed.running = true }
    Timer {
        interval: 1000; repeat: true; running: root.alerts.length > 0
        onTriggered: {
            root.now = Date.now() / 1000
            root.alerts = root.alerts.filter(a => root.now - a.ts <= root.expireSeconds)
        }
    }

    PanelWindow {
        id: win
        visible: root.alerts.length > 0
        screen: {
            const monitor = Hyprland.focusedMonitor
            const match = monitor ? Quickshell.screens.find(s => s.name === monitor.name) : null
            return match || Quickshell.screens[0]
        }
        anchors { top: true }
        margins { top: 28 }
        implicitWidth: 460
        implicitHeight: cards.implicitHeight + 24
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gps-pet-alert"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ColumnLayout {
            id: cards
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.topMargin: 8
            spacing: 10

            Repeater {
                model: root.alerts
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: body.implicitHeight + 28
                    radius: Theme.radiusPanel
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.accentTertiary

                    RowLayout {
                        id: body
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            width: 36; height: 36; radius: 18
                            color: Theme.accentTertiary
                            Text { anchors.centerIn: parent; text: "!"; color: Theme.surfaceDeep; font.bold: true; font.pixelSize: 20 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: root.label(modelData.tool) + " needs permission"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: root.waited(modelData.ts); color: Theme.accentTertiary; font.family: Theme.fontMono; font.pixelSize: 10 }
                            }
                            Text { text: (modelData.title || "permission") + (modelData.detail ? " · " + modelData.detail : ""); color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: root.project(modelData.cwd) + (modelData.ws ? "  ·  ws " + modelData.ws : ""); color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
                                Rectangle {
                                    visible: typeof modelData.addr === "string" && modelData.addr !== ""
                                    implicitWidth: jumpText.implicitWidth + 20; implicitHeight: 26; radius: 13; color: Theme.brandAccent
                                    Text { id: jumpText; anchors.centerIn: parent; text: "Jump"; color: Theme.brandAccentFg; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.jump(modelData) }
                                }
                                Rectangle {
                                    implicitWidth: dismissText.implicitWidth + 20; implicitHeight: 26; radius: 13; color: Theme.card
                                    Text { id: dismissText; anchors.centerIn: parent; text: "Dismiss"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.remove(modelData.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
