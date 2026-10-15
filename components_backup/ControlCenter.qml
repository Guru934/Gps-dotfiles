import Quickshell
import QtQuick
import qs.config

Scope {
    id: root

    required property var hub

    // Hover Tooltip Popup
    PanelWindow {
        visible: root.hub !== null && root.hub.tooltipText !== "" && !root.hub.dashboardOpen && !root.hub.powerMenuOpen

        anchors {
            bottom: true
            left: true
        }

        exclusionMode: ExclusionMode.Ignore
        margins {
            bottom: 16
            left: 64
        }

        implicitWidth: tipText.implicitWidth + 20
        implicitHeight: 28
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.surface
            border.width: 1
            border.color: Theme.brandAccent

            Text {
                id: tipText
                anchors.centerIn: parent
                text: root.hub ? root.hub.tooltipText : ""
                color: Theme.textMain
                font.family: Theme.fontUi
                font.pixelSize: 11
            }
        }
    }

    // Dynamic Single-Purpose Popup Window
    PanelWindow {
        id: popupWindow
        visible: root.hub !== null && root.hub.dashboardOpen

        anchors {
            bottom: true
            left: true
        }

        exclusionMode: ExclusionMode.Ignore
        margins {
            bottom: 8
            left: 62
        }

        implicitWidth: 336
        implicitHeight: popupCol.implicitHeight + 28
        color: "transparent"

        property bool hasEntered: false

        onVisibleChanged: {
            if (visible) {
                hasEntered = false
                autoHideTimer.stop()
            }
        }

        Timer {
            id: autoHideTimer
            interval: 380
            repeat: false
            onTriggered: {
                if (!cardHover.hovered && root.hub) {
                    root.hub.dashboardOpen = false
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusOverlay
            color: Theme.surface
            border.width: 1
            border.color: Theme.brandAccent

            HoverHandler {
                id: cardHover
                onHoveredChanged: {
                    if (hovered) {
                        popupWindow.hasEntered = true
                        autoHideTimer.stop()
                    } else if (popupWindow.hasEntered) {
                        autoHideTimer.restart()
                    }
                }
            }

            Column {
                id: popupCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 14
                }
                spacing: 8

                // ============================================================
                // VIEW 1: WI-FI ONLY POPUP
                // ============================================================
                Column {
                    visible: root.hub !== null && root.hub.activePopup === "wifi"
                    width: parent.width
                    spacing: 8

                    Row {
                        width: parent.width
                        Text {
                            text: "󰖩  WI-FI NETWORKS (" + (root.hub ? root.hub.netDevice : "wlan0") + ")"
                            color: Theme.brandAccent
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.1
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 30
                            radius: 7
                            color: (root.hub && root.hub.wifiEnabled) ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: (root.hub && root.hub.wifiEnabled) ? "󰖩  Wi-Fi: ON" : "󰖪  Wi-Fi: OFF"
                                color: (root.hub && root.hub.wifiEnabled) ? Theme.brandAccentFg : Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.toggleWifiPower()
                            }
                        }

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 30
                            radius: 7
                            color: rescanMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: (root.hub && root.hub.wifiScanning) ? "󰑐  Scanning..." : "󰑐  Rescan Wi-Fi"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: rescanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.rescanWifi()
                            }
                        }
                    }

                    Repeater {
                        model: root.hub ? root.hub.wifiNetworks : []

                        Rectangle {
                            required property var modelData
                            width: popupCol.width
                            height: 32
                            radius: 7
                            color: netItemMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: modelData.active ? Theme.statusGood : Theme.border

                            Row {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.active ? "󰄬" : "󰖩"
                                    color: modelData.active ? Theme.statusGood : Theme.brandAccent
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 105
                                    elide: Text.ElideRight
                                    text: modelData.ssid + " (" + modelData.signal + "%)"
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: modelData.active
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.active ? "Disconnect" : "Connect"
                                    color: modelData.active ? Theme.statusWarn : Theme.brandAccent
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: netItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.hub) return
                                    if (parent.modelData.active)
                                        root.hub.disconnectWifi()
                                    else
                                        root.hub.connectWifi(parent.modelData.ssid)
                                }
                            }
                        }
                    }
                }

                // ============================================================
                // VIEW 2: BLUETOOTH ONLY POPUP
                // ============================================================
                Column {
                    visible: root.hub !== null && root.hub.activePopup === "bt"
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "󰂯  BLUETOOTH DEVICES"
                        color: Theme.brandAccent
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.1
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 30
                            radius: 7
                            color: (root.hub && root.hub.btPowered) ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: (root.hub && root.hub.btPowered) ? "󰂯  BT: ON" : "󰂲  BT: OFF"
                                color: (root.hub && root.hub.btPowered) ? Theme.brandAccentFg : Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.toggleBtPower()
                            }
                        }

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 30
                            radius: 7
                            color: btScanMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: (root.hub && root.hub.btScanning) ? "󰑐  Searching..." : "󰑐  Search Devices"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: btScanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.scanBluetooth()
                            }
                        }
                    }

                    Text {
                        visible: !root.hub || root.hub.btDevices.length === 0
                        text: "No devices found yet. Click Search Devices."
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                    }

                    Repeater {
                        model: root.hub ? root.hub.btDevices : []

                        Rectangle {
                            required property var modelData
                            width: popupCol.width
                            height: 32
                            radius: 7
                            color: btItemMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: modelData.connected ? Theme.statusGood : Theme.border

                            Row {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.connected ? "󰂱" : "󰂯"
                                    color: modelData.connected ? Theme.statusGood : Theme.brandAccent
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 110
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: modelData.connected
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.connected ? "󰂲 Disconnect" : "󰂱 Connect"
                                    color: modelData.connected ? Theme.statusWarn : Theme.brandAccent
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: btItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.hub) return
                                    root.hub.toggleBtDevice(parent.modelData.mac, parent.modelData.connected)
                                }
                            }
                        }
                    }
                }

                // ============================================================
                // VIEW 3: BATTERY & POWER MODE ONLY POPUP
                // ============================================================
                Column {
                    visible: root.hub !== null && root.hub.activePopup === "battery"
                    width: parent.width
                    spacing: 8

                    Row {
                        width: parent.width
                        Text {
                            text: ((root.hub && root.hub.onAcPower) ? "󰂄  AC POWER · " : "󰁹  BATTERY · ")
                                + (root.hub ? root.hub.batteryPct : 100) + "%"
                            color: (root.hub && root.hub.onAcPower) ? Theme.statusGood : Theme.brandAccent
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.1
                        }
                    }

                    Text {
                        text: "Select Power Profile (Current: " + (root.hub ? root.hub.powerProfile : "balanced") + ")"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "power-saver", label: "󰌪 Saver" },
                                { id: "balanced", label: "󰗑 Balanced" },
                                { id: "performance", label: "󱐋 Perf" }
                            ]

                            Rectangle {
                                required property var modelData
                                readonly property bool active: root.hub !== null
                                    && root.hub.powerProfile === modelData.id
                                width: (parent.width - 12) / 3
                                height: 36
                                radius: 8
                                color: active
                                    ? Theme.brandAccent
                                    : (profMouse.containsMouse ? Theme.cardHover : Theme.card)
                                border.width: 1
                                border.color: active ? Theme.brandAccent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData.label
                                    color: parent.active ? Theme.brandAccentFg : Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: parent.active
                                }

                                MouseArea {
                                    id: profMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.hub) root.hub.setPowerProfile(parent.modelData.id)
                                }
                            }
                        }
                    }
                }

                // ============================================================
                // VIEW 4: CALENDAR + POMODORO FOCUS TIMER POPUP
                // ============================================================
                Column {
                    visible: root.hub !== null && root.hub.activePopup === "clock"
                    width: parent.width
                    spacing: 10

                    Row {
                        width: parent.width
                        height: 26

                        Text {
                            width: parent.width - 84
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰃭  " + (root.hub ? root.hub.calTitle : "")
                            color: Theme.brandAccent
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Row {
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                model: [
                                    { label: "‹", act: -1 },
                                    { label: "•", act: 0 },
                                    { label: "›", act: 1 }
                                ]

                                Rectangle {
                                    required property var modelData
                                    width: 24
                                    height: 22
                                    radius: 6
                                    color: calNavMouse.containsMouse ? Theme.cardHover : Theme.card
                                    border.width: 1
                                    border.color: Theme.border

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.modelData.label
                                        color: Theme.textMain
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: calNavMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.hub) return
                                            if (parent.modelData.act === 0) root.hub.resetCalendar()
                                            else root.hub.changeCalendarMonth(parent.modelData.act)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: calInnerCol.implicitHeight + 16
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            id: calInnerCol
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 4

                            Grid {
                                width: parent.width
                                columns: 7

                                Repeater {
                                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                    Item {
                                        required property string modelData
                                        width: calInnerCol.width / 7
                                        height: 20
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            color: Theme.brandAccent
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            Grid {
                                width: parent.width
                                columns: 7

                                Repeater {
                                    model: root.hub ? root.hub.calCells : []

                                    Item {
                                        required property var modelData
                                        width: calInnerCol.width / 7
                                        height: 24

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 24
                                            height: 22
                                            radius: 6
                                            color: parent.modelData.isToday ? Theme.brandAccent : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: parent.parent.modelData.label
                                                color: parent.parent.modelData.isToday
                                                    ? Theme.brandAccentFg
                                                    : (parent.parent.modelData.inMonth ? Theme.textMain : Theme.textMuted)
                                                opacity: parent.parent.modelData.inMonth ? 1.0 : 0.35
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                font.bold: parent.parent.modelData.isToday
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: pomoCol.implicitHeight + 18
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: (root.hub && root.hub.pomoRunning) ? Theme.statusGood : Theme.border

                        Column {
                            id: pomoCol
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 9
                            }
                            spacing: 8

                            Row {
                                width: parent.width

                                Column {
                                    width: parent.width - 130
                                    spacing: 1

                                    Text {
                                        text: "󰔛  " + (root.hub ? root.hub.pomoPhase : "Focus Timer")
                                        color: (root.hub && root.hub.pomoRunning) ? Theme.statusGood : Theme.brandAccent
                                        font.family: Theme.fontUi
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    Text {
                                        text: root.hub ? root.hub.pomoDisplay : "25:00"
                                        color: Theme.textMain
                                        font.family: Theme.fontMono
                                        font.pixelSize: 20
                                        font.bold: true
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                Row {
                                    spacing: 6
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        width: 68
                                        height: 30
                                        radius: 7
                                        color: (root.hub && root.hub.pomoRunning) ? Theme.statusWarn : Theme.brandAccent

                                        Text {
                                            anchors.centerIn: parent
                                            text: (root.hub && root.hub.pomoRunning) ? "󰏤 Pause" : "󰐊 Start"
                                            color: Theme.brandAccentFg
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (root.hub) root.hub.togglePomodoro()
                                        }
                                    }

                                    Rectangle {
                                        width: 54
                                        height: 30
                                        radius: 7
                                        color: rstMouse.containsMouse ? Theme.cardHover : Theme.track
                                        border.width: 1
                                        border.color: Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Reset"
                                            color: Theme.textMain
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                        }

                                        MouseArea {
                                            id: rstMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (root.hub) root.hub.resetPomodoro()
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 5

                                Repeater {
                                    model: [
                                        { label: "25m Focus", mins: 25, title: "Pomodoro Focus" },
                                        { label: "5m Break", mins: 5, title: "Short Break" },
                                        { label: "15m Break", mins: 15, title: "Long Break" },
                                        { label: "+5 Min", mins: -5, title: "" }
                                    ]

                                    Rectangle {
                                        required property var modelData
                                        width: (parent.width - 15) / 4
                                        height: 26
                                        radius: 6
                                        color: presetMouse.containsMouse ? Theme.cardHover : Theme.track
                                        border.width: 1
                                        border.color: presetMouse.containsMouse ? Theme.brandAccent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.parent.modelData.label
                                            color: Theme.textMain
                                            font.family: Theme.fontUi
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: presetMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.hub) return
                                                if (parent.modelData.mins === -5)
                                                    root.hub.addPomodoroMinutes(5)
                                                else
                                                    root.hub.setPomodoroPreset(parent.modelData.mins, parent.modelData.title)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ============================================================
                // VIEW 5: MAIN SETTINGS ONLY POPUP (Gear Button 󰒓)
                // ============================================================
                Column {
                    visible: root.hub !== null && root.hub.activePopup === "settings"
                    width: parent.width
                    spacing: 9

                    Row {
                        width: parent.width
                        height: 24

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 134
                            text: "✦ GPS CONTROL CENTER"
                            color: Theme.brandAccent
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.2
                        }

                        Rectangle {
                            width: 62
                            height: 22
                            radius: 6
                            color: wallMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: Theme.border
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "󰸉 Wall"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                font.bold: true
                            }

                            MouseArea {
                                id: wallMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.cycleWallpaper()
                            }
                        }

                        Item { width: 6; height: 1 }

                        Rectangle {
                            width: 64
                            height: 22
                            radius: 6
                            color: (root.hub && root.hub.dndEnabled) ? Theme.brandAccent : Theme.card
                            border.width: 1
                            border.color: (root.hub && root.hub.dndEnabled) ? Theme.brandAccent : Theme.border
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: (root.hub && root.hub.dndEnabled) ? "󰂛 DND On" : "󰂚 Alerts"
                                color: (root.hub && root.hub.dndEnabled) ? Theme.brandAccentFg : Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hub) root.hub.dndEnabled = !root.hub.dndEnabled
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            anchors { fill: parent; margins: 9 }
                            spacing: 5

                            Row {
                                Text {
                                    text: (root.hub && root.hub.isMuted) ? "󰝟  Audio (Muted)" : "󰕾  Audio Volume"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "  ·  " + (root.hub ? root.hub.volumePct : 0) + "%"
                                    color: Theme.textMain
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                id: volTrack
                                width: parent.width
                                height: 10
                                radius: 5
                                color: Theme.track

                                Rectangle {
                                    width: parent.width * Math.min(1.0, (root.hub ? root.hub.volumePct : 0) / 100.0)
                                    height: parent.height
                                    radius: 5
                                    color: (root.hub && root.hub.isMuted) ? Theme.statusWarn : Theme.brandAccent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (root.hub) root.hub.setVolumeRatio(mouse.x / volTrack.width)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            anchors { fill: parent; margins: 9 }
                            spacing: 5

                            Row {
                                Text {
                                    text: "󰖨  Display Brightness"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "  ·  " + (root.hub ? root.hub.brightnessPct : 10) + "%"
                                    color: Theme.textMain
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                id: brightTrack
                                width: parent.width
                                height: 10
                                radius: 5
                                color: Theme.track

                                Rectangle {
                                    width: parent.width * Math.min(1.0, (root.hub ? root.hub.brightnessPct : 10) / 100.0)
                                    height: parent.height
                                    radius: 5
                                    color: Theme.brandAccent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (root.hub) root.hub.setBrightnessPct((mouse.x / brightTrack.width) * 100)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Row {
                            anchors { fill: parent; margins: 10 }
                            spacing: 8

                            Column {
                                width: parent.width - 102
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (root.hub && root.hub.mediaTitle !== "")
                                        ? root.hub.mediaTitle
                                        : "No active media"
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (root.hub && root.hub.mediaArtist !== "")
                                        ? root.hub.mediaArtist
                                        : "Play audio in browser or media player"
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                }
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: [
                                        { icon: "󰒮", act: "prev" },
                                        { icon: (root.hub && root.hub.mediaStatus === "Playing") ? "󰏤" : "󰐊", act: "toggle" },
                                        { icon: "󰒭", act: "next" }
                                    ]

                                    Rectangle {
                                        required property var modelData
                                        width: 28
                                        height: 28
                                        radius: 7
                                        color: mBtnMouse.containsMouse ? Theme.cardHover : Theme.track
                                        border.width: 1
                                        border.color: mBtnMouse.containsMouse ? Theme.brandAccent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.icon
                                            color: Theme.brandAccent
                                            font.family: Theme.fontMono
                                            font.pixelSize: 13
                                        }

                                        MouseArea {
                                            id: mBtnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.hub) return
                                                if (parent.modelData.act === "prev") root.hub.mediaPrev()
                                                else if (parent.modelData.act === "toggle") root.hub.mediaPlayPause()
                                                else if (parent.modelData.act === "next") root.hub.mediaNext()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "󰀻 Apps", kind: "exec", cmd: ["env", "LC_CTYPE=C.UTF-8", "rofi", "-show", "drun"] },
                                { label: "󰉋 Files", kind: "exec", cmd: ["thunar"] },
                                { label: "󰄀 Shot", kind: "shot", cmd: [] },
                                { label: "󰐥 Power", kind: "power", cmd: [] }
                            ]

                            Rectangle {
                                required property var modelData
                                width: (parent.width - 18) / 4
                                height: 34
                                radius: 8
                                color: actMouse.containsMouse ? Theme.cardHover : Theme.card
                                border.width: 1
                                border.color: actMouse.containsMouse ? Theme.brandAccent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData.label
                                    color: parent.modelData.kind === "power" ? Theme.statusDanger : Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                MouseArea {
                                    id: actMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.hub) return
                                        const k = parent.modelData.kind
                                        root.hub.dashboardOpen = false
                                        if (k === "exec") {
                                            Quickshell.execDetached(parent.modelData.cmd)
                                        } else if (k === "shot") {
                                            root.hub.triggerScreenshot()
                                        } else if (k === "power") {
                                            root.hub.openPowerMenu()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
