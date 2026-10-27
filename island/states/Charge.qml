// Island state: charge — plug-in/unplug flash (260×44) · low battery (260×44) · critical (260×44) · expanded telemetry (360×110, on hover)
// Live battery telemetry from UPower via Island.qml (`core`) + power-profiles-daemon via `powerprofilesctl` while active.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: st
    required property var core
    readonly property string key: "charge"

    readonly property bool active: core.mode === key
    readonly property bool isCrit: core.hasBat && !core.charging && !core.full && core.batPct <= 5
    readonly property bool isLow: core.hasBat && !core.charging && !core.full && !isCrit && (core.batPct <= 20 || core.chargeKind === "low")
    readonly property bool expanded: core.hovered
    readonly property bool showPlug: !expanded && !isLow && !isCrit
    readonly property bool showLow: !expanded && isLow
    readonly property bool showCrit: !expanded && isCrit

    property string profile: ""
    property bool hasSaver: false
    property bool hasBalanced: false
    property bool hasPerf: false
    property string pendingProfile: ""
    readonly property bool hasProfiles: profile !== ""

    readonly property real tte: core.hasBat && core.bat ? core.bat.timeToEmpty : 0
    readonly property string pctText: core.hasBat ? Math.round(core.batPct) + "%" : ""
    readonly property string stateWord: core.charging ? "CHARGING" : core.full ? "FULL" : "ON BATTERY"
    readonly property string telemetryHeadline: core.watts >= 0.1 ? core.watts.toFixed(1) + " W · " + stateWord : stateWord
    readonly property string etaText: core.charging && core.ttf > 0
        ? core.fmtEta(core.ttf) + " to full"
        : (!core.charging && tte > 0 ? core.fmtEta(tte) + " left" : "")
    readonly property string tempText: core.showTemp && core.temp > 0 ? core.temp + "°C" : ""
    readonly property string critTimeText: tte > 0 ? (tte >= 60 ? core.fmtEta(tte) : core.fmt(tte)) : ""

    readonly property real w: expanded ? 360 : 260
    readonly property real h: expanded ? (hasProfiles ? 110 : 78) : 44
    readonly property color tone: isCrit ? core.coral : isLow ? core.amber : core.teal
    readonly property color accent: tone

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    onActiveChanged: if (active && !profRead.running) profRead.running = true
    onExpandedChanged: if (st.active && st.expanded && st.core.chargeOn) st.core.flashCharge(st.core.chargeKind)

    function selectProfile(p) {
        if (!p || profSet.running) return
        pendingProfile = p
        profSet.running = true
    }

    Process {
        id: profRead
        command: ["sh", "-c", 'cur=$(powerprofilesctl get 2>/dev/null); list=$(powerprofilesctl list 2>/dev/null); printf "%s\n%s\n" "$cur" "$list"']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                const cur = (lines[0] || "").trim()
                st.profile = cur
                const rest = lines.slice(1).join("\n")
                st.hasSaver = rest.indexOf("power-saver") >= 0 || cur === "power-saver"
                st.hasBalanced = rest.indexOf("balanced") >= 0 || cur === "balanced"
                st.hasPerf = rest.indexOf("performance") >= 0 || cur === "performance"
            }
        }
    }

    Process {
        id: profSet
        command: ["sh", "-c", 'powerprofilesctl set "$1" >/dev/null 2>&1; powerprofilesctl get 2>/dev/null', "sh", st.pendingProfile]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = text.trim()
                if (cur !== "") st.profile = cur
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: st.active && st.expanded
        onTriggered: {
            if (st.core.chargeOn) st.core.flashCharge(st.core.chargeKind)
            if (!profRead.running) profRead.running = true
        }
    }

    // ── small local widgets ──
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    component Ico: Text {
        property string name: ""
        property string alt: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 15
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component RingGauge: Item {
        id: rg
        property int size: 28
        property real strokeWidth: 2.5
        property real pct: 0
        property color arcColor: st.tone
        implicitWidth: size
        implicitHeight: size
        onPctChanged: ringCanvas.requestPaint()
        onArcColorChanged: ringCanvas.requestPaint()
        onVisibleChanged: if (visible) ringCanvas.requestPaint()

        Canvas {
            id: ringCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width / 2
                const cy = height / 2
                const r = (Math.min(width, height) - rg.strokeWidth * 2) / 2
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
                ctx.lineWidth = rg.strokeWidth
                ctx.stroke()

                const clamped = Math.max(0, Math.min(100, rg.pct))
                if (clamped > 0.1) {
                    const start = -Math.PI / 2
                    const end = start + (clamped / 100) * Math.PI * 2
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, start, end)
                    ctx.strokeStyle = rg.arcColor
                    ctx.lineWidth = rg.strokeWidth
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }
        }
    }

    component GovBtn: Rectangle {
        id: gb
        property string profKey: ""
        property string labelText: ""
        property string iconName: ""
        property string iconAlt: ""
        readonly property bool isCurrent: st.profile === profKey

        Layout.fillWidth: true
        implicitHeight: 24
        radius: height / 2
        color: isCurrent
            ? Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.20)
            : (gm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
        border.width: isCurrent ? 1 : 0
        border.color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.30)
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
                visible: gb.isCurrent
                width: 6
                height: 6
                radius: 3
                color: st.tone
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: st.visible && st.expanded && gb.isCurrent
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1.0; duration: 700 }
                }
            }

            Ico {
                visible: !gb.isCurrent
                name: gb.iconName
                alt: gb.iconAlt
                font.pixelSize: 13
                color: gm.containsMouse ? st.core.text : st.core.dim
            }

            Mono {
                text: gb.labelText.toUpperCase()
                font.pixelSize: 9
                font.letterSpacing: 0.8
                font.weight: gb.isCurrent ? Font.DemiBold : Font.Medium
                color: gb.isCurrent ? st.tone : (gm.containsMouse ? st.core.text : st.core.dim)
            }
        }

        MouseArea {
            id: gm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: st.selectProfile(gb.profKey)
        }
    }

    // ═══════════ STATE 01: plug-in / unplug flash (260×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showPlug ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.15)

                Ico {
                    anchors.centerIn: parent
                    name: st.core.charging ? "bolt" : st.core.full ? "battery_full" : "battery_std"
                    alt: st.core.charging ? "⚡" : "B"
                    font.pixelSize: 17
                    color: st.tone
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showPlug && st.core.charging
                        NumberAnimation { to: 0.45; duration: 750 }
                        NumberAnimation { to: 1.0; duration: 750 }
                    }
                }
            }

            Mono {
                Layout.fillWidth: true
                text: st.stateWord
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: st.tone
            }

            RowLayout {
                visible: st.core.watts >= 0.1
                spacing: 2

                Mono {
                    text: Math.round(st.core.watts).toString()
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.text
                }

                Mono {
                    text: "W"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: st.tone
                }
            }

            Rectangle {
                visible: st.core.hasBat
                implicitHeight: 22
                implicitWidth: plugPctTxt.implicitWidth + 16
                radius: 11
                color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.20)

                Mono {
                    id: plugPctTxt
                    anchors.centerIn: parent
                    text: st.pctText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.tone
                }
            }
        }
    }

    // ═══════════ STATE 02: expanded telemetry & governor (360×110) ═══════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        opacity: st.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                visible: st.core.hasBat
                implicitWidth: 56
                implicitHeight: 56

                RingGauge {
                    anchors.fill: parent
                    size: 56
                    strokeWidth: 4.5
                    pct: st.core.batPct
                    arcColor: st.tone
                }

                Mono {
                    anchors.centerIn: parent
                    text: st.pctText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.text
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Ico {
                        name: st.core.charging ? "bolt" : st.isCrit ? "warning" : st.isLow ? "battery_alert" : st.core.full ? "battery_full" : "battery_std"
                        alt: st.core.charging ? "⚡" : "B"
                        font.pixelSize: 15
                        color: st.tone
                    }

                    Mono {
                        Layout.fillWidth: true
                        text: st.telemetryHeadline
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                        color: st.core.text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: st.etaText !== "" || st.tempText !== ""
                    spacing: 4

                    Mono {
                        visible: st.etaText !== ""
                        text: st.etaText
                        font.pixelSize: 9
                        color: st.core.dim
                    }

                    Mono {
                        visible: st.etaText !== "" && st.tempText !== ""
                        text: "·"
                        font.pixelSize: 9
                        color: st.core.dim
                    }

                    Mono {
                        visible: st.tempText !== ""
                        text: st.tempText
                        font.pixelSize: 9
                        color: st.core.dim
                    }
                }
            }

            Item {
                visible: st.core.health > 0
                Layout.alignment: Qt.AlignTop
                implicitWidth: healthPill.implicitWidth
                implicitHeight: 20

                Rectangle {
                    id: healthPill
                    implicitHeight: 20
                    implicitWidth: healthTxt.implicitWidth + 16
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.04)

                    Mono {
                        id: healthTxt
                        anchors.centerIn: parent
                        text: Math.round(st.core.health) + "% HEALTH"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 0.5
                        color: st.tone
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: st.hasProfiles
            spacing: 6

            GovBtn {
                visible: st.hasSaver
                profKey: "power-saver"
                labelText: "Saver"
                iconName: "eco"
                iconAlt: "E"
            }

            GovBtn {
                visible: st.hasBalanced
                profKey: "balanced"
                labelText: "Balanced"
                iconName: "balance"
                iconAlt: "B"
            }

            GovBtn {
                visible: st.hasPerf
                profKey: "performance"
                labelText: "Perf"
                iconName: "speed"
                iconAlt: "P"
            }
        }
    }

    // ═══════════ STATE 03: low battery (260×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showLow ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Item {
                implicitWidth: 28
                implicitHeight: 28

                RingGauge {
                    anchors.fill: parent
                    size: 28
                    strokeWidth: 2.5
                    pct: st.core.batPct
                    arcColor: st.core.amber
                }

                Ico {
                    anchors.centerIn: parent
                    name: "battery_alert"
                    alt: "!"
                    font.pixelSize: 13
                    color: st.core.amber
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Mono {
                    visible: st.core.hasBat
                    text: st.pctText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.amber
                }

                Txt {
                    Layout.fillWidth: true
                    text: "· plug in"
                    font.pixelSize: 11
                    color: st.core.dim
                }
            }

            Item {
                implicitWidth: 8
                implicitHeight: 8

                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: st.core.amber
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showLow
                        NumberAnimation { to: 0.2; duration: 700 }
                        NumberAnimation { to: 0.9; duration: 700 }
                    }
                }
            }

            Rectangle {
                implicitWidth: 24
                implicitHeight: 24
                radius: 12
                color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.15)

                Ico {
                    anchors.centerIn: parent
                    name: "power"
                    alt: "P"
                    font.pixelSize: 14
                    color: st.core.amber
                }
            }
        }
    }

    // ═══════════ STATE 04: critical battery (260×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showCrit ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Item {
                implicitWidth: 28
                implicitHeight: 28

                RingGauge {
                    anchors.fill: parent
                    size: 28
                    strokeWidth: 2.5
                    pct: st.core.batPct
                    arcColor: st.core.coral
                }

                Ico {
                    anchors.centerIn: parent
                    name: "warning"
                    alt: "!"
                    font.pixelSize: 13
                    color: st.core.coral
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showCrit
                        NumberAnimation { to: 0.3; duration: 450 }
                        NumberAnimation { to: 1.0; duration: 450 }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Mono {
                    visible: st.core.hasBat
                    text: st.pctText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.coral
                }

                Txt {
                    Layout.fillWidth: true
                    text: "· critical"
                    font.pixelSize: 11
                    color: st.core.text
                }
            }

            Mono {
                visible: st.critTimeText !== ""
                text: st.critTimeText
                font.pixelSize: 10
                font.weight: Font.Medium
                color: st.core.coral
            }

            Item {
                implicitWidth: 8
                implicitHeight: 8

                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: st.core.coral
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showCrit
                        NumberAnimation { to: 0.15; duration: 350 }
                        NumberAnimation { to: 1.0; duration: 350 }
                    }
                }
            }
        }
    }
}
