import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config
import "../ControlLogic.js" as ControlLogic

Item {
    id: st

    required property var core
    readonly property string key: "control"
    readonly property bool active: core.mode === key
    readonly property bool expanded: core.hovered || Boolean(core.controlExpanded) || localExpanded
    readonly property real w: expanded ? 460 : 180
    readonly property real h: expanded ? Math.min(560, Math.max(380, controlContent.implicitHeight + footerRow.implicitHeight + 8 + 40)) : 36
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)
    readonly property string repoRoot: Quickshell.env("GPS_ROOT") || (core && core.repoRoot ? core.repoRoot : "")

    // ───────────── live state (populated only while active) ─────────────
    property bool localExpanded: false
    property bool dndExpanded: false
    property bool audioOutputsExpanded: false
    property var audioSinks: []
    property int defaultSinkId: 0

    property bool editTilesMode: false
    property var controlTiles: ControlLogic.DEFAULT_TILES.map(t => Object.assign({}, t))
    readonly property var visibleTiles: {
        const list = Array.isArray(st.controlTiles) ? st.controlTiles : ControlLogic.DEFAULT_TILES
        return list.filter(t => t && t.enabled !== false)
    }
    readonly property string controlTilesPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/gps/control_tiles.json"

    function moveTileUp(index) {
        if (index <= 0) return
        const next = ControlLogic.moveTile(controlTiles, index, index - 1)
        saveControlTiles(next)
    }

    function moveTileDown(index) {
        if (!controlTiles || index >= controlTiles.length - 1) return
        const next = ControlLogic.moveTile(controlTiles, index, index + 1)
        saveControlTiles(next)
    }

    function toggleTile(id) {
        const next = ControlLogic.toggleTileEnabled(controlTiles, id)
        saveControlTiles(next)
    }

    function resetControlTiles() {
        saveControlTiles(ControlLogic.DEFAULT_TILES)
    }

    function saveControlTiles(newTiles) {
        st.controlTiles = ControlLogic.validateControlTiles(newTiles)
        const raw = ControlLogic.serializeControlTiles(st.controlTiles)
        const path = st.controlTilesPath
        const script = 'd="$(dirname "$1")" && mkdir -m 0700 -p "$d" && tmp="${d}/.$(basename "$1").tmp.$$" && printf "%s\\n" "$2" > "$tmp" && chmod 0600 "$tmp" && mv -f "$tmp" "$1"'
        Quickshell.execDetached(["sh", "-c", script, "sh", path, raw])
    }

    FileView {
        id: tilesFile
        path: st.controlTilesPath
        watchChanges: true
        onLoaded: {
            st.controlTiles = ControlLogic.deserializeControlTiles(tilesFile.text())
        }
        onFileChanged: tilesFile.reload()
    }

    property bool hasNmcli: false
    property bool wifiEnabled: false
    property string wifiSsid: ""

    property bool hasBt: false
    property bool btEnabled: false
    property string btDevice: ""

    property bool hasSunset: false
    property bool nightLightOn: false
    property int nightKelvin: 0
    property int targetKelvin: 4000
    readonly property var kelvinSteps: [3200, 4000, 4500, 5000]

    property bool hasIdleTool: false
    property bool idleDaemonOn: false
    property int idleTimeoutSec: 0

    property bool keepAwakeOn: false
    property bool gameModeOn: false
    property bool isRecording: false
    property string recordFile: ""
    readonly property string recordStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/gps/record-state.json"

    FileView {
        id: recordStateFile
        path: st.recordStatePath
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(recordStateFile.text())
                st.isRecording = Boolean(data && data.recording === true)
                st.recordFile = (data && data.file) ? String(data.file) : ""
            } catch (e) {
                st.isRecording = false
            }
        }
        onFileChanged: recordStateFile.reload()
    }

    property bool hasPpd: false
    property string powerProfile: ""
    property var profileList: ControlLogic.DEFAULT_PROFILES

    property int fallbackBrightPct: -1
    property real dragBright: -1
    readonly property bool brightAvailable: core.hasBrightness || fallbackBrightPct >= 0
    readonly property real liveBright: dragBright >= 0
        ? dragBright
        : (core.hasBrightness ? core.brightness : (fallbackBrightPct >= 0 ? fallbackBrightPct / 100 : 0))

    property real dragVol: -1
    readonly property real liveVol: dragVol >= 0 ? dragVol : (core.muted ? 0 : Math.max(0, Math.min(1.5, core.volume)))

    property real dragMicVol: -1
    readonly property real liveMicVol: dragMicVol >= 0 ? dragMicVol : ((core.sourceAudio && core.micMuted) ? 0 : Math.max(0, Math.min(1.5, core.micVolume)))

    // ───────────── MPRIS media state ─────────────
    readonly property var player: MediaNowPlaying.player
    readonly property bool hasActiveMedia: player !== null && player.trackTitle !== "" && (player.isPlaying || player.playbackState === MprisPlaybackState.Paused)
    readonly property bool hasProgress: hasActiveMedia && Boolean(player.positionSupported) && Boolean(player.lengthSupported) && player.length > 0
    readonly property real progressFraction: hasProgress ? Math.max(0, Math.min(1, displayPos / (player.length * 1000))) : 0

    property real posBase: 0
    property real posStamp: 0
    property real tickNow: 0
    function syncPos() {
        if (player) {
            posBase = player.position * 1000
            posStamp = Date.now()
            tickNow = Date.now()
        }
    }
    onPlayerChanged: syncPos()
    readonly property real displayPos: {
        if (!hasActiveMedia || !player.positionSupported) return 0
        if (!player.isPlaying) return Math.max(0, player.position * 1000)
        let pos = posBase + Math.max(0, tickNow - posStamp)
        if (player.length > 0) pos = Math.min(pos, player.length * 1000)
        return Math.max(pos, player.position * 1000)
    }

    // ───────────── Telemetry state (polled only while panel is open) ─────────────
    property int cpuUsage: -1
    property real memUsedGiB: 0
    property real memTotalGiB: 0
    property int memPct: -1
    property int tempC: -1
    property var prevCpuData: null

    property int uptimeSec: 0
    property string kernelVer: ""
    property bool hasWlogout: false
    property bool hasSystemctl: false
    property bool hasLocker: false
    property bool confirmPower: false

    readonly property bool flightMode: (hasNmcli || hasBt) && (!hasNmcli || !wifiEnabled) && (!hasBt || !btEnabled)

    readonly property string uptimeText: {
        if (uptimeSec <= 0) return ""
        const h = Math.floor(uptimeSec / 3600)
        const m = Math.floor((uptimeSec % 3600) / 60)
        return h > 0 ? ("up " + h + "h " + m + "m") : ("up " + m + "m")
    }
    readonly property string sessionSummary: {
        const parts = []
        if (uptimeText !== "") parts.push(uptimeText)
        if (kernelVer !== "") parts.push("Linux " + kernelVer)
        return parts.join(" · ")
    }

    readonly property string batteryTimeText: {
        if (!core.hasBat) return ""
        const s = core.charging ? core.ttf : (core.bat ? (core.bat.timeToEmpty || 0) : 0)
        return ControlLogic.formatBatteryTime(s, core.charging)
    }

    readonly property string compactPowerProfile: {
        if (!powerProfile) return ""
        const p = powerProfile.toLowerCase()
        if (p === "power-saver") return "SAVER"
        if (p === "performance") return "PERF"
        return p.toUpperCase()
    }

    readonly property string headerBadgeText: {
        const parts = []
        if (core.hasBat) parts.push(Math.round(core.batPct) + "%")
        if (batteryTimeText !== "") parts.push(batteryTimeText)
        if (compactPowerProfile !== "") parts.push(compactPowerProfile)
        return parts.join(" · ")
    }

    readonly property string idleSubtitle: {
        if (!hasIdleTool) return "Off"
        if (keepAwakeOn) return "paused by Keep awake"
        if (!idleDaemonOn) return "Off"
        if (idleTimeoutSec > 0) {
            const mins = Math.round(idleTimeoutSec / 60)
            return mins > 0 ? (mins + " min") : (idleTimeoutSec + " sec")
        }
        return "Active"
    }

    readonly property string dndSubtitle: {
        return ControlLogic.formatDndSubText(core.dndState, core.dnd, Date.now())
    }

    // ───────────── lifecycle & dismissal ─────────────
    onActiveChanged: {
        if (active) {
            confirmPower = false
            dndExpanded = false
            audioOutputsExpanded = false
            editTilesMode = false
            triggerProbe()
            refreshSinks()
        } else {
            localExpanded = false
            confirmPower = false
            dndExpanded = false
            audioOutputsExpanded = false
            editTilesMode = false
            dragBright = -1
            dragVol = -1
            dragMicVol = -1
            if (sysProbe.running) sysProbe.running = false
            if (sinksProc.running) sinksProc.running = false
            if (telemetryProc.running) telemetryProc.running = false
        }
    }

    focus: active && expanded
    Keys.onEscapePressed: {
        if (editTilesMode) {
            editTilesMode = false
            return
        }
        if (dndExpanded) {
            dndExpanded = false
            return
        }
        if (audioOutputsExpanded) {
            audioOutputsExpanded = false
            return
        }
        localExpanded = false
        confirmPower = false
        if (typeof core.setControl === "function") core.setControl("close")
    }

    // ───────────── active-only polling & commands ─────────────
    function triggerProbe() {
        if (active && !sysProbe.running) sysProbe.running = true
    }
    function scheduleProbe(ms) {
        if (!active) return
        probeDelay.interval = ms || 350
        probeDelay.restart()
    }
    function runCmd(script, args, delayMs) {
        if (!active) return
        Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args || []))
        scheduleProbe(delayMs || 350)
    }

    Process {
        id: sysProbe
        running: false
        command: [
            "timeout", "3s", "sh", "-c",
            "export LC_ALL=C.UTF-8; " +
            "command -v nmcli >/dev/null 2>&1 && echo 'has_nmcli=1' || echo 'has_nmcli=0'; " +
            "echo \"wifi_radio=$(nmcli radio wifi 2>/dev/null)\"; " +
            "echo \"wifi_ssid=$(nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$1==\"wifi\" && $2==\"connected\"{sub(/^[^:]*:[^:]*:/,\"\"); print; exit}')\"; " +
            "if [ -d /sys/class/bluetooth ] && [ -n \"$(ls -A /sys/class/bluetooth 2>/dev/null)\" ]; then echo 'has_bt=1'; else echo 'has_bt=0'; fi; " +
            "echo \"bt_power=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}')\"; " +
            "bt_dev=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-); " +
            "if [ -z \"$bt_dev\" ]; then " +
            "  bt_dev=$(bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "    [ -n \"$mac\" ] || continue; " +
            "    bluetoothctl info \"$mac\" 2>/dev/null | grep -q 'Connected: yes' && { printf '%s\\n' \"$name\"; break; }; " +
            "  done); " +
            "fi; " +
            "echo \"bt_dev=$bt_dev\"; " +
            "command -v hyprsunset >/dev/null 2>&1 && echo 'has_sunset=1' || echo 'has_sunset=0'; " +
            "pgrep -x hyprsunset >/dev/null 2>&1 && echo 'sunset_run=1' || echo 'sunset_run=0'; " +
            "echo \"sunset_k=$(ps -C hyprsunset -o args= 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"-t\" && $(i+1)~ /^[0-9]+$/){print $(i+1); exit}}')\"; " +
            "if command -v gps-idle >/dev/null 2>&1; then gps-idle env-status; elif [ -n \"$GPS_ROOT\" ] && [ -x \"$GPS_ROOT/scripts/gps-idle\" ]; then \"$GPS_ROOT/scripts/gps-idle\" env-status; else echo 'has_idle=0'; echo 'idle_run=0'; echo 'idle_t=300'; fi; " +
            "pgrep -f \"systemd-inhibit.*sleep infinity\" >/dev/null 2>&1 && echo 'keepawake_run=1' || echo 'keepawake_run=0'; " +
            "if command -v gps-gamemode >/dev/null 2>&1; then gps-gamemode status 2>/dev/null; elif [ -n \"$GPS_ROOT\" ] && [ -x \"$GPS_ROOT/scripts/gps-gamemode\" ]; then \"$GPS_ROOT/scripts/gps-gamemode\" status 2>/dev/null; else echo 'active=0'; fi; " +
            "prof=''; ppd_ok=0; if command -v powerprofilesctl >/dev/null 2>&1; then prof=$(powerprofilesctl get 2>/dev/null); [ -n \"$prof\" ] && ppd_ok=1; fi; echo \"has_ppd=$ppd_ok\"; " +
            "[ -z \"$prof\" ] && prof=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null); " +
            "[ -z \"$prof\" ] && prof=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null); " +
            "echo \"profile=$prof\"; " +
            "profiles_raw=$(powerprofilesctl list 2>/dev/null | tr '\\n' '|'); [ -z \"$profiles_raw\" ] && profiles_raw=$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null); echo \"profiles_raw=$profiles_raw\"; " +
            "echo \"bright=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')\"; " +
            "echo \"uptime=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)\"; " +
            "echo \"kernel=$(uname -r 2>/dev/null)\"; " +
            "command -v wlogout >/dev/null 2>&1 && echo 'has_wlogout=1' || echo 'has_wlogout=0'; " +
            "command -v systemctl >/dev/null 2>&1 && echo 'has_systemctl=1' || echo 'has_systemctl=0'; " +
            "if [ -f \"${XDG_RUNTIME_DIR:-/tmp}/gps/record-state.json\" ]; then grep -q '\"recording\": *true' \"${XDG_RUNTIME_DIR:-/tmp}/gps/record-state.json\" && echo 'is_recording=1' || echo 'is_recording=0'; else echo 'is_recording=0'; fi; " +
            "if command -v gps-lock >/dev/null 2>&1 || { [ -n \"$GPS_ROOT\" ] && [ -x \"$GPS_ROOT/scripts/gps-lock\" ]; } || command -v hyprlock >/dev/null 2>&1 || command -v loginctl >/dev/null 2>&1; then echo 'has_locker=1'; else echo 'has_locker=0'; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!st.active) return
                const map = {}
                for (const line of text.split("\n")) {
                    const idx = line.indexOf("=")
                    if (idx > 0) map[line.slice(0, idx).trim()] = line.slice(idx + 1).trim()
                }
                st.hasNmcli = map.has_nmcli === "1"
                st.wifiEnabled = map.wifi_radio === "enabled"
                st.wifiSsid = map.wifi_ssid || ""

                st.hasBt = map.has_bt === "1"
                st.btEnabled = map.bt_power === "yes"
                st.btDevice = map.bt_dev || ""

                st.hasSunset = map.has_sunset === "1"
                st.nightLightOn = map.sunset_run === "1"
                const k = parseInt(map.sunset_k || "", 10)
                st.nightKelvin = !isNaN(k) && k > 0 ? k : (st.nightLightOn ? st.targetKelvin : 0)
                if (!isNaN(k) && k > 0) st.targetKelvin = k

                st.hasIdleTool = map.has_idle === "1"
                st.idleDaemonOn = map.idle_run === "1"
                const idleSec = parseInt(map.idle_t || "", 10)
                st.idleTimeoutSec = !isNaN(idleSec) && idleSec > 0 ? idleSec : 0

                st.keepAwakeOn = map.keepawake_run === "1"
                st.gameModeOn = (map.active === "1" || map.gamemode_run === "1")
                if (map.is_recording === "1") st.isRecording = true
                else if (map.is_recording === "0" && !recordStateFile.exists) st.isRecording = false

                st.hasPpd = map.has_ppd === "1"
                st.powerProfile = map.profile || ""
                if (map.profiles_raw) {
                    st.profileList = ControlLogic.parseProfiles(map.profiles_raw.replace(/\|/g, "\n"))
                }

                const bp = parseInt(map.bright || "", 10)
                st.fallbackBrightPct = !isNaN(bp) && bp >= 0 ? bp : -1

                const up = parseInt(map.uptime || "", 10)
                st.uptimeSec = !isNaN(up) && up > 0 ? up : 0
                st.kernelVer = map.kernel || ""
                st.hasWlogout = map.has_wlogout === "1"
                st.hasSystemctl = map.has_systemctl === "1"
                st.hasLocker = map.has_locker === "1"
            }
        }
    }

    Process {
        id: sinksProc
        command: ["python3", (st.repoRoot ? (st.repoRoot + "/scripts/audio-sinks.py") : "audio-sinks.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    if (data && Array.isArray(data.sinks)) {
                        st.audioSinks = data.sinks
                        st.defaultSinkId = typeof data.default_id === "number" ? data.default_id : 0
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: sinkSwitchProc
        onExited: (code, status) => {
            st.refreshSinks()
        }
    }

    function refreshSinks() {
        if (!sinksProc.running) sinksProc.running = true
    }

    function selectSink(id) {
        if (!id || sinkSwitchProc.running) return
        const rootPath = st.repoRoot
        sinkSwitchProc.command = ["python3", (rootPath ? (rootPath + "/scripts/audio-sinks.py") : "audio-sinks.py"), "--switch", String(id)]
        sinkSwitchProc.running = true
    }

    function applyMicVolume(ratio) {
        if (!core.sourceAudio) return
        const clamped = Math.max(0, Math.min(1.5, ratio))
        if (core.sourceAudio.muted && clamped > 0) core.sourceAudio.muted = false
        core.sourceAudio.volume = clamped
    }

    Connections {
        target: st.player
        function onPositionChanged() { st.syncPos() }
        function onTrackTitleChanged() { st.syncPos() }
    }

    Timer {
        interval: 250
        repeat: true
        running: st.active && st.expanded && st.hasActiveMedia && Boolean(st.player && st.player.isPlaying)
        onTriggered: st.tickNow = Date.now()
    }

    Process {
        id: telemetryProc
        running: false
        command: [
            "sh", "-c",
            "read -r _ u n s i w irq sirq st _ < /proc/stat 2>/dev/null; echo \"CPU $u $n $s $i $w $irq $sirq $st\"; " +
            "awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} END{print \"MEM\", t, a}' /proc/meminfo 2>/dev/null; " +
            "temp=-1; " +
            "for z in /sys/class/thermal/thermal_zone*; do " +
            "  t=$(cat \"$z/type\" 2>/dev/null); " +
            "  case \"$t\" in x86_pkg_temp|k10temp|coretemp|cpu*) " +
            "    temp=$(cat \"$z/temp\" 2>/dev/null); [ -n \"$temp\" ] && break ;; " +
            "  esac; " +
            "done; " +
            "if [ -z \"$temp\" ] || [ \"$temp\" -le 0 ] 2>/dev/null; then " +
            "  for h in /sys/class/hwmon/hwmon*; do " +
            "    n=$(cat \"$h/name\" 2>/dev/null); " +
            "    case \"$n\" in coretemp|k10temp) " +
            "      temp=$(cat \"$h/temp1_input\" 2>/dev/null); [ -n \"$temp\" ] && break ;; " +
            "    esac; " +
            "  done; " +
            "fi; " +
            "echo \"TEMP $temp\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!st.active || !st.expanded) return
                for (const line of text.split("\n")) {
                    if (line.startsWith("CPU ")) {
                        const nums = line.slice(4).trim().split(/\s+/).map(Number)
                        const res = ControlLogic.parseCpuUsage(nums, st.prevCpuData)
                        st.prevCpuData = res.prev
                        if (res.usage >= 0) st.cpuUsage = res.usage
                    } else if (line.startsWith("MEM ")) {
                        const parts = line.slice(4).trim().split(/\s+/).map(Number)
                        if (parts.length >= 2) {
                            const res = ControlLogic.parseMemUsage(parts[0], parts[1])
                            st.memTotalGiB = res.totalGiB
                            st.memUsedGiB = res.usedGiB
                            st.memPct = res.pct
                        }
                    } else if (line.startsWith("TEMP ")) {
                        st.tempC = ControlLogic.parseTempC(line.slice(5).trim())
                    }
                }
            }
        }
    }

    Timer {
        id: telemetryTimer
        interval: 1500
        repeat: true
        running: st.active && st.expanded
        triggeredOnStart: true
        onTriggered: {
            if (!telemetryProc.running) telemetryProc.running = true
        }
    }

    Timer {
        id: pollTimer
        interval: 2500
        repeat: true
        running: st.active
        triggeredOnStart: true
        onTriggered: st.triggerProbe()
    }

    Timer {
        id: probeDelay
        interval: 350
        repeat: false
        running: false
        onTriggered: if (st.active) st.triggerProbe()
    }

    Timer {
        id: powerConfirmTimer
        interval: 3000
        repeat: false
        running: false
        onTriggered: st.confirmPower = false
    }

    // ───────────── actions ─────────────
    function toggleWifi() {
        if (!hasNmcli) return
        const next = !wifiEnabled
        wifiEnabled = next
        if (!next) wifiSsid = ""
        runCmd('nmcli radio wifi "$1"', [next ? "on" : "off"], 450)
    }

    function toggleBluetooth() {
        if (!hasBt) return
        const next = !btEnabled
        btEnabled = next
        if (!next) btDevice = ""
        runCmd('bluetoothctl power "$1" >/dev/null 2>&1', [next ? "on" : "off"], 500)
    }

    function toggleDnd() {
        dndExpanded = false
        core.setDnd(!core.dnd)
    }

    function toggleNightLight() {
        if (!hasSunset) return
        const next = !nightLightOn
        nightLightOn = next
        if (next) {
            nightKelvin = targetKelvin
            runCmd('pkill -x hyprsunset >/dev/null 2>&1; setsid hyprsunset -t "$1" >/dev/null 2>&1 &', [String(targetKelvin)], 400)
        } else {
            nightKelvin = 0
            runCmd('pkill -x hyprsunset >/dev/null 2>&1', [], 350)
        }
    }

    function cycleNightKelvin() {
        if (!hasSunset) return
        const idx = kelvinSteps.indexOf(targetKelvin)
        const nextK = kelvinSteps[(idx + 1) % kelvinSteps.length]
        targetKelvin = nextK
        nightLightOn = true
        nightKelvin = nextK
        runCmd('pkill -x hyprsunset >/dev/null 2>&1; setsid hyprsunset -t "$1" >/dev/null 2>&1 &', [String(nextK)], 400)
    }

    function toggleIdleLock() {
        if (!hasIdleTool) return
        const next = !idleDaemonOn
        idleDaemonOn = next
        if (next)
            runCmd('command -v gps-idle >/dev/null 2>&1 && gps-idle start || { [ -n "$GPS_ROOT" ] && "$GPS_ROOT/scripts/gps-idle" start; }', [], 400)
        else
            runCmd('command -v gps-idle >/dev/null 2>&1 && gps-idle stop || { [ -n "$GPS_ROOT" ] && "$GPS_ROOT/scripts/gps-idle" stop; }', [], 350)
    }

    function toggleKeepAwake() {
        const next = !keepAwakeOn
        keepAwakeOn = next
        if (next) {
            runCmd('setsid systemd-inhibit --what=idle:sleep --who="GPS" --why="Keep awake" sleep infinity </dev/null >/dev/null 2>&1 &', [], 350)
        } else {
            runCmd('pkill -f "systemd-inhibit.*sleep infinity" >/dev/null 2>&1', [], 300)
        }
    }

    function toggleFlightMode() {
        if (!hasNmcli && !hasBt) return
        const enableFlight = !flightMode
        if (enableFlight) {
            wifiEnabled = false
            wifiSsid = ""
            btEnabled = false
            btDevice = ""
            runCmd('nmcli radio all off >/dev/null 2>&1; bluetoothctl power off >/dev/null 2>&1', [], 500)
        } else {
            if (hasNmcli) wifiEnabled = true
            if (hasBt) btEnabled = true
            runCmd('(command -v nmcli >/dev/null 2>&1 && nmcli radio all on >/dev/null 2>&1); (command -v bluetoothctl >/dev/null 2>&1 && bluetoothctl power on >/dev/null 2>&1)', [], 600)
        }
    }

    function toggleGameMode() {
        const next = !gameModeOn
        gameModeOn = next
        runCmd('command -v gps-gamemode >/dev/null 2>&1 && gps-gamemode toggle || { [ -n "$GPS_ROOT" ] && "$GPS_ROOT/scripts/gps-gamemode" toggle; }', [], 400)
    }

    function cyclePowerProfile() {
        const next = ControlLogic.cycleProfile(powerProfile, profileList)
        powerProfile = next
        runCmd('powerprofilesctl set "$1" >/dev/null 2>&1 || (echo "$1" > /sys/firmware/acpi/platform_profile 2>/dev/null)', [next], 400)
    }

    function toggleMicMute() {
        if (!core.sourceAudio) return
        core.sourceAudio.muted = !core.sourceAudio.muted
    }

    function openSettings(section) {
        const settingsPath = st.repoRoot ? (st.repoRoot + "/settings.qml") : "settings.qml"
        if (section && section !== "") {
            runCmd('quickshell ipc -p "$1" call settings open "$2" >/dev/null 2>&1 || setsid quickshell -p "$1" >/dev/null 2>&1 &', [settingsPath, section], 200)
        } else {
            runCmd('quickshell ipc -p "$1" call settings toggle >/dev/null 2>&1 || setsid quickshell -p "$1" >/dev/null 2>&1 &', [settingsPath], 200)
        }
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
    }

    function openMediaHub() {
        if (core && typeof core.openMediaHub === "function") {
            core.openMediaHub()
        } else {
            const rootPath = st.repoRoot
            Quickshell.execDetached([(rootPath ? (rootPath + "/scripts/gps-ipc") : "gps-ipc"), "mediahub", "toggle"])
        }
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
    }

    function openToolbox() {
        if (core && typeof core.openToolbox === "function") {
            core.openToolbox()
        } else {
            const rootPath = st.repoRoot
            Quickshell.execDetached([(rootPath ? (rootPath + "/scripts/gps-ipc") : "gps-ipc"), "toolbox", "toggle"])
        }
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
    }

    function applyVolume(ratio) {
        if (!core.sinkAudio) return
        const clamped = Math.max(0, Math.min(1.5, ratio))
        if (core.sinkAudio.muted && clamped > 0) core.sinkAudio.muted = false
        core.sinkAudio.volume = clamped
    }

    function commitBrightness(ratio) {
        if (!brightAvailable) return
        const pct = Math.max(1, Math.min(100, Math.round(ratio * 100)))
        fallbackBrightPct = pct
        Brightness.setPercent(pct)
    }

    function lockScreen() {
        if (!hasLocker) return
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
        Quickshell.execDetached(["sh", "-c", "command -v gps-lock >/dev/null 2>&1 && exec gps-lock || { [ -n \"$GPS_ROOT\" ] && exec \"$GPS_ROOT/scripts/gps-lock\"; }"])
    }

    function suspendSystem() {
        if (!hasSystemctl) return
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
        Quickshell.execDetached(["systemctl", "suspend"])
    }

    function triggerPower() {
        if (hasWlogout) {
            localExpanded = false
            if (typeof core.setControl === "function") core.setControl("close")
            Quickshell.execDetached(["wlogout"])
            return
        }
        if (!hasSystemctl) return
        if (!confirmPower) {
            confirmPower = true
            powerConfirmTimer.restart()
            return
        }
        confirmPower = false
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
        Quickshell.execDetached(["systemctl", "poweroff"])
    }

    // ───────────── local components ─────────────
    component Ico: Text {
        property string name: ""
        property string alt: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 16
        color: st.core.text
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    component HeaderButton: Rectangle {
        id: hb
        property string iconName: ""
        property string iconAlt: ""
        property string tooltipText: ""
        property bool active: false
        signal triggered()

        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        radius: Theme.radiusCard
        activeFocusOnTab: true
        color: hb.active ? Theme.brandAccent : ((hbMa.containsMouse || hb.activeFocus) ? Theme.cardHover : Theme.card)
        border.width: Theme.borderWidth
        border.color: hb.activeFocus ? Theme.accentPrimary : Theme.outlineSoft
        scale: hbMa.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 90 } }

        ToolTip.visible: (hbMa.containsMouse || hb.activeFocus) && tooltipText !== ""
        ToolTip.text: tooltipText
        ToolTip.delay: 400

        Keys.onReturnPressed: hb.triggered()
        Keys.onSpacePressed: hb.triggered()

        Ico {
            anchors.centerIn: parent
            name: hb.iconName
            alt: hb.iconAlt
            font.pixelSize: 16
            color: hb.active ? Theme.brandAccentFg : ((hbMa.containsMouse || hb.activeFocus) ? Theme.textMain : Theme.textMuted)
        }

        MouseArea {
            id: hbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.triggered()
        }
    }

    component ToggleTile: Rectangle {
        id: tile
        property string iconName: ""
        property string iconAlt: ""
        property string titleText: ""
        property string subText: ""
        property string trailIcon: ""
        property string trailAlt: ""
        property bool tileOn: false
        property bool tileAvailable: true
        property bool tileInteractable: true
        property string tooltipText: ""
        signal toggled()
        signal trailClicked()

        readonly property color activeBg: Theme.brandAccent
        readonly property color activeFg: Theme.brandAccentFg
        readonly property color inactiveBg: (tileMa.containsMouse || tile.activeFocus) ? Theme.cardHover : Theme.card
        readonly property color inactiveFg: Theme.textMain

        Layout.fillWidth: true
        Layout.preferredHeight: 54
        implicitHeight: 54
        radius: Theme.radiusCard
        opacity: tileAvailable ? 1.0 : 0.45
        activeFocusOnTab: tileAvailable && tileInteractable

        color: tileOn ? (tileMa.containsMouse ? Qt.lighter(activeBg, 1.08) : activeBg) : inactiveBg
        border.width: tile.activeFocus ? 2 : (tileOn ? 0 : Theme.borderWidth)
        border.color: tile.activeFocus ? Theme.accentPrimary : Theme.outlineSoft
        scale: (tileMa.pressed || trailMa.pressed) ? 0.98 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

        ToolTip.visible: (tileMa.containsMouse || tile.activeFocus) && tooltipText !== ""
        ToolTip.text: tooltipText
        ToolTip.delay: 400

        Keys.onReturnPressed: if (tileInteractable) tile.toggled()
        Keys.onSpacePressed: if (tileInteractable) tile.toggled()

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: tile.tileOn ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                Ico {
                    anchors.centerIn: parent
                    name: tile.iconName
                    alt: tile.iconAlt
                    font.pixelSize: 18
                    color: tile.tileOn ? tile.activeFg : Theme.textMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: tile.titleText
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: tile.tileOn ? tile.activeFg : tile.inactiveFg
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: tile.subText !== ""
                    text: tile.subText
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: tile.tileOn ? Qt.rgba(tile.activeFg.r, tile.activeFg.g, tile.activeFg.b, 0.85) : Theme.textMuted
                    elide: Text.ElideRight
                }
            }

            Item {
                visible: tile.trailIcon !== ""
                Layout.preferredWidth: 24
                Layout.preferredHeight: 28

                Ico {
                    anchors.centerIn: parent
                    name: tile.trailIcon
                    alt: tile.trailAlt
                    font.pixelSize: 16
                    color: tile.tileOn ? tile.activeFg : Theme.textMuted
                }
            }
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            anchors.rightMargin: tile.trailIcon !== "" ? 32 : 0
            hoverEnabled: tile.tileInteractable
            cursorShape: tile.tileInteractable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tile.tileInteractable) tile.toggled()
        }

        MouseArea {
            id: trailMa
            visible: tile.trailIcon !== ""
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 32
            hoverEnabled: tile.tileInteractable
            cursorShape: tile.tileInteractable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tile.tileInteractable) tile.trailClicked()
        }
    }

    component SliderRow: RowLayout {
        id: srow
        property string iconName: ""
        property string iconAlt: ""
        property color tone: Theme.brandAccent
        property real value: 0
        property real maxValue: 1.0
        property string labelText: ""
        property string trailIcon: ""
        property string trailAlt: ""
        signal iconClicked()
        signal trailClicked()
        signal moved(real v)
        signal released(real v)

        Layout.fillWidth: true
        spacing: 10

        Item {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20

            Ico {
                anchors.centerIn: parent
                name: srow.iconName
                alt: srow.iconAlt
                font.pixelSize: 18
                color: srow.tone
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: srow.iconClicked()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 12

            Rectangle {
                id: track
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, srow.value))
                    height: parent.height
                    radius: height / 2
                    color: srow.tone
                    Behavior on width {
                        enabled: !sliderMa.pressed
                        NumberAnimation { duration: 100 }
                    }
                }
            }

            MouseArea {
                id: sliderMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function ratioAt(mx) {
                    return Math.max(0, Math.min(1, mx / Math.max(1, width))) * srow.maxValue
                }
                onPressed: m => srow.moved(ratioAt(m.x))
                onPositionChanged: m => { if (pressed) srow.moved(ratioAt(m.x)) }
                onReleased: m => srow.released(ratioAt(m.x))
                onWheel: w => {
                    const step = w.angleDelta.y > 0 ? 0.05 : -0.05
                    const next = Math.max(0, Math.min(srow.maxValue, srow.value + step))
                    srow.moved(next)
                    srow.released(next)
                }
            }
        }

        Text {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: srow.labelText
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: Font.Medium
            color: Theme.textMain
            elide: Text.ElideRight
        }

        Item {
            visible: srow.trailIcon !== ""
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20

            Ico {
                anchors.centerIn: parent
                name: srow.trailIcon
                alt: srow.trailAlt
                font.pixelSize: 18
                color: trailMa.containsMouse ? Theme.accentPrimary : Theme.textMuted
            }

            MouseArea {
                id: trailMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: srow.trailClicked()
            }
        }
    }

    component ActionCircle: Rectangle {
        id: ac
        property string iconName: ""
        property string iconAlt: ""
        property bool danger: false
        property bool armed: false
        property string tooltipText: ""
        signal triggered()

        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: 18
        activeFocusOnTab: true
        color: danger
            ? (armed ? Theme.statusDanger : (acMa.containsMouse ? Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.34) : Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.22)))
            : ((acMa.containsMouse || ac.activeFocus) ? Theme.cardHover : Theme.card)
        border.width: ac.activeFocus ? 2 : Theme.borderWidth
        border.color: ac.activeFocus ? Theme.accentPrimary : (danger ? Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.40) : Theme.outlineSoft)
        scale: acMa.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        ToolTip.visible: (acMa.containsMouse || ac.activeFocus) && tooltipText !== ""
        ToolTip.text: tooltipText
        ToolTip.delay: 400

        Keys.onReturnPressed: ac.triggered()
        Keys.onSpacePressed: ac.triggered()

        Ico {
            anchors.centerIn: parent
            name: ac.iconName
            alt: ac.iconAlt
            font.pixelSize: 16
            color: ac.danger ? (ac.armed ? "#000000" : Theme.statusDanger) : Theme.textMain
        }

        MouseArea {
            id: acMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ac.triggered()
        }
    }

    // ───────────── Tile Delegates for dynamic customization ─────────────
    Component {
        id: compWifi
        ToggleTile {
            iconName: st.wifiEnabled ? "wifi" : "wifi_off"
            iconAlt: "W"
            titleText: "Wi-Fi"
            subText: !st.hasNmcli ? "No nmcli" : (st.wifiEnabled ? (st.wifiSsid !== "" ? st.wifiSsid : "On") : "Off")
            trailIcon: "chevron_right"
            trailAlt: ">"
            tileOn: st.wifiEnabled
            tileAvailable: st.hasNmcli
            tooltipText: "Wi-Fi radio toggle · click arrow for network settings"
            onToggled: st.toggleWifi()
            onTrailClicked: st.openSettings("network")
        }
    }

    Component {
        id: compBt
        ToggleTile {
            iconName: st.btEnabled ? "bluetooth" : "bluetooth_disabled"
            iconAlt: "B"
            titleText: "Bluetooth"
            subText: !st.hasBt ? "No adapter" : (st.btEnabled ? (st.btDevice !== "" ? st.btDevice : "On") : "Off")
            trailIcon: "chevron_right"
            trailAlt: ">"
            tileOn: st.btEnabled
            tileAvailable: st.hasBt
            tooltipText: "Bluetooth power toggle · click arrow for bluetooth settings"
            onToggled: st.toggleBluetooth()
            onTrailClicked: st.openSettings("network")
        }
    }

    Component {
        id: compDnd
        ToggleTile {
            iconName: st.core.dnd ? "notifications_off" : "notifications"
            iconAlt: "D"
            titleText: "Do not disturb"
            subText: st.dndSubtitle
            trailIcon: "tune"
            trailAlt: "*"
            tileOn: st.core.dnd
            tileAvailable: true
            tooltipText: "Do Not Disturb · tap toggles, chevron selects duration"
            onToggled: st.toggleDnd()
            onTrailClicked: st.dndExpanded = !st.dndExpanded
        }
    }

    Component {
        id: compIdle
        ToggleTile {
            iconName: "timer"
            iconAlt: "I"
            titleText: "Idle lock"
            subText: st.idleSubtitle
            tileOn: st.idleDaemonOn && !st.keepAwakeOn
            tileAvailable: st.hasIdleTool
            tooltipText: st.keepAwakeOn
                ? "Idle lock is temporarily paused by Keep awake"
                : "Automated session locking daemon (hypridle)"
            onToggled: st.toggleIdleLock()
        }
    }

    Component {
        id: compKeepAwake
        ToggleTile {
            iconName: "coffee"
            iconAlt: "K"
            titleText: "Keep awake"
            subText: st.keepAwakeOn ? "Active" : "Off"
            tileOn: st.keepAwakeOn
            tileAvailable: true
            tooltipText: "Inhibit idle sleep and screen timeout (systemd-inhibit)"
            onToggled: st.toggleKeepAwake()
        }
    }

    Component {
        id: compFlight
        ToggleTile {
            iconName: "flight"
            iconAlt: "F"
            titleText: "Flight mode"
            subText: st.flightMode ? "Enabled" : "Disabled"
            tileOn: st.flightMode
            tileAvailable: st.hasNmcli || st.hasBt
            tooltipText: "Disable all wireless radios simultaneously"
            onToggled: st.toggleFlightMode()
        }
    }

    Component {
        id: compNightLight
        ToggleTile {
            iconName: "nightlight"
            iconAlt: "N"
            titleText: "Night light"
            subText: !st.hasSunset ? "Not installed" : (st.nightLightOn ? (st.nightKelvin > 0 ? (st.nightKelvin + "K Shift") : "On") : "Off")
            trailIcon: st.hasSunset ? "tune" : ""
            trailAlt: "*"
            tileOn: st.nightLightOn
            tileAvailable: st.hasSunset
            tooltipText: st.hasSunset ? "Blue-light filter · click arrow to cycle color temperature" : "hyprsunset is not installed (sudo pacman -S hyprsunset)"
            onToggled: st.toggleNightLight()
            onTrailClicked: st.cycleNightKelvin()
        }
    }

    Component {
        id: compGameMode
        ToggleTile {
            iconName: "sports_esports"
            iconAlt: "G"
            titleText: "Game mode"
            subText: st.gameModeOn ? "Active" : "Off"
            tileOn: st.gameModeOn
            tileAvailable: true
            tooltipText: "Disable animations, blur, shadows & gaps for max gaming performance"
            onToggled: st.toggleGameMode()
        }
    }

    Component {
        id: compPowerProfile
        ToggleTile {
            iconName: "speed"
            iconAlt: "P"
            titleText: "Power profile"
            subText: st.powerProfile !== "" ? st.powerProfile : "Default"
            tileOn: st.powerProfile === "performance"
            tileAvailable: st.profileList.length > 0
            tooltipText: "Cycle device power profile (" + (st.powerProfile || "balanced") + ")"
            onToggled: st.cyclePowerProfile()
        }
    }

    Component {
        id: compMic
        ToggleTile {
            iconName: (st.core.sourceAudio && st.core.micMuted) ? "mic_off" : "mic"
            iconAlt: "M"
            titleText: "Microphone"
            subText: st.core.sourceAudio ? (st.core.micMuted ? "Muted" : (Math.round(st.core.micVolume * 100) + "%")) : "No input"
            tileOn: st.core.sourceAudio ? st.core.micMuted : false
            tileAvailable: st.core.sourceAudio !== null
            tooltipText: "Toggle microphone mute"
            onToggled: st.toggleMicMute()
        }
    }

    Component {
        id: compScreenshot
        ToggleTile {
            iconName: "screenshot_monitor"
            iconAlt: "S"
            titleText: "Screenshot"
            subText: "Snip region"
            tileOn: false
            tileAvailable: true
            tileInteractable: true
            tooltipText: "Take region screenshot (Print)"
            onToggled: {
                const rootPath = st.repoRoot
                Quickshell.execDetached([(rootPath ? (rootPath + "/scripts/gps-shot") : "gps-shot"), "region"])
                localExpanded = false
                if (typeof core.setControl === "function") core.setControl("close")
            }
        }
    }

    Component {
        id: compRecord
        ToggleTile {
            iconName: "screen_record"
            iconAlt: "R"
            titleText: "Record"
            subText: st.isRecording ? "Recording..." : "Start capture"
            tileOn: st.isRecording
            tileAvailable: true
            tileInteractable: true
            tooltipText: st.isRecording ? "Stop screen recording" : "Start screen recording"
            onToggled: {
                const rootPath = st.repoRoot
                Quickshell.execDetached([(rootPath ? (rootPath + "/scripts/gps-record") : "gps-record"), "toggle"])
                st.scheduleProbe(350)
            }
        }
    }

    // ───────────── STATE 01: Collapsed Pill (180x36) ─────────────
    Item {
        id: compactView
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        opacity: st.expanded ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Ico {
                visible: st.hasNmcli
                name: !st.wifiEnabled ? "wifi_off" : (st.wifiSsid !== "" ? "wifi" : "network_wifi")
                alt: "W"
                font.pixelSize: 14
                color: st.wifiEnabled ? Theme.brandAccent : Theme.textMuted
            }

            Ico {
                visible: st.hasBt
                name: !st.btEnabled ? "bluetooth_disabled" : (st.btDevice !== "" ? "bluetooth_connected" : "bluetooth")
                alt: "B"
                font.pixelSize: 14
                color: st.btEnabled ? Theme.brandAccent : Theme.textMuted
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 2
            visible: st.core.hasBat

            Ico {
                name: (st.core.charging || st.core.full) ? "bolt" : "battery_5_bar"
                alt: "+"
                font.pixelSize: 13
                color: (!st.core.charging && st.core.batPct <= 20) ? Theme.statusDanger : Theme.brandAccent
            }

            Text {
                text: Math.round(st.core.batPct) + "%"
                font.family: Theme.fontMono
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: Theme.textMain
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: st.core.sinkAudio !== null

            Ico {
                name: st.core.volIcon()
                alt: "V"
                font.pixelSize: 14
                color: Theme.textMuted
            }

            Text {
                text: st.core.muted ? "0" : String(Math.round(st.core.volume * 100))
                font.family: Theme.fontMono
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: Theme.textMuted
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.localExpanded = true
        }
    }

    // ───────────── STATE 02: Expanded Control Center (460 x up to 560) ─────────────
    Item {
        id: expandedView
        anchors.fill: parent
        anchors.margins: 20
        opacity: st.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Flickable {
            id: controlScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: footerRow.top
            anchors.bottomMargin: 8
            clip: true
            contentWidth: width
            contentHeight: controlContent.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: controlContent
                width: controlScroll.width
                spacing: 12

                // Header: Battery Chip + Profile + Media Hub, Toolbox, Settings buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        visible: st.headerBadgeText !== ""
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: Math.min(280, badgeText.implicitWidth + (st.core.hasBat ? 22 : 0) + 24)
                        radius: Theme.radiusCard
                        color: badgeMa.containsMouse ? Theme.cardHover : Theme.card
                        border.width: Theme.borderWidth
                        border.color: badgeMa.containsMouse ? Theme.accentPrimary : Theme.outlineSoft

                        RowLayout {
                            id: badgeRow
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Ico {
                                visible: st.core.hasBat
                                name: st.core.charging ? "battery_charging_full" : "battery_5_bar"
                                alt: "B"
                                font.pixelSize: 14
                                color: (!st.core.charging && st.core.batPct <= 20) ? Theme.statusDanger : Theme.brandAccent
                            }

                            Text {
                                id: badgeText
                                Layout.fillWidth: true
                                text: st.headerBadgeText
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Theme.textMain
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: badgeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: st.cyclePowerProfile()
                        }

                        ToolTip.visible: badgeMa.containsMouse
                        ToolTip.text: {
                            const details = []
                            if (st.core.hasBat) {
                                details.push(Math.round(st.core.batPct) + "%" + (st.batteryTimeText !== "" ? (" (" + st.batteryTimeText + ")") : ""))
                            }
                            if (st.powerProfile !== "") {
                                details.push("Profile: " + st.powerProfile)
                            }
                            const prefix = details.length > 0 ? (details.join(" · ") + "\n") : ""
                            return prefix + "Click to cycle power profile (" + (st.powerProfile || "balanced") + ")"
                        }
                        ToolTip.delay: 300
                    }

                    Item { Layout.fillWidth: true }

                    HeaderButton {
                        iconName: "hub"
                        iconAlt: "M"
                        tooltipText: "Media Hub"
                        onTriggered: st.openMediaHub()
                    }

                    HeaderButton {
                        iconName: "construction"
                        iconAlt: "T"
                        tooltipText: "Toolbox"
                        onTriggered: st.openToolbox()
                    }

                    HeaderButton {
                        iconName: "settings"
                        iconAlt: "S"
                        tooltipText: "Settings"
                        onTriggered: st.openSettings("")
                    }

                    HeaderButton {
                        iconName: "tune"
                        iconAlt: "*"
                        active: st.editTilesMode
                        tooltipText: st.editTilesMode ? "Done customizing" : "Customize tiles"
                        onTriggered: st.editTilesMode = !st.editTilesMode
                    }
                }

                // Tiles Customization Edit Mode View
                Rectangle {
                    visible: st.editTilesMode
                    Layout.fillWidth: true
                    implicitHeight: editContentCol.implicitHeight + 20
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: Theme.borderWidth
                    border.color: Theme.brandAccent

                    ColumnLayout {
                        id: editContentCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "CUSTOMIZE TILES"
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                                color: Theme.brandAccent
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: 96
                                radius: 6
                                color: rstMa.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: Theme.outlineSoft
                                Text {
                                    anchors.centerIn: parent
                                    text: "Reset Defaults"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 9
                                    font.weight: Font.Medium
                                    color: Theme.textMuted
                                }
                                MouseArea {
                                    id: rstMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: st.resetControlTiles()
                                }
                            }
                            Rectangle {
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: 60
                                radius: 6
                                color: Theme.brandAccent
                                Text {
                                    anchors.centerIn: parent
                                    text: "Done"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.brandAccentFg
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: st.editTilesMode = false
                                }
                            }
                        }

                        Repeater {
                            model: st.controlTiles
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Theme.outlineSoft

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 4
                                        color: upMa.containsMouse ? Theme.cardHover : "transparent"
                                        opacity: index > 0 ? 1.0 : 0.25
                                        Ico {
                                            anchors.centerIn: parent
                                            name: "arrow_upward"
                                            alt: "^"
                                            font.pixelSize: 14
                                            color: Theme.textMain
                                        }
                                        MouseArea {
                                            id: upMa
                                            anchors.fill: parent
                                            enabled: index > 0
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: st.moveTileUp(index)
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 4
                                        color: downMa.containsMouse ? Theme.cardHover : "transparent"
                                        opacity: (st.controlTiles && index < st.controlTiles.length - 1) ? 1.0 : 0.25
                                        Ico {
                                            anchors.centerIn: parent
                                            name: "arrow_downward"
                                            alt: "v"
                                            font.pixelSize: 14
                                            color: Theme.textMain
                                        }
                                        MouseArea {
                                            id: downMa
                                            anchors.fill: parent
                                            enabled: Boolean(st.controlTiles && index < st.controlTiles.length - 1)
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: st.moveTileDown(index)
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: modelData.enabled ? Theme.textMain : Theme.textMuted
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 64
                                        Layout.preferredHeight: 22
                                        radius: 6
                                        color: modelData.enabled ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.2) : Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1
                                        border.color: modelData.enabled ? Theme.brandAccent : Theme.outlineSoft

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Ico {
                                                name: modelData.enabled ? "visibility" : "visibility_off"
                                                alt: modelData.enabled ? "O" : "X"
                                                font.pixelSize: 12
                                                color: modelData.enabled ? Theme.brandAccent : Theme.textMuted
                                            }
                                            Text {
                                                text: modelData.enabled ? "Shown" : "Hidden"
                                                font.family: Theme.fontUi
                                                font.pixelSize: 9
                                                font.weight: Font.Medium
                                                color: modelData.enabled ? Theme.brandAccent : Theme.textMuted
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: st.toggleTile(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Two-Column Grid of Enabled Tiles
                GridLayout {
                    visible: !st.editTilesMode
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10
                    uniformCellWidths: true

                    Repeater {
                        model: st.visibleTiles
                        delegate: Loader {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 54
                            Layout.row: Math.floor(index / 2)
                            Layout.column: index % 2
                            sourceComponent: {
                                switch (modelData.id) {
                                    case "wifi": return compWifi;
                                    case "bluetooth": return compBt;
                                    case "dnd": return compDnd;
                                    case "idle": return compIdle;
                                    case "keepawake": return compKeepAwake;
                                    case "flight": return compFlight;
                                    case "nightlight": return compNightLight;
                                    case "gamemode": return compGameMode;
                                    case "powerprofile": return compPowerProfile;
                                    case "mic": return compMic;
                                    case "screenshot": return compScreenshot;
                                    case "record": return compRecord;
                                    default: return null;
                                }
                            }
                        }
                    }
                }

                // DND Duration Selector Drawer (visible when dndExpanded is true)
                Rectangle {
                    visible: st.dndExpanded
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: Theme.borderWidth
                    border.color: Theme.outlineSoft

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        Text {
                            text: "DND for:"
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Theme.textMuted
                        }

                        Repeater {
                            model: [
                                { label: "15m", mins: 15 },
                                { label: "30m", mins: 30 },
                                { label: "1h", mins: 60 },
                                { label: "2h", mins: 120 },
                                { label: "Till 8 AM", mins: ControlLogic.calcMinutesUntilNext(8, 0, Date.now()) }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: chipMa.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: chipMa.containsMouse ? Theme.accentPrimary : Theme.outlineSoft

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: Theme.textMain
                                }

                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        st.core.dndSnooze(modelData.mins)
                                        st.dndExpanded = false
                                    }
                                }
                            }
                        }
                    }
                }

                // Sliders Matrix (Volume & Brightness)
                Rectangle {
                    visible: st.core.sinkAudio !== null || st.brightAvailable
                    Layout.fillWidth: true
                    implicitHeight: slidersCol.implicitHeight + 20
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: Theme.borderWidth
                    border.color: Theme.outlineSoft

                    ColumnLayout {
                        id: slidersCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        SliderRow {
                            visible: st.core.sinkAudio !== null
                            iconName: st.core.volIcon()
                            iconAlt: "V"
                            tone: st.core.muted ? Theme.textMuted : Theme.brandAccent
                            value: st.liveVol
                            maxValue: 1.5
                            labelText: st.core.muted ? "Mute" : (Math.round(st.liveVol * 100) + "%")
                            trailIcon: st.audioOutputsExpanded ? "expand_less" : "expand_more"
                            trailAlt: st.audioOutputsExpanded ? "^" : "v"
                            onIconClicked: if (st.core.sinkAudio) st.core.sinkAudio.muted = !st.core.sinkAudio.muted
                            onTrailClicked: {
                                st.audioOutputsExpanded = !st.audioOutputsExpanded
                                if (st.audioOutputsExpanded) st.refreshSinks()
                            }
                            onMoved: v => {
                                st.dragVol = v
                                st.applyVolume(v)
                            }
                            onReleased: v => {
                                st.applyVolume(v)
                                st.dragVol = -1
                            }
                        }

                        // Inline expanded audio output sinks list
                        ColumnLayout {
                            visible: st.audioOutputsExpanded && st.audioSinks.length > 0
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: st.audioSinks
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: 8
                                    color: modelData.default
                                        ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.16)
                                        : (sinkMa.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.04))
                                    border.width: 1
                                    border.color: modelData.default ? Theme.brandAccent : Theme.outlineSoft
                                    opacity: modelData.available === false ? 0.45 : 1.0

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Ico {
                                            name: modelData.default ? "check" : "speaker"
                                            alt: modelData.default ? "✓" : "S"
                                            font.pixelSize: 13
                                            color: modelData.default ? Theme.brandAccent : Theme.textMuted
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name + (modelData.available === false ? " · (unavailable)" : "")
                                            font.family: Theme.fontUi
                                            font.pixelSize: 11
                                            font.weight: modelData.default ? Font.DemiBold : Font.Normal
                                            color: modelData.default ? Theme.brandAccent : Theme.textMain
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: sinkMa
                                        anchors.fill: parent
                                        hoverEnabled: modelData.available !== false
                                        cursorShape: modelData.available !== false ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (modelData.available !== false && !modelData.default) {
                                                st.selectSink(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Mic volume slider (hidden if there is no input)
                        SliderRow {
                            visible: st.core.sourceAudio !== null
                            iconName: (st.core.sourceAudio && st.core.micMuted) ? "mic_off" : "mic"
                            iconAlt: "M"
                            tone: (st.core.sourceAudio && st.core.micMuted) ? Theme.textMuted : Theme.brandAccent
                            value: st.liveMicVol
                            maxValue: 1.5
                            labelText: (st.core.sourceAudio && st.core.micMuted) ? "Mute" : (Math.round(st.liveMicVol * 100) + "%")
                            onIconClicked: if (st.core.sourceAudio) st.core.sourceAudio.muted = !st.core.sourceAudio.muted
                            onMoved: v => {
                                st.dragMicVol = v
                                st.applyMicVolume(v)
                            }
                            onReleased: v => {
                                st.applyMicVolume(v)
                                st.dragMicVol = -1
                            }
                        }

                        SliderRow {
                            visible: st.brightAvailable
                            iconName: "light_mode"
                            iconAlt: "L"
                            tone: Theme.statusWarn
                            value: st.liveBright
                            maxValue: 1.0
                            labelText: Math.round(st.liveBright * 100) + "%"
                            onIconClicked: st.openSettings("display")
                            onMoved: v => st.dragBright = Math.max(0.05, Math.min(1, v))
                            onReleased: v => {
                                const clamped = Math.max(0.05, Math.min(1, v))
                                st.dragBright = -1
                                st.commitBrightness(clamped)
                            }
                        }
                    }
                }

                // MPRIS Now-Playing Card (hidden when nothing plays)
                Rectangle {
                    visible: st.hasActiveMedia
                    Layout.fillWidth: true
                    implicitHeight: st.hasProgress ? 96 : 64
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: Theme.borderWidth
                    border.color: Theme.outlineSoft

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Album Art / Fallback
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                                clip: true

                                Image {
                                    id: coverImg
                                    anchors.fill: parent
                                    source: (st.player && st.player.trackArtUrl) ? st.player.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                Ico {
                                    visible: coverImg.status !== Image.Ready
                                    anchors.centerIn: parent
                                    name: "music_note"
                                    alt: "♫"
                                    font.pixelSize: 20
                                    color: Theme.textMuted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: st.openMediaHub()
                                }
                            }

                            // Title & Artist
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: (st.player && st.player.trackTitle) ? st.player.trackTitle : ""
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.textMain
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (st.player && st.player.trackArtist) ? st.player.trackArtist : "Unknown Artist"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                }
                            }

                            // Transport Controls
                            RowLayout {
                                spacing: 4

                                // Previous
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: prevMa.containsMouse ? Theme.cardHover : "transparent"
                                    opacity: Boolean(st.player && st.player.canGoPrevious) ? 1.0 : 0.35

                                    Ico {
                                        anchors.centerIn: parent
                                        name: "skip_previous"
                                        alt: "|<"
                                        font.pixelSize: 18
                                        color: Theme.textMain
                                    }

                                    MouseArea {
                                        id: prevMa
                                        anchors.fill: parent
                                        enabled: Boolean(st.player && st.player.canGoPrevious)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (st.player && st.player.canGoPrevious) st.player.previous()
                                    }
                                }

                                // Play / Pause
                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: playMa.containsMouse ? Qt.lighter(Theme.brandAccent, 1.08) : Theme.brandAccent

                                    Ico {
                                        anchors.centerIn: parent
                                        name: (st.player && st.player.isPlaying) ? "pause" : "play_arrow"
                                        alt: (st.player && st.player.isPlaying) ? "||" : ">"
                                        font.pixelSize: 18
                                        color: Theme.brandAccentFg
                                    }

                                    MouseArea {
                                        id: playMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (st.player) st.player.togglePlaying()
                                    }
                                }

                                // Next
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: nextMa.containsMouse ? Theme.cardHover : "transparent"
                                    opacity: Boolean(st.player && st.player.canGoNext) ? 1.0 : 0.35

                                    Ico {
                                        anchors.centerIn: parent
                                        name: "skip_next"
                                        alt: ">|"
                                        font.pixelSize: 18
                                        color: Theme.textMain
                                    }

                                    MouseArea {
                                        id: nextMa
                                        anchors.fill: parent
                                        enabled: Boolean(st.player && st.player.canGoNext)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (st.player && st.player.canGoNext) st.player.next()
                                    }
                                }
                            }
                        }

                        // Progress bar
                        RowLayout {
                            visible: st.hasProgress
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: ControlLogic.formatDuration(st.displayPos)
                                font.family: Theme.fontMono
                                font.pixelSize: 9
                                color: Theme.textMuted
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.08)
                                clip: true

                                Rectangle {
                                    width: parent.width * st.progressFraction
                                    height: parent.height
                                    radius: 2
                                    color: Theme.brandAccent
                                }
                            }

                            Text {
                                text: st.player ? ControlLogic.formatDuration(st.player.length * 1000) : "0:00"
                                font.family: Theme.fontMono
                                font.pixelSize: 9
                                color: Theme.textMuted
                            }
                        }
                    }
                }

                // Compact CPU / RAM / Temp Strip
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Theme.radiusCard
                    color: Theme.card
                    border.width: Theme.borderWidth
                    border.color: Theme.outlineSoft

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        // CPU Item
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Ico {
                                    name: "memory"
                                    alt: "C"
                                    font.pixelSize: 15
                                    color: Theme.brandAccent
                                }
                                Text {
                                    text: "CPU"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: st.cpuUsage >= 0 ? (st.cpuUsage + "%") : "--%"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Theme.textMain
                                }
                            }
                            ToolTip.visible: cpuMa.containsMouse
                            ToolTip.text: "CPU usage: " + (st.cpuUsage >= 0 ? (st.cpuUsage + "%") : "measuring\u2026")
                            ToolTip.delay: 300
                            MouseArea { id: cpuMa; anchors.fill: parent; hoverEnabled: true }
                        }

                        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 16; color: Theme.outlineSoft }

                        // RAM Item
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Ico {
                                    name: "storage"
                                    alt: "R"
                                    font.pixelSize: 15
                                    color: Theme.accentSecondary
                                }
                                Text {
                                    text: "RAM"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: st.memPct >= 0 ? (st.memPct + "%") : "--%"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Theme.textMain
                                }
                            }
                            ToolTip.visible: ramMa.containsMouse
                            ToolTip.text: "RAM: " + st.memUsedGiB.toFixed(1) + " / " + st.memTotalGiB.toFixed(1) + " GiB (" + st.memPct + "%)"
                            ToolTip.delay: 300
                            MouseArea { id: ramMa; anchors.fill: parent; hoverEnabled: true }
                        }

                        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 16; color: Theme.outlineSoft }

                        // TEMP Item
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Ico {
                                    name: "thermostat"
                                    alt: "T"
                                    font.pixelSize: 15
                                    color: st.tempC >= 80 ? Theme.statusDanger : (st.tempC >= 70 ? Theme.statusWarn : Theme.brandAccent)
                                }
                                Text {
                                    text: "TEMP"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: st.tempC > 0 ? (st.tempC + "°C") : "--°C"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Theme.textMain
                                }
                            }
                            ToolTip.visible: tempMa.containsMouse
                            ToolTip.text: "CPU package temperature: " + (st.tempC > 0 ? (st.tempC + "°C") : "measuring\u2026")
                            ToolTip.delay: 300
                            MouseArea { id: tempMa; anchors.fill: parent; hoverEnabled: true }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Bottom Session Strip & Footer Actions (pinned so lock/sleep/power is visible and never clipped)
        RowLayout {
            id: footerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 8

            RowLayout {
                visible: st.sessionSummary !== ""
                Layout.fillWidth: true
                spacing: 6

                Ico {
                    name: "memory"
                    alt: "M"
                    font.pixelSize: 14
                    color: Theme.textMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: st.sessionSummary
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: Theme.textMuted
                    elide: Text.ElideRight
                }
            }

            Item {
                visible: st.sessionSummary === ""
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 8

                ActionCircle {
                    iconName: "lock"
                    iconAlt: "L"
                    tooltipText: "Lock screen"
                    onTriggered: st.lockScreen()
                }

                ActionCircle {
                    iconName: "bedtime"
                    iconAlt: "Z"
                    tooltipText: "Suspend system"
                    onTriggered: st.suspendSystem()
                }

                ActionCircle {
                    iconName: st.confirmPower ? "check" : "power_settings_new"
                    iconAlt: st.confirmPower ? "!" : "P"
                    danger: true
                    armed: st.confirmPower
                    tooltipText: st.confirmPower ? "Click again to confirm power off" : "Power off system"
                    onTriggered: st.triggerPower()
                }
            }
        }
    }
}
