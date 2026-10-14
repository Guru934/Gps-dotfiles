import Quickshell
import QtQuick
import qs.config

Scope {
    id: root

    required property var hub

    // Hover Tooltip Popup (below top-right bar)
    PanelWindow {
        visible: root.hub !== null && root.hub.tooltipText !== "" && !root.hub.dashboardOpen && !root.hub.powerMenuOpen

        anchors {
            top: true
            right: true
        }

        exclusionMode: ExclusionMode.Ignore
        margins {
            top: 52
            right: 14
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

    // Main Control Center Window (Screen C)
    PanelWindow {
        visible: root.hub !== null && root.hub.dashboardOpen

        anchors {
            top: true
            right: true
        }

        exclusionMode: ExclusionMode.Ignore
        margins {
            top: 54
            right: 12
        }

        implicitWidth: 344
        implicitHeight: 378
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusOverlay
            color: Theme.surface
            border.width: 1
            border.color: Theme.brandAccent

            Column {
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 10

                // Header
                Row {
                    width: parent.width
                    Text {
                        text: "✦ GPS CONTROL CENTER"
                        color: Theme.brandAccent
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                }

                // Network + Battery 2-Column Row
                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 50
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            anchors { fill: parent; margins: 8 }
                            spacing: 2

                            Text {
                                text: "󰖩  NETWORK (" + (root.hub ? root.hub.netDevice : "wlan0") + ")"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.hub ? root.hub.netName : "Offline"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 50
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            anchors { fill: parent; margins: 8 }
                            spacing: 2

                            Text {
                                text: (root.hub && root.hub.onAcPower) ? "󰂄  AC POWER" : "󰁹  BATTERY"
                                color: (root.hub && root.hub.onAcPower) ? Theme.statusGood : Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }

                            Text {
                                text: (root.hub ? root.hub.batteryPct : 100) + "% Charge"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }
                }

                // Audio Volume Slider Card
                Rectangle {
                    width: parent.width
                    height: 54
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

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

                // Brightness Slider Card (Clear Sun Icon 󰖨)
                Rectangle {
                    width: parent.width
                    height: 54
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

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

                // MPRIS Media Card (playerctl)
                Rectangle {
                    width: parent.width
                    height: 60
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

                // Quick Actions Row
                Row {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "󰀻 Apps", kind: "exec", cmd: ["rofi", "-show", "drun"] },
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
                                text: parent.modelData.label
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
