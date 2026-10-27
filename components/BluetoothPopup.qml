import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config

// Compact Bluetooth popup docked immediately right of the Left Rail,
// vertically anchored near the rail Bluetooth icon (hub.popupAnchorY,
// clamped on-screen). All state and actions live on the master shell (hub).
PanelWindow {
    id: root

    property var hub: null
    readonly property var devices: root.hub ? root.hub.btDevices : []
    readonly property bool isOpen: root.hub ? (root.hub.dashboardOpen && root.hub.activePopup === "bt") : false
    readonly property bool busy: root.hub ? (root.hub.btScanning || root.hub.btPending !== "") : false
    readonly property var targetScreen: (root.hub && root.hub.popupScreen)
        ? root.hub.popupScreen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    function close() {
        hideTimer.stop()
        if (root.hub) root.hub.closePopup()
    }

    onIsOpenChanged: if (!root.isOpen) hideTimer.stop()

    screen: targetScreen
    anchors { top: true; left: true }
    margins {
        // Rail is 54 wide; dock with an 8px gap. Clamp vertically so the
        // popup never leaves the screen even if the anchor is at an edge.
        left: 62
        top: {
            const h = root.height > 0 ? root.height : 320
            const sh = root.targetScreen ? root.targetScreen.height : 900
            const ay = (root.hub && root.hub.popupAnchorY >= 0) ? root.hub.popupAnchorY : Math.round(sh / 2)
            return Math.max(8, Math.min(Math.max(8, sh - h - 8), ay - h / 2))
        }
    }
    implicitWidth: 330
    implicitHeight: Math.min(350, Math.max(190, mainCol.implicitHeight + 24))
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.isOpen; onActivated: root.close() }

    // Cursor-leave dismissal with a grace period. The timer only ever starts
    // when the pointer exits the popup, so moving in from the rail icon can
    // never close it prematurely; entering cancels a pending dismissal.
    Timer {
        id: hideTimer
        interval: 350
        repeat: false
        onTriggered: root.close()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        MouseArea {
            anchors.fill: parent
            z: 20
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: hideTimer.stop()
            onExited: hideTimer.start()
        }

        Column {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 26
                Text { text: "BLUETOOTH"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 14; font.bold: true; anchors { left: parent.left; verticalCenter: parent.verticalCenter } }
                Row {
                    spacing: 6
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    // Power toggle pill
                    Rectangle {
                        width: 52; height: 26; radius: 13
                        color: (root.hub && root.hub.btPowered) ? Theme.brandAccent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: (root.hub && root.hub.btPowered) ? "ON" : "OFF"
                            color: (root.hub && root.hub.btPowered) ? Theme.brandAccentFg : Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub) root.hub.toggleBtPower() }
                    }
                    // Close button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: closeMouse.containsMouse ? Theme.cardHover : Theme.card
                        Text { anchors.centerIn: parent; text: "✕"; color: Theme.textMuted; font.pixelSize: 11 }
                        MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                    }
                }
            }

            Text {
                width: parent.width
                text: {
                    if (!root.hub) return "Unavailable"
                    if (!root.hub.btPowered) return "Adapter off"
                    if (root.hub.btConnectedName !== "") return "Connected: " + root.hub.btConnectedName
                    return "On · no device connected"
                }
                color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                elide: Text.ElideRight
            }

            // Error banner (honest failures only)
            Rectangle {
                width: parent.width; height: errText.implicitHeight + 12
                radius: 8; color: "#3A2226"; border.width: 1; border.color: Theme.statusDanger
                visible: root.hub && root.hub.btError !== ""
                Text {
                    id: errText; anchors.fill: parent; anchors.margins: 6
                    text: root.hub ? root.hub.btError : ""
                    color: Theme.statusDanger; font.family: Theme.fontUi; font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            // Notice banner (loading / success states)
            Rectangle {
                width: parent.width; height: noticeText.implicitHeight + 12
                radius: 8; color: Theme.card; border.width: 1; border.color: Theme.border
                visible: root.hub && root.hub.btError === "" && root.hub.btNotice !== ""
                Text {
                    id: noticeText; anchors.fill: parent; anchors.margins: 6
                    text: root.hub ? root.hub.btNotice : ""
                    color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                width: parent.width; height: 30; radius: 9
                color: scanMouse.containsMouse ? Theme.cardHover : Theme.card
                border.width: 1; border.color: scanMouse.containsMouse ? Theme.brandAccent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: (root.hub && root.hub.btScanning) ? "Scanning…" : "⟳  Scan for devices"
                    color: (root.hub && root.hub.btScanning) ? Theme.textMuted : Theme.textMain
                    font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true
                }
                MouseArea { id: scanMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub) root.hub.scanBluetooth() }
            }

            Text { text: "DEVICES"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }

            // Loading state
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                visible: (root.hub && root.hub.btScanning) && root.devices.length === 0
                text: "Scanning for devices…"
                color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 11
            }

            // Empty state
            Column {
                width: parent.width; spacing: 4
                visible: !(root.hub && root.hub.btScanning) && root.devices.length === 0
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: (root.hub && !root.hub.btPowered) ? "Bluetooth adapter is off." : "No devices found."
                    color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 11
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Put the device in pairing mode, then scan."
                    color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9
                }
            }

            ListView {
                id: devList
                width: parent.width
                height: devList.visible ? Math.min(192, devList.contentHeight) : 0
                spacing: 6
                clip: true
                visible: root.devices.length > 0
                model: root.devices
                delegate: Rectangle {
                    required property var modelData
                    width: devList.width
                    height: 58
                    radius: 10
                    color: modelData.connected ? "#243B3A" : Theme.card
                    border.width: 1
                    border.color: modelData.connected ? Theme.brandAccent : Theme.border
                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        Text {
                            width: parent.width
                            text: modelData.name
                            color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true
                            elide: Text.ElideRight
                        }
                        Item {
                            width: parent.width; height: 24
                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: parent.width - actionRow.width - 8
                                text: (modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Found")) + " · " + modelData.mac
                                color: modelData.connected ? Theme.brandAccent : Theme.textMuted
                                font.family: Theme.fontMono; font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                            Row {
                                id: actionRow
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                // Pair button (only for unpaired devices)
                                Rectangle {
                                    width: 52; height: 24; radius: 7
                                    visible: !modelData.paired && !modelData.connected
                                    color: pairMouse.containsMouse ? Theme.cardHover : Theme.card
                                    border.width: 1; border.color: Theme.border
                                    Text { anchors.centerIn: parent; text: "Pair"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true }
                                    MouseArea { id: pairMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub) root.hub.pairBtDevice(modelData.mac) }
                                }
                                // Connect / Disconnect button
                                Rectangle {
                                    width: 86; height: 24; radius: 7
                                    color: connMouse.containsMouse ? Theme.brandAccent : (modelData.connected ? Theme.card : Theme.brandAccent)
                                    border.width: 1; border.color: Theme.brandAccent
                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (root.hub && root.hub.btBusyMac === modelData.mac && root.hub.btPending !== "") return "…"
                                            return modelData.connected ? "Disconnect" : "Connect"
                                        }
                                        color: (connMouse.containsMouse || !modelData.connected) ? Theme.brandAccentFg : Theme.textMain
                                        font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true
                                    }
                                    MouseArea { id: connMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub) root.hub.toggleBtDevice(modelData.mac, modelData.connected) }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Pairing success is only shown after the adapter confirms it."
                color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 8
                wrapMode: Text.WordWrap
            }
        }
    }
}
