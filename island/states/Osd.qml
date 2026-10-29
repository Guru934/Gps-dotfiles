// Island state: osd — volume level (290×44) · audio muted (290×44) · display backlight (290×44) · audio route switch (290×44) · mic privacy guard (290×44)
// Live PipeWire audio/mic & /sys/class/backlight telemetry from Island.qml (`core`) + `wpctl` route inspection while active.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.config

Item {
    id: st
    required property var core
    readonly property string key: "osd"

    readonly property bool active: core.mode === key
    readonly property string kind: (core.osdKind && core.osdKind !== "") ? core.osdKind : "vol"

    readonly property bool showMic: kind === "mic" && core.sourceAudio !== null
    readonly property bool showRoute: kind === "route"
    readonly property bool showBright: kind === "bright"
    readonly property bool showMute: !showMic && !showRoute && !showBright && (kind === "mute" || core.muted)
    readonly property bool showVol: !showMic && !showRoute && !showBright && !showMute

    readonly property int volPct: Math.max(0, Math.round(core.volume * 100))
    readonly property real volNorm: Math.max(0, Math.min(1, core.volume))

    readonly property bool hasBri: Brightness.available
    readonly property int briPct: Brightness.percent
    readonly property real briNorm: Math.max(0, Math.min(1, Brightness.percent / 100.0))
    readonly property string briIcon: briPct < 35 ? "brightness_low" : briPct < 75 ? "brightness_medium" : "light_mode"

    readonly property bool micIsMuted: Boolean(core.micMuted)
    readonly property int micPct: Math.max(0, Math.round(core.micVolume * 100))

    property string routeSub: ""
    readonly property string sinkTitle: core.sinkName || ""
    readonly property string routeIcon: {
        const s = (sinkTitle + " " + routeSub).toLowerCase()
        if (/headphone|headset|buds|airpods|earphone|handsfree|a2dp/.test(s)) return "headphones"
        if (/hdmi|displayport|dp\b|tv|monitor/.test(s)) return "tv"
        if (/usb|dac|s\/pdif|iec958|optical|coax/.test(s)) return "Headphones" === s ? "headphones" : "speaker"
        return "headphones"
    }

    readonly property real w: 290
    readonly property real h: 44
    readonly property color tone: (showMute || (showMic && micIsMuted))
        ? core.coral
        : showBright
            ? core.amber
            : showRoute
                ? core.lav
                : core.teal
    readonly property color accent: tone

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function refreshRouteMeta() {
        if (!active || !showRoute) return
        if (!routeProc.running) routeProc.running = true
    }

    onActiveChanged: if (active && showRoute) refreshRouteMeta()
    onShowRouteChanged: if (active && showRoute) refreshRouteMeta()

    Connections {
        target: st.core
        function onSinkNameChanged() {
            st.routeSub = ""
            if (st.active && st.showRoute) st.refreshRouteMeta()
        }
    }

    // Hold OSD open while cursor is hovering over the pill
    Timer {
        interval: 800
        repeat: true
        running: false
        onTriggered: st.core.pokeOsd(st.kind)
    }

    // Inspect real bus type & negotiated sample rate/bit-depth for State 04 only while active
    Process {
        id: routeProc
        command: [
            "sh", "-c",
            'out=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null); ' +
            'bus=$(printf "%s\\n" "$out" | sed -n \'s/.*device\\.bus = "\\([^"]*\\)".*/\\1/p\' | head -n1); ' +
            'api=$(printf "%s\\n" "$out" | sed -n \'s/.*device\\.api = "\\([^"]*\\)".*/\\1/p\' | head -n1); ' +
            'form=$(printf "%s\\n" "$out" | sed -n \'s/.*device\\.form-factor = "\\([^"]*\\)".*/\\1/p\' | head -n1); ' +
            'fmt=$(printf "%s\\n" "$out" | sed -n \'s/.*audio\\.format = "\\([^"]*\\)".*/\\1/p\' | head -n1); ' +
            'rate=$(printf "%s\\n" "$out" | sed -n \'s/.*audio\\.rate = "\\([0-9]*\\)".*/\\1/p\' | head -n1); ' +
            'printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$bus" "$api" "$form" "$fmt" "$rate"'
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("\t")
                const bus = (p[0] || "").toLowerCase()
                const api = (p[1] || "").toLowerCase()
                const form = (p[2] || "").toLowerCase()
                const fmt = (p[3] || "").toUpperCase()
                const rateNum = parseInt(p[4]) || 0

                let kindStr = ""
                if (bus === "bluetooth" || api.indexOf("bluez") >= 0) {
                    kindStr = form ? ("BT " + form.toUpperCase()) : "BLUETOOTH"
                } else if (bus === "usb") {
                    kindStr = (form === "headset" || form === "headphones") ? "USB AUDIO" : "USB DAC"
                } else if (bus === "pci" || api === "alsa") {
                    kindStr = form ? form.toUpperCase() : "BUILT-IN AUDIO"
                } else if (form) {
                    kindStr = form.toUpperCase()
                }

                let rateStr = ""
                if (rateNum > 0) {
                    rateStr = (rateNum % 1000 === 0 ? (rateNum / 1000) : (rateNum / 1000).toFixed(1)) + "kHz"
                }

                let bitsStr = ""
                const bm = fmt.match(/(16|24|32|64)/)
                if (bm) bitsStr = bm[1] + "-bit"

                const spec = (rateStr && bitsStr) ? (rateStr + " / " + bitsStr) : (rateStr || bitsStr)
                const parts = []
                if (kindStr) parts.push(kindStr)
                if (spec) parts.push(spec)
                st.routeSub = parts.join(" · ")
            }
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
        font.pixelSize: 18
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component IconCircle: Rectangle {
        property color badgeColor: st.core.teal
        property real bgAlpha: 0.10
        property string name: ""
        property string alt: ""
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, bgAlpha)

        Ico {
            anchors.centerIn: parent
            name: parent.name
            alt: parent.alt
            font.pixelSize: 18
            color: parent.badgeColor
        }
    }

    component DotBar: Item {
        id: db
        property real value: 0
        property color barColor: st.core.teal
        Layout.fillWidth: true
        implicitHeight: 14

        Rectangle {
            id: trackBg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 5
            radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
                id: fillRect
                width: parent.width * Math.max(0, Math.min(1, db.value))
                height: parent.height
                radius: 2.5
                color: db.barColor
                Behavior on width { NumberAnimation { duration: 90 } }
            }
        }

        Rectangle {
            visible: db.value > 0.01
            width: 8
            height: 8
            radius: 4
            color: db.barColor
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(db.width - width, fillRect.width - width / 2))
            Behavior on x { NumberAnimation { duration: 90 } }
        }
    }

    // ═══════════ STATE 01: VOLUME LEVEL (290×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showVol ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            IconCircle {
                badgeColor: st.core.teal
                bgAlpha: 0.10
                name: st.core.volIcon()
                alt: "♪"
            }

            DotBar {
                visible: st.core.sinkAudio !== null
                value: st.volNorm
                barColor: st.core.teal
            }

            Mono {
                visible: st.core.sinkAudio !== null
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: st.volPct + "%"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: st.core.text
            }
        }
    }

    // ═══════════ STATE 02: AUDIO MUTED (290×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showMute ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            IconCircle {
                badgeColor: st.core.coral
                bgAlpha: 0.15
                name: "volume_off"
                alt: "×"
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 18
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.07)

                Mono {
                    anchors.centerIn: parent
                    text: "ZERO GAIN"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.0
                    color: st.core.coral
                }
            }

            Rectangle {
                implicitHeight: 20
                implicitWidth: mutedBadgeTxt.implicitWidth + 16
                radius: 10
                color: Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.20)

                Mono {
                    id: mutedBadgeTxt
                    anchors.centerIn: parent
                    text: "MUTED"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                    color: st.core.coral
                }
            }
        }
    }

    // ═══════════ STATE 03: DISPLAY BACKLIGHT (290×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showBright ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            IconCircle {
                badgeColor: st.core.amber
                bgAlpha: 0.10
                name: st.briIcon
                alt: "☀"
            }

            DotBar {
                visible: st.hasBri
                value: st.briNorm
                barColor: st.core.amber
            }

            Mono {
                visible: st.hasBri
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: st.briPct + "%"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: st.core.text
            }
        }
    }

    // ═══════════ STATE 04: AUDIO ROUTE SWITCH (290×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showRoute ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            IconCircle {
                badgeColor: st.core.lav
                bgAlpha: 0.15
                name: st.routeIcon
                alt: "☊"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Txt {
                    Layout.fillWidth: true
                    visible: st.sinkTitle !== ""
                    text: st.sinkTitle
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.text
                }

                Mono {
                    Layout.fillWidth: true
                    visible: st.routeSub !== ""
                    text: st.routeSub
                    font.pixelSize: 9
                    font.letterSpacing: 0.5
                    color: st.core.dim
                }
            }

            Rectangle {
                visible: st.sinkTitle !== ""
                implicitHeight: 20
                implicitWidth: activeChipRow.implicitWidth + 16
                radius: 10
                color: Qt.rgba(st.core.lav.r, st.core.lav.g, st.core.lav.b, 0.20)

                RowLayout {
                    id: activeChipRow
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: st.core.lav
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: st.visible && st.showRoute
                            NumberAnimation { to: 0.3; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }

                    Mono {
                        text: "ACTIVE"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: st.core.lav
                    }
                }
            }
        }
    }

    // ═══════════ STATE 05: MIC PRIVACY GUARD (290×44) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showMic ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8

            IconCircle {
                badgeColor: st.micIsMuted ? st.core.coral : st.core.teal
                bgAlpha: 0.15
                name: st.micIsMuted ? "mic_off" : "mic"
                alt: st.micIsMuted ? "×" : "M"
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 24

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Ico {
                        name: st.micIsMuted ? "lock" : "lock_open"
                        alt: st.micIsMuted ? "🔒" : "🔓"
                        font.pixelSize: 14
                        color: st.micIsMuted ? st.core.coral : st.core.teal
                    }

                    Mono {
                        text: st.micIsMuted ? "MIC MUTED" : "MIC LIVE"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                        color: st.micIsMuted ? st.core.coral : st.core.teal
                    }
                }
            }

            Rectangle {
                implicitHeight: 20
                implicitWidth: micStatusTxt.implicitWidth + 20
                radius: 10
                color: st.micIsMuted
                    ? st.core.coral
                    : Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.20)

                Mono {
                    id: micStatusTxt
                    anchors.centerIn: parent
                    text: st.micIsMuted ? "OFF" : (st.micPct + "%")
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: st.micIsMuted ? "#000000" : st.core.teal
                }
            }
        }
    }
}
