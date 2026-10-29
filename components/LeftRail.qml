import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null
    property var notifications: null
    property var wallpaperCarousel: null

    // Dimensional & Placement Properties (Top-level configurable contract)
    property int railWidth: 40
    property int railMarginLeft: 6
    property int railMarginTop: 6
    property int railMarginBottom: 6
    property int railRadius: 18

    // Built-in Power Menu State
    property bool powerPopupOpen: false
    property string pendingPowerLabel: ""
    property var pendingPowerCmd: []

    IpcHandler {
        target: "rail"
        function togglePower() { root.powerPopupOpen = !root.powerPopupOpen }
        function openPower() { root.powerPopupOpen = true }
        function closePower() { root.powerPopupOpen = false }
    }

    // Live Clock State
    property string hoursText: Qt.formatTime(new Date(), "HH")
    property string minutesText: Qt.formatTime(new Date(), "mm")
    property string dateTooltip: Qt.formatDate(new Date(), "dddd, dd MMM yyyy")
    property bool colonVisible: true

    // Live Hardware & Connectivity States
    property bool wifiEnabled: true
    property bool wifiConnected: false
    property string wifiSsid: "Disconnected"

    property bool btEnabled: true
    property bool btConnected: false

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
    exclusiveZone: root.railWidth + root.railMarginLeft
    color: "transparent"

    // ========================================================================
    // BACKGROUND POLLING: Wi-Fi, Bluetooth, Volume, Brightness, Media Status
    // ========================================================================
    Process {
        id: sysPollProc
        command: [
            "sh", "-c",
            "wifi_line=$(nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | grep '^wifi:connected:' | head -n1); "
            + "wifi_radio=$(nmcli radio wifi 2>/dev/null); "
            + "bt_power=$(bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 1 || echo 0); "
            + "bt_conn=$(bluetoothctl info 2>/dev/null | grep -q 'Connected: yes' && echo 1 || echo 0); "
            + "vol_line=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null); "
            + "med_line=$(playerctl metadata --format '{{status}}|{{title}}' 2>/dev/null | head -n1); "
            + "printf 'WIFI:%s|%s\\nBT:%s|%s\\nVOL:%s\\nMED:%s\\n' "
            + "\"$wifi_radio\" \"$wifi_line\" \"$bt_power\" \"$bt_conn\" \"$vol_line\" \"$med_line\""
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
            if (line.startsWith("WIFI:")) {
                const payload = line.slice(5)
                const sep = payload.indexOf("|")
                const radio = sep !== -1 ? payload.slice(0, sep).trim() : payload.trim()
                const connInfo = sep !== -1 ? payload.slice(sep + 1).trim() : ""
                root.wifiEnabled = (radio === "enabled")
                if (root.wifiEnabled && connInfo.startsWith("wifi:connected:")) {
                    root.wifiConnected = true
                    root.wifiSsid = connInfo.slice(15) || "Connected"
                } else {
                    root.wifiConnected = false
                    root.wifiSsid = root.wifiEnabled ? "Not Connected" : "Wi-Fi Off"
                }
            } else if (line.startsWith("BT:")) {
                const parts = line.slice(3).split("|")
                root.btEnabled = (parts[0] === "1")
                root.btConnected = (parts.length > 1 && parts[1] === "1")
            } else if (line.startsWith("VOL:")) {
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
    // FLOATING GLASS CAPSULE SURFACE
    // ========================================================================
    Rectangle {
        id: railBg
        anchors.fill: parent
        radius: root.railRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.48)
        border.width: 1
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.45)

        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

        // ====================================================================
        // 1. TOP SECTION: Brand Launcher + Workspaces
        // ====================================================================
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

        // ====================================================================
        // 2. MIDDLE SECTION: Auto-Centered Media Equalizer & Capture Pod
        // ====================================================================
        Item {
            id: middleZone
            anchors {
                top: topSection.bottom
                bottom: lowerSection.top
                left: parent.left
                right: parent.right
            }

            Rectangle {
                id: middlePod
                width: 32
                height: midPodCol.implicitHeight + 10
                anchors.centerIn: parent
                radius: 10
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
                        onClicked: Quickshell.execDetached(["sh", "-c", "grim -g \"$(slurp)\" - | swappy -f -"])
                    }
                }
            }
        }

        // ====================================================================
        // 3. LOWER SECTION: System Dock + Audio/Bri + Clock + Battery + Power
        // ====================================================================
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
                color: Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.45)
                border.width: 1
                border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
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
                            fastRefreshTimer.restart()
                        }
                    }

                    // Bluetooth Button
                    RailButton {
                        id: btBtn
                        glyph: !root.btEnabled ? "󰂲" : (root.btConnected ? "󰂱" : "󰂯")
                        iconColor: !root.btEnabled ? Theme.textMuted : (root.btConnected ? Theme.brandAccent : Theme.accentSecondary)
                        accentColor: Theme.accentSecondary
                        tooltip: !root.btEnabled
                            ? "Bluetooth: Off"
                            : (root.btConnected ? "Bluetooth: Connected" : "Bluetooth: On (Not Connected)")
                        onClicked: {
                            if (root.hub) root.hub.openPopup("bt", btBtn.mapToItem(railBg, 16, 12).y)
                            fastRefreshTimer.restart()
                        }
                    }

                    Rectangle {
                        width: 18
                        height: 1
                        color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.50)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Audio Button (compact, percentage in tooltip)
                    RailButton {
                        glyph: root.isMuted
                            ? "󰝟"
                            : (root.volumePct < 35 ? "󰕿" : (root.volumePct < 75 ? "󰖀" : "󰕾"))
                        iconColor: root.isMuted ? Theme.statusDanger : Theme.accentSecondary
                        accentColor: root.isMuted ? Theme.statusDanger : Theme.accentSecondary
                        tooltip: (root.isMuted ? "Audio Muted" : ("Volume: " + root.volumePct + "%"))
                            + " · Click: Mute · Scroll: ±5%"
                        onClicked: root.toggleAudioMute()
                        onScrolledUp: root.changeVolume(5)
                        onScrolledDown: root.changeVolume(-5)
                    }

                    // Brightness Button (compact, percentage in tooltip)
                    RailButton {
                        visible: Brightness.available
                        glyph: Brightness.percent < 35
                            ? "󰃞"
                            : (Brightness.percent < 75 ? "󰃟" : "󰖨")
                        iconColor: Theme.accentTertiary
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
                        glyph: "󰂚"
                        accentColor: Theme.accentTertiary
                        iconColor: Theme.accentTertiary
                        tooltip: "Notifications (Super+N)"
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
                                Quickshell.execDetached([Quickshell.env("HOME") + "/Projects/my-rice/scripts/pick-wall.fish"])
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
                            Quickshell.env("HOME") + "/Projects/my-rice/settings.qml"
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
                radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.powerPopupOpen
                    ? "#FF4D6D"
                    : (pwrBtnMouse.containsMouse ? "#3D1A26" : "#28131B")
                border.width: 1
                border.color: (root.powerPopupOpen || pwrBtnMouse.containsMouse) ? "#FF4D6D" : "#6E2B3E"

                scale: pwrBtnMouse.pressed ? 0.90 : (pwrBtnMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale {
                    enabled: Theme.animationsEnabled && !Theme.reducedMotion
                    NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                }
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    color: root.powerPopupOpen ? "#140A0E" : "#FF5C77"
                    font.family: Theme.fontMono
                    font.pixelSize: 13
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
            radius: 14
            color: Theme.surface
            border.width: 1
            border.color: "#FF4D6D"

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
                    margins: 12
                }
                spacing: 6

                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 24
                        text: root.pendingPowerLabel !== ""
                            ? ("CONFIRM " + root.pendingPowerLabel.toUpperCase() + "?")
                            : "󰐥  SYSTEM POWER"
                        color: "#FF5C77"
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.1
                    }
                    Text {
                        text: "✕"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 12
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
                            { icon: "󰌾", label: "Lock Screen", color: Theme.brandAccent,    confirm: false, cmd: ["sh", "-c", "pidof hyprlock || hyprlock || loginctl lock-session"] },
                            { icon: "󰤄", label: "Suspend",     color: Theme.accentSecondary,confirm: false, cmd: ["systemctl", "suspend"] },
                            { icon: "󰍃", label: "Log Out",     color: Theme.statusWarn,      confirm: true,  cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
                            { icon: "󰜉", label: "Reboot",      color: "#FB923C",            confirm: true,  cmd: ["systemctl", "reboot"] },
                            { icon: "󰐥", label: "Shut Down",   color: "#FF4D6D",            confirm: true,  cmd: ["systemctl", "poweroff"] }
                        ]

                        Rectangle {
                            id: pwrOption
                            required property var modelData
                            width: pwrCol.width
                            height: 32
                            radius: 8
                            color: pwrOptMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: pwrOptMouse.containsMouse ? pwrOption.modelData.color : Theme.border

                            scale: pwrOptMouse.pressed ? 0.97 : (pwrOptMouse.containsMouse ? 1.02 : 1.0)
                            Behavior on scale {
                                enabled: Theme.animationsEnabled && !Theme.reducedMotion
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

                            Row {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.icon
                                    color: pwrOption.modelData.color
                                    font.family: Theme.fontMono
                                    font.pixelSize: 14
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.label
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
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
                        radius: 8
                        color: "#FF4D6D"

                        Text {
                            anchors.centerIn: parent
                            text: "Yes, " + root.pendingPowerLabel
                            color: "#140A0E"
                            font.family: Theme.fontUi
                            font.pixelSize: 11
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
                        radius: 8
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: 11
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
    // 5. ICON RAIL BUTTON COMPONENT (Compact)
    // ========================================================================
    component RailButton: Rectangle {
        id: button
        property string glyph: "•"
        property string tooltip: ""
        property color accentColor: Theme.brandAccent
        property color iconColor: Theme.textMain
        signal clicked()
        signal scrolledUp()
        signal scrolledDown()

        width: 28
        height: 24
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

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: mouse.containsMouse ? button.accentColor : button.iconColor
            opacity: mouse.containsMouse ? 1.0 : 0.92
            font.family: Theme.fontMono
            font.pixelSize: 13
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
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
