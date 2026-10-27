import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// Layer-shell host for the dashboard drawer. Visibility, open/close
// animations, auto-hide, Escape and the edge-sensor cooldown all live here;
// Dashboard owns the visuals below it.
//
// Hub contract (same as the legacy dashboard):
//   - closePopup()      called on open, so the drawer and radio popups never overlap
//   - dashLastHide      stamped on close so the edge sensor's cooldown starts immediately
PanelWindow {
    id: root
    property var hub: null
    property bool isOpen: false
    property bool closing: false
    // Set by the bottom-right sensor while its hot zone is hovered, so the
    // small gap between the panel edge and the screen corner never counts
    // as "pointer left the console".
    property bool triggerHovered: false
    // Live binding to the hub setting; 400 ms default when no hub is attached.
    property int autoHideDelay: root.hub ? root.hub.dashboardAutoHideMs : 400
    property int openDuration: 240
    property int closeDuration: 170
    property int panelMargin: 10
    property int panelVerticalMargin: 8
    property string activeTab: "home"

    signal tabChanged(string tabName)

    readonly property bool covering: root.isOpen || root.closing
    readonly property int drawerWidth: root.screen
        ? Math.min(Theme.dashboardWidth, root.screen.width - 24)
        : Theme.dashboardWidth

    function open() {
        if (root.isOpen) return
        closeResetTimer.stop()
        root.closing = false
        root.isOpen = true
    }

    function close() {
        if (!root.isOpen) return
        root.isOpen = false
        root.closing = true
        closeResetTimer.restart()
    }

    function toggle() {
        if (root.isOpen) root.close()
        else root.open()
    }

    function scheduleHide() {
        if (!root.isOpen) return
        if (root.triggerHovered || contentHover.hovered) {
            hideTimer.stop()
            return
        }
        hideTimer.restart()
    }

    function probePointer() {
        if (!root.isOpen) return
        if (root.triggerHovered) {
            hideTimer.stop()
            return
        }
        if (!pointerProbe.running) pointerProbe.running = true
    }

    function finishPointerProbe(inside) {
        if (!root.isOpen) return
        if (inside || root.triggerHovered) {
            hideTimer.restart()
            return
        }
        root.close()
    }

    function pointerInsidePanel(px, py) {
        if (!root.screen) return false
        const left = root.screen.x + root.screen.width - root.drawerWidth - root.panelMargin
        const top = root.screen.y + root.panelVerticalMargin
        const right = left + root.drawerWidth
        const bottom = root.screen.y + root.screen.height - root.panelVerticalMargin
        return px >= left && px < right && py >= top && py < bottom
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            hideTimer.stop()
            if (root.hub && typeof root.hub.closePopup === "function") root.hub.closePopup()
        } else {
            // Stop any pending auto-hide first, then stamp the cooldown so the
            // bottom-right sensor cannot instantly reopen the drawer.
            hideTimer.stop()
            pointerProbe.running = false
            if (root.hub) root.hub.dashLastHide = Date.now()
        }
    }

    onTriggerHoveredChanged: {
        if (!root.isOpen) return
        if (root.triggerHovered) hideTimer.stop()
        else root.scheduleHide()
    }

    Component.onDestruction: {
        hideTimer.stop()
        closeResetTimer.stop()
        pointerProbe.running = false
    }

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; right: true }
    margins { top: root.panelVerticalMargin; bottom: root.panelVerticalMargin; right: root.panelMargin }
    implicitWidth: root.drawerWidth
    color: "transparent"
    // The window must stay mapped through the close animation, then unmap:
    // an invisible overlay surface would still swallow pointer input.
    visible: root.covering
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut {
        objectName: "escapeShortcut"
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.isOpen
        onActivated: root.close()
    }

    // Auto-hide: 400 ms after the pointer leaves the whole drawer and the
    // bottom-right hot zone; entering either one cancels. The timer only ever
    // starts on exit, so arriving from the sensor can never close the drawer
    // prematurely.
    Timer {
        id: hideTimer
        interval: root.autoHideDelay
        repeat: false
        onTriggered: {
            if (!root.isOpen || root.triggerHovered || contentHover.hovered) return
            root.probePointer()
        }
    }

    Process {
        id: pointerProbe
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: pointerProbeOut
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.finishPointerProbe(false)
                return
            }
            const parts = String(pointerProbeOut.text).trim().split(/[\s,]+/)
            const px = Number(parts[0])
            const py = Number(parts[1])
            const valid = parts.length >= 2 && Number.isFinite(px) && Number.isFinite(py)
            root.finishPointerProbe(valid && root.pointerInsidePanel(px, py))
        }
    }

    // Keeps the surface mapped until the slide/fade-out finished.
    Timer {
        id: closeResetTimer
        interval: root.closeDuration + 60
        repeat: false
        onTriggered: root.closing = false
    }

    Item {
        id: contentRoot
        objectName: "contentRoot"
        // No anchors here: the slide relies on x, and anchors would win over
        // (and silently reset) the x binding.
        width: root.width
        height: root.height
        x: root.isOpen ? 0 : root.width
        opacity: root.isOpen ? 1 : 0

        Behavior on x {
            NumberAnimation {
                duration: root.isOpen ? root.openDuration : root.closeDuration
                easing.type: root.isOpen ? Easing.OutCubic : Easing.InCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: root.isOpen ? root.openDuration : root.closeDuration
                easing.type: root.isOpen ? Easing.OutCubic : Easing.InCubic
            }
        }

        Dashboard {
            anchors.fill: parent
            hub: root.hub
            isOpen: root.isOpen
            covering: root.covering
            activeTab: root.activeTab
            onCloseRequested: root.close()
            onTabRequested: (tabName) => {
                root.activeTab = tabName
                root.tabChanged(tabName)
            }
        }

        HoverHandler {
            id: contentHover
            onHoveredChanged: {
                if (hovered || root.triggerHovered) hideTimer.stop()
                else root.scheduleHide()
            }
        }
    }
}
