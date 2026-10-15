import QtQuick
import qs.config

Column {
    id: root

    required property var hub
    spacing: 6

    // 1. Compact Media Button
    Rectangle {
        visible: root.hub !== null && root.hub.mediaStatus !== "Stopped" && root.hub.mediaTitle !== ""
        width: Theme.sideButtonSize
        height: Theme.sideButtonSize
        radius: Theme.radiusPill
        color: mediaMouse.containsMouse ? Theme.cardHover : Theme.card
        border.width: 1
        border.color: (root.hub && root.hub.mediaStatus === "Playing") ? Theme.brandAccent : Theme.border

        Text {
            anchors.centerIn: parent
            text: (root.hub && root.hub.mediaStatus === "Playing") ? "󰎆" : "󰏤"
            color: (root.hub && root.hub.mediaStatus === "Playing") ? Theme.brandAccent : Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 14
        }

        MouseArea {
            id: mediaMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip(
                (root.hub.mediaStatus === "Playing" ? "Playing: " : "Paused: ") + root.hub.mediaTitle
            )
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.mediaPlayPause()
            onWheel: event => {
                if (!root.hub) return
                if (event.angleDelta.y > 0) root.hub.mediaPrev()
                else if (event.angleDelta.y < 0) root.hub.mediaNext()
            }
        }
    }

    // 2. Wi-Fi & Bluetooth Vertical Island
    Rectangle {
        width: Theme.sideButtonSize
        height: netBtCol.implicitHeight + 10
        radius: Theme.radiusPill
        color: Theme.card
        border.width: 1
        border.color: Theme.border

        Column {
            id: netBtCol
            anchors.centerIn: parent
            spacing: 4

            // Wi-Fi Button -> Opens ONLY Wi-Fi Popup
            Rectangle {
                readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "wifi"
                width: 26
                height: 24
                radius: 6
                color: active ? Theme.brandAccent : (wifiMouse.containsMouse ? Theme.cardHover : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: (!root.hub || !root.hub.wifiEnabled || root.hub.netType === "disconnected") ? "󰖪" : "󰖩"
                    color: parent.active
                        ? Theme.brandAccentFg
                        : ((!root.hub || !root.hub.wifiEnabled || root.hub.netType === "disconnected") ? Theme.statusWarn : Theme.brandAccent)
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip("Wi-Fi: " + root.hub.netName)
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.openPopup("wifi")
                }
            }

            Rectangle { width: 16; height: 1; color: Theme.border; anchors.horizontalCenter: parent.horizontalCenter }

            // Bluetooth Button -> Opens ONLY Bluetooth Popup
            Rectangle {
                readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "bt"
                width: 26
                height: 24
                radius: 6
                color: active ? Theme.brandAccent : (btMouse.containsMouse ? Theme.cardHover : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: (root.hub && root.hub.btPowered) ? "󰂯" : "󰂲"
                    color: parent.active
                        ? Theme.brandAccentFg
                        : ((root.hub && root.hub.btPowered) ? Theme.brandAccent : Theme.textMuted)
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }

                MouseArea {
                    id: btMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(
                        "Bluetooth: " + (root.hub.btPowered ? (root.hub.btConnectedName || "On") : "Off")
                    )
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.openPopup("bt")
                }
            }
        }
    }

    // 3. Audio + Battery Vertical Island
    Rectangle {
        width: Theme.sideButtonSize
        height: hwCol.implicitHeight + 12
        radius: Theme.radiusPill
        color: Theme.card
        border.width: 1
        border.color: Theme.border

        Column {
            id: hwCol
            anchors.centerIn: parent
            spacing: 6

            // Audio (Click = Mute, Scroll = Volume)
            Rectangle {
                width: 28
                height: volCol.implicitHeight + 4
                radius: 6
                color: audioMouse.containsMouse ? Theme.cardHover : "transparent"

                Column {
                    id: volCol
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.hub && root.hub.isMuted) ? "󰝟" : "󰕾"
                        color: (root.hub && root.hub.isMuted) ? Theme.statusWarn : Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.hub ? root.hub.volumePct : 0) + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                MouseArea {
                    id: audioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip("Volume: " + root.hub.volumePct + "% (Click: Mute · Scroll: Vol)")
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.toggleMute()
                    onWheel: event => {
                        if (!root.hub) return
                        if (event.angleDelta.y > 0) root.hub.stepVolume(0.05)
                        else if (event.angleDelta.y < 0) root.hub.stepVolume(-0.05)
                    }
                }
            }

            Rectangle { width: 16; height: 1; color: Theme.border; anchors.horizontalCenter: parent.horizontalCenter }

            // Battery -> Opens ONLY Power Mode Selector (Scroll = Brightness)
            Rectangle {
                readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "battery"
                width: 28
                height: batCol.implicitHeight + 4
                radius: 6
                color: active ? Theme.brandAccent : (batMouse.containsMouse ? Theme.cardHover : "transparent")

                Column {
                    id: batCol
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.hub && root.hub.onAcPower) ? "󰂄" : "󰁹"
                        color: parent.active
                            ? Theme.brandAccentFg
                            : ((root.hub && root.hub.onAcPower) ? Theme.statusGood : Theme.brandAccent)
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.hub ? root.hub.batteryPct : 100) + "%"
                        color: parent.active ? Theme.brandAccentFg : Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                MouseArea {
                    id: batMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(
                        "Power Mode: " + root.hub.powerProfile + " (Click: Switch Mode · Scroll: Brightness)"
                    )
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.openPopup("battery")
                    onWheel: event => {
                        if (!root.hub) return
                        if (event.angleDelta.y > 0) root.hub.stepBrightness(5)
                        else if (event.angleDelta.y < 0) root.hub.stepBrightness(-5)
                    }
                }
            }
        }
    }

    // 4. Vertical Clock (Click -> Opens Calendar & Pomodoro Popup)
    ClockCard {
        hub: root.hub
    }

    // 5. Main Settings Gear Button (󰒓) -> Opens ONLY Main Settings
    Rectangle {
        readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "settings"
        width: Theme.sideButtonSize
        height: Theme.sideButtonSize
        radius: Theme.radiusPill
        color: active ? Theme.brandAccent : (dashMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: active ? Theme.brandAccent : Theme.border

        Text {
            anchors.centerIn: parent
            text: "󰒓"
            color: parent.active ? Theme.brandAccentFg : Theme.brandAccent
            font.family: Theme.fontMono
            font.pixelSize: 14
        }

        MouseArea {
            id: dashMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip("Main Settings & Sliders")
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.openPopup("settings")
        }
    }
}
