import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config

// Compact Wi-Fi popup docked immediately right of the Left Rail, vertically
// anchored near the rail Wi-Fi icon (hub.popupAnchorY, clamped on-screen).
// All state and actions live on the master shell (hub); this is pure UI.
PanelWindow {
    id: root

    property var hub: null
    readonly property var networks: root.hub ? root.hub.wifiNetworks : []
    readonly property bool isOpen: root.hub ? (root.hub.dashboardOpen && root.hub.activePopup === "wifi") : false
    readonly property bool busy: root.hub ? (root.hub.wifiScanning || root.hub.wifiPending !== "") : false
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
            const h = root.height > 0 ? root.height : 400
            const sh = root.targetScreen ? root.targetScreen.height : 900
            const ay = (root.hub && root.hub.popupAnchorY >= 0) ? root.hub.popupAnchorY : Math.round(sh / 2)
            return Math.max(8, Math.min(Math.max(8, sh - h - 8), ay - h / 2))
        }
    }
    implicitWidth: 330
    implicitHeight: Math.min(430, Math.max(200, mainCol.implicitHeight + 24))
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
                Text { text: "WI-FI"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 14; font.bold: true; anchors { left: parent.left; verticalCenter: parent.verticalCenter } }
                Row {
                    spacing: 6
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    // Power toggle pill
                    Rectangle {
                        width: 52; height: 26; radius: 13
                        color: (root.hub && root.hub.wifiStatusAvailable && root.hub.wifiEnabled)
                            ? Theme.brandAccent
                            : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: !root.hub || !root.hub.wifiStatusAvailable
                                ? "N/A"
                                : (root.hub.wifiEnabled ? "ON" : "OFF")
                            color: (root.hub && root.hub.wifiStatusAvailable && root.hub.wifiEnabled)
                                ? Theme.brandAccentFg
                                : Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.hub && root.hub.wifiStatusAvailable
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (root.hub) root.hub.toggleWifiPower()
                        }
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
                    if (!root.hub || !root.hub.wifiStatusAvailable) return "Unavailable"
                    if (root.hub.wifiConnected) return "Connected: " + root.hub.netName
                    return root.hub.wifiEnabled ? "Not connected" : "Radio disabled"
                }
                color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                elide: Text.ElideRight
            }

            // Error banner (honest failures only)
            Rectangle {
                width: parent.width; height: errText.implicitHeight + 12
                radius: Theme.radiusSm; color: Theme.statusDangerBg; border.width: Theme.borderWidth; border.color: Theme.statusDangerBorder
                visible: root.hub && root.hub.wifiError !== ""
                Text {
                    id: errText; anchors.fill: parent; anchors.margins: 6
                    text: root.hub ? root.hub.wifiError : ""
                    color: Theme.statusDangerFg; font.family: Theme.fontUi; font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }

            // Notice banner (loading / success states)
            Rectangle {
                width: parent.width; height: noticeText.implicitHeight + 12
                radius: Theme.radiusSm; color: Theme.card; border.width: Theme.borderWidth; border.color: Theme.outlineSoft
                visible: root.hub && root.hub.wifiError === "" && root.hub.wifiNotice !== ""
                Text {
                    id: noticeText; anchors.fill: parent; anchors.margins: 6
                    text: root.hub ? root.hub.wifiNotice : ""
                    color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                width: parent.width; height: 30; radius: 9
                color: scanMouse.containsMouse ? Theme.cardHover : Theme.card
                border.width: 1; border.color: scanMouse.containsMouse ? Theme.brandAccent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "Scanning…" : "⟳  Scan for networks"
                    color: root.busy ? Theme.textMuted : Theme.textMain
                    font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true
                }
                MouseArea { id: scanMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub) root.hub.rescanWifi() }
            }

            Text { text: "AVAILABLE NETWORKS"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }

            // Loading state
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                visible: root.busy && root.networks.length === 0
                text: "Scanning for networks…"
                color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 11
            }

            // Empty state
            Column {
                width: parent.width; spacing: 4
                visible: !root.busy && root.networks.length === 0
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: (!root.hub || !root.hub.wifiStatusAvailable)
                        ? "Wi-Fi is unavailable."
                        : (!root.hub.wifiEnabled ? "Wi-Fi radio is off." : "No networks found.")
                    color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 11
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Try scanning again."
                    color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 9
                }
            }

            ListView {
                id: netList
                width: parent.width
                height: netList.visible ? Math.min(208, netList.contentHeight) : 0
                spacing: 6
                clip: true
                visible: root.networks.length > 0
                model: root.networks
                delegate: Rectangle {
                    id: networkRow
                    required property var modelData
                    readonly property bool activeNetwork: root.hub
                        && root.hub.netType === "wifi"
                        && root.hub.netName === modelData.ssid
                    width: netList.width
                    height: 46
                    radius: Theme.radiusMd
                    color: activeNetwork ? Qt.alpha(Theme.brandAccent, 0.18) : Theme.card
                    border.width: Theme.borderWidth
                    border.color: activeNetwork ? Theme.brandAccent : Theme.outlineSoft
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8
                        Column {
                            width: parent.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: (modelData.secured ? "🔒 " : "") + modelData.ssid
                                color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: (activeNetwork ? "Connected · " : "") + modelData.signal + "%" + (modelData.secured ? " · secured" : " · open")
                                color: activeNetwork ? Theme.brandAccent : Theme.textMuted
                                font.family: Theme.fontMono; font.pixelSize: 8
                            }
                        }
                        Rectangle {
                            width: 84; height: 26; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: btnMouse.containsMouse ? Theme.brandAccent : (activeNetwork ? Theme.card : Theme.brandAccent)
                            border.width: 1
                            border.color: Theme.brandAccent
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (root.hub && root.hub.wifiPending === "connect" && root.hub.wifiPendingTarget === modelData.ssid) return "…"
                                    return networkRow.activeNetwork ? "Leave" : "Join"
                                }
                                color: (btnMouse.containsMouse || !networkRow.activeNetwork) ? Theme.brandAccentFg : Theme.textMain
                                font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true
                            }
                            MouseArea {
                                id: btnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.hub) return
                                    if (networkRow.activeNetwork) root.hub.disconnectWifi()
                                    else root.hub.connectWifi(modelData.ssid, modelData.secured)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Secured networks ask for a password via a system prompt. Passwords are never shown or stored here."
                color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 8
                wrapMode: Text.WordWrap
            }
        }
    }
}
