import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import QtQuick
import qs.config
import qs.components

Scope {
    id: root

    // UI Popup Routing: "wifi", "bt", "battery", "clock", or "settings"
    property bool dashboardOpen: false
    property string activePopup: "settings"
    property bool powerMenuOpen: false
    property string pendingPowerAction: ""
    property var pendingPowerCmd: []
    property string tooltipText: ""

    // Set to true once Tide Island is running so Tide Island owns top-center notifications/OSD
    property bool tideIslandActive: true

    // Wallpaper & DND State
    property int wallpaperMode: 0
    property bool dndEnabled: false

    // Notification Toast State
    property bool toastVisible: false
    property string toastApp: ""
    property string toastSummary: ""
    property string toastBody: ""
    property bool toastUrgent: false

    // OSD State
    property bool osdVisible: false
    property string osdIcon: "󰕾"
    property int osdValue: 0

    // Calendar & Pomodoro Timer State
    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth()
    property string calTitle: ""
    property var calCells: []

    property bool pomoRunning: false
    property string pomoPhase: "Pomodoro Focus"
    property int pomoTargetSec: 25 * 60
    property int pomoRemainingSec: 25 * 60
    readonly property string pomoDisplay: {
        const m = Math.floor(pomoRemainingSec / 60)
        const s = pomoRemainingSec % 60
        return (m < 10 ? "0" + m : "" + m) + ":" + (s < 10 ? "0" + s : "" + s)
    }
    readonly property string pomoShortText: Math.ceil(pomoRemainingSec / 60) + "m"

    // Wi-Fi State
    property bool wifiEnabled: true
    property bool wifiScanning: false
    property string netType: "disconnected"
    property string netName: "Offline"
    property string netDevice: "wlan0"
    property var wifiNetworks: []

    // Bluetooth State
    property bool btPowered: false
    property bool btScanning: false
    property string btConnectedName: ""
    property var btDevices: []

    // Brightness, Power Profile, and Media State
    property int brightnessPct: 10
    property string powerProfile: "balanced"
    property string mediaStatus: "Stopped"
    property string mediaArtist: ""
    property string mediaTitle: ""

    Component.onCompleted: {
        root.rebuildCalendar()
        Quickshell.execDetached([
            "hyprctl", "--batch",
            "keyword misc:disable_hyprland_logo true ; "
            + "keyword misc:disable_splash_rendering true ; "
            + "keyword misc:background_color 0x0e121d ; "
            + "keyword general:col.active_border rgba(eeb7d8ee) rgba(9ce5c0ee) 45deg ; "
            + "keyword general:col.inactive_border rgba(3a3a54aa) ; "
            + "keyword decoration:rounding 12"
        ])
    }

    // NotificationServer handled by Tide Island

    IpcHandler {
        target: "dashboard"
        function toggle() { dashboard.toggle() }
        function open() { dashboard.isOpen = true }
        function close() { dashboard.isOpen = false }
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

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

    // Pomodoro 1-second countdown timer (only runs when pomoRunning is true)
    Timer {
        interval: 1000
        running: root.pomoRunning
        repeat: true
        onTriggered: {
            if (root.pomoRemainingSec > 1) {
                root.pomoRemainingSec -= 1
            } else {
                root.pomoRemainingSec = 0
                root.pomoRunning = false
                root.toastApp = "Pomodoro Timer"
                root.toastSummary = "✦ " + root.pomoPhase + " Complete!"
                root.toastBody = "Time for a break or your next session."
                root.toastUrgent = true
                root.toastVisible = true
                toastTimer.restart()
            }
        }
    }

    // Processes: Wi-Fi, Bluetooth, Brightness, Power Profiles, Media
    Process {
        id: nmcliProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseNmcli(this.text)
        }
    }

    Process {
        id: wifiRadioProc
        command: ["nmcli", "radio", "wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = (this.text.trim() === "enabled")
            }
        }
    }

    Process {
        id: wifiListProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                root.parseWifiList(this.text)
            }
        }
    }

    Process {
        id: wifiRescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: wifiListProc.running = true
    }

    Process {
        id: btStatusProc
        command: [
            "sh", "-c",
            "bluetoothctl show | grep -q '\''Powered: yes'\'' && echo '\''ON'\'' || echo '\''OFF'\''; "
            + "bluetoothctl devices | while read -r _ mac name; do "
            + "  if [ -n \"$mac\" ]; then "
            + "    conn=$(bluetoothctl info \"$mac\" | grep -q '\''Connected: yes'\'' && echo '\''1'\'' || echo '\''0'\''); "
            + "    echo \"$conn|$mac|$name\"; "
            + "  fi; "
            + "done"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.btScanning = false
                root.parseBtOutput(this.text)
            }
        }
    }

    Process {
        id: btScanProc
        command: ["sh", "-c", "bluetoothctl --timeout 4 scan on >/dev/null 2>&1"]
        onExited: btStatusProc.running = true
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
        id: profileReadProc
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const mode = this.text.trim()
                if (mode !== "") root.powerProfile = mode
            }
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
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            if (!nmcliProc.running) nmcliProc.running = true
            if (!mediaReadProc.running) mediaReadProc.running = true
            if (root.dashboardOpen) {
                if (root.activePopup === "battery" && !profileReadProc.running) profileReadProc.running = true
                if (root.activePopup === "bt" && !btStatusProc.running) btStatusProc.running = true
            }
        }
    }

    Timer {
        id: osdTimer
        interval: 1500
        repeat: false
        onTriggered: root.osdVisible = false
    }

    Timer {
        id: toastTimer
        interval: 4500
        repeat: false
        onTriggered: root.toastVisible = false
    }

    Timer {
        id: screenshotTimer
        interval: 180
        repeat: false
        onTriggered: Quickshell.execDetached(["sh", "-c", "grim -g \"$(slurp)\" - | swappy -f -"])
    }

    // ------------------------------------------------------------------------
    // CALENDAR & POMODORO FUNCTIONS
    // ------------------------------------------------------------------------
    function rebuildCalendar() {
        const months = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        root.calTitle = months[root.calMonth] + " " + root.calYear

        const now = new Date()
        const firstDay = new Date(root.calYear, root.calMonth, 1)
        const startOffset = (firstDay.getDay() + 6) % 7 // Monday = 0
        const daysInMonth = new Date(root.calYear, root.calMonth + 1, 0).getDate()
        const daysInPrev = new Date(root.calYear, root.calMonth, 0).getDate()

        const cells = []
        for (let i = 0; i < 42; i++) {
            const dNum = i - startOffset + 1
            let label = ""
            let inMonth = false
            let isToday = false

            if (dNum < 1) {
                label = "" + (daysInPrev + dNum)
            } else if (dNum > daysInMonth) {
                label = "" + (dNum - daysInMonth)
            } else {
                label = "" + dNum
                inMonth = true
                isToday = (
                    dNum === now.getDate() &&
                    root.calMonth === now.getMonth() &&
                    root.calYear === now.getFullYear()
                )
            }
            cells.push({ label: label, inMonth: inMonth, isToday: isToday })
        }
        root.calCells = cells
    }

    function changeCalendarMonth(delta) {
        let m = root.calMonth + delta
        let y = root.calYear
        if (m < 0) { m = 11; y -= 1 }
        else if (m > 11) { m = 0; y += 1 }
        root.calMonth = m
        root.calYear = y
        root.rebuildCalendar()
    }

    function resetCalendar() {
        const now = new Date()
        root.calYear = now.getFullYear()
        root.calMonth = now.getMonth()
        root.rebuildCalendar()
    }

    function togglePomodoro() {
        if (root.pomoRemainingSec <= 0) {
            root.pomoRemainingSec = root.pomoTargetSec
        }
        root.pomoRunning = !root.pomoRunning
    }

    function resetPomodoro() {
        root.pomoRunning = false
        root.pomoRemainingSec = root.pomoTargetSec
    }

    function setPomodoroPreset(mins, title) {
        root.pomoRunning = false
        root.pomoPhase = title
        root.pomoTargetSec = mins * 60
        root.pomoRemainingSec = mins * 60
    }

    function addPomodoroMinutes(mins) {
        root.pomoRemainingSec += mins * 60
        root.pomoTargetSec = Math.max(root.pomoTargetSec, root.pomoRemainingSec)
    }

    // ------------------------------------------------------------------------
    // ISOLATED POPUP ROUTER
    // ------------------------------------------------------------------------
    function setTooltip(text) { root.tooltipText = text }
    function clearTooltip() { root.tooltipText = "" }
    function dismissToast() { root.toastVisible = false }

    function openPopup(kind) {
        root.tooltipText = ""
        root.powerMenuOpen = false
        if (root.dashboardOpen && root.activePopup === kind) {
            root.dashboardOpen = false
            return
        }
        root.activePopup = kind
        root.dashboardOpen = true

        if (kind === "wifi") {
            nmcliProc.running = true
            wifiRadioProc.running = true
            wifiListProc.running = true
        } else if (kind === "bt") {
            btStatusProc.running = true
        } else if (kind === "battery") {
            profileReadProc.running = true
        } else if (kind === "clock") {
            root.rebuildCalendar()
        } else if (kind === "settings") {
            brightReadProc.running = true
            mediaReadProc.running = true
        }
    }

    function toggleDashboard() {
        openPopup("settings")
    }

    function runCenterAction(action) {
        if (action === "wall") cycleWallpaper()
        else if (action === "clip") Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "call", "tide", "openClipboard"])
        else if (action === "notif") Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "call", "tide", "openNotificationCenter"])
    }

    function cycleWallpaper() {
        root.wallpaperMode = (root.wallpaperMode + 1) % 3
        Quickshell.execDetached(["/home/rice/Projects/my-rice/scripts/cycle-wall.fish"])
    }

    // Wi-Fi Actions
    function toggleWifiPower() {
        const next = root.wifiEnabled ? "off" : "on"
        root.wifiEnabled = !root.wifiEnabled
        Quickshell.execDetached(["nmcli", "radio", "wifi", next])
        nmcliProc.running = true
        wifiListProc.running = true
    }

    function rescanWifi() {
        root.wifiScanning = true
        wifiRescanProc.running = true
    }

    function connectWifi(ssid) {
        if (!ssid) return
        Quickshell.execDetached(["/home/rice/Projects/my-rice/scripts/wifi-connect.sh", ssid])
        nmcliProc.running = true
        wifiListProc.running = true
    }

    function disconnectWifi() {
        Quickshell.execDetached(["nmcli", "device", "disconnect", root.netDevice])
        nmcliProc.running = true
        wifiListProc.running = true
    }

    function parseWifiList(raw) {
        const lines = raw.trim().split("\n")
        const seen = {}
        const result = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (!line) continue
            const parts = line.split(":")
            if (parts.length < 3) continue
            const inUse = (parts[0].trim() === "*")
            const ssid = parts[1].trim()
            const sig = parseInt(parts[2], 10) || 0
            if (!ssid || seen[ssid]) continue
            seen[ssid] = true
            result.push({
                active: inUse,
                ssid: ssid,
                signal: sig
            })
            if (result.length >= 6) break
        }
        root.wifiNetworks = result
    }

    // Bluetooth Actions
    function toggleBtPower() {
        const next = root.btPowered ? "off" : "on"
        root.btPowered = !root.btPowered
        Quickshell.execDetached(["bluetoothctl", "power", next])
        btStatusProc.running = true
    }

    function scanBluetooth() {
        root.btScanning = true
        btScanProc.running = true
    }

    function toggleBtDevice(mac, isConnected) {
        if (!mac) return
        const action = isConnected ? "disconnect" : "connect"
        Quickshell.execDetached(["bluetoothctl", action, mac])
        btStatusProc.running = true
    }

    function parseBtOutput(raw) {
        const lines = raw.trim().split("\n")
        if (lines.length === 0) return
        root.btPowered = (lines[0].trim() === "ON")
        const devs = []
        let firstConnected = ""
        for (let i = 1; i < lines.length; i++) {
            const parts = lines[i].split("|")
            if (parts.length < 3) continue
            const conn = (parts[0] === "1")
            const mac = parts[1]
            const name = parts.slice(2).join("|")
            if (conn && firstConnected === "") firstConnected = name
            devs.push({
                connected: conn,
                mac: mac,
                name: name
            })
        }
        root.btConnectedName = firstConnected
        root.btDevices = devs
    }

    function setPowerProfile(mode) {
        root.powerProfile = mode
        Quickshell.execDetached(["powerprofilesctl", "set", mode])
        profileReadProc.running = true
    }

    function showOsd(icon, val) {
        if (root.tideIslandActive) return
        root.osdIcon = icon
        root.osdValue = Math.max(0, Math.min(150, Math.round(val)))
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
        const clamped = Math.max(0.0, Math.min(1.5, ratio))
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
    LeftRail           { hub: root; notifications: notifCenter; dashboard: dashboard }
    NotifCenter        { id: notifCenter; hub: root }
    NotifToast         { hub: root }
    Dashboard          { id: dashboard; hub: root }
    ControlCenter      { hub: root }
    PowerMenu          { hub: root }
    OsdOverlay         { hub: root }
    // NotificationToasts { hub: root }
}
