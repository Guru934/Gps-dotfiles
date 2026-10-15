import QtQuick
import qs.config

Grid {
    id: root

    required property var hub
    readonly property bool horiz: root.hub !== null && root.hub.isHorizontal

    columns: horiz ? 6 : 1
    spacing: 6

    // 1. Wi-Fi Button
    Rectangle {
        id: wifiBtn
        readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "wifi"
        width: Theme.sideButtonSize
        height: 30
        radius: Theme.radiusPill
        color: active ? Theme.brandAccent : (wifiMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: active ? Theme.brandAccent : Theme.border

        Behavior on color { ColorAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: (!root.hub || !root.hub.wifiEnabled || root.hub.netType === "disconnected") ? "󰖪" : "󰖩"
            color: wifiBtn.active
                ? Theme.brandAccentFg
                : ((!root.hub || !root.hub.wifiEnabled || root.hub.netType === "disconnected") ? Theme.statusWarn : Theme.brandAccent)
            font.family: Theme.fontMono
            font.pixelSize: 14
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

    // 2. Bluetooth Button
    Rectangle {
        id: btBtn
        readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "bt"
        width: Theme.sideButtonSize
        height: 30
        radius: Theme.radiusPill
        color: active ? Theme.brandAccent : (btMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: active ? Theme.brandAccent : Theme.border

        Behavior on color { ColorAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: (root.hub && root.hub.btPowered) ? "󰂯" : "󰂲"
            color: btBtn.active
                ? Theme.brandAccentFg
                : ((root.hub && root.hub.btPowered) ? Theme.brandAccent : Theme.textMuted)
            font.family: Theme.fontMono
            font.pixelSize: 14
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

    // 3. Audio Pill (High-Contrast Percentage)
    Rectangle {
        id: audioBtn
        width: root.horiz ? 58 : Theme.sideButtonSize
        height: root.horiz ? Theme.sideButtonSize : 42
        radius: Theme.radiusPill
        color: audioMouse.containsMouse ? Theme.cardHover : Theme.card
        border.width: 1
        border.color: Theme.border

        Column {
            visible: !root.horiz
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
                font.pixelSize: 10
                font.bold: true
            }
        }

        Row {
            visible: root.horiz
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: (root.hub && root.hub.isMuted) ? "󰝟" : "󰕾"
                color: (root.hub && root.hub.isMuted) ? Theme.statusWarn : Theme.brandAccent
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                text: (root.hub ? root.hub.volumePct : 0) + "%"
                color: Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            id: audioMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip("Volume: " + root.hub.volumePct + "%")
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.toggleMute()
            onWheel: event => {
                if (!root.hub) return
                if (event.angleDelta.y > 0) root.hub.stepVolume(0.05)
                else if (event.angleDelta.y < 0) root.hub.stepVolume(-0.05)
            }
        }
    }

    // 4. Battery Pill (High-Contrast Text on Active Accent)
    Rectangle {
        id: batBtn
        readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "battery"
        width: root.horiz ? 58 : Theme.sideButtonSize
        height: root.horiz ? Theme.sideButtonSize : 42
        radius: Theme.radiusPill
        color: active ? Theme.brandAccent : (batMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: active ? Theme.brandAccent : Theme.border

        Behavior on color { ColorAnimation { duration: 200 } }

        Column {
            visible: !root.horiz
            anchors.centerIn: parent
            spacing: 1

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.hub && root.hub.onAcPower) ? "󰂄" : "󰁹"
                color: batBtn.active
                    ? Theme.brandAccentFg
                    : ((root.hub && root.hub.onAcPower) ? Theme.statusGood : Theme.brandAccent)
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.hub ? root.hub.batteryPct : 100) + "%"
                color: batBtn.active ? Theme.brandAccentFg : Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 10
                font.bold: true
            }
        }

        Row {
            visible: root.horiz
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: (root.hub && root.hub.onAcPower) ? "󰂄" : "󰁹"
                color: batBtn.active
                    ? Theme.brandAccentFg
                    : ((root.hub && root.hub.onAcPower) ? Theme.statusGood : Theme.brandAccent)
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                text: (root.hub ? root.hub.batteryPct : 100) + "%"
                color: batBtn.active ? Theme.brandAccentFg : Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip("Power Mode: " + root.hub.powerProfile)
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.openPopup("battery")
            onWheel: event => {
                if (!root.hub) return
                if (event.angleDelta.y > 0) root.hub.stepBrightness(5)
                else if (event.angleDelta.y < 0) root.hub.stepBrightness(-5)
            }
        }
    }

    // 5. Clock Card
    ClockCard {
        hub: root.hub
    }

    // 6. Main Settings Gear Button (󰒓)
    Rectangle {
        id: gearBtn
        readonly property bool active: root.hub !== null && root.hub.dashboardOpen && root.hub.activePopup === "settings"
        width: Theme.sideButtonSize
        height: Theme.sideButtonSize
        radius: Theme.radiusPill
        color: active ? Theme.brandAccent : (dashMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: active ? Theme.brandAccent : Theme.border

        Behavior on color { ColorAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: "󰒓"
            color: gearBtn.active ? Theme.brandAccentFg : Theme.brandAccent
            font.family: Theme.fontMono
            font.pixelSize: 15
        }

        MouseArea {
            id: dashMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip("Settings & Bar Position")
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.openPopup("settings")
        }
    }
}
