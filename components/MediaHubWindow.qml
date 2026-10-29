import QtQuick
import Quickshell
import Quickshell.Io

// Single Media Hub surface. MediaHub.qml stays the reusable content
// component; this normal floating window only provides visibility, sizing,
// close wiring and validated external links. The instance is created once in
// shell.qml, so repeated button presses never create duplicate windows.
FloatingWindow {
    id: root
    property var hub: null
    property bool isOpen: false
    // The content is built on first open and then kept alive, so page state
    // survives close/reopen without loading the large hub at shell startup.
    property bool hubLoaded: false

    readonly property var targetScreen: (root.hub && root.hub.popupScreen)
        ? root.hub.popupScreen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    readonly property int initialWidth: root.targetScreen
        ? Math.min(1400, Math.max(960, Math.round(root.targetScreen.width * 0.8)))
        : 1180
    readonly property int initialHeight: root.targetScreen
        ? Math.min(900, Math.max(600, Math.round(root.targetScreen.height * 0.8)))
        : 760
    readonly property int minWidth: root.targetScreen
        ? Math.min(960, Math.max(480, root.targetScreen.width - 60))
        : 960
    readonly property int minHeight: root.targetScreen
        ? Math.min(600, Math.max(360, root.targetScreen.height - 60))
        : 600
    readonly property bool hyprlandAvailable: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    property int floatAttempts: 0

    function open() {
        if (root.hub) {
            if (typeof root.hub.closePopup === "function") root.hub.closePopup()
            if (typeof root.hub.closeDashboard === "function") root.hub.closeDashboard()
        }
        root.hubLoaded = true
        if (root.isOpen) return
        root.isOpen = true
    }

    function close() {
        root.isOpen = false
    }

    function toggle() {
        if (root.isOpen) root.close()
        else root.open()
    }

    function openWallhavenSource(url) {
        const value = String(url || "")
        if (!/^https:\/\/wallhaven\.cc\/w\/[A-Za-z0-9]{6,12}$/.test(value))
            return false
        Quickshell.execDetached(["xdg-open", value])
        return true
    }

    function openMusicSource(url) {
        const value = String(url || "")
        if (value.length < 9 || value.length > 2048 || /[\u0000-\u0020\u007f]/.test(value))
            return false
        const match = /^https:\/\/([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(?:[/?#][^\s]*)?$/i.exec(value)
        if (!match)
            return false
        if (match[2] && (Number(match[2]) < 1 || Number(match[2]) > 65535))
            return false
        Quickshell.execDetached(["xdg-open", value])
        return true
    }

    function openSource(url) {
        return root.openWallhavenSource(url) || root.openMusicSource(url)
    }

    // Hyprland tiles ordinary toplevels unless a float rule exists. Rather
    // than editing the user's compositor config, ask Hyprland to float this
    // specific title after it maps. The call is a no-op without Hyprland.
    function requestFloating() {
        if (root.floatAttempts >= 16 || clientProc.running || floatProc.running) return
        clientProc.running = true
    }

    function handleClients(text) {
        root.floatAttempts += 1
        var clients = null
        try { clients = JSON.parse(text) } catch (error) { clients = null }
        if (!Array.isArray(clients)) {
            if (root.floatAttempts < 16) return
            floatTimer.stop()
            return
        }
        var address = ""
        var found = false
        for (var i = 0; i < clients.length; i++) {
            var client = clients[i]
            if (client && client.title === root.title && client.mapped === true) {
                found = true
                if (client.floating === true) {
                    floatTimer.stop()
                    return
                }
                address = String(client.address || "")
                break
            }
        }
        if (!found) {
            if (root.floatAttempts < 16) return
            floatTimer.stop()
            return
        }
        if (!/^0x[0-9a-f]+$/i.test(address)) {
            floatTimer.stop()
            return
        }
        floatTimer.stop()
        const code = 'local w = hl.get_window("address:' + address + '"); '
            + 'if w then '
            + 'hl.dispatch(hl.dsp.window.float({ action = "set", window = w })); '
            + 'hl.dispatch(hl.dsp.window.center({ window = w })) '
            + 'end'
        floatProc.command = ["hyprctl", "eval", code]
        floatProc.running = true
    }

    title: "GPS Media Hub"
    screen: root.targetScreen
    visible: root.isOpen
    color: "transparent"
    implicitWidth: root.initialWidth
    implicitHeight: root.initialHeight
    minimumSize: Qt.size(root.minWidth, root.minHeight)
    onClosed: root.isOpen = false
    onVisibleChanged: {
        if (visible && root.hyprlandAvailable) {
            root.floatAttempts = 0
            floatTimer.restart()
        } else {
            floatTimer.stop()
        }
    }

    Timer {
        id: floatTimer
        interval: 140
        repeat: true
        onTriggered: root.requestFloating()
    }

    Process {
        id: clientProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.handleClients(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.floatAttempts < 16 && root.isOpen)
                floatTimer.restart()
        }
    }

    Process {
        id: floatProc
        command: []
        onExited: {
            root.floatAttempts = 0
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.isOpen
        onActivated: root.close()
    }

    Item {
        anchors.fill: parent
        clip: true

        Loader {
            anchors.fill: parent
            active: root.hubLoaded
            sourceComponent: mediaHubContent
        }
    }

    Component {
        id: mediaHubContent

        MediaHub {
            showCloseButton: true
            onCloseRequested: root.close()
            onSourceLinkRequested: (url) => root.openSource(url)
        }
    }
}
