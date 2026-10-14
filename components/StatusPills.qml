import QtQuick
import qs.config

Row {
    id: root

    required property var hub
    spacing: 6

    // 1. Standalone Media Pill (Click = Play/Pause, Scroll = Prev/Next Track)
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
                text: (root.hub && root.hub.mediaStatus === "Playing") ? "󰐊" : "󰏤"
                color: Theme.brandAccent
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 110)
                elide: Text.ElideRight
                text: root.hub ? root.hub.mediaTitle : ""
                color: Theme.textMain
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            id: mediaMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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

    // 2. Unified Hardware Status Island (Wi-Fi + Brightness + Audio + Battery)
    Rectangle {
        height: Theme.pillHeight
        width: hwRow.implicitWidth + 12
        radius: Theme.radiusPill
        color: Theme.card
        border.width: 1
        border.color: Theme.border

        Row {
            id: hwRow
            anchors.centerIn: parent
            spacing: 2

            // A. Network Segment
            Rectangle {
                height: 22
                width: netSeg.implicitWidth + 10
                radius: 6
                color: netMouse.containsMouse ? Theme.cardHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: netSeg
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (!root.hub || root.hub.netType === "wifi")
                            ? "󰖩"
                            : (root.hub.netType === "ethernet" ? "󰈀" : "󰖪")
                        color: (root.hub && root.hub.netType === "disconnected") ? Theme.statusWarn : Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 82)
                        elide: Text.ElideRight
                        text: root.hub ? root.hub.netName : "Offline"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.hub) root.hub.toggleDashboard()
                }
            }

            Rectangle { width: 1; height: 12; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }

            // B. Brightness Segment (Scroll Wheel -> nvidia_wmi_ec_backlight)
            Rectangle {
                height: 22
                width: brightSeg.implicitWidth + 10
                radius: 6
                color: brightMouse.containsMouse ? Theme.cardHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: brightSeg
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰃠"
                        color: Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.hub ? root.hub.brightnessPct : 10) + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: brightMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
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

            Rectangle { width: 1; height: 12; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }

            // C. Audio Segment (Click = Mute, Scroll Wheel = Volume)
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
                        color: Theme.textMain
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

            // D. Battery Segment
            Rectangle {
                height: 22
                width: batSeg.implicitWidth + 10
                radius: 6
                color: "transparent"
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
            }
        }
    }

    // 3. SystemClock Pill
    ClockCard {
    }

    // 4. Control Center Toggle Button (◉)
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
            text: "◉"
            color: (root.hub && root.hub.dashboardOpen) ? Theme.brandAccentFg : Theme.brandAccent
            font.family: Theme.fontMono
            font.pixelSize: 13
            font.bold: true
        }

        MouseArea {
            id: dashMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.hub) root.hub.toggleDashboard()
        }
    }
}
