import QtQuick
import Quickshell
import Quickshell.Hyprland

// Single Media Hub surface. MediaHub.qml stays the reusable content
// component; this standard window tiles by default following the compositor
// layout. The instance is created once in shell.qml, so repeated button presses
// never create duplicate windows and refocus any existing window.
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

    function focusWindow() {
        Quickshell.execDetached([
            "hyprctl", "eval",
            'local w = hl.get_window("title:' + root.title + '"); if w then hl.dispatch(hl.dsp.focus({ window = w })) end'
        ])
    }

    function isWindowFocused() {
        return Hyprland.activeToplevel !== null && Hyprland.activeToplevel.title === root.title
    }

    function open() {
        if (root.hub) {
            if (typeof root.hub.closePopup === "function") root.hub.closePopup()
            if (typeof root.hub.closeDashboard === "function") root.hub.closeDashboard()
        }
        root.hubLoaded = true
        if (root.isOpen) {
            root.focusWindow()
            return
        }
        root.isOpen = true
    }

    function close() {
        root.isOpen = false
    }

    function toggle() {
        if (!root.isOpen) {
            root.open()
        } else if (!root.isWindowFocused()) {
            root.focusWindow()
        } else {
            root.close()
        }
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

    title: "GPS Media Hub"
    screen: root.targetScreen
    visible: root.isOpen
    color: "transparent"
    implicitWidth: root.initialWidth
    implicitHeight: root.initialHeight
    onClosed: root.isOpen = false

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
