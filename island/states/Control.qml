import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import "../ControlLogic.js" as ControlLogic

Item {
    id: st

    required property var core
    readonly property string key: "control"
    readonly property bool active: core.mode === key
    readonly property bool expanded: core.hovered || Boolean(core.controlExpanded) || localExpanded
    readonly property real w: expanded ? 460 : 180
    readonly property real h: expanded ? Math.min(560, Math.max(380, controlContent.implicitHeight + 40)) : 36
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    // ───────────── live state (populated only while active) ─────────────
    property bool localExpanded: false
    property bool dndExpanded: false
    property bool audioOutputsExpanded: false
    property var audioSinks: []
    property int defaultSinkId: 0

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

    readonly property string headerBadgeText: {
        const parts = []
        if (core.hasBat) parts.push(Math.round(core.batPct) + "%")
        if (batteryTimeText !== "") parts.push(batteryTimeText)
        if (powerProfile !== "") parts.push(powerProfile.toUpperCase())
        return parts.join(" · ")
    }

    readonly property string idleSubtitle: {
        if (!hasIdleTool) return "Off"
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
            triggerProbe()
            refreshSinks()
        } else {
            localExpanded = false
            confirmPower = false
            dndExpanded = false
            audioOutputsExpanded = false
            dragBright = -1
            dragVol = -1
            dragMicVol = -1
            if (sysProbe.running) sysProbe.running = false
            if (sinksProc.running) sinksProc.running = false
        }
    }

    focus: active && expanded
    Keys.onEscapePressed: {
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
            "if [ -x \"$HOME/Projects/my-rice/scripts/gps-idle\" ]; then \"$HOME/Projects/my-rice/scripts/gps-idle\" env-status; elif command -v gps-idle >/dev/null 2>&1; then gps-idle env-status; else echo 'has_idle=0'; echo 'idle_run=0'; echo 'idle_t=300'; fi; " +
            "pgrep -f \"systemd-inhibit.*sleep infinity\" >/dev/null 2>&1 && echo 'keepawake_run=1' || echo 'keepawake_run=0'; " +
            "if [ -x \"$HOME/Projects/my-rice/scripts/gps-gamemode\" ]; then \"$HOME/Projects/my-rice/scripts/gps-gamemode\" status 2>/dev/null; else echo 'active=0'; fi; " +
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
            "if command -v gps-lock >/dev/null 2>&1 || [ -x \"$HOME/Projects/my-rice/scripts/gps-lock\" ] || command -v hyprlock >/dev/null 2>&1 || command -v loginctl >/dev/null 2>&1; then echo 'has_locker=1'; else echo 'has_locker=0'; fi"
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
        command: ["python3", (Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice")) + "/scripts/audio-sinks.py"]
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
        const rootPath = Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice")
        sinkSwitchProc.command = ["python3", rootPath + "/scripts/audio-sinks.py", "--switch", String(id)]
        sinkSwitchProc.running = true
    }

    function applyMicVolume(ratio) {
        if (!core.sourceAudio) return
        const clamped = Math.max(0, Math.min(1.5, ratio))
        if (core.sourceAudio.muted && clamped > 0) core.sourceAudio.muted = false
        core.sourceAudio.volume = clamped
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
            runCmd('command -v gps-idle >/dev/null 2>&1 && gps-idle start || "$HOME/Projects/my-rice/scripts/gps-idle" start', [], 400)
        else
            runCmd('command -v gps-idle >/dev/null 2>&1 && gps-idle stop || "$HOME/Projects/my-rice/scripts/gps-idle" stop', [], 350)
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
        runCmd('"$HOME/Projects/my-rice/scripts/gps-gamemode" toggle', [], 400)
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
        const settingsPath = Quickshell.env("HOME") + "/Projects/my-rice/settings.qml"
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
            const rootPath = Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice")
            Quickshell.execDetached([rootPath + "/scripts/gps-ipc", "mediahub", "toggle"])
        }
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
    }

    function openToolbox() {
        if (core && typeof core.openToolbox === "function") {
            core.openToolbox()
        } else {
            const rootPath = Quickshell.env("GPS_ROOT") || (Quickshell.env("HOME") + "/Projects/my-rice")
            Quickshell.execDetached([rootPath + "/scripts/gps-ipc", "toolbox", "toggle"])
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
        Quickshell.execDetached(["sh", "-c", "command -v gps-lock >/dev/null 2>&1 && exec gps-lock || exec \"$HOME/Projects/my-rice/scripts/gps-lock\""])
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
        signal triggered()

        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        radius: Theme.radiusCard
        activeFocusOnTab: true
        color: (hbMa.containsMouse || hb.activeFocus) ? Theme.cardHover : Theme.card
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
            color: (hbMa.containsMouse || hb.activeFocus) ? Theme.textMain : Theme.textMuted
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
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: controlContent.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

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
                        Layout.preferredWidth: Math.min(260, badgeRow.implicitWidth + 18)
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
                        ToolTip.text: "Click to cycle power profile (" + (st.powerProfile || "balanced") + ")"
                        ToolTip.delay: 400
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
                }

                // Two-Column Grid of K1 Tiles
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10
                    uniformCellWidths: true

                    // 1. Wi-Fi
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

                    // 2. Bluetooth
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

                    // 3. Do Not Disturb
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

                    // 4. Idle lock
                    ToggleTile {
                        iconName: "timer"
                        iconAlt: "I"
                        titleText: "Idle lock"
                        subText: st.idleSubtitle
                        tileOn: st.idleDaemonOn
                        tileAvailable: st.hasIdleTool
                        tooltipText: "Automated session locking daemon (hypridle)"
                        onToggled: st.toggleIdleLock()
                    }

                    // 5. Keep awake
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

                    // 6. Flight mode
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

                    // 7. Night light
                    ToggleTile {
                        iconName: "nightlight"
                        iconAlt: "N"
                        titleText: "Night light"
                        subText: !st.hasSunset ? "sudo pacman -S hyprsunset" : (st.nightLightOn ? (st.nightKelvin > 0 ? (st.nightKelvin + "K Shift") : "On") : "Off")
                        trailIcon: st.hasSunset ? "tune" : ""
                        trailAlt: "*"
                        tileOn: st.nightLightOn
                        tileAvailable: st.hasSunset
                        tooltipText: st.hasSunset ? "Blue-light filter · click arrow to cycle color temperature" : "hyprsunset is not installed (sudo pacman -S hyprsunset)"
                        onToggled: st.toggleNightLight()
                        onTrailClicked: st.cycleNightKelvin()
                    }

                    // 8. Game mode
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

                    // 9. Power profile
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

                    // 10. Microphone mute
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

                    // 11. Screenshot (Reserved)
                    ToggleTile {
                        iconName: "screenshot_monitor"
                        iconAlt: "S"
                        titleText: "Screenshot"
                        subText: "Reserved"
                        tileOn: false
                        tileAvailable: false
                        tileInteractable: false
                        tooltipText: "Screenshot capture (reserved slot)"
                    }

                    // 12. Record (Reserved)
                    ToggleTile {
                        iconName: "screen_record"
                        iconAlt: "R"
                        titleText: "Record"
                        subText: "Reserved"
                        tileOn: false
                        tileAvailable: false
                        tileInteractable: false
                        tooltipText: "Screen recording (reserved slot)"
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

                Item { Layout.fillHeight: true }

                // Bottom Session Strip & Footer Actions
                RowLayout {
                    Layout.fillWidth: true
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
    }
}
