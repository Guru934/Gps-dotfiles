import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null
    property var notifications: null
    property var wallpaperCarousel: null

    // Built-in Power Menu State
    property bool powerPopupOpen: false
    property string pendingPowerLabel: ""
    property var pendingPowerCmd: []

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
    property int brightnessPct: 100

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
        // Bolt glyph only while the battery is actually charging — being
        // plugged in with "Not charging" (threshold) keeps the level glyph.
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
        if (root.battCharging || root.battFull) return "#4DF0D0"
        if (root.battPct <= 15) return "#FF5C77"
        if (root.battPct <= 30) return "#F5C17A"
        return "#6EE7A8"
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

    // Full-height left edge anchor
    anchors {
        top: true
        bottom: true
        left: true
    }

    // Flush 52px width (positive fixed width prevents layer-shell full-screen stretch)
    implicitWidth: 52
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
            + "bri_line=$(brightnessctl -m 2>/dev/null | head -n1); "
            + "med_line=$(playerctl metadata --format '{{status}}|{{title}}' 2>/dev/null | head -n1); "
            + "printf 'WIFI:%s|%s\\nBT:%s|%s\\nVOL:%s\\nBRI:%s\\nMED:%s\\n' "
            + "\"$wifi_radio\" \"$wifi_line\" \"$bt_power\" \"$bt_conn\" \"$vol_line\" \"$bri_line\" \"$med_line\""
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
            } else if (line.startsWith("BRI:")) {
                const bParts = line.slice(4).split(",")
                if (bParts.length >= 4) {
                    const parsed = parseInt(bParts[3].replace("%", ""), 10)
                    if (!isNaN(parsed)) root.brightnessPct = parsed
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

    function changeBrightness(deltaPct) {
        const nextBri = Math.max(5, Math.min(100, root.brightnessPct + deltaPct))
        root.brightnessPct = nextBri
        Quickshell.execDetached(["brightnessctl", "-q", "set", nextBri + "%"])
        fastRefreshTimer.restart()
    }

    function cycleBrightnessPreset() {
        let nextBri = 100
        if (root.brightnessPct >= 90) nextBri = 25
        else if (root.brightnessPct < 40) nextBri = 50
        else if (root.brightnessPct < 70) nextBri = 75
        else nextBri = 100
        root.brightnessPct = nextBri
        Quickshell.execDetached(["brightnessctl", "-q", "set", nextBri + "%"])
        fastRefreshTimer.restart()
    }

    // ========================================================================
    // MAIN FLUSH FULL-HEIGHT RAIL SURFACE (Zero floating gaps)
    // ========================================================================
    Rectangle {
        id: railBg
        anchors.fill: parent
        radius: 0

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#FA121622" }
            GradientStop { position: 0.5; color: Theme.surface }
            GradientStop { position: 1.0; color: "#FA16111D" }
        }

        // Right-edge full-height separator line
        Rectangle {
            width: 1
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.35)
        }

        // Center-right neon accent glow strip
        Rectangle {
            width: 2
            height: parent.height * 0.38
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            opacity: root.mediaPlaying ? 0.85 : 0.40
            Behavior on opacity { NumberAnimation { duration: 300 } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.35; color: Theme.brandAccent }
                GradientStop { position: 0.65; color: "#FF4D6D" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // ====================================================================
        // 1. TOP SECTION: Brand Launcher + Workspaces
        // ====================================================================
        Column {
            id: topSection
            anchors {
                top: parent.top
                topMargin: 10
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 8

            BrandMark {
                anchors.horizontalCenter: parent.horizontalCenter
            }

            WorkspaceIndicator {
                hub: root.hub
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // ====================================================================
        // 2. MIDDLE SECTION: Auto-Centered Media Equalizer & Capture Pod
        //    (Animates ONLY when audio/media is actively playing!)
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
                width: 40
                height: midPodCol.implicitHeight + 14
                anchors.centerIn: parent
                radius: 12
                color: midPodHover.hovered ? Theme.cardHover : Theme.card
                border.width: 1
                border.color: root.mediaPlaying
                    ? "#4DF0D0"
                    : (midPodHover.hovered ? Theme.brandAccent : Theme.border)

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                HoverHandler { id: midPodHover }

                Column {
                    id: midPodCol
                    anchors.centerIn: parent
                    spacing: 6

                    // 5-Bar Media Equalizer (Stops automatically when paused/idle)
                    Item {
                        width: 28
                        height: 22
                        anchors.horizontalCenter: parent.horizontalCenter

                        Row {
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: [
                                    { idleH: 4, pauseH: 6,  maxH: 17, dur: 420, col: "#4DF0D0" },
                                    { idleH: 4, pauseH: 10, maxH: 21, dur: 320, col: "#38BDF8" },
                                    { idleH: 4, pauseH: 13, maxH: 19, dur: 490, col: "#FF4D6D" },
                                    { idleH: 4, pauseH: 9,  maxH: 22, dur: 360, col: "#F5C17A" },
                                    { idleH: 4, pauseH: 5,  maxH: 16, dur: 440, col: "#4DF0D0" }
                                ]

                                Rectangle {
                                    id: eqBar
                                    required property var modelData
                                    width: 3
                                    radius: 1.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.mediaPlaying
                                        ? eqBar.modelData.col
                                        : (root.mediaPaused ? Theme.brandAccent : Theme.textMuted)
                                    opacity: root.mediaPlaying ? 1.0 : (root.mediaPaused ? 0.75 : 0.40)

                                    height: root.mediaPaused ? eqBar.modelData.pauseH : eqBar.modelData.idleH

                                    Behavior on height {
                                        enabled: !root.mediaPlaying
                                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    SequentialAnimation on height {
                                        running: root.mediaPlaying
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            to: eqBar.modelData.maxH
                                            duration: eqBar.modelData.dur
                                            easing.type: Easing.InOutSine
                                        }
                                        NumberAnimation {
                                            to: 5
                                            duration: eqBar.modelData.dur + 70
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

                    // Status Label under Equalizer ("PLAY" / "PAUSE" / "IDLE")
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.mediaPlaying ? "PLAY" : (root.mediaPaused ? "PAUSE" : "IDLE")
                        color: root.mediaPlaying ? Theme.brandAccent : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        font.bold: true
                    }

                    Rectangle {
                        width: 24
                        height: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.border
                    }

                    // Area Screenshot Action
                    RailButton {
                        glyph: "󰄀"
                        accentColor: "#F5C17A"
                        tooltip: "Area Screenshot"
                        onClicked: Quickshell.execDetached(["sh", "-c", "grim -g \"$(slurp)\" - | swappy -f -"])
                    }
                }
            }
        }

        // ====================================================================
        // 3. LOWER SECTION: System Dock + Audio/Brightness % + Clock + Power
        // ====================================================================
        Column {
            id: lowerSection
            anchors {
                bottom: parent.bottom
                bottomMargin: 10
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 6

            // Unified Lower Control Island
            Rectangle {
                width: 40
                height: sysCol.implicitHeight + 10
                radius: 12
                color: Theme.card
                border.width: 1
                border.color: Theme.border
                anchors.horizontalCenter: parent.horizontalCenter

                Column {
                    id: sysCol
                    anchors.centerIn: parent
                    spacing: 4

                    // Wi-Fi Button (Shows 󰖪 in coral-red when disconnected/off, 󰖩 in cyan when connected)
                    RailButton {
                        id: wifiBtn
                        glyph: root.wifiConnected ? "󰖩" : "󰖪"
                        iconColor: root.wifiConnected ? "#4DF0D0" : "#FF5C77"
                        accentColor: root.wifiConnected ? "#4DF0D0" : "#FF5C77"
                        tooltip: "Wi-Fi: " + root.wifiSsid
                        onClicked: {
                            if (root.hub) root.hub.openPopup("wifi", wifiBtn.mapToItem(railBg, 18, 16).y)
                            fastRefreshTimer.restart()
                        }
                    }

                    // Bluetooth Button (Shows 󰂱 when connected, 󰂯 when on, 󰂲 when off)
                    RailButton {
                        id: btBtn
                        glyph: !root.btEnabled ? "󰂲" : (root.btConnected ? "󰂱" : "󰂯")
                        iconColor: !root.btEnabled ? Theme.textMuted : (root.btConnected ? "#4DF0D0" : "#60A5FA")
                        accentColor: "#60A5FA"
                        tooltip: !root.btEnabled
                            ? "Bluetooth: Off"
                            : (root.btConnected ? "Bluetooth: Connected" : "Bluetooth: On (Not Connected)")
                        onClicked: {
                            if (root.hub) root.hub.openPopup("bt", btBtn.mapToItem(railBg, 18, 16).y)
                            fastRefreshTimer.restart()
                        }
                    }

                    Rectangle {
                        width: 24
                        height: 1
                        color: Theme.border
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Audio Pill with Dynamic Mute Icon + Live Volume Percentage
                    MetricPill {
                        id: volPill
                        glyph: root.isMuted
                            ? "󰝟"
                            : (root.volumePct < 35 ? "󰕿" : (root.volumePct < 75 ? "󰖀" : "󰕾"))
                        label: root.isMuted ? "MUTE" : (root.volumePct + "%")
                        accentColor: root.isMuted ? "#FF5C77" : "#A78BFA"
                        alertMode: root.isMuted
                        tooltip: (root.isMuted ? "Audio Muted" : ("Volume: " + root.volumePct + "%"))
                            + " (Click: Mute · Scroll: ±5%)"
                        onClicked: root.toggleAudioMute()
                        onScrolledUp: root.changeVolume(5)
                        onScrolledDown: root.changeVolume(-5)
                    }

                    // Brightness Pill with Sun Icon + Live Brightness Percentage
                    MetricPill {
                        id: briPill
                        glyph: root.brightnessPct < 35
                            ? "󰃞"
                            : (root.brightnessPct < 75 ? "󰃟" : "󰖨")
                        label: root.brightnessPct + "%"
                        accentColor: "#F5C17A"
                        alertMode: false
                        tooltip: "Brightness: " + root.brightnessPct + "% (Click: Cycle Preset · Scroll: ±5%)"
                        onClicked: root.cycleBrightnessPreset()
                        onScrolledUp: root.changeBrightness(5)
                        onScrolledDown: root.changeBrightness(-5)
                    }

                    Rectangle {
                        width: 24
                        height: 1
                        color: Theme.border
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Notifications
                    RailButton {
                        glyph: "󰂚"
                        accentColor: "#F5C17A"
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

                    // Wallpaper Carousel
                    RailButton {
                        glyph: "󰸉"
                        accentColor: "#F472B6"
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
                        accentColor: "#DDB8FF"
                        tooltip: "Local AI Chat \u00b7 Ollama"
                        onClicked: {
                            if (root.hub) root.hub.toggleAIChat()
                        }
                    }

                    // Settings
                    RailButton {
                        glyph: "󰒓"
                        accentColor: "#38BDF8"
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

            // Live Digital Clock Pill
            Rectangle {
                id: clockPill
                width: 40
                height: clockInner.implicitHeight + 8
                radius: 10
                color: clockMouse.containsMouse ? Theme.cardHover : Theme.card
                border.width: 1
                border.color: clockMouse.containsMouse ? Theme.brandAccent : Theme.border
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Column {
                    id: clockInner
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.hoursText
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Rectangle {
                        width: 4
                        height: 4
                        radius: 2
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
                        font.pixelSize: 11
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
                            root.hub.openPopup("clock", clockPill.mapToItem(railBg, 18, 16).y)
                        }
                    }
                }
            }

            // Live Battery Pill (real UPower telemetry; click -> Power & Battery popup)
            Rectangle {
                id: battPill
                visible: root.batPresent
                width: 40
                height: 34
                radius: 10
                anchors.horizontalCenter: parent.horizontalCenter
                color: battMouse.containsMouse ? Theme.cardHover : Theme.card
                border.width: 1
                border.color: battMouse.containsMouse ? root.batteryColor() : Theme.border

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.batteryGlyph()
                        color: root.batteryColor()
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.battPct + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: 8
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
                            root.hub.openPopup("battery", battPill.mapToItem(railBg, 18, 16).y)
                        }
                    }
                }
            }

            // Glowing Crimson Power Button
            Rectangle {
                id: powerBtn
                width: 40
                height: 34
                radius: 10
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.powerPopupOpen
                    ? "#FF4D6D"
                    : (pwrBtnMouse.containsMouse ? "#3D1A26" : "#28131B")
                border.width: 1
                border.color: (root.powerPopupOpen || pwrBtnMouse.containsMouse) ? "#FF4D6D" : "#6E2B3E"

                scale: pwrBtnMouse.pressed ? 0.90 : (pwrBtnMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    color: root.powerPopupOpen ? "#140A0E" : "#FF5C77"
                    font.family: Theme.fontMono
                    font.pixelSize: 15
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
                        // Never stack the dangerous power menu on top of a radio popup.
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
            bottom: 10
            left: 58
        }

        implicitWidth: 248
        implicitHeight: pwrCol.implicitHeight + 28
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
            radius: 16
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
                    margins: 14
                }
                spacing: 7

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
                    spacing: 5

                    Repeater {
                        model: [
                            { icon: "󰌾", label: "Lock Screen", color: "#4DF0D0", confirm: false, cmd: ["sh", "-c", "pidof hyprlock || hyprlock || loginctl lock-session"] },
                            { icon: "󰤄", label: "Suspend",     color: "#60A5FA", confirm: false, cmd: ["systemctl", "suspend"] },
                            { icon: "󰍃", label: "Log Out",     color: "#F5C17A", confirm: true,  cmd: ["hyprctl", "dispatch", "exit"] },
                            { icon: "󰜉", label: "Reboot",      color: "#FB923C", confirm: true,  cmd: ["systemctl", "reboot"] },
                            { icon: "󰐥", label: "Shut Down",   color: "#FF4D6D", confirm: true,  cmd: ["systemctl", "poweroff"] }
                        ]

                        Rectangle {
                            id: pwrOption
                            required property var modelData
                            width: pwrCol.width
                            height: 34
                            radius: 9
                            color: pwrOptMouse.containsMouse ? Theme.cardHover : Theme.card
                            border.width: 1
                            border.color: pwrOptMouse.containsMouse ? pwrOption.modelData.color : Theme.border

                            scale: pwrOptMouse.pressed ? 0.97 : (pwrOptMouse.containsMouse ? 1.02 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on border.color { ColorAnimation { duration: 140 } }

                            Row {
                                anchors {
                                    fill: parent
                                    leftMargin: 12
                                    rightMargin: 12
                                }
                                spacing: 10

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.icon
                                    color: pwrOption.modelData.color
                                    font.family: Theme.fontMono
                                    font.pixelSize: 15
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pwrOption.modelData.label
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
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
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 36
                        radius: 9
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
                        width: (parent.width - 8) / 2
                        height: 36
                        radius: 9
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
    // 5. METRIC PILL COMPONENT (Icon + Live Percentage for Audio & Brightness)
    // ========================================================================
    component MetricPill: Rectangle {
        id: mPill
        property string glyph: "󰕾"
        property string label: "100%"
        property string tooltip: ""
        property color accentColor: Theme.brandAccent
        property bool alertMode: false
        signal clicked()
        signal scrolledUp()
        signal scrolledDown()

        width: 34
        height: 36
        radius: 8
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        color: mMouse.containsMouse
            ? Qt.rgba(mPill.accentColor.r, mPill.accentColor.g, mPill.accentColor.b, 0.20)
            : (mPill.alertMode ? Qt.rgba(1.0, 0.30, 0.42, 0.16) : Qt.rgba(0, 0, 0, 0.18))
        border.width: (mMouse.containsMouse || mPill.alertMode) ? 1 : 0
        border.color: mPill.accentColor

        scale: mMouse.pressed ? 0.90 : (mMouse.containsMouse ? 1.08 : 1.0)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: mPill.glyph
                color: mPill.accentColor
                font.family: Theme.fontMono
                font.pixelSize: 13
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: mPill.label
                color: mPill.alertMode ? mPill.accentColor : Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 8
                font.bold: true
            }
        }

        MouseArea {
            id: mMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip(mPill.tooltip)
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: mPill.clicked()
            onWheel: event => {
                if (event.angleDelta.y > 0) mPill.scrolledUp()
                else if (event.angleDelta.y < 0) mPill.scrolledDown()
            }
        }
    }

    // ========================================================================
    // 6. ICON RAIL BUTTON COMPONENT
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

        width: 32
        height: 26
        radius: 7
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        color: mouse.containsMouse
            ? Qt.rgba(button.accentColor.r, button.accentColor.g, button.accentColor.b, 0.18)
            : "transparent"
        border.width: mouse.containsMouse ? 1 : 0
        border.color: button.accentColor

        scale: mouse.pressed ? 0.88 : (mouse.containsMouse ? 1.10 : 1.0)

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Rectangle {
            width: 2.5
            height: mouse.containsMouse ? 12 : 0
            radius: 1.5
            color: button.accentColor
            anchors {
                left: parent.left
                leftMargin: 1
                verticalCenter: parent.verticalCenter
            }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: mouse.containsMouse ? button.accentColor : button.iconColor
            opacity: mouse.containsMouse ? 1.0 : 0.92
            font.family: Theme.fontMono
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 140 } }
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
