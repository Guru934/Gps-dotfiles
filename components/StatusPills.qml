import QtQuick
import qs.config

Row {
    id: root

    required property var hub
    spacing: 6

    // 1. Unambiguous Media Pill (Hidden when stopped; 󰎆 = Playing, 󰏤 = Paused)
    Rectangle {
        visible: root.hub !== null && root.hub.mediaStatus !== "Stopped" && root.hub.mediaTitle !== ""
        height: Theme.pillHeight
        width: mediaRow.implicitWidth + 14
        radius: Theme.radiusPill
        color: mediaMouse.containsMouse ? Theme.cardHover : Theme.card
        border.width: 1
        border.color: (root.hub && root.hub.mediaStatus === "Playing") ? Theme.brandAccent : Theme.border

        Row {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (root.hub && root.hub.mediaStatus === "Playing") ? "󰎆" : "󰏤"
                color: (root.hub && root.hub.mediaStatus === "Playing") ? Theme.brandAccent : Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 120)
                elide: Text.ElideRight
                text: root.hub ? root.hub.mediaTitle : ""
                color: (root.hub && root.hub.mediaStatus === "Playing") ? Theme.textMain : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.bold: (root.hub && root.hub.mediaStatus === "Playing")
            }
        }

        MouseArea {
            id: mediaMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip(
                (root.hub.mediaStatus === "Playing" ? "Playing: " : "Paused: ")
                + root.hub.mediaTitle
                + (root.hub.mediaArtist !== "" ? " — " + root.hub.mediaArtist : "")
                + "  (Click: Play/Pause · Scroll: Prev/Next)"
            )
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.mediaPlayPause()
            onWheel: event => {
                if (!root.hub) return
                if (event.angleDelta.y > 0)
                    root.hub.mediaPrev()
                else if (event.angleDelta.y < 0)
                    root.hub.mediaNext()
            }
        }
    }

    // 2. Merged Hardware Pill: [ 󰖩  ·  󰕾 95%  ·  󰂄 80% ]
    Rectangle {
        height: Theme.pillHeight
        width: hwRow.implicitWidth + 14
        radius: Theme.radiusPill
        color: Theme.card
        border.width: 1
        border.color: Theme.border

        Row {
            id: hwRow
            anchors.centerIn: parent
            spacing: 4

            // A. Compact Wi-Fi Icon (SSID shown on hover tooltip or in Control Center)
            Rectangle {
                height: 22
                width: 24
                radius: 6
                color: netMouse.containsMouse ? Theme.cardHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: (!root.hub || root.hub.netType === "wifi")
                        ? "󰖩"
                        : (root.hub.netType === "ethernet" ? "󰈀" : "󰖪")
                    color: (root.hub && root.hub.netType === "disconnected") ? Theme.statusWarn : Theme.brandAccent
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(
                        "Network: " + root.hub.netName + " (" + root.hub.netDevice + ") · Click for Control Center"
                    )
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.toggleDashboard()
                }
            }

            Rectangle { width: 1; height: 12; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }

            // B. Audio Volume (Click = Mute, Scroll = Volume)
            Rectangle {
                height: 22
                width: audioSeg.implicitWidth + 10
                radius: 6
                color: audioMouse.containsMouse ? Theme.cardHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: audioSeg
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.hub && root.hub.isMuted) ? "󰝟" : "󰕾"
                        color: (root.hub && root.hub.isMuted) ? Theme.statusWarn : Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.hub ? root.hub.volumePct : 0) + "%"
                        color: (root.hub && root.hub.isMuted) ? Theme.textMuted : Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: audioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(
                        "Volume: " + root.hub.volumePct + "% · Click to Mute · Scroll to adjust"
                    )
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.toggleMute()
                    onWheel: event => {
                        if (!root.hub) return
                        if (event.angleDelta.y > 0)
                            root.hub.stepVolume(0.05)
                        else if (event.angleDelta.y < 0)
                            root.hub.stepVolume(-0.05)
                    }
                }
            }

            Rectangle { width: 1; height: 12; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }

            // C. Battery & Power (Scroll = Adjust Brightness with OSD!)
            Rectangle {
                height: 22
                width: batSeg.implicitWidth + 10
                radius: 6
                color: batMouse.containsMouse ? Theme.cardHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: batSeg
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.hub && root.hub.onAcPower) ? "󰂄" : "󰁹"
                        color: (root.hub && root.hub.onAcPower)
                            ? Theme.statusGood
                            : ((root.hub && root.hub.batteryPct <= 20) ? Theme.statusWarn : Theme.brandAccent)
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.hub ? root.hub.batteryPct : 100) + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: batMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(
                        (root.hub.onAcPower ? "AC Power · " : "Battery · ")
                        + root.hub.batteryPct + "%  |  Brightness: "
                        + root.hub.brightnessPct + "% (Scroll here to adjust)"
                    )
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: if (root.hub) root.hub.toggleDashboard()
                    onWheel: event => {
                        if (!root.hub) return
                        if (event.angleDelta.y > 0)
                            root.hub.stepBrightness(5)
                        else if (event.angleDelta.y < 0)
                            root.hub.stepBrightness(-5)
                    }
                }
            }
        }
    }

    // 3. SystemClock Pill
    ClockCard {
    }

    // 4. Control Center / Quick Settings Button (󰒓)
    Rectangle {
        width: Theme.pillHeight
        height: Theme.pillHeight
        radius: Theme.radiusPill
        color: (root.hub && root.hub.dashboardOpen)
            ? Theme.brandAccent
            : (dashMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.width: 1
        border.color: (root.hub && root.hub.dashboardOpen) ? Theme.brandAccent : Theme.border

        Text {
            anchors.centerIn: parent
            text: "󰒓"
            color: (root.hub && root.hub.dashboardOpen) ? Theme.brandAccentFg : Theme.brandAccent
            font.family: Theme.fontMono
            font.pixelSize: 13
        }

        MouseArea {
            id: dashMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip("Control Center & Power Menu")
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: if (root.hub) root.hub.toggleDashboard()
        }
    }
}
