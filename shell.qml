import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import QtQuick
import Quickshell.Wayland
import qs.config
import qs.components
import "pet"

Scope {
    id: root

    readonly property string repoRoot: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

    // UI Popup Routing: "wifi", "bt", "battery", "clock", or "settings"
    property bool dashboardOpen: false
    property string activePopup: "settings"
    // Dashboard behaviour settings (owned here, consumed by DashboardHost /
    // the edge sensor / SysProbe so the System tab never duplicates state).
    property bool edgeHotspotEnabled: true
    property int dashboardAutoHideMs: 400
    property int telemetryTickMs: 1000
    // Right-edge activation strip configuration
    property int edgeSensorWidth: 5
    property int edgeSensorMarginTop: 60      // Clears top-center island zone / corner
    property int edgeSensorMarginBottom: 40   // Clears bottom corner widgets
    // Wall-clock ms of the last Dashboard close; the edge sensor
    // ignores hover until a short cooldown has passed so closing the drawer
    // can never be immediately undone by the surface that appears under the
    // pointer as the panel unmaps.
    property real dashLastHide: 0
    readonly property int dashboardReopenCooldownMs: 800
    // Screen point the current popup anchors to (set by the rail icon that
    // opened it; screen coordinates of the rail window, i.e. screen coords).
    property real popupAnchorY: -1
    readonly     property var popupScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
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
    // Wi-Fi operation feedback (never holds passwords)
    property string wifiError: ""
    property string wifiNotice: ""
    property string wifiPending: ""
    property string wifiPendingTarget: ""
    property int wifiVerifyTries: 0
    property int wifiScanGen: 0
    property int wifiListGen: 0

    // Bluetooth State
    property bool btPowered: false
    property bool btScanning: false
    property string btConnectedName: ""
    property var btDevices: []
    // Bluetooth operation feedback
    property string btError: ""
    property string btNotice: ""
    property string btPending: ""
    property string btPendingTarget: ""
    property string btBusyMac: ""
    property int btVerifyTries: 0
    property int btScanGen: 0
    property int btStatusGen: 0

    // Brightness, Power Profile, and Media State
    readonly property int brightnessPct: Brightness.percent
    property string powerProfile: "balanced"
    property string mediaStatus: "Stopped"
    property string mediaArtist: ""
    property string mediaTitle: ""

    function toHyprRgba(col, alphaHex) {
        const c = Qt.color(col)
        const toHex = v => Math.max(0, Math.min(255, Math.round(v * 255))).toString(16).padStart(2, "0")
        const a = alphaHex !== undefined ? alphaHex : toHex(c.a)
        return "rgba(" + toHex(c.r) + toHex(c.g) + toHex(c.b) + a + ")"
    }

    Component.onCompleted: {
        root.rebuildCalendar()
        const b1 = root.toHyprRgba(Theme.brandAccent, "ee")
        const b2 = root.toHyprRgba(Theme.accentSecondary, "ee")
        const inact = root.toHyprRgba(Theme.border, "aa")
        Quickshell.execDetached([
            "hyprctl", "--batch",
            "keyword misc:disable_hyprland_logo true ; "
            + "keyword misc:disable_splash_rendering true ; "
            + "keyword misc:background_color 0x0e121d ; "
            + "keyword general:col.active_border " + b1 + " " + b2 + " 45deg ; "
            + "keyword general:col.inactive_border " + inact + " ; "
            + "keyword decoration:rounding 12"
        ])
    }

    // NotificationServer handled by Tide Island

    IpcHandler {
        target: "dashboard"
        function toggle() { root.toggleDashboard() }
        function open() { root.openDashboard(true) }
        function close() { root.closeDashboard() }
    }

    IpcHandler {
        target: "notifcenter"
        function toggle() { notifCenter.toggle() }
        function open() { notifCenter.open = true }
        function close() { notifCenter.open = false }
        function section(sec: int) { notifCenter.currentSection = sec }
        function status(): string { return JSON.stringify({ open: notifCenter.open, section: notifCenter.currentSection, unread: notifCenter.unreadCount, dnd: notifCenter.dndActive }) }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle() { root.toggleWallpaperCarousel() }
        function open() { aiChat.close(); wallpaperCarousel.isOpen = true }
        function close() { wallpaperCarousel.isOpen = false }
    }

    IpcHandler {
        target: "aichat"
        function toggle() { aiChat.toggle() }
        function open() { aiChat.open() }
        function close() { aiChat.close() }
        function send(text: string) { root.openAIChat(); aiChat.send(text, false) }
        function stop() { aiChat.stopGeneration() }
        function clear() { aiChat.clearNow() }
        function regenerate() { aiChat.regenerate() }
    }

    IpcHandler {
        target: "popup"
        function open(kind: string) { root.openPopup(kind, -1) }
        function close() { root.closePopup() }
        function powerProfiles(): string { return batteryPopup.powerProfilesJson() }
        function setPowerProfile(id: string) { batteryPopup.setProfile(id) }
    }

    IpcHandler {
        target: "mediahub"
        function toggle() { root.toggleMediaHub() }
        function open() { root.openMediaHub() }
        function close() { root.closeMediaHub() }
        function togglePlayback() { mediaHubWindow.toggleMusicPlayback() }
        function nextTrack() { mediaHubWindow.nextMusicTrack() }
        function previousTrack() { mediaHubWindow.previousMusicTrack() }
        function stopPlayback() { mediaHubWindow.stopMusicPlayback() }
        function seekPlayback(position: real) { mediaHubWindow.seekMusicPlayback(position) }
        function setPage(p: int) { if (mediaHubWindow.hubItem) mediaHubWindow.hubItem.page = p }
        function getDownloadsState(): string {
            if (!mediaHubWindow.hubItem) return JSON.stringify({ loaded: false })
            var h = mediaHubWindow.hubItem
            return JSON.stringify({
                loaded: true,
                page: h.page,
                connected: h.downloadBackendConnected,
                ready: h.downloadsStateReady,
                toolStatus: h.downloadsBackend ? h.downloadsBackend.toolStatus : null,
                dlInspecting: h.dlInspecting,
                dlBusy: h.dlBusy,
                dlCanMerge: h.dlCanMerge,
                dlError: h.dlError,
                dlInspection: h.dlInspection,
                downloads: h.downloads,
                downloading: h.downloadsBackend ? h.downloadsBackend.downloading : false,
                activeJobId: h.downloadsBackend ? h.downloadsBackend.activeJobId : ""
            })
        }
        function inspectUrl(url: string): string {
            if (!mediaHubWindow.hubItem) return JSON.stringify({ ok: false, reason: "not_loaded" })
            mediaHubWindow.hubItem.dlUrlText = url
            var ok = mediaHubWindow.hubItem.inspectDownloadUrl()
            return JSON.stringify({ ok: ok })
        }
        function setDownloadDest(dest: string) {
            if (mediaHubWindow.hubItem) mediaHubWindow.hubItem.dlDirectory = dest
        }
        function enqueueDownload(): string {
            if (!mediaHubWindow.hubItem) return JSON.stringify({ ok: false, reason: "not_loaded" })
            var ok = mediaHubWindow.hubItem.enqueueInspectedDownload()
            return JSON.stringify({ ok: ok })
        }
        function cancelJob(jobId: string): string {
            if (!mediaHubWindow.hubItem) return JSON.stringify({ ok: false, reason: "not_loaded" })
            var job = mediaHubWindow.hubItem.downloadJob(jobId)
            if (job) mediaHubWindow.hubItem.dlAction(job, "cancel")
            return JSON.stringify({ ok: true })
        }
        function clearQueue(): string {
            if (!mediaHubWindow.hubItem) return JSON.stringify({ ok: false, reason: "not_loaded" })
            mediaHubWindow.hubItem.downloads = []
            return JSON.stringify({ ok: true })
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle() { root.toggleClipboard() }
        function open() { root.openClipboard() }
        function close() { root.closeClipboard() }
        function count(): int { return clipboardPicker.itemCount }
    }

    IpcHandler {
        target: "toolbox"
        function toggle() { root.toggleToolbox() }
        function open() { root.openToolbox() }
        function close() { root.closeToolbox() }
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
                root.checkWifiPending()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    root.wifiError = "Wi-Fi radio query failed. Is NetworkManager (nmcli) installed?"
            }
        }
    }

    Process {
        id: wifiListProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                // Passive list (no rescan): safe to apply whenever it arrives,
                // but a stale rescan result must not clear a newer scan.
                if (root.wifiListGen === root.wifiScanGen) {
                    root.wifiScanning = false
                    root.parseWifiList(this.text)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "" && root.wifiListGen === root.wifiScanGen) {
                    root.wifiScanning = false
                    root.wifiError = "Wi-Fi scan failed (" + this.text.trim().split("\n")[0] + ")."
                }
            }
        }
        onExited: (code, sig) => {
            if (code !== 0 && root.wifiListGen === root.wifiScanGen) {
                root.wifiScanning = false
                if (root.wifiError === "")
                    root.wifiError = "Wi-Fi list unavailable (nmcli exit " + code + ")."
            }
        }
    }

    Process {
        id: wifiRescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "") {
                    root.wifiScanning = false
                    root.wifiError = "Wi-Fi rescan failed (" + this.text.trim().split("\n")[0] + ")."
                }
            }
        }
        onExited: (code, sig) => {
            if (code !== 0) {
                root.wifiScanning = false
                if (root.wifiError === "")
                    root.wifiError = "Wi-Fi rescan failed (exit " + code + ")."
                return
            }
            root.wifiListGen = root.wifiScanGen
            if (!wifiListProc.running) wifiListProc.running = true
        }
    }

    Process {
        id: btStatusProc
        command: [
            "sh", "-c",
            "bluetoothctl show | grep -q '\''Powered: yes'\'' && echo '\''ON'\'' || echo '\''OFF'\''; "
            + "bluetoothctl devices | while read -r _ mac name; do "
            + "  if [ -n \"$mac\" ]; then "
            + "    info=$(bluetoothctl info \"$mac\" 2>/dev/null); "
            + "    conn=$(printf '%s' \"$info\" | grep -q '\''Connected: yes'\'' && echo '\''1'\'' || echo '\''0'\''); "
            + "    paired=$(printf '%s' \"$info\" | grep -q '\''Paired: yes'\'' && echo '\''1'\'' || echo '\''0'\''); "
            + "    echo \"$conn|$paired|$mac|$name\"; "
            + "  fi; "
            + "done"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.btStatusGen === root.btScanGen) {
                    root.btScanning = false
                    root.parseBtOutput(this.text)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "" && root.btStatusGen === root.btScanGen) {
                    root.btScanning = false
                    root.btError = "Bluetooth query failed. Is BlueZ (bluetoothctl) installed?"
                }
            }
        }
        onExited: (code, sig) => {
            if (code !== 0 && root.btStatusGen === root.btScanGen) {
                root.btScanning = false
                if (root.btError === "")
                    root.btError = "Bluetooth status unavailable (exit " + code + ")."
            }
        }
    }

    Process {
        id: btScanProc
        command: ["sh", "-c", "bluetoothctl --timeout 6 scan on >/dev/null 2>&1"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "") {
                    root.btScanning = false
                    root.btError = "Bluetooth scan failed."
                }
            }
        }
        onExited: (code, sig) => {
            if (code !== 0) {
                root.btScanning = false
                if (root.btError === "")
                    root.btError = "Bluetooth scan failed (exit " + code + ")."
                return
            }
            root.btStatusGen = root.btScanGen
            if (!btStatusProc.running) btStatusProc.running = true
        }
    }

    // One-shot command runners: track async completion so state is only
    // reported as changed after the command exits AND a re-read verifies it.
    Process {
        id: wifiCmdProc
        stderr: StdioCollector {
            onStreamFinished: {
                // Stash first stderr line; the onExited handler decides.
                if (this.text.trim() !== "")
                    root.wifiError = this.text.trim().split("\n")[0]
            }
        }
        onExited: (code, sig) => {
            if (code !== 0) {
                // A direct open-network connect failing usually means the
                // network actually needs a secret: fall back to the rofi
                // password prompt instead of declaring failure.
                if (root.wifiPending === "connect" && root.wifiPendingTarget !== "") {
                    root.connectWifiWithPrompt(root.wifiPendingTarget)
                    root.refreshWifiReads()
                    return
                }
                root.wifiPending = ""
                if (root.wifiError === "")
                    root.wifiError = "Wi-Fi command failed (exit " + code + "). State re-read below."
            }
            root.refreshWifiReads()
            root.wifiVerifyTries = 0
            wifiVerifyTimer.restart()
        }
    }

    Process {
        id: btCmdProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    root.btError = this.text.trim().split("\n")[0]
            }
        }
        onExited: (code, sig) => {
            if (code !== 0) {
                // Never claim pairing/connection success from a started
                // command: keep verification running so the re-read decides.
                if (root.btError === "")
                    root.btError = "Bluetooth command exited " + code + ". Verifying actual state…"
                if (root.btPending === "connect-dev")
                    root.btNotice = "Connect did not complete yet. Use Pair first if the device is not paired."
            }
            root.refreshBtReads()
            root.btVerifyTries = 0
            btVerifyTimer.restart()
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
                if (root.activePopup === "bt" && !btStatusProc.running && !btScanProc.running) btStatusProc.running = true
                if (root.activePopup === "wifi" && !wifiListProc.running && !wifiRescanProc.running && !wifiCmdProc.running) {
                    root.wifiListGen = root.wifiScanGen
                    wifiListProc.running = true
                }
            }
        }
    }

    // Re-poll after an async Wi-Fi command until the target state is observed
    // (or attempts run out). Success is only reported after verification.
    Timer {
        id: wifiVerifyTimer
        interval: 1500
        repeat: true
        onTriggered: {
            root.wifiVerifyTries += 1
            root.refreshWifiReads()
            if (root.checkWifiPending()) {
                stop()
                return
            }
            // Connecting via an external password prompt can take a while.
            const limit = (root.wifiPending === "connect") ? 24 : 5
            if (root.wifiVerifyTries >= limit) {
                stop()
                if (root.wifiPending !== "") {
                    root.wifiPending = ""
                    root.wifiError = "Change not confirmed after re-read. Check the device state."
                }
            }
        }
    }

    // Same verification pattern for Bluetooth commands.
    Timer {
        id: btVerifyTimer
        interval: 1500
        repeat: true
        onTriggered: {
            root.btVerifyTries += 1
            root.refreshBtReads()
            if (root.checkBtPending()) {
                stop()
            } else if (root.btVerifyTries >= 5) {
                stop()
                if (root.btPending !== "") {
                    root.btPending = ""
                    root.btBusyMac = ""
                    root.btError = "Change not confirmed after re-read. Check the adapter/device."
                }
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

    function openPopup(kind, anchorY) {
        root.tooltipText = ""
        aiChat.close()
        if (anchorY !== undefined && anchorY >= 0)
            root.popupAnchorY = anchorY
        if (root.dashboardOpen && root.activePopup === kind) {
            root.dashboardOpen = false
            return
        }
        root.activePopup = kind
        root.dashboardOpen = true
        // Keep the Dashboard drawer closed while a radio popup is open so the
        // two never compete for attention. Routed through the dispatcher so
        // whichever dashboard implementation is active gets closed.
        root.closeDashboard()

        if (kind === "wifi") {
            root.wifiError = ""
            if (!nmcliProc.running) nmcliProc.running = true
            if (!wifiRadioProc.running) wifiRadioProc.running = true
            if (!wifiListProc.running && !wifiRescanProc.running && !wifiCmdProc.running) {
                root.wifiListGen = root.wifiScanGen
                wifiListProc.running = true
            }
        } else if (kind === "bt") {
            root.btError = ""
            if (!btStatusProc.running && !btScanProc.running && !btCmdProc.running) {
                root.btStatusGen = root.btScanGen
                btStatusProc.running = true
            }
        } else if (kind === "battery") {
            if (!profileReadProc.running) profileReadProc.running = true
        } else if (kind === "clock") {
            root.rebuildCalendar()
        } else if (kind === "settings") {
            Brightness.refresh()
            if (!mediaReadProc.running) mediaReadProc.running = true
        }
    }

    function closePopup() {
        root.dashboardOpen = false
    }

    // Dashboard dispatchers: every entry point (IPC, edge sensor, popup
    // router) routes through these to the single DashboardHost instance.
    function openDashboard(pinned) {
        aiChat.close()
        notifCenter.close()
        dashboardHost.open(pinned)
    }

    function closeDashboard() {
        dashboardHost.close()
    }

    function toggleDashboard() {
        if (!root.dashboardOpen) aiChat.close()
        dashboardHost.toggle()
    }

    function openAIChat() {
        aiChat.open()
    }

    function closeAIChat() {
        aiChat.close()
    }

    function toggleAIChat() {
        aiChat.toggle()
    }

    // Media Hub is a single hosted surface; open() is idempotent so repeated
    // entry-point clicks can never spawn a second window.
    function openMediaHub() {
        mediaHubWindow.open()
    }

    function closeMediaHub() {
        mediaHubWindow.close()
    }

    function toggleMediaHub() {
        mediaHubWindow.toggle()
    }

    function openClipboard() {
        clipboardPicker.open()
    }

    function closeClipboard() {
        clipboardPicker.close()
    }

    function toggleClipboard() {
        clipboardPicker.toggle()
    }

    function openToolbox() {
        toolboxWindow.open()
    }

    function closeToolbox() {
        toolboxWindow.close()
    }

    function toggleToolbox() {
        toolboxWindow.toggle()
    }

    function closeWallpaperCarousel() {
        wallpaperCarousel.isOpen = false
    }

    // Routes match the verified left-rail/tools-tab form: explicit instance
    // path (two quickshell instances exist) and --any-display because the
    // spawned child may lack display context. Tide has no openNotificationCenter;
    // toggleNotificationCenter is the real, verified function.
    function runCenterAction(action) {
        if (action === "wall") cycleWallpaper()
        else if (action === "clip") Quickshell.execDetached([root.repoRoot + "/scripts/gps-ipc", "clipboard", "toggle"])
        else if (action === "notif") Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "--any-display", "-p", Quickshell.env("HOME") + "/.local/share/tide-island", "call", "tide", "toggleNotificationCenter"])
    }

    function cycleWallpaper() {
        root.wallpaperMode = (root.wallpaperMode + 1) % 3
        Quickshell.execDetached([root.repoRoot + "/scripts/cycle-wall.fish"])
    }

    function toggleWallpaperCarousel() {
        aiChat.close()
        wallpaperCarousel.toggle()
    }

    // Wi-Fi Actions (async with verification; passwords never touch QML)
    function refreshWifiReads() {
        if (!nmcliProc.running) nmcliProc.running = true
        if (!wifiRadioProc.running) wifiRadioProc.running = true
        if (!wifiListProc.running && !wifiRescanProc.running && !wifiCmdProc.running) {
            root.wifiListGen = root.wifiScanGen
            wifiListProc.running = true
        }
    }

    // Returns true when a pending Wi-Fi operation is verified complete.
    function checkWifiPending() {
        if (root.wifiPending === "power") {
            const wantOn = (root.wifiPendingTarget === "on")
            if (root.wifiEnabled === wantOn) {
                root.wifiPending = ""
                root.wifiError = ""
                root.wifiNotice = wantOn ? "Wi-Fi enabled." : "Wi-Fi disabled."
                return true
            }
            return false
        }
        if (root.wifiPending === "connect") {
            if (root.netName === root.wifiPendingTarget) {
                root.wifiPending = ""
                root.wifiError = ""
                root.wifiNotice = "Connected to " + root.wifiPendingTarget + "."
                root.wifiPendingTarget = ""
                return true
            }
            return false
        }
        if (root.wifiPending === "disconnect") {
            if (root.netType === "disconnected") {
                root.wifiPending = ""
                root.wifiError = ""
                root.wifiNotice = "Disconnected."
                return true
            }
            return false
        }
        return true
    }

    function toggleWifiPower() {
        if (wifiCmdProc.running) {
            root.wifiError = "A Wi-Fi operation is already running."
            return
        }
        const target = root.wifiEnabled ? "off" : "on"
        root.wifiError = ""
        root.wifiNotice = (target === "on" ? "Enabling" : "Disabling") + " Wi-Fi…"
        root.wifiPending = "power"
        root.wifiPendingTarget = target
        root.wifiVerifyTries = 0
        wifiCmdProc.command = ["nmcli", "radio", "wifi", target]
        wifiCmdProc.running = true
    }

    function rescanWifi() {
        if (root.wifiScanning || wifiRescanProc.running || wifiListProc.running) return
        root.wifiError = ""
        root.wifiNotice = ""
        root.wifiScanning = true
        root.wifiScanGen += 1
        wifiRescanProc.running = true
    }

    function connectWifi(ssid, secured) {
        if (!ssid || wifiCmdProc.running) {
            if (wifiCmdProc.running) root.wifiError = "A Wi-Fi operation is already running."
            return
        }
        root.wifiError = ""
        root.wifiNotice = "Connecting to " + ssid + "…"
        root.wifiPending = "connect"
        root.wifiPendingTarget = ssid
        root.wifiVerifyTries = 0
        // Secured networks need a secret: delegate the password prompt to the
        // helper script (rofi -password). The password never enters QML state.
        if (secured) {
            Quickshell.execDetached([root.repoRoot + "/scripts/wifi-connect.sh", ssid])
            root.wifiNotice = "Connecting to " + ssid + "… (password prompt if required)"
            wifiVerifyTimer.restart()
            return
        }
        wifiCmdProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        wifiCmdProc.running = true
    }

    // Called when a direct connect fails, most likely for a missing secret.
    function connectWifiWithPrompt(ssid) {
        Quickshell.execDetached([root.repoRoot + "/scripts/wifi-connect.sh", ssid])
        root.wifiNotice = "Password required — answer the prompt for " + ssid + "…"
        root.wifiVerifyTries = 0
        wifiVerifyTimer.restart()
    }

    function disconnectWifi() {
        if (wifiCmdProc.running) {
            root.wifiError = "A Wi-Fi operation is already running."
            return
        }
        root.wifiError = ""
        root.wifiNotice = "Disconnecting…"
        root.wifiPending = "disconnect"
        root.wifiVerifyTries = 0
        wifiCmdProc.command = ["nmcli", "device", "disconnect", root.netDevice]
        wifiCmdProc.running = true
    }

    function parseWifiList(raw) {
        const lines = raw.trim().split("\n")
        const seen = {}
        const result = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (!line) continue
            const parts = line.split(":")
            if (parts.length < 4) continue
            // Fields: IN-USE : SSID (may itself contain ':') : SIGNAL : SECURITY
            const inUse = (parts[0].trim() === "*")
            const sig = parseInt(parts[parts.length - 2], 10) || 0
            const security = parts[parts.length - 1].trim()
            const ssid = parts.slice(1, parts.length - 2).join(":").trim()
            if (!ssid || seen[ssid]) continue
            seen[ssid] = true
            result.push({
                active: inUse,
                ssid: ssid,
                signal: sig,
                security: security,
                secured: (security !== "" && security !== "--")
            })
            if (result.length >= 12) break
        }
        root.wifiNetworks = result
        if (result.length === 0 && !root.wifiScanning)
            root.wifiNotice = ""
    }

    // Bluetooth Actions (async with verification)
    function refreshBtReads() {
        if (!btStatusProc.running && !btScanProc.running && !btCmdProc.running) {
            root.btStatusGen = root.btScanGen
            btStatusProc.running = true
        }
    }

    function btDeviceByMac(mac) {
        for (let i = 0; i < root.btDevices.length; i++) {
            if (root.btDevices[i].mac === mac) return root.btDevices[i]
        }
        return null
    }

    // Returns true when a pending Bluetooth operation is verified complete.
    function checkBtPending() {
        if (root.btPending === "power") {
            const wantOn = (root.btPendingTarget === "on")
            if (root.btPowered === wantOn) {
                root.btPending = ""
                root.btError = ""
                root.btNotice = wantOn ? "Bluetooth on." : "Bluetooth off."
                return true
            }
            return false
        }
        if (root.btPending === "connect-dev" || root.btPending === "disconnect-dev" || root.btPending === "pair") {
            const dev = root.btDeviceByMac(root.btPendingTarget)
            if (root.btPending === "pair" && dev && dev.paired) {
                root.btPending = ""
                root.btBusyMac = ""
                root.btError = ""
                root.btNotice = "Paired with " + dev.name + "."
                return true
            }
            if (root.btPending === "connect-dev" && dev && dev.connected) {
                root.btPending = ""
                root.btBusyMac = ""
                root.btError = ""
                root.btNotice = "Connected to " + dev.name + "."
                return true
            }
            if (root.btPending === "disconnect-dev" && (!dev || !dev.connected)) {
                root.btPending = ""
                root.btBusyMac = ""
                root.btError = ""
                root.btNotice = "Disconnected."
                return true
            }
            return false
        }
        return true
    }

    function toggleBtPower() {
        if (btCmdProc.running) {
            root.btError = "A Bluetooth operation is already running."
            return
        }
        const target = root.btPowered ? "off" : "on"
        root.btError = ""
        root.btNotice = (target === "on" ? "Turning" : "Switching") + " Bluetooth " + target + "…"
        root.btPending = "power"
        root.btPendingTarget = target
        root.btVerifyTries = 0
        btCmdProc.command = ["bluetoothctl", "power", target]
        btCmdProc.running = true
    }

    function scanBluetooth() {
        if (root.btScanning || btScanProc.running || btStatusProc.running || btCmdProc.running) return
        root.btError = ""
        root.btNotice = ""
        root.btScanning = true
        root.btScanGen += 1
        btScanProc.running = true
    }

    function toggleBtDevice(mac, isConnected) {
        if (!mac || btCmdProc.running) {
            if (btCmdProc.running) root.btError = "A Bluetooth operation is already running."
            return
        }
        const action = isConnected ? "disconnect" : "connect"
        root.btError = ""
        root.btNotice = (isConnected ? "Disconnecting " : "Connecting ") + mac + "…"
        root.btPending = isConnected ? "disconnect-dev" : "connect-dev"
        root.btPendingTarget = mac
        root.btBusyMac = mac
        root.btVerifyTries = 0
        btCmdProc.command = ["bluetoothctl", action, mac]
        btCmdProc.running = true
    }

    function pairBtDevice(mac) {
        if (!mac || btCmdProc.running) {
            if (btCmdProc.running) root.btError = "A Bluetooth operation is already running."
            return
        }
        root.btError = ""
        root.btNotice = "Pairing with " + mac + "… confirm on the device if asked."
        root.btPending = "pair"
        root.btPendingTarget = mac
        root.btBusyMac = mac
        root.btVerifyTries = 0
        btCmdProc.command = ["bluetoothctl", "pair", mac]
        btCmdProc.running = true
    }

    function parseBtOutput(raw) {
        const lines = raw.trim().split("\n")
        if (lines.length === 0) return
        root.btPowered = (lines[0].trim() === "ON")
        const devs = []
        let firstConnected = ""
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i]
            if (!line) continue
            const parts = line.split("|")
            let conn = false
            let paired = false
            let mac = ""
            let name = ""
            if (parts.length >= 4) {
                // conn|paired|mac|name
                conn = (parts[0] === "1")
                paired = (parts[1] === "1")
                mac = parts[2].trim()
                name = parts.slice(3).join("|").trim()
            } else if (parts.length === 3) {
                // legacy conn|mac|name
                conn = (parts[0] === "1")
                mac = parts[1].trim()
                name = parts.slice(2).join("|").trim()
            } else {
                continue
            }
            if (!mac) continue
            if (conn && firstConnected === "") firstConnected = name
            devs.push({
                connected: conn,
                paired: paired,
                mac: mac,
                name: name === "" ? mac : name
            })
            if (devs.length >= 20) break
        }
        root.btConnectedName = firstConnected
        root.btDevices = devs
        root.checkBtPending()
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
        let foundDev = root.netDevice || "wlan0"
        let firstWifiDev = ""

        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split(":")
            if (parts.length < 4) continue
            const dev = parts[0]
            const type = parts[1]
            const state = parts[2]
            const conn = parts.slice(3).join(":")

            if (type === "wifi" && !firstWifiDev) {
                firstWifiDev = dev
            }

            if ((type === "wifi" || type === "ethernet") && state === "connected") {
                foundDev = dev
                foundType = type
                foundName = conn !== "" ? conn : dev
                break
            }
        }
        if (foundType === "disconnected" && firstWifiDev) {
            foundDev = firstWifiDev
        }
        root.netDevice = foundDev
        root.netType = foundType
        root.netName = foundName
        root.checkWifiPending()
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
        const target = Math.max(1, Math.min(100, Math.round(targetPct)))
        Brightness.setPercent(target)
        root.showOsd("󰖨", target)
    }

    function stepBrightness(deltaPct) {
        const target = Math.max(1, Math.min(100, Math.round(Brightness.percent + deltaPct)))
        Brightness.step(deltaPct)
        root.showOsd("󰖨", target)
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

    function triggerScreenshot() {
        screenshotTimer.start()
    }

    // Active shell surfaces. Tide Island remains the notification D-Bus owner.
    // Right-edge activation strip: thin vertical overlay sensor that opens
    // DashboardHost on hover.
    PanelWindow {
        id: dashboardEdgeSensor
        screen: root.popupScreen

        // Activation strip configuration
        property int stripWidth: root.edgeSensorWidth
        property int stripMarginTop: root.edgeSensorMarginTop
        property int stripMarginBottom: root.edgeSensorMarginBottom

        anchors {
            top: true
            bottom: true
            right: true
        }
        margins {
            top: stripMarginTop
            bottom: stripMarginBottom
            right: 0
        }
        implicitWidth: stripWidth
        color: "transparent"
        // While the hotspot is disabled the surface is unmapped, so it cannot
        // capture pointer input at all (a real off, not visual-only).
        visible: root.edgeHotspotEnabled
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gps-dashboard-hotzone"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        onVisibleChanged: {
            if (!visible) dashboardHost.triggerHovered = false
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onEntered: {
                dashboardHost.triggerHovered = true
                if (!root.edgeHotspotEnabled) return
                if (!dashboardHost.isOpen
                        && Date.now() - root.dashLastHide > root.dashboardReopenCooldownMs)
                    root.openDashboard()
            }
            onExited: dashboardHost.triggerHovered = false
            onClicked: {
                if (!dashboardHost.isOpen) {
                    root.openDashboard(true)
                } else {
                    root.closeDashboard()
                }
            }
        }
    }

    LeftRail {
    hub: root
    notifications: notifCenter
    wallpaperCarousel: wallpaperCarousel
    }
    NotifCenter        { id: notifCenter; hub: root }
    NotifToast         { hub: root }
    // Canonical dashboard drawer. It owns its closePopup() call on open and
    // its own dashLastHide stamping on close - shell.qml must not duplicate
    // either for this instance.
    DashboardHost {
        id: dashboardHost
        hub: root
    }
    WallpaperCarousel  { id: wallpaperCarousel; hub: root }
    AIChat             { id: aiChat; hub: root }
    MediaHubWindow     { id: mediaHubWindow; hub: root }
    ToolboxWindow      { id: toolboxWindow; hub: root }
    WifiPopup          { hub: root }
    BluetoothPopup     { hub: root }
    BatteryPopup       { id: batteryPopup; hub: root }
    ClipboardPicker    { id: clipboardPicker; hub: root }
    Pet                { id: pet }
    onToastVisibleChanged: if (root.toastVisible) pet.wave()
}
