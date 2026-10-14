import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import QtQuick
import qs.config
import qs.components

Scope {
    id: root

    // UI Overlay & Tooltip States
    property bool dashboardOpen: false
    property bool powerMenuOpen: false
    property string pendingPowerAction: ""
    property var pendingPowerCmd: []
    property string tooltipText: ""

    // OSD State
    property bool osdVisible: false
    property string osdIcon: "󰕾"
    property int osdValue: 0

    // Network, Brightness, and Media State
    property string netType: "disconnected"
    property string netName: "Offline"
    property string netDevice: "wlan0"
    property int brightnessPct: 10
    property string mediaStatus: "Stopped"
    property string mediaArtist: ""
    property string mediaTitle: ""

    // Automatically remove the clashing cyan Hyprland droplet & sync borders on load
    Component.onCompleted: {
        Quickshell.execDetached([
            "hyprctl", "--batch",
            "keyword misc:disable_hyprland_logo true ; "
            + "keyword misc:disable_splash_rendering true ; "
            + "keyword misc:background_color 0x111522 ; "
            + "keyword general:col.active_border rgba(eeb7d8ee) rgba(9ce5c0ee) 45deg ; "
            + "keyword general:col.inactive_border rgba(3a3a54aa) ; "
            + "keyword decoration:rounding 12"
        ])
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // Audio & Battery Computed Properties
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property bool audioReady: audioSink !== null && audioSink.audio !== null
    readonly property bool isMuted: audioReady ? audioSink.audio.muted : false
    readonly property int volumePct: audioReady ? Math.round(audioSink.audio.volume * 100) : 0

    readonly property var batDevice: UPower.displayDevice
    readonly property int batteryPct: {
        if (!batDevice) return 0
        const raw = batDevice.percentage
        return raw <= 1.0 ? Math.round(raw * 100) : Math.round(raw)
    }
    readonly property bool onAcPower: !UPower.onBattery

    // Processes: Network (nmcli), Brightness (brightnessctl), Media (playerctl)
    Process {
        id: nmcliProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseNmcli(this.text)
        }
    }

    Process {
        id: brightReadProc
        command: ["brightnessctl", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseBrightness(this.text)
        }
    }

    Process {
        id: mediaReadProc
        command: ["playerctl", "metadata", "--format", "{{status}}|{{artist}}|{{title}}"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseMedia(this.text)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            if (!nmcliProc.running) nmcliProc.running = true
            if (!mediaReadProc.running) mediaReadProc.running = true
        }
    }

    Timer {
        id: osdTimer
        interval: 1500
        repeat: false
        onTriggered: root.osdVisible = false
    }

    Timer {
        id: screenshotTimer
        interval: 180
        repeat: false
        onTriggered: Quickshell.execDetached(["sh", "-c", "grim -g \"$(slurp)\" - | swappy -f -"])
    }

    // Tooltip & OSD Helpers
    function setTooltip(text) {
        root.tooltipText = text
    }

    function clearTooltip() {
        root.tooltipText = ""
    }

    function showOsd(icon, val) {
        root.osdIcon = icon
        root.osdValue = Math.max(0, Math.min(100, Math.round(val)))
        root.osdVisible = true
        osdTimer.restart()
    }

    function parseNmcli(raw) {
        const lines = raw.trim().split("\n")
        let foundType = "disconnected"
        let foundName = "Offline"
        let foundDev = "wlan0"

        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split(":")
            if (parts.length < 4) continue
            const dev = parts[0]
            const type = parts[1]
            const state = parts[2]
            const conn = parts.slice(3).join(":")

            if ((type === "wifi" || type === "ethernet") && state === "connected") {
                foundDev = dev
                foundType = type
                foundName = conn !== "" ? conn : dev
                break
            }
        }
        root.netDevice = foundDev
        root.netType = foundType
        root.netName = foundName
    }

    function parseBrightness(raw) {
        const line = raw.trim().split("\n")[0]
        if (!line) return
        const parts = line.split(",")
        if (parts.length >= 4) {
            const parsed = parseInt(parts[3].replace("%", ""), 10)
            if (!isNaN(parsed)) root.brightnessPct = parsed
        }
    }

    function parseMedia(raw) {
        const line = raw.trim().split("\n")[0]
        if (!line || line.indexOf("|") === -1) {
            root.mediaStatus = "Stopped"
            root.mediaArtist = ""
            root.mediaTitle = ""
            return
        }
        const parts = line.split("|")
        root.mediaStatus = parts[0] || "Stopped"
        root.mediaArtist = parts[1] || ""
        root.mediaTitle = parts.slice(2).join("|") || ""
    }

    function setBrightnessPct(targetPct) {
        const clamped = Math.max(5, Math.min(100, Math.round(targetPct)))
        root.brightnessPct = clamped
        Quickshell.execDetached(["brightnessctl", "-q", "set", clamped + "%"])
        root.showOsd("󰖨", clamped)
    }

    function stepBrightness(deltaPct) {
        setBrightnessPct(root.brightnessPct + deltaPct)
    }

    function setVolumeRatio(ratio) {
        if (!root.audioReady) return
        const clamped = Math.max(0.0, Math.min(1.0, ratio))
        root.audioSink.audio.muted = false
        root.audioSink.audio.volume = clamped
        root.showOsd("󰕾", clamped * 100)
    }

    function stepVolume(delta) {
        if (!root.audioReady) return
        setVolumeRatio(root.audioSink.audio.volume + delta)
    }

    function toggleMute() {
        if (!root.audioReady) return
        root.audioSink.audio.muted = !root.audioSink.audio.muted
        root.showOsd(root.audioSink.audio.muted ? "󰝟" : "󰕾", root.volumePct)
    }

    function mediaPlayPause() {
        Quickshell.execDetached(["playerctl", "play-pause"])
        mediaReadProc.running = true
    }

    function mediaNext() {
        Quickshell.execDetached(["playerctl", "next"])
        mediaReadProc.running = true
    }

    function mediaPrev() {
        Quickshell.execDetached(["playerctl", "previous"])
        mediaReadProc.running = true
    }

    function toggleDashboard() {
        root.tooltipText = ""
        root.powerMenuOpen = false
        root.dashboardOpen = !root.dashboardOpen
        if (root.dashboardOpen) {
            nmcliProc.running = true
            brightReadProc.running = true
            mediaReadProc.running = true
        }
    }

    function openPowerMenu() {
        root.tooltipText = ""
        root.dashboardOpen = false
        root.pendingPowerAction = ""
        root.powerMenuOpen = true
    }

    function triggerScreenshot() {
        screenshotTimer.start()
    }

    // Modular Surfaces
    // WallpaperLayer { hub: root }
    GpsPanel       { hub: root }
    ControlCenter  { hub: root }
    PowerMenu      { hub: root }
    OsdOverlay     { hub: root }
}
