// TrayPopup.qml — System Tray popup panel for the GPS Left Rail.
//
// Docked to the right of the rail (left: railWidth + 6 = 46px) following the
// same PanelWindow / WlrLayer.Overlay / cursor-leave-timer pattern used by
// WifiPopup, BluetoothPopup, and BatteryPopup.
//
// Items with Status::Active or Status::NeedsAttention are shown first.
// Items with Status::Passive are collected in a collapsible "more" row.
// Left-click  → item.activate()
// Right-click → opens the item's DBus menu via QsMenuOpener
// Middle-click → item.secondaryActivate()
// Scroll      → item.scroll(±120, false)
// Tooltips    → item.tooltipTitle (or item.title as fallback)
// Icons       → item.icon (themed name or pixmap path); fallback glyph "󰠦"
// NeedsAttention items get a brandAccent accent dot.
// The popup is visible only while hub.activePopup === "tray".

import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import qs.config

PanelWindow {
    id: root

    // Injected from shell.qml
    property var hub: null

    // -----------------------------------------------------------------------
    // Visibility gating — same toggle pattern as WifiPopup / BluetoothPopup
    // -----------------------------------------------------------------------
    readonly property bool shouldBeVisible: root.hub !== null
        && root.hub.dashboardOpen
        && root.hub.activePopup === "tray"

    visible: shouldBeVisible

    onShouldBeVisibleChanged: {
        if (!shouldBeVisible) {
            hideTimer.stop()
            passiveExpanded = false
            // Close any open context menu
            if (menuOpener.menu !== null) menuOpener.menu = null
        }
    }

    // -----------------------------------------------------------------------
    // Layer-shell positioning — same contract as WifiPopup (left: 46, Overlay)
    // -----------------------------------------------------------------------
    screen: root.hub ? root.hub.popupScreen : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "gps-tray-popup"

    exclusionMode: ExclusionMode.Ignore

    anchors {
        left: true
    }

    margins {
        left: 46   // railWidth(40) + gap(6)
        top: {
            const ay = root.hub ? root.hub.popupAnchorY : 0
            const h  = root.implicitHeight
            const sh = root.screen ? root.screen.height : 800
            return Math.max(6, Math.min(ay, sh - h - 6))
        }
    }

    implicitWidth:  280
    implicitHeight: Math.min(Math.max(popupCard.implicitHeight + 2, 80), 460)

    color: "transparent"

    // -----------------------------------------------------------------------
    // Keyboard shortcut — Escape closes
    // -----------------------------------------------------------------------
    Keys.onEscapePressed: if (root.hub) root.hub.closePopup()

    // -----------------------------------------------------------------------
    // Cursor-leave auto-close timer (350 ms grace, same as WifiPopup)
    // -----------------------------------------------------------------------
    property bool hasEnteredPopup: false

    onVisibleChanged: {
        if (visible) {
            hasEnteredPopup = false
            hideTimer.stop()
        }
    }

    Timer {
        id: hideTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!popupHover.hovered && root.hub) root.hub.closePopup()
        }
    }

    // -----------------------------------------------------------------------
    // State — passive items expand/collapse row
    // -----------------------------------------------------------------------
    property bool passiveExpanded: false

    // -----------------------------------------------------------------------
    // Item lists derived from SystemTray.items
    // -----------------------------------------------------------------------
    // Active + NeedsAttention items (shown by default)
    readonly property var visibleItems: {
        const out = []
        for (let i = 0; i < SystemTray.items.count; ++i) {
            const it = SystemTray.items.values[i]
            if (it.status !== SystemTrayItem.Passive) out.push(it)
        }
        // NeedsAttention first, then Active, stable secondary by id
        out.sort((a, b) => {
            const sa = a.status === SystemTrayItem.NeedsAttention ? 0 : 1
            const sb = b.status === SystemTrayItem.NeedsAttention ? 0 : 1
            if (sa !== sb) return sa - sb
            return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
        })
        return out
    }

    // Passive items
    readonly property var passiveItems: {
        const out = []
        for (let i = 0; i < SystemTray.items.count; ++i) {
            const it = SystemTray.items.values[i]
            if (it.status === SystemTrayItem.Passive) out.push(it)
        }
        out.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
        return out
    }

    // -----------------------------------------------------------------------
    // Menu opener (shared; only one context menu at a time)
    // -----------------------------------------------------------------------
    QsMenuOpener {
        id: menuOpener
        // menu is set dynamically in onRightClicked handlers
    }

    // -----------------------------------------------------------------------
    // Main card
    // -----------------------------------------------------------------------
    Rectangle {
        id: popupCard
        anchors.fill: parent
        radius: Theme.radiusCard
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.glassBorder
        implicitHeight: innerCol.implicitHeight + 24

        HoverHandler {
            id: popupHover
            onHoveredChanged: {
                if (hovered) {
                    root.hasEnteredPopup = true
                    hideTimer.stop()
                } else if (root.hasEnteredPopup) {
                    hideTimer.restart()
                }
            }
        }

        Column {
            id: innerCol
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins: Theme.paddingMd
            }
            spacing: Theme.spacingMd

            // ----------------------------------------------------------------
            // Header row
            // ----------------------------------------------------------------
            Row {
                width: parent.width
                spacing: 0

                Text {
                    width: parent.width - 24
                    text: "SYSTEM TRAY"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSizeCaption
                    font.bold: true
                    font.letterSpacing: 1.2
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    text: "✕"
                    width: 24
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSizeSecondary
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.hub) root.hub.closePopup()
                    }
                }
            }

            // ----------------------------------------------------------------
            // Empty state
            // ----------------------------------------------------------------
            Text {
                visible: SystemTray.items.count === 0
                width: parent.width
                text: "No tray items"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSizeSecondary
                horizontalAlignment: Text.AlignHCenter
                padding: Theme.paddingMd
            }

            // ----------------------------------------------------------------
            // Visible items grid (Active + NeedsAttention)
            // ----------------------------------------------------------------
            Flow {
                id: visibleGrid
                visible: root.visibleItems.length > 0
                width: parent.width
                spacing: Theme.spacingSm

                Repeater {
                    model: root.visibleItems

                    delegate: TrayItemButton {
                        required property var modelData
                        trayItem: modelData
                        menuOpener: menuOpener
                    }
                }
            }

            // ----------------------------------------------------------------
            // Passive items section ("more" toggle)
            // ----------------------------------------------------------------
            Column {
                visible: root.passiveItems.length > 0
                width: parent.width
                spacing: Theme.spacingSm

                // "More" toggle row
                Rectangle {
                    width: parent.width
                    height: Theme.controlHeightSm
                    radius: Theme.radiusSm
                    color: moreToggleMouse.containsMouse
                        ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.10)
                        : "transparent"
                    border.width: moreToggleMouse.containsMouse ? 1 : 0
                    border.color: Theme.outlineSoft

                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXs

                        Text {
                            text: root.passiveExpanded ? "󰅃" : "󰅀"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeCaption
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.passiveExpanded
                                ? "hide passive"
                                : (root.passiveItems.length + " more")
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSizeCaption
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: moreToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.passiveExpanded = !root.passiveExpanded
                    }
                }

                // Passive items grid
                Flow {
                    visible: root.passiveExpanded
                    width: parent.width
                    spacing: Theme.spacingSm

                    Repeater {
                        model: root.passiveItems

                        delegate: TrayItemButton {
                            required property var modelData
                            trayItem: modelData
                            menuOpener: menuOpener
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Inline TrayItemButton component
    // -----------------------------------------------------------------------
    component TrayItemButton: Rectangle {
        id: itemBtn
        property var trayItem: null
        property var menuOpener: null

        width:  36
        height: 36
        radius: Theme.radiusSm
        color: itemMouse.containsMouse
            ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.15)
            : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.60)
        border.width: itemMouse.containsMouse ? 1 : 0
        border.color: itemBtn.trayItem && itemBtn.trayItem.status === SystemTrayItem.NeedsAttention
            ? Theme.brandAccent
            : Theme.outlineSoft

        scale: itemMouse.pressed ? 0.88 : (itemMouse.containsMouse ? 1.06 : 1.0)

        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        Behavior on scale {
            enabled: Theme.animationsEnabled && !Theme.reducedMotion
            NumberAnimation { duration: 120; easing.type: Easing.OutBack }
        }

        // Tray icon — themed icon name or pixmap path
        Image {
            id: itemIcon
            anchors.centerIn: parent
            width:  20
            height: 20
            sourceSize.width:  20
            sourceSize.height: 20
            fillMode: Image.PreserveAspectFit
            source: {
                if (!itemBtn.trayItem) return ""
                const ic = itemBtn.trayItem.icon
                if (!ic || ic === "") return ""
                // Quickshell resolves themed icon names as "image://icon/<name>"
                // and absolute paths directly. We let the Image handle it.
                if (ic.startsWith("/") || ic.startsWith("qrc:") || ic.startsWith("file:"))
                    return ic
                return "image://icon/" + ic
            }
            visible: status === Image.Ready
        }

        // Fallback glyph when icon is missing or failed to load
        Text {
            anchors.centerIn: parent
            visible: !itemIcon.visible
            text: "󰠦"
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 16
        }

        // NeedsAttention accent dot (bottom-right)
        Rectangle {
            visible: itemBtn.trayItem && itemBtn.trayItem.status === SystemTrayItem.NeedsAttention
            anchors {
                right:  parent.right
                bottom: parent.bottom
                margins: 3
            }
            width:  6
            height: 6
            radius: 3
            color: Theme.brandAccent
        }

        // Tooltip
        ToolTip.visible: itemMouse.containsMouse && tooltipText !== ""
        ToolTip.text:    tooltipText
        ToolTip.delay:   500

        readonly property string tooltipText: {
            if (!itemBtn.trayItem) return ""
            const tt = itemBtn.trayItem.tooltipTitle
            return (tt && tt !== "") ? tt : itemBtn.trayItem.title
        }

        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onClicked: (event) => {
                if (!itemBtn.trayItem) return
                if (event.button === Qt.LeftButton) {
                    if (itemBtn.trayItem.onlyMenu && itemBtn.trayItem.hasMenu) {
                        openMenu()
                    } else {
                        itemBtn.trayItem.activate()
                    }
                } else if (event.button === Qt.RightButton) {
                    openMenu()
                } else if (event.button === Qt.MiddleButton) {
                    itemBtn.trayItem.secondaryActivate()
                }
            }

            onWheel: (event) => {
                if (!itemBtn.trayItem) return
                const delta = event.angleDelta.y > 0 ? 120 : -120
                itemBtn.trayItem.scroll(delta, false)
            }

            function openMenu() {
                if (!itemBtn.trayItem || !itemBtn.trayItem.hasMenu) return
                if (!itemBtn.menuOpener) return
                // Graceful: item may disappear; guard with null check at bind time
                const m = itemBtn.trayItem.menu
                if (!m) return
                itemBtn.menuOpener.menu = m
                // Use item.display() to let the native menu position itself.
                // Falls back to a basic open call if display() is not available.
                if (typeof itemBtn.trayItem.display === "function") {
                    itemBtn.trayItem.display(root, itemBtn.x, itemBtn.y)
                } else {
                    itemBtn.menuOpener.menu.open()
                }
            }
        }
    }
}
