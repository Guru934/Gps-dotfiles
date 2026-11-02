import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components.dashboard

// System tab: live telemetry, dashboard-engine behaviour switches, display
// brightness, default audio output, power profiles and session info.
//
// Everything shown is read from the real system through the shared SysProbe
// (one /proc tick, slow df, slow nvidia-smi) plus a handful of one-shot
// readers. Controls write to the real hub (shell.qml) so the drawer host,
// the edge sensor and the probes actually change behaviour. Nothing here
// fabricates readings: unavailable sources render a placeholder and the
// corresponding control is disabled instead of pretending to work.
Item {
    id: root
    property bool isOpen: false
    property var hub: null

    readonly property bool edgeHotspot: root.hub ? root.hub.edgeHotspotEnabled : true
    readonly property int autoHideMs: root.hub ? root.hub.dashboardAutoHideMs : 400
    readonly property int tickMs: root.hub ? root.hub.telemetryTickMs : 1000

    readonly property color cardFill: Theme.surfaceBase
    readonly property color chipFill: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.7)

    function fmtUptime(s) {
        if (s < 0) return "\u2014"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return "up " + d + "d " + h + "h"
        if (h > 0) return "up " + h + "h " + m + "m"
        return "up " + Math.max(1, m) + "m"
    }

    function fmtBytes(b) {
        if (b < 0) return "\u2014"
        const gib = b / 1073741824
        return gib >= 100 ? Math.round(gib) + "G" : gib.toFixed(1) + "G"
    }

    function cpuSubtitle() {
        const parts = []
        if (probe.coreCount > 0) parts.push(probe.coreCount + " THREADS")
        if (probe.baseMhz > 0) parts.push("BASE " + (probe.baseMhz / 1000).toFixed(2) + " GHZ")
        return parts.length > 0 ? parts.join(" \u00b7 ") : "\u2014"
    }

    function coreSummary() {
        const parts = []
        if (probe.freqMhz > 0) parts.push((probe.freqMhz / 1000).toFixed(2) + " GHZ")
        if (probe.cpuTempC >= 0) parts.push(probe.cpuTempC + "\u00b0C")
        if (probe.pkgWatts >= 0) parts.push(probe.pkgWatts.toFixed(1) + "W PKG")
        return parts.length > 0 ? parts.join(" \u00b7 ") : "\u2014"
    }

    function thermalsText() {
        const parts = []
        if (probe.cpuTempC >= 0) parts.push("CPU " + probe.cpuTempC + "\u00b0C")
        if (probe.nvmeTempC >= 0) parts.push("NVMe " + probe.nvmeTempC + "\u00b0C")
        return parts.length > 0 ? parts.join(" \u00b7 ") : "\u2014"
    }

    function fansText() {
        if (probe.fan1Rpm >= 0 && probe.fan2Rpm >= 0) return "FANS " + probe.fan1Rpm + " / " + probe.fan2Rpm + " RPM"
        if (probe.fan1Rpm >= 0) return "FAN " + probe.fan1Rpm + " RPM"
        if (probe.fan2Rpm >= 0) return "FAN " + probe.fan2Rpm + " RPM"
        return ""
    }

    function vramLine() {
        if (probe.gpuMemTotalMib <= 0) return "VRAM: \u2014"
        const used = probe.gpuMemUsedMib >= 0 ? (probe.gpuMemUsedMib / 1024).toFixed(1) : "\u2014"
        const total = (probe.gpuMemTotalMib / 1024).toFixed(1)
        const pct = probe.gpuMemUsedMib >= 0 ? " (" + Math.round(100 * probe.gpuMemUsedMib / probe.gpuMemTotalMib) + "%)" : ""
        return "VRAM: " + used + " / " + total + " GB" + pct
    }

    SysProbe {
        id: probe
        active: root.isOpen
        tickMs: root.tickMs
    }

    // ------------------------------------------------------------------
    // Session / runtime versions (one-shot per open)
    // ------------------------------------------------------------------
    property string qsVersion: ""
    property string compositorVersion: ""

    Process {
        id: sessionProc
        command: ["sh", "-c", "quickshell --version 2>/dev/null | head -1; hyprctl version 2>/dev/null | head -1"]
        running: root.isOpen
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines.length > 0) {
                    const q = /Quickshell\s+([\d.]+)/.exec(lines[0])
                    if (q) root.qsVersion = q[1]
                }
                if (lines.length > 1) {
                    const h = /^Hyprland\s+([\d.]+)/.exec(lines[1])
                    if (h) root.compositorVersion = h[1]
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Default audio sink name (slow re-read while the tab is visible)
    // ------------------------------------------------------------------
    property string sinkName: ""

    Process {
        id: sinkNameProc
        command: ["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = /node\.description = "(.*)"/.exec(text)
                const n = /node\.nick = "(.*)"/.exec(text)
                root.sinkName = d ? d[1] : (n ? n[1] : "")
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.sinkName === "") root.sinkName = ""
        }
    }

    Timer {
        id: sinkNameTimer
        interval: 5000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: {
            if (!sinkNameProc.running) sinkNameProc.running = true
        }
    }

    // Volume glue, same "drag wins briefly" pattern as the Home tab tile.
    property real volUi: 0
    property real volStamp: 0

    Connections {
        target: probe
        function onVolumeChanged() {
            if (probe.volumeAvailable && Date.now() - root.volStamp > 1200) {
                root.volUi = probe.volume
                volSlider.value = probe.volume
            }
        }
    }

    function volumeMoved(v) {
        root.volStamp = Date.now()
        root.volUi = v
        volApplyTimer.restart()
    }

    Timer {
        id: volApplyTimer
        interval: 160
        repeat: false
        onTriggered: Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(root.volUi * 100) + "%"])
    }

    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    }

    // ------------------------------------------------------------------
    // Display brightness (brightnessctl; graceful when no backlight exists)
    // ------------------------------------------------------------------
    readonly property int brightPct: Brightness.percent
    readonly property string brightDevice: Brightness.device
    readonly property bool brightAvailable: Brightness.available
    readonly property bool brightnessReady: Brightness.available && Brightness.percent >= 0

    property int pendingBrightPct: -1

    Timer {
        id: brightDebounce
        interval: 80
        repeat: false
        onTriggered: {
            if (pendingBrightPct >= 0) Brightness.setPercent(pendingBrightPct)
        }
    }

    function applyBrightness(pct) {
        Brightness.setPercent(Math.round(pct))
    }

    function brightMoved(v) {
        pendingBrightPct = Math.round(v)
        brightDebounce.restart()
    }

    function stepBrightness(delta) {
        Brightness.step(delta)
    }

    // ------------------------------------------------------------------
    // Power profiles (real list from powerprofilesctl, verified writes)
    // ------------------------------------------------------------------
    property var profiles: []
    property string powerProfile: ""
    property string profileDriver: ""
    property string pendingProfile: ""
    property bool profileBusy: false
    property string profileError: ""
    property int profileVerifyTries: 0

    function profileLabel(id) {
        return id.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
    }

    function profileIcon(id) {
        if (id === "power-saver") return "nightlight"
        if (id === "balanced") return "balance"
        if (id === "performance") return "rocket_launch"
        return "bolt"
    }

    function parseProfiles(raw) {
        const lines = raw.split("\n")
        const list = []
        let drv = ""
        for (const line of lines) {
            const m = /^\s*(\*)?\s*([a-z][a-z0-9-]+):\s*$/.exec(line)
            if (m) {
                list.push({ id: m[2], active: m[1] === "*", degraded: false })
            } else if (list.length > 0 && /Degraded:\s*yes/.test(line)) {
                list[list.length - 1].degraded = true
            } else if (drv === "") {
                const dm = /CpuDriver:\s*(\S+)/.exec(line)
                if (dm) drv = dm[1]
            }
        }
        root.profileDriver = drv
        root.profiles = list
        const act = list.find(p => p.active)
        if (act) root.powerProfile = act.id
        root.checkProfilePending()
    }

    function setProfile(id) {
        if (!id || root.profileBusy || id === root.powerProfile) return
        root.profileBusy = true
        root.profileError = ""
        root.pendingProfile = id
        root.profileVerifyTries = 0
        profileSetProc.command = ["powerprofilesctl", "set", id]
        profileSetProc.running = true
    }

    // Returns true once the requested profile is confirmed active.
    function checkProfilePending() {
        if (root.pendingProfile === "") return true
        if (root.powerProfile === root.pendingProfile) {
            root.pendingProfile = ""
            root.profileBusy = false
            root.profileError = ""
            return true
        }
        return false
    }

    Process {
        id: profileListProc
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseProfiles(text)
        }
        onExited: (code, status) => {
            if (code !== 0 && root.profileError === "")
                root.profileError = "power profiles unavailable (exit " + code + ")"
        }
    }

    Process {
        id: profileSetProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.profileError === "")
                    root.profileError = text.trim().split("\n")[0]
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.pendingProfile = ""
                root.profileBusy = false
                if (root.profileError === "")
                    root.profileError = "profile change failed (exit " + code + ")"
                return
            }
            // Success is only claimed after the re-read confirms it.
            profileVerifyTimer.start()
        }
    }

    Timer {
        id: profileVerifyTimer
        interval: 900
        repeat: true
        onTriggered: {
            if (root.pendingProfile === "") {
                stop()
                return
            }
            root.profileVerifyTries += 1
            if (!profileListProc.running) profileListProc.running = true
            if (root.profileVerifyTries >= 5) {
                stop()
                if (root.pendingProfile !== "") {
                    root.pendingProfile = ""
                    root.profileBusy = false
                    root.profileError = "profile change not confirmed after re-read"
                }
            }
        }
    }

    Timer {
        id: profileRefreshTimer
        interval: 8000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: {
            if (!profileListProc.running && root.pendingProfile === "") profileListProc.running = true
        }
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content
            width: parent.width
            spacing: Theme.dashboardSpacingMd

            // HUD header row: section label + runtime chips.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.dashboardSpacingSm

                Text {
                    text: "HUD // SYSTEM TELEMETRY"
                    color: Theme.accentPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                    font.bold: true
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: qsChip.implicitWidth + 12
                    implicitHeight: 16
                    radius: 8
                    color: root.chipFill

                    Text {
                        id: qsChip
                        anchors.centerIn: parent
                        text: "WAYLAND // QS-" + (root.qsVersion !== "" ? root.qsVersion : "\u2026")
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(7)
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: liveRow.implicitWidth + 12
                    implicitHeight: 16
                    radius: 8
                    color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.1)

                    RowLayout {
                        id: liveRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.accentPrimary

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "LIVE (" + root.tickMs + "ms)"
                            color: Theme.accentPrimary
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            font.bold: true
                        }
                    }
                }
            }

            // ---------- Engine control ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: engine.implicitHeight + 20

                ColumnLayout {
                    id: engine
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "tune"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "DASHBOARD ENGINE"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: "QUICKSHELL HOST"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                        }
                    }

                    // Edge hotspot switch.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.55)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: Theme.dashboardSpacingSm

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "swipe_left"
                                color: Theme.accentSecondary
                                font.pixelSize: Theme.dashboardText(16)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                Text {
                                    text: "EDGE HOTSPOT"
                                    color: Theme.textMain
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.dashboardText(11)
                                    font.bold: true
                                }

                                Text {
                                    text: "bottom-right hot zone opens this drawer"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                }
                            }

                            DashToggle {
                                Layout.alignment: Qt.AlignVCenter
                                checked: root.edgeHotspot
                                accent: Theme.accentSecondary
                                onToggled: (checked) => {
                                    if (root.hub) root.hub.edgeHotspotEnabled = checked
                                }
                            }
                        }
                    }

                    // Auto-dismiss grace slider.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: grace.implicitHeight + 16
                        radius: 10
                        color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.4)

                        ColumnLayout {
                            id: grace
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                DashIcon {
                                    Layout.alignment: Qt.AlignVCenter
                                    name: "timer"
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.dashboardText(13)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "AUTO-DISMISS GRACE"
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(8)
                                    font.bold: true
                                }

                                Text {
                                    text: root.autoHideMs + " MS"
                                    color: Theme.accentPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(9)
                                    font.bold: true
                                }
                            }

                            DashSlider {
                                id: graceSlider
                                Layout.fillWidth: true
                                from: 150
                                to: 800
                                value: root.autoHideMs
                                accent: Theme.accentPrimary
                                onMoved: (v) => {
                                    const rounded = Math.round(v / 25) * 25
                                    if (root.hub)
                                        root.hub.dashboardAutoHideMs = rounded
                                    graceSlider.value = rounded
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "150MS SNAP"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: "800MS RELAXED"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                }
                            }
                        }
                    }

                    // Telemetry polling rate.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "TELEMETRY POLLING RATE"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { ms: 1000, label: "1S LIVE" },
                                    { ms: 3000, label: "3S BALANCED" },
                                    { ms: 5000, label: "5S ECO" }
                                ]

                                delegate: Item {
                                    id: selector
                                    required property var modelData
                                    readonly property bool selected: root.tickMs === modelData.ms

                                    Layout.fillWidth: true
                                    implicitHeight: 26

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 7
                                        color: selector.selected
                                            ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.9)
                                            : (selectorHover.hovered ? Theme.surfaceVariant : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6))
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: selector.modelData.label
                                        color: selector.selected ? Theme.onAccent : Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.dashboardText(8)
                                        font.bold: selector.selected
                                    }

                                    HoverHandler {
                                        id: selectorHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: {
                                            if (root.hub) root.hub.telemetryTickMs = selector.modelData.ms
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Display brightness ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: brightness.implicitHeight + 20

                ColumnLayout {
                    id: brightness
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "brightness_6"
                            color: Theme.accentTertiary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "DISPLAY BRIGHTNESS"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: root.brightAvailable
                                ? (root.brightDevice !== "" ? root.brightDevice : "BRIGHTNESSCTL")
                                : "NO BACKLIGHT"
                            color: root.brightAvailable ? Theme.textDim : Theme.statusWarn
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: (minusHover.hovered && brightnessReady) ? Theme.surfaceVariant : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            DashIcon {
                                anchors.centerIn: parent
                                name: "remove"
                                color: brightnessReady ? Theme.textMain : Theme.textDim
                                font.pixelSize: Theme.dashboardText(14)
                            }

                            HoverHandler {
                                id: minusHover
                                cursorShape: brightnessReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }

                            TapHandler {
                                enabled: brightnessReady
                                onTapped: root.stepBrightness(-5)
                            }
                        }

                        DashSlider {
                            id: brightSlider
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            from: 5
                            to: 100
                            interactive: brightnessReady
                            value: Brightness.percent
                            accent: Theme.accentTertiary
                            onMoved: (v) => root.brightMoved(v)
                        }

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: (plusHover.hovered && brightnessReady) ? Theme.surfaceVariant : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            DashIcon {
                                anchors.centerIn: parent
                                name: "add"
                                color: brightnessReady ? Theme.textMain : Theme.textDim
                                font.pixelSize: Theme.dashboardText(14)
                            }

                            HoverHandler {
                                id: plusHover
                                cursorShape: brightnessReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }

                            TapHandler {
                                enabled: brightnessReady
                                onTapped: root.stepBrightness(5)
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 32
                            text: root.brightPct >= 0 ? root.brightPct + "%" : "\u2014"
                            color: Theme.textMain
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(10)
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.brightAvailable
                        text: "no adjustable backlight device was found"
                        color: Theme.statusWarn
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(8)
                    }
                }
            }

            // ---------- Compute telemetry ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                DashIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: "memory"
                    color: Theme.accentPrimary
                    font.pixelSize: Theme.dashboardText(13)
                }

                Text {
                    Layout.fillWidth: true
                    text: "COMPUTE HARDWARE TELEMETRY"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    text: probe.coreCount > 0 ? (probe.coreCount + " LOGICAL CPUs") : "READING\u2026"
                    color: Theme.accentPrimaryDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                    font.bold: true
                }
            }

            // CPU card.
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: cpuCol.implicitHeight + 20

                ColumnLayout {
                    id: cpuCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.1)

                            DashIcon {
                                anchors.centerIn: parent
                                name: "developer_board"
                                color: Theme.accentPrimary
                                font.pixelSize: Theme.dashboardText(16)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: probe.cpuModelLong !== "" ? probe.cpuModelLong : "\u2014"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.dashboardText(12)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.cpuSubtitle()
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: probe.cpuReady ? Math.round(probe.cpuUsage) + "%" : "\u2014"
                                color: Theme.accentPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(19)
                                font.bold: true
                            }

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: "LOAD"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.letterSpacing: 0.5
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: "CORE DISTRIBUTION"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                        }

                        Text {
                            text: root.coreSummary()
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.55)

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2

                            Repeater {
                                model: Math.max(1, probe.coreUsage.length)

                                delegate: Item {
                                    id: coreBar
                                    required property int index
                                    readonly property real used: index < probe.coreUsage.length && probe.coreUsage[index] >= 0
                                        ? probe.coreUsage[index] : 0

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.25)
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        radius: 2
                                        height: Math.max(2, parent.height * Math.max(0, Math.min(1, coreBar.used / 100)))
                                        color: Theme.accentPrimary
                                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // GPU card.
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: gpuCol.implicitHeight + 20

                ColumnLayout {
                    id: gpuCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.12)

                            DashIcon {
                                anchors.centerIn: parent
                                name: "videogame_asset"
                                color: Theme.accentSecondary
                                font.pixelSize: Theme.dashboardText(16)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: !probe.gpuAvailable
                                    ? "GPU TELEMETRY UNAVAILABLE"
                                    : (probe.gpuName !== "" ? probe.gpuName.replace(/^NVIDIA\s+/, "") : "\u2014")
                                color: probe.gpuAvailable ? Theme.textMain : Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.dashboardText(12)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: !probe.gpuAvailable
                                    ? "no discrete GPU interface detected"
                                    : root.vramLine()
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            visible: probe.gpuAvailable

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: probe.gpuTempC >= 0 ? probe.gpuTempC + "\u00b0C" : "\u2014"
                                color: Theme.accentSecondary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(19)
                                font.bold: true
                            }

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: probe.gpuPowerW >= 0 ? probe.gpuPowerW.toFixed(1) + " W" : "\u2014"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: probe.gpuAvailable
                        implicitHeight: 8
                        radius: 4
                        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * (probe.gpuMemTotalMib > 0 && probe.gpuMemUsedMib >= 0
                                ? Math.max(0, Math.min(1, probe.gpuMemUsedMib / probe.gpuMemTotalMib))
                                : 0)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.accentPrimary }
                                GradientStop { position: 1; color: Theme.accentSecondary }
                            }
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            // RAM + storage pair.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.dashboardSpacingSm

                DashSurface {
                    Layout.fillWidth: true
                    fill: root.cardFill
                    radius: 14
                    implicitHeight: ramCol.implicitHeight + 16

                    ColumnLayout {
                        id: ramCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "data_usage"
                                color: Theme.accentPrimary
                                font.pixelSize: Theme.dashboardText(12)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "RAM"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }

                            Text {
                                text: probe.memPct >= 0 ? probe.memPct + "%" : "\u2014"
                                color: Theme.accentPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 2.5
                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * (probe.memPct >= 0 ? Math.max(0, Math.min(1, probe.memPct / 100)) : 0)
                                color: Theme.accentPrimary
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: probe.memReady ? probe.memUsedGiB.toFixed(1) + " G" : "\u2014"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(9)
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: probe.memReady ? probe.memTotalGiB.toFixed(1) + " G" : "\u2014"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(9)
                            }
                        }
                    }
                }

                DashSurface {
                    Layout.fillWidth: true
                    fill: root.cardFill
                    radius: 14
                    implicitHeight: diskCol.implicitHeight + 16

                    ColumnLayout {
                        id: diskCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "storage"
                                color: Theme.accentTertiary
                                font.pixelSize: Theme.dashboardText(12)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "NVME ROOT (/)"
                                color: Theme.textMain
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }

                            Text {
                                visible: probe.nvmeTempC >= 0
                                text: probe.nvmeTempC + "\u00b0C"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }

                            Text {
                                text: probe.storageReady ? Math.round(probe.storageFraction * 100) + "%" : "\u2014"
                                color: Theme.accentTertiary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 2.5
                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * probe.storageFraction
                                color: Theme.accentTertiary
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: probe.storageReady ? root.fmtBytes(probe.fsFreeBytes) + " free" : "\u2014"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(9)
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: probe.storageReady ? root.fmtBytes(probe.fsTotalBytes) + " cap" : "\u2014"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(9)
                            }
                        }
                    }
                }
            }

            // ---------- Audio ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: audioCol.implicitHeight + 20

                ColumnLayout {
                    id: audioCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "headphones"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "DEFAULT AUDIO OUTPUT"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 34
                            implicitHeight: 16
                            radius: 8
                            color: root.chipFill

                            Text {
                                anchors.centerIn: parent
                                text: "WPCTL"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.sinkName !== "" ? root.sinkName : "\u2014"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.dashboardText(12)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 26
                            implicitHeight: 26

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: muteHover.hovered ? Theme.surfaceVariant : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            DashIcon {
                                anchors.centerIn: parent
                                name: probe.volumeMuted ? "volume_off" : "volume_up"
                                color: probe.volumeMuted ? Theme.statusDanger : Theme.textMain
                                font.pixelSize: Theme.dashboardText(15)
                            }

                            HoverHandler {
                                id: muteHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                enabled: probe.volumeAvailable
                                onTapped: root.toggleMute()
                            }
                        }

                        DashSlider {
                            id: volSlider
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            from: 0
                            to: 1
                            interactive: probe.volumeAvailable
                            value: root.volUi
                            accent: probe.volumeMuted ? Theme.statusDanger : Theme.accentPrimary
                            onMoved: (v) => root.volumeMoved(v)
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 30
                            text: probe.volumeAvailable ? Math.round(root.volUi * 100) + "%" : "\u2014"
                            color: Theme.textMain
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(10)
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "output devices can be switched from the MEDIA tab"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(7)
                    }
                }
            }

            // ---------- Power ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: powerCol.implicitHeight + 20

                ColumnLayout {
                    id: powerCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "bolt"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "POWER PROFILE"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "thermostat"
                                color: probe.cpuTempC >= 0 ? Theme.accentPrimary : Theme.textDim
                                font.pixelSize: Theme.dashboardText(12)
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: probe.cpuTempC >= 0 ? probe.cpuTempC + "\u00b0C" : "\u2014"
                                color: Theme.accentPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                font.bold: true
                            }
                        }
                    }

                    // Real profile tiles, one per supported profile.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: root.profiles

                            delegate: Item {
                                id: profileTile
                                required property var modelData
                                readonly property bool active: root.powerProfile === modelData.id

                                Layout.fillWidth: true
                                implicitHeight: 54
                                opacity: root.profileBusy && !active ? 0.6 : 1

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: profileTile.active
                                        ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.92)
                                        : (tileHover.hovered && !root.profileBusy ? Theme.surfaceVariant : Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.55))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 1

                                    DashIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        name: root.profileIcon(profileTile.modelData.id)
                                        color: profileTile.active ? Theme.onAccent : Theme.textMuted
                                        font.pixelSize: Theme.dashboardText(17)
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.profileLabel(profileTile.modelData.id)
                                        color: profileTile.active ? Theme.onAccent : Theme.textMain
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.dashboardText(9)
                                        font.bold: profileTile.active
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        visible: profileTile.active || profileTile.modelData.degraded
                                        text: profileTile.active
                                            ? "ACTIVE"
                                            : "DEGRADED"
                                        color: profileTile.active
                                            ? Qt.rgba(Theme.onAccent.r, Theme.onAccent.g, Theme.onAccent.b, 0.75)
                                            : Theme.statusWarn
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.dashboardText(6)
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                    }
                                }

                                HoverHandler {
                                    id: tileHover
                                    cursorShape: root.profileBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                }

                                TapHandler {
                                    enabled: !root.profileBusy
                                    onTapped: root.setProfile(profileTile.modelData.id)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: root.profiles.length > 0
                                ? ("DRIVER: " + (root.profileDriver !== "" ? root.profileDriver : "\u2014"))
                                : (root.profileError !== "" ? root.profileError : "querying profiles\u2026")
                            color: root.profileError !== "" ? Theme.statusDanger : Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            visible: root.profileBusy
                            text: "APPLYING\u2026"
                            color: Theme.accentPrimary
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            font.bold: true
                        }
                    }

                    // Thermal strip: real temperatures and fan readings.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 8
                        color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.5)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: Theme.dashboardSpacingSm

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                color: probe.cpuTempC >= 80 ? Theme.statusWarn : Theme.accentPrimary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.thermalsText()
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }

                            Text {
                                visible: root.fansText() !== ""
                                text: root.fansText()
                                color: Theme.accentPrimaryDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // ---------- Session ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: sessionCol.implicitHeight + 16

                ColumnLayout {
                    id: sessionCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "dvr"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "SESSION & RUNTIME"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: kernelChip.implicitWidth + 12
                            implicitHeight: 16
                            radius: 8
                            color: root.chipFill

                            Text {
                                id: kernelChip
                                anchors.centerIn: parent
                                text: probe.kernel !== "" ? probe.kernel : "\u2014"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Text {
                                text: "COMPOSITOR"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.letterSpacing: 0.5
                            }

                            Text {
                                text: root.compositorVersion !== "" ? "Hyprland " + root.compositorVersion : "\u2014"
                                color: Theme.textMain
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 1
                            implicitHeight: 20
                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Text {
                                text: "UPTIME"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.letterSpacing: 0.5
                            }

                            Text {
                                text: root.fmtUptime(probe.uptimeSec)
                                color: Theme.accentPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 1
                            implicitHeight: 20
                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Text {
                                text: "SHELL"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.letterSpacing: 0.5
                            }

                            Text {
                                text: root.qsVersion !== "" ? "Quickshell " + root.qsVersion : "\u2014"
                                color: Theme.textMain
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(10)
                                font.bold: true
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
