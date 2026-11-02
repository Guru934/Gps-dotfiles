import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null
    property var notifications: null
    property var wallpaperCarousel: null

    // Dimensional & Placement Properties (Top-level configurable contract)
    property int railWidth: 40
    property int railMarginLeft: 0
    property int railMarginTop: 6
    property int railMarginBottom: 6
    property int railRadius: 18

    // Rail Layout Mode: "split" (default: 3 floating capsules) | "full" (legacy full-slab)
    property string railLayout: "split"
    readonly property bool isSplit: root.railLayout === "split"

    // Wallpaper-adaptive glass alpha & tint based on left strip luminance:
    // Bright wallpaper (high luminance): darker, higher-alpha glass (~0.60 - 0.82) for >=4.5:1 text contrast
    // Dark wallpaper (low luminance): lighter, lower-alpha glass (~0.35 - 0.45)
    readonly property real railGlassAlpha: {
        const l = Math.max(0.0, Math.min(1.0, Theme.leftLuminance))
        return 0.38 + 0.44 * Math.pow(l, 1.2)
    }
    readonly property color glassColor: {
        const l = Math.max(0.0, Math.min(1.0, Theme.leftLuminance))
        const a = root.railGlassAlpha
        const darken = 1.0 - l * 0.55
        return Qt.rgba(Theme.surface.r * darken, Theme.surface.g * darken, Theme.surface.b * darken, a)
    }
    readonly property color glassBorderColor: {
        const l = Math.max(0.0, Math.min(1.0, Theme.leftLuminance))
        const a = 0.35 + 0.35 * l
        return Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, a)
    }
    readonly property string repoRoot: Quickshell.env("GPS_ROOT") || (root.hub && root.hub.repoRoot ? root.hub.repoRoot : "")

    // Built-in Power Menu State
    property bool powerPopupOpen: false
    property string pendingPowerLabel: ""
    property var pendingPowerCmd: []

    // Screen Recording Indicator State
    property bool isRecording: false
    readonly property string recordStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/gps/record-state.json"

    FileView {
        id: railRecordStateFile
        path: root.recordStatePath
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(railRecordStateFile.text())
                root.isRecording = Boolean(data && data.recording === true)
            } catch (e) {
                root.isRecording = false
            }
        }
        onFileChanged: railRecordStateFile.reload()
    }

    IpcHandler {
        target: "rail"
        function togglePower() { root.powerPopupOpen = !root.powerPopupOpen }
        function openPower() { root.powerPopupOpen = true }
        function closePower() { root.powerPopupOpen = false }
        function setLayout(layout: string) {
            if (layout === "split" || layout === "full") {
                root.railLayout = layout
            }
        }
        function getLayout(): string { return root.railLayout }
        function getCapsuleGeometry(): string {
            return JSON.stringify({
                isSplit: root.isSplit,
                top: { x: topCapsule.x, y: topCapsule.y, w: topCapsule.width, h: topCapsule.height },
                mid: { x: midCapsule.x, y: midCapsule.y, w: midCapsule.width, h: midCapsule.height },
                btm: { x: btmCapsule.x, y: btmCapsule.y, w: btmCapsule.width, h: btmCapsule.height },
                gap1: { top: topCapsule.y + topCapsule.height, bottom: midCapsule.y, height: midCapsule.y - (topCapsule.y + topCapsule.height) },
                gap2: { top: midCapsule.y + midCapsule.height, bottom: btmCapsule.y, height: btmCapsule.y - (midCapsule.y + midCapsule.height) }
            })
        }
    }

    // Live Clock State
    property string hoursText: Qt.formatTime(new Date(), "HH")
    property string minutesText: Qt.formatTime(new Date(), "mm")
    property string dateTooltip: Qt.formatDate(new Date(), "dddd, dd MMM yyyy")
    property bool colonVisible: true

    // Live Hardware & Connectivity States
    readonly property bool wifiEnabled: root.hub ? root.hub.wifiEnabled : false
    readonly property bool wifiConnected: root.hub ? root.hub.wifiConnected : false
    readonly property string wifiSsid: root.hub ? root.hub.netName : "Unavailable"

    readonly property bool btAvailable: root.hub ? root.hub.btAvailable : false
    readonly property bool btEnabled: root.hub ? root.hub.btPowered : false
    readonly property bool btConnected: root.hub ? root.hub.btConnected : false
    readonly property string btConnectedName: root.hub ? root.hub.btConnectedName : ""

    property int fallbackVolPct: 75
    property bool fallbackMuted: false
    readonly property int brightnessPct: Brightness.percent

    // Live Battery State (shared UPower service; hidden honestly when no battery)
    readonly property var batDevice: UPower.displayDevice
    readonly property bool batPresent: batDevice !== null && batDevice.isPresent
    readonly property int battPct: {
        if (!root.batPresent) return -1
        const raw = batDevice.percentage
        const pct = raw <= 1.0 ? Math.round(raw * 100) : Math.round(raw)
        return Math.max(0, Math.min(100, pct))
    }
    readonly property bool battCharging: root.batPresent
        && (batDevice.state === UPowerDeviceState.Charging
            || batDevice.state === UPowerDeviceState.PendingCharge)
    readonly property bool battFull: root.batPresent
        && batDevice.state === UPowerDeviceState.FullyCharged
    readonly property string battStatusText: {
        if (!root.batPresent) return ""
        switch (batDevice.state) {
        case UPowerDeviceState.Charging: return "Charging"
        case UPowerDeviceState.Discharging: return "On battery"
        case UPowerDeviceState.FullyCharged: return "Full"
        case UPowerDeviceState.PendingCharge: return root.battPct >= 99 ? "Full" : "Not charging"
        case UPowerDeviceState.PendingDischarge: return "Unplugged"
        case UPowerDeviceState.Empty: return "Empty"
        }
        return "Unknown"
    }

    function batteryGlyph() {
        if (!root.batPresent) return ""
        if (batDevice.state === UPowerDeviceState.Charging) return "󰂄"
        if (root.battFull || root.battPct >= 90) return "󰁹"
        if (root.battPct >= 70) return "󰂀"
        if (root.battPct >= 50) return "󰁾"
        if (root.battPct >= 30) return "󰁼"
        if (root.battPct >= 15) return "󰁻"
        return "󰁺"
    }

    function batteryColor() {
        if (!root.batPresent) return Theme.textMuted
        if (root.battCharging || root.battFull) return Theme.brandAccent
        if (root.battPct <= 15) return Theme.statusDanger
        if (root.battPct <= 30) return Theme.statusWarn
        return Theme.statusGood
    }

    // Live Media State (Equalizer only animates when mediaPlaying === true)
    property bool mediaPlaying: false
    property bool mediaPaused: false
    property string mediaTitle: ""

    // PipeWire Reactive Tracker (with wpctl fallback)
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property bool audioReady: audioSink !== null && audioSink.audio !== null
    readonly property bool isMuted: audioReady ? audioSink.audio.muted : root.fallbackMuted
    readonly property int volumePct: audioReady
        ? Math.round(audioSink.audio.volume * 100)
        : root.fallbackVolPct

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    // Layer-Shell Floating Capsule Setup
    WlrLayershell.namespace: "gps-rail"
    WlrLayershell.layer: WlrLayer.Top
    anchors {
        top: true
        bottom: true
        left: true
    }
    margins {
        left: root.railMarginLeft
        top: root.railMarginTop
        bottom: root.railMarginBottom
    }
    implicitWidth: root.railWidth
    exclusiveZone: root.railWidth
    color: "transparent"

    Region {
        id: splitMask
        Region { item: topCapsule }
        Region { item: midCapsule }
        Region { item: btmCapsule }
    }

    Region {
        id: fullMask
        item: railBg
    }

    mask: root.isSplit ? splitMask : fullMask

    // ========================================================================
    // BACKGROUND POLLING: Bluetooth, Volume, Brightness, Media Status
    // ========================================================================
    Process {
        id: sysPollProc
        command: [
            "sh", "-c",
            "vol_line=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null); "
            + "med_line=$(playerctl metadata --format '{{status}}|{{title}}' 2>/dev/null | head -n1); "
            + "rec_line=$(cat \"${XDG_RUNTIME_DIR:-/tmp}/gps/record-state.json\" 2>/dev/null | grep -o '\"recording\": *true' || echo ''); "
            + "printf 'VOL:%s\\nMED:%s\\nREC:%s\\n' "
            + "\"$vol_line\" \"$med_line\" \"$rec_line\""
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseSystemState(this.text)
        }
    }

    Timer {
        id: fastRefreshTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!sysPollProc.running) sysPollProc.running = true
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            if (!sysPollProc.running) sysPollProc.running = true
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.hoursText = Qt.formatTime(now, "HH")
            root.minutesText = Qt.formatTime(now, "mm")
            root.dateTooltip = Qt.formatDate(now, "dddd, dd MMM yyyy")
            root.colonVisible = !root.colonVisible
        }
    }

    function parseSystemState(raw) {
        if (!raw) return
        const lines = raw.trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.startsWith("VOL:")) {
                const vText = line.slice(4).trim()
                root.fallbackMuted = vText.indexOf("MUTED") !== -1
                const m = vText.match(/([0-9]+(?:\.[0-9]+)?)/)
                if (m) {
                    root.fallbackVolPct = Math.round(parseFloat(m[1]) * 100)
                }
            } else if (line.startsWith("MED:")) {
                const mPayload = line.slice(4).trim()
                if (!mPayload) {
                    root.mediaPlaying = false
                    root.mediaPaused = false
                    root.mediaTitle = ""
                } else {
                    const mSep = mPayload.indexOf("|")
                    const st = mSep !== -1 ? mPayload.slice(0, mSep).trim() : mPayload
                    const title = mSep !== -1 ? mPayload.slice(mSep + 1).trim() : ""
                    root.mediaPlaying = (st === "Playing")
                    root.mediaPaused = (st === "Paused")
                    root.mediaTitle = title
                }
            } else if (line.startsWith("REC:")) {
                const rPayload = line.slice(4).trim()
                if (rPayload !== "") {
                    root.isRecording = true
                } else if (!railRecordStateFile.exists) {
                    root.isRecording = false
                }
            }
        }
    }

    function changeVolume(deltaPct) {
        const nextPct = Math.max(0, Math.min(150, root.volumePct + deltaPct))
        root.fallbackVolPct = nextPct
        if (root.audioReady) {
            root.audioSink.audio.muted = false
            root.audioSink.audio.volume = nextPct / 100.0
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
            Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", nextPct + "%"])
        }
        fastRefreshTimer.restart()
    }

    function toggleAudioMute() {
        if (root.audioReady) {
            root.audioSink.audio.muted = !root.audioSink.audio.muted
        } else {
            root.fallbackMuted = !root.fallbackMuted
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        }
        fastRefreshTimer.restart()
    }

    function cycleBrightnessPreset() {
        let nextBri = 100
        if (Brightness.percent >= 90) nextBri = 25
        else if (Brightness.percent < 40) nextBri = 50
        else if (Brightness.percent < 70) nextBri = 75
        else nextBri = 100
        Brightness.setPercent(nextBri)
    }

    // ========================================================================
    // FLOATING GLASS CAPSULE SURFACE / THREE SPLIT CAPSULES
    // ========================================================================
    Rectangle {
        id: railBg
        anchors.fill: parent
        radius: root.railRadius
        color: root.isSplit ? "transparent" : root.glassColor
        border.width: root.isSplit ? 0 : 1
        border.color: root.isSplit ? "transparent" : root.glassBorderColor

        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

        // ====================================================================
        // 1. TOP CAPSULE: Brand Launcher + Workspaces
        // ====================================================================
        Rectangle {
            id: topCapsule
            width: root.railWidth
            height: topSection.implicitHeight + 16
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            radius: root.railRadius
            color: root.isSplit ? root.glassColor : "transparent"
            border.width: root.isSplit ? 1 : 0
            border.color: root.isSplit ? root.glassBorderColor : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

            Column {
                id: topSection
                anchors {
                    top: parent.top
                    topMargin: 8
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 6

                BrandMark {
                    hub: root.hub
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                WorkspaceIndicator {
                    hub: root.hub
                    workspaceCount: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // ====================================================================
        // 2. CENTER CAPSULE: Vertically Centered Media Equalizer & Capture Pod
        // ====================================================================
        Rectangle {
            id: midCapsule
            width: root.railWidth
            height: midPodCol.implicitHeight + 16
            anchors.horizontalCenter: parent.horizontalCenter
            radius: root.railRadius
            color: root.isSplit
                ? (midHover.hovered ? Qt.rgba(Theme.cardHover.r, Theme.cardHover.g, Theme.cardHover.b, 0.55) : root.glassColor)
                : "transparent"
            border.width: root.isSplit ? 1 : 0
            border.color: root.isSplit
                ? (root.mediaPlaying ? Theme.brandAccent : (midHover.hovered ? Theme.accentSecondary : root.glassBorderColor))
                : "transparent"

            readonly property int minGap: 8
            y: {
                const topEnd = topCapsule.y + topCapsule.height
                const btmStart = btmCapsule.y
                const available = btmStart - topEnd
                if (available <= height) return topEnd
                return topEnd + Math.round((available - height) / 2)
            }

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

            HoverHandler { id: midHover }

            Rectangle {
                id: middlePod
                width: 32
                height: midPodCol.implicitHeight + 10
                anchors.centerIn: parent
                radius: 10
                visible: !root.isSplit
                color: midPodHover.hovered
                    ? Qt.rgba(Theme.cardHover.r, Theme.cardHover.g, Theme.cardHover.b, 0.55)
                    : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.40)
                border.width: 1
                border.color: root.mediaPlaying
                    ? Theme.brandAccent
                    : (midPodHover.hovered ? Theme.accentSecondary : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50))

                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                HoverHandler { id: midPodHover }
            }

                Column {
                    id: midPodCol
                    anchors.centerIn: parent
                    spacing: 4

                    // 5-Bar Media Equalizer (Animates when mediaPlaying === true)
                    Item {
                        width: 24
                        height: 18
                        anchors.horizontalCenter: parent.horizontalCenter

                        Row {
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: [
                                    { idleH: 3, pauseH: 5,  maxH: 14, dur: 420 },
                                    { idleH: 3, pauseH: 8,  maxH: 17, dur: 320 },
                                    { idleH: 3, pauseH: 10, maxH: 15, dur: 490 },
                                    { idleH: 3, pauseH: 7,  maxH: 18, dur: 360 },
                                    { idleH: 3, pauseH: 4,  maxH: 13, dur: 440 }
                                ]

                                Rectangle {
                                    id: eqBar
                                    required property var modelData
                                    width: 2.5
                                    radius: 1.25
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.mediaPlaying
                                        ? Theme.brandAccent
                                        : (root.mediaPaused ? Theme.accentSecondary : Theme.textMuted)
                                    opacity: root.mediaPlaying ? 1.0 : (root.mediaPaused ? 0.75 : 0.40)

                                    height: root.mediaPaused ? eqBar.modelData.pauseH : eqBar.modelData.idleH

                                    Behavior on height {
                                        enabled: !root.mediaPlaying && Theme.animationsEnabled && !Theme.reducedMotion
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                                    SequentialAnimation on height {
                                        running: root.mediaPlaying && Theme.animationsEnabled && !Theme.reducedMotion
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            to: eqBar.modelData.maxH
                                            duration: eqBar.modelData.dur
                                            easing.type: Easing.InOutSine
                                        }
                                        NumberAnimation {
                                            to: 4
                                            duration: eqBar.modelData.dur + 60
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                if (!root.hub) return
                                const st = root.mediaPlaying
                                    ? ("Playing: " + (root.mediaTitle || "Media"))
                                    : (root.mediaPaused ? ("Paused: " + (root.mediaTitle || "Media")) : "No Media Playing (Click to Play)")
                                root.hub.setTooltip(st + " · Scroll: Next/Prev")
                            }
                            onExited: if (root.hub) root.hub.clearTooltip()
                            onClicked: {
                                Quickshell.execDetached(["playerctl", "play-pause"])
                                fastRefreshTimer.restart()
                            }
                            onWheel: event => {
                                if (event.angleDelta.y > 0)
                                    Quickshell.execDetached(["playerctl", "previous"])
                                else if (event.angleDelta.y < 0)
                                    Quickshell.execDetached(["playerctl", "next"])
                                fastRefreshTimer.restart()
                            }
                        }
                    }

                    // Status Label ("PLAY" / "PAUSE" / "IDLE")
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.mediaPlaying ? "PLAY" : (root.mediaPaused ? "PAUSE" : "IDLE")
                        color: root.mediaPlaying ? Theme.brandAccent : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 7
                        font.bold: true
                    }

                    Rectangle {
                        width: 18
                        height: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                    }

                    // Area Screenshot Action
                    RailButton {
                        glyph: "󰄀"
                        accentColor: Theme.accentTertiary
                        tooltip: "Area Screenshot"
                        onClicked: Quickshell.execDetached([(root.repoRoot ? (root.repoRoot + "/scripts/gps-shot") : "gps-shot"), "region"])
                    }

                    // Screen Recording Active Indicator
                    Rectangle {
                        id: recPill
                        visible: root.isRecording
                        width: 24
                        height: 24
                        radius: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Qt.rgba(Theme.statusDangerBorder.r, Theme.statusDangerBorder.g, Theme.statusDangerBorder.b, 0.20)
                        border.width: 1.5
                        border.color: Theme.statusDangerBorder

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: Theme.statusDangerBorder

                            SequentialAnimation on opacity {
                                running: root.isRecording && Theme.animationsEnabled && !Theme.reducedMotion
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.2; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([(root.repoRoot ? (root.repoRoot + "/scripts/gps-record") : "gps-record"), "stop"])
                            onEntered: if (root.hub) root.hub.setTooltip("Recording active · Click to stop")
                            onExited: if (root.hub) root.hub.clearTooltip()
                        }
                    }
                }
        }

        // ====================================================================
        // 3. BOTTOM CAPSULE: System Dock + Audio/Bri + Clock + Battery + Power
        // ====================================================================
        Rectangle {
            id: btmCapsule
            width: root.railWidth
            height: lowerSection.implicitHeight + 16
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
            }
            radius: root.railRadius
            color: root.isSplit ? root.glassColor : "transparent"
            border.width: root.isSplit ? 1 : 0
            border.color: root.isSplit ? root.glassBorderColor : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

            Column {
                id: lowerSection
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 8
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 5

                // Unified Lower Control Island
                Rectangle {
                    width: 32
                    height: sysCol.implicitHeight + 8
                    radius: 10
                    color: root.isSplit ? "transparent" : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.45)
                    border.width: root.isSplit ? 0 : 1
                    border.color: root.isSplit ? "transparent" : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                Column {
                    id: sysCol
                    anchors.centerIn: parent
                    spacing: 3

                    // Wi-Fi Button
                    RailButton {
                        id: wifiBtn
                        glyph: root.wifiConnected ? "󰖩" : "󰖪"
                        iconColor: root.wifiConnected ? Theme.brandAccent : Theme.statusDanger
                        accentColor: root.wifiConnected ? Theme.brandAccent : Theme.statusDanger
                        tooltip: "Wi-Fi: " + root.wifiSsid
                        onClicked: {
                            if (root.hub) root.hub.openPopup("wifi", wifiBtn.mapToItem(railBg, 16, 12).y)
                        }
                    }

                    // Bluetooth Button
                    RailButton {
                        id: btBtn
                        glyph: !root.btAvailable ? "󰂲" : (!root.btEnabled ? "󰂲" : (root.btConnected ? "󰂱" : "󰂯"))
                        iconColor: !root.btAvailable ? Theme.textMuted : (!root.btEnabled ? Theme.textMuted : (root.btConnected ? Theme.brandAccent : Theme.accentSecondary))
                        accentColor: Theme.accentSecondary
                        tooltip: !root.btAvailable
                            ? "Bluetooth: Unavailable"
                            : (!root.btEnabled
                                ? "Bluetooth: Off"
                                : (root.btConnected
                                    ? ("Bluetooth: Connected" + (root.btConnectedName !== "" ? " (" + root.btConnectedName + ")" : ""))
                                    : "Bluetooth: On (Not Connected)"))
                        onClicked: {
                            if (root.hub) root.hub.openPopup("bt", btBtn.mapToItem(railBg, 16, 12).y)
                        }
                    }

                    // System Tray Button (visible only when at least one item is registered)
                    RailButton {
                        id: trayBtn
                        visible: trayBtn.trayCount > 0
                        readonly property int trayCount: (SystemTray.items && SystemTray.items.values) ? SystemTray.items.values.length : 0
                        glyph: "󰠦"
                        sublabel: trayBtn.trayCount > 9 ? "9+" : (trayBtn.trayCount > 1 ? "" + trayBtn.trayCount : "")
                        accentColor: Theme.brandAccent
                        iconColor: Theme.textMain
                        tooltip: "System Tray (" + trayBtn.trayCount + " item" + (trayBtn.trayCount !== 1 ? "s" : "") + ")"
                        onClicked: {
                            if (root.hub) root.hub.openPopup("tray", trayBtn.mapToItem(railBg, 16, 12).y)
                        }
                    }

                    Rectangle {
                        width: 18
                        height: 1
                        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Audio Button (dynamic mute icon + live volume percentage)
                    RailButton {
                        glyph: root.isMuted
                            ? "󰝟"
                            : (root.volumePct < 35 ? "󰕿" : (root.volumePct < 75 ? "󰖀" : "󰕾"))
                        sublabel: root.isMuted ? "MUT" : (root.volumePct + "%")
                        iconColor: root.isMuted ? Theme.statusDanger : Theme.accentSecondary
                        sublabelColor: root.isMuted ? Theme.statusDanger : Theme.textMain
                        accentColor: root.isMuted ? Theme.statusDanger : Theme.accentSecondary
                        tooltip: (root.isMuted ? "Audio Muted" : ("Volume: " + root.volumePct + "%"))
                            + " · Click: Mute · Scroll: ±5%"
                        onClicked: root.toggleAudioMute()
                        onScrolledUp: root.changeVolume(5)
                        onScrolledDown: root.changeVolume(-5)
                    }

                    // Brightness Button (sun icon + live brightness percentage)
                    RailButton {
                        visible: Brightness.available
                        glyph: Brightness.percent < 35
                            ? "󰃞"
                            : (Brightness.percent < 75 ? "󰃟" : "󰖨")
                        sublabel: Brightness.percent + "%"
                        iconColor: Theme.accentTertiary
                        sublabelColor: Theme.textMain
                        accentColor: Theme.accentTertiary
                        tooltip: "Brightness: " + Brightness.percent + "% · Click: Cycle · Scroll: ±5%"
                        onClicked: root.cycleBrightnessPreset()
                        onScrolledUp: Brightness.step(5)
                        onScrolledDown: Brightness.step(-5)
                    }

                    Rectangle {
                        width: 18
                        height: 1
                        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Notifications
                    RailButton {
                        readonly property bool dndOn: root.notifications ? root.notifications.dndActive : false
                        readonly property int unread: root.notifications ? root.notifications.unreadCount : 0

                        glyph: dndOn ? "󰂛" : "󰂚"
                        accentColor: dndOn ? Theme.statusWarn : Theme.accentTertiary
                        iconColor: dndOn ? Theme.statusWarn : Theme.accentTertiary
                        sublabel: unread > 0 ? (unread > 99 ? "99+" : "" + unread) : ""
                        sublabelColor: Theme.brandAccent
                        tooltip: dndOn
                            ? "Notifications (Do Not Disturb · Super+N)"
                            : (unread > 0 ? ("Notifications (" + unread + " unread · Super+N)") : "Notifications (Super+N)")
                        onClicked: {
                            if (root.notifications) {
                                root.notifications.toggle()
                            } else {
                                Quickshell.execDetached([
                                    "quickshell", "ipc", "--any-display",
                                    "-p", Quickshell.env("HOME") + "/.local/share/tide-island",
                                    "call", "tide", "toggleNotificationCenter"
                                ])
                            }
                        }
                    }

                    // Wallpaper Carousel / Tools
                    RailButton {
                        glyph: "󰸉"
                        accentColor: Theme.brandAccent
                        iconColor: Theme.brandAccent
                        tooltip: "Wallpaper Carousel (Super+W)"
                        onClicked: {
                            if (root.hub) {
                                root.hub.toggleWallpaperCarousel()
                            } else if (root.wallpaperCarousel) {
                                root.wallpaperCarousel.toggle()
                            } else {
                                Quickshell.execDetached([root.repoRoot ? (root.repoRoot + "/scripts/pick-wall.fish") : "pick-wall.fish"])
                            }
                        }
                    }

                    // Local AI Chat (Ollama, 127.0.0.1 only)
                    RailButton {
                        glyph: "󰧑"
                        accentColor: Theme.accentSecondary
                        iconColor: Theme.accentSecondary
                        tooltip: "Local AI Chat · Ollama"
                        onClicked: {
                            if (root.hub) root.hub.toggleAIChat()
                        }
                    }

                    // Settings
                    RailButton {
                        glyph: "󰒓"
                        accentColor: Theme.brandAccent
                        iconColor: Theme.textMain
                        tooltip: "Settings (Super+,)"
                        onClicked: Quickshell.execDetached([
                            "quickshell",
                            "--no-duplicate",
                            "-p",
                            root.repoRoot ? (root.repoRoot + "/settings.qml") : "settings.qml"
                        ])
                    }
                }
            }

            // Live Digital Clock Pill (compact stacked)
            Rectangle {
                id: clockPill
                width: 32
                height: clockInner.implicitHeight + 6
                radius: 8
                color: clockMouse.containsMouse
                    ? Qt.rgba(Theme.cardHover.r, Theme.cardHover.g, Theme.cardHover.b, 0.55)
                    : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.45)
                border.width: 1
                border.color: clockMouse.containsMouse
                    ? Theme.brandAccent
                    : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                Column {
                    id: clockInner
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.hoursText
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Rectangle {
                        width: 3
                        height: 3
                        radius: 1.5
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.brandAccent
                        opacity: root.colonVisible ? 1.0 : 0.25
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.minutesText
                        color: Theme.brandAccent
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip(root.dateTooltip)
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: {
                        if (root.hub && root.hub.openPopup) {
                            root.hub.openPopup("clock", clockPill.mapToItem(railBg, 16, 12).y)
                        }
                    }
                }
            }

            // Live Battery Pill (battery % stays visible)
            Rectangle {
                id: battPill
                visible: root.batPresent
                width: 32
                height: 28
                radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                color: battMouse.containsMouse
                    ? Qt.rgba(Theme.cardHover.r, Theme.cardHover.g, Theme.cardHover.b, 0.55)
                    : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.45)
                border.width: 1
                border.color: battMouse.containsMouse
                    ? root.batteryColor()
                    : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)

                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.batteryGlyph()
                        color: root.batteryColor()
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.battPct + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 7
                        font.bold: true
                    }
                }

                MouseArea {
                    id: battMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip("Battery: " + root.battPct + "% · " + root.battStatusText + " — Click: power profiles")
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: {
                        if (root.hub && root.hub.openPopup) {
                            root.hub.openPopup("battery", battPill.mapToItem(railBg, 16, 12).y)
                        }
                    }
                }
            }

            // Crimson Power Button
            Rectangle {
                id: powerBtn
                width: 32
                height: 28
                radius: Theme.radiusSm
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.powerPopupOpen
                    ? Theme.statusDangerBorder
                    : (pwrBtnMouse.containsMouse ? Theme.statusDangerBg : Qt.alpha(Theme.statusDangerBg, 0.45))
                border.width: Theme.borderWidth
                border.color: (root.powerPopupOpen || pwrBtnMouse.containsMouse) ? Theme.statusDangerBorder : Qt.alpha(Theme.statusDangerBorder, 0.45)

                scale: pwrBtnMouse.pressed ? 0.90 : (pwrBtnMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale {
                    enabled: Theme.animationsEnabled && !Theme.reducedMotion
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack }
                }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    color: root.powerPopupOpen ? Theme.surfaceDeep : Theme.statusDangerFg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                }

                MouseArea {
                    id: pwrBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.hub) root.hub.setTooltip("Power Menu")
                    onExited: if (root.hub) root.hub.clearTooltip()
                    onClicked: {
                        if (root.hub && root.hub.closePopup) root.hub.closePopup()
                        root.pendingPowerLabel = ""
                        root.powerPopupOpen = !root.powerPopupOpen
                    }
                }
            }
        }
        }
    }

    // ========================================================================
    // 4. BUILT-IN ANIMATED POWER MENU POPUP WINDOW
    // ========================================================================
    PanelWindow {
        id: powerMenuWindow
        visible: root.powerPopupOpen
        screen: root.screen

        anchors {
            bottom: true
            left: true
        }

        exclusionMode: ExclusionMode.Ignore
        margins {
            bottom: root.railMarginBottom
            left: root.railWidth + root.railMarginLeft + 6
        }

        implicitWidth: 240
        implicitHeight: pwrCol.implicitHeight + 24
        color: "transparent"

        property bool hasEnteredPopup: false

        onVisibleChanged: {
            if (visible) {
                hasEnteredPopup = false
                pwrHideTimer.stop()
            }
        }

        Timer {
            id: pwrHideTimer
            interval: 420
            repeat: false
            onTriggered: {
                if (!pwrPopupHover.hovered) {
                    root.powerPopupOpen = false
                    root.pendingPowerLabel = ""
                }
            }
        }

        Rectangle {
            id: pwrCard
            anchors.fill: parent
            radius: Theme.radiusCard
            color: Theme.surface
            border.width: Theme.borderWidth
            border.color: Theme.statusDangerBorder

            HoverHandler {
                id: pwrPopupHover
                onHoveredChanged: {
                    if (hovered) {
                        powerMenuWindow.hasEnteredPopup = true
                        pwrHideTimer.stop()
                    } else if (powerMenuWindow.hasEnteredPopup) {
                        pwrHideTimer.restart()
                    }
                }
            }

            Column {
                id: pwrCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Theme.paddingMd
                }
                spacing: Theme.spacingSm

                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 24
                        text: root.pendingPowerLabel !== ""
                            ? ("CONFIRM " + root.pendingPowerLabel.toUpperCase() + "?")
                            : "󰐥  SYSTEM POWER"
                        color: Theme.statusDangerFg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSizeSecondary
                        font.bold: true
                        font.letterSpacing: 1.1
                    }
                    Text {
                        text: "✕"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSizeSecondary
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.powerPopupOpen = false
                                root.pendingPowerLabel = ""
                            }
                        }
                    }
                }

                Column {
                    visible: root.pendingPowerLabel === ""
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: [
                            { icon: "󰌾", label: "Lock Screen", color: Theme.brandAccent,    confirm: false, cmd: ["sh", "-c", "command -v gps-lock >/dev/null 2>&1 && exec gps-lock || { [ -n \"$GPS_ROOT\" ] && exec \"$GPS_ROOT/scripts/gps-lock\"; }"] },
                            { icon: "󰤄", label: "Suspend",     color: Theme.accentSecondary,confirm: false, cmd: ["systemctl", "suspend"] },
                            { icon: "󰍃", label: "Log Out",     color: Theme.statusWarn,      confirm: true,  cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
                            { icon: "󰜉", label: "Reboot",      color: Theme.statusWarn,      confirm: true,  cmd: ["systemctl", "reboot"] },
                            { icon: "󰐥", label: "Shut Down",   color: Theme.statusDangerBorder, confirm: true, cmd: ["systemctl", "poweroff"] }
                        ]

                        Rectangle {
                            id: pwrOption
                            required property var modelData
                            width: pwrCol.width
                            height: Theme.controlHeightMd
                            radius: Theme.radiusSm
                            color: pwrOptMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: Theme.borderWidth
                            border.color: pwrOptMouse.containsMouse ? pwrOption.modelData.color : Theme.outlineSoft

                            scale: pwrOptMouse.pressed ? 0.97 : (pwrOptMouse.containsMouse ? 1.02 : 1.0)
                            Behavior on scale {
                                enabled: Theme.animationsEnabled && !Theme.reducedMotion
                                NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                            }
                            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                            Row {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: Theme.spacingSm

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.icon
                                    color: pwrOption.modelData.color
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeSubheading
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.label
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.fontSizeSecondary
                                    font.bold: pwrOptMouse.containsMouse
                                }
                            }

                            MouseArea {
                                id: pwrOptMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (pwrOption.modelData.confirm) {
                                        root.pendingPowerLabel = pwrOption.modelData.label
                                        root.pendingPowerCmd = pwrOption.modelData.cmd
                                    } else {
                                        root.powerPopupOpen = false
                                        Quickshell.execDetached(pwrOption.modelData.cmd)
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    visible: root.pendingPowerLabel !== ""
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 34
                        radius: Theme.radiusSm
                        color: Theme.statusDangerBorder

                        Text {
                            anchors.centerIn: parent
                            text: "Yes, " + root.pendingPowerLabel
                            color: Theme.onAccent
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSizeSecondary
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const cmd = root.pendingPowerCmd
                                root.pendingPowerLabel = ""
                                root.powerPopupOpen = false
                                Quickshell.execDetached(cmd)
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 34
                        radius: Theme.radiusSm
                        color: Theme.card
                        border.width: Theme.borderWidth
                        border.color: Theme.outlineSoft

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSizeSecondary
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pendingPowerLabel = ""
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // 5. ICON RAIL BUTTON COMPONENT (Compact with optional sublabel)
    // ========================================================================
    component RailButton: Rectangle {
        id: button
        property string glyph: "•"
        property string tooltip: ""
        property color accentColor: Theme.brandAccent
        property color iconColor: Theme.textMain
        property string sublabel: ""
        property color sublabelColor: Theme.textMain
        signal clicked()
        signal scrolledUp()
        signal scrolledDown()

        width: 28
        height: button.sublabel !== "" ? 30 : 24
        radius: 6
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        color: mouse.containsMouse
            ? Qt.rgba(button.accentColor.r, button.accentColor.g, button.accentColor.b, 0.18)
            : "transparent"
        border.width: mouse.containsMouse ? 1 : 0
        border.color: button.accentColor

        scale: mouse.pressed ? 0.90 : (mouse.containsMouse ? 1.08 : 1.0)

        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        Behavior on scale {
            enabled: Theme.animationsEnabled && !Theme.reducedMotion
            NumberAnimation { duration: 140; easing.type: Easing.OutBack }
        }

        Column {
            anchors.centerIn: parent
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: button.glyph
                color: mouse.containsMouse ? button.accentColor : button.iconColor
                opacity: mouse.containsMouse ? 1.0 : 0.92
                font.family: Theme.fontMono
                font.pixelSize: button.sublabel !== "" ? 11 : 13
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            }

            Text {
                visible: button.sublabel !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: button.sublabel
                color: mouse.containsMouse ? button.accentColor : button.sublabelColor
                font.family: Theme.fontMono
                font.pixelSize: 8
                font.bold: true
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip(button.tooltip)
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: button.clicked()
            onWheel: event => {
                if (event.angleDelta.y > 0) button.scrolledUp()
                else if (event.angleDelta.y < 0) button.scrolledDown()
            }
        }
    }
}
