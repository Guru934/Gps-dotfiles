import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: st

    required property var core
    readonly property string key: "control"
    readonly property bool active: core.mode === key
    readonly property bool expanded: core.hovered || Boolean(core.controlExpanded) || localExpanded
    readonly property real w: expanded ? 440 : 180
    readonly property real h: expanded ? 380 : 36
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    // ───────────── live state (populated only while active) ─────────────
    property bool localExpanded: false

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

    property bool hasPpd: false
    property string powerProfile: ""
    readonly property var profileOrder: ["power-saver", "balanced", "performance"]

    property int fallbackBrightPct: -1
    property real dragBright: -1
    readonly property bool brightAvailable: core.hasBrightness || fallbackBrightPct >= 0
    readonly property real liveBright: dragBright >= 0
        ? dragBright
        : (core.hasBrightness ? core.brightness : (fallbackBrightPct >= 0 ? fallbackBrightPct / 100 : 0))

    property real dragVol: -1
    readonly property real liveVol: dragVol >= 0 ? dragVol : (core.muted ? 0 : Math.max(0, Math.min(1.5, core.volume)))

    property int uptimeSec: 0
    property string kernelVer: ""
    property bool hasWlogout: false
    property bool hasSystemctl: false
    property bool hasLocker: false
    property bool confirmPower: false

    // Focus setup is intentionally local to this in-memory control surface.
    // The running session itself remains owned by Island.qml.
    property string focusWorkInput: "25"
    property string focusBreakInput: "5"
    property string focusCountInput: "4"
    property string focusTitleInput: ""
    property string focusPreset: "25/5"
    property string focusError: ""

    readonly property bool focusInputsValid:
        validFocusMinutes(focusWorkInput, false)
        && validFocusMinutes(focusBreakInput, true)
        && validFocusCount(focusCountInput)
    readonly property real focusProgress:
        core.focusOn && core.focusPhaseSeconds > 0
        ? Math.max(0, Math.min(1,
            1 - core.focusRemaining / core.focusPhaseSeconds))
        : 0
    readonly property color focusTone: core.focusBreak ? core.lav : core.teal

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
    readonly property string headerBadgeText: {
        const parts = []
        if (core.hasBat) parts.push(Math.round(core.batPct) + "%")
        if (powerProfile !== "") parts.push(powerProfile.toUpperCase())
        return parts.join(" · ")
    }
    readonly property string idleSubtitle: {
        if (!hasIdleTool) return ""
        if (!idleDaemonOn) return "Off"
        if (idleTimeoutSec > 0) {
            const mins = Math.round(idleTimeoutSec / 60)
            return mins > 0 ? (mins + " min") : (idleTimeoutSec + " sec")
        }
        return "Active"
    }

    function validFocusMinutes(value, allowZero) {
        if (typeof value !== "string" || !/^\d+$/.test(value)) return false
        const n = Number(value)
        return Number.isInteger(n) && n >= (allowZero ? 0 : 1) && n <= 10080
    }

    function validFocusCount(value) {
        if (typeof value !== "string" || !/^\d+$/.test(value)) return false
        const n = Number(value)
        return Number.isInteger(n) && n >= 1 && n <= 1000
    }

    function applyFocusPreset(work, rest, name) {
        focusWorkInput = String(work)
        focusBreakInput = String(rest)
        focusPreset = name
        focusError = ""
    }

    function startFocusFromCard() {
        focusError = ""
        if (!focusInputsValid) {
            focusError = "Enter valid minutes and a session count."
            return
        }
        if (typeof core.startFocus !== "function") {
            focusError = "Focus controls are unavailable."
            return
        }
        const started = core.startFocus(
            Number(focusWorkInput) * 60,
            Number(focusBreakInput) * 60,
            Number(focusCountInput),
            focusTitleInput
        )
        if (!started) focusError = "Those Focus settings were rejected."
    }

    // ───────────── lifecycle & dismissal ─────────────
    onActiveChanged: {
        if (active) {
            confirmPower = false
            triggerProbe()
        } else {
            localExpanded = false
            confirmPower = false
            dragBright = -1
            dragVol = -1
            if (sysProbe.running) sysProbe.running = false
        }
    }

    focus: active && expanded
    Keys.onEscapePressed: {
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
            "command -v hypridle >/dev/null 2>&1 && echo 'has_idle=1' || echo 'has_idle=0'; " +
            "pgrep -x hypridle >/dev/null 2>&1 && echo 'idle_run=1' || echo 'idle_run=0'; " +
            "echo \"idle_t=$(awk -F= '/^[[:space:]]*timeout[[:space:]]*=/{gsub(/[^0-9]/,\"\",$2); if($2>0){print $2; exit}}' \"$HOME/.config/hypr/hypridle.conf\" 2>/dev/null)\"; " +
            "prof=''; ppd_ok=0; if command -v powerprofilesctl >/dev/null 2>&1; then prof=$(powerprofilesctl get 2>/dev/null); [ -n \"$prof\" ] && ppd_ok=1; fi; echo \"has_ppd=$ppd_ok\"; " +
            "[ -z \"$prof\" ] && prof=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null); " +
            "[ -z \"$prof\" ] && prof=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null); " +
            "echo \"profile=$prof\"; " +
            "echo \"bright=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')\"; " +
            "echo \"uptime=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)\"; " +
            "echo \"kernel=$(uname -r 2>/dev/null)\"; " +
            "command -v wlogout >/dev/null 2>&1 && echo 'has_wlogout=1' || echo 'has_wlogout=0'; " +
            "command -v systemctl >/dev/null 2>&1 && echo 'has_systemctl=1' || echo 'has_systemctl=0'; " +
            "if command -v loginctl >/dev/null 2>&1 || command -v hyprlock >/dev/null 2>&1 || command -v swaylock >/dev/null 2>&1; then echo 'has_locker=1'; else echo 'has_locker=0'; fi"
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

                st.hasPpd = map.has_ppd === "1"
                st.powerProfile = map.profile || ""

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
            runCmd('pgrep -x hypridle >/dev/null 2>&1 || setsid hypridle >/dev/null 2>&1 &', [], 400)
        else
            runCmd('pkill -x hypridle >/dev/null 2>&1', [], 350)
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

    function cyclePowerProfile() {
        if (!hasPpd) return
        const curIdx = profileOrder.indexOf(powerProfile)
        const nextProf = profileOrder[(curIdx + 1) % profileOrder.length]
        powerProfile = nextProf
        runCmd('powerprofilesctl set "$1" >/dev/null 2>&1', [nextProf], 400)
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

    function applyVolume(ratio) {
        if (!core.sinkAudio) return
        const clamped = Math.max(0, Math.min(1.5, ratio))
        if (core.sinkAudio.muted && clamped > 0) core.sinkAudio.muted = false
        core.sinkAudio.volume = clamped
    }

    function commitBrightness(ratio) {
        if (!brightAvailable) return
        const pct = Math.max(5, Math.min(100, Math.round(ratio * 100)))
        fallbackBrightPct = pct
        runCmd('brightnessctl -q set "$1"', [pct + "%"], 250)
    }

    function lockScreen() {
        if (!hasLocker) return
        localExpanded = false
        if (typeof core.setControl === "function") core.setControl("close")
        Quickshell.execDetached(["sh", "-c", "loginctl lock-session >/dev/null 2>&1 || hyprlock >/dev/null 2>&1 || swaylock >/dev/null 2>&1"])
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

    // ───────────── local self-contained components ─────────────
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
        signal toggled()
        signal trailClicked()

        readonly property color inkColor: "#00201c"
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        radius: 12
        visible: tileAvailable
        color: tileOn
            ? (tileMa.containsMouse ? Qt.lighter(st.core.teal, 1.05) : st.core.teal)
            : (tileMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06))
        border.width: tileOn ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
        scale: (tileMa.pressed || trailMa.pressed) ? 0.98 : 1.0
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
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
                    color: tile.tileOn ? tile.inkColor : st.core.dim
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: tile.titleText
                    font.family: st.core.uiFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: tile.tileOn ? tile.inkColor : st.core.text
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: tile.subText !== ""
                    text: tile.subText
                    font.family: st.core.monoFont
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: tile.tileOn ? Qt.rgba(0, 0.13, 0.11, 0.80) : st.core.dim
                    elide: Text.ElideRight
                }
            }

            Item {
                visible: tile.trailIcon !== ""
                Layout.preferredWidth: 20
                Layout.preferredHeight: 28

                Ico {
                    anchors.centerIn: parent
                    name: tile.trailIcon
                    alt: tile.trailAlt
                    font.pixelSize: 16
                    color: tile.tileOn ? Qt.rgba(0, 0.13, 0.11, 0.72) : st.core.dim
                }
            }
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            anchors.rightMargin: tile.trailIcon !== "" ? 30 : 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }

        MouseArea {
            id: trailMa
            visible: tile.trailIcon !== ""
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 30
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.trailClicked()
        }
    }

    component SliderRow: RowLayout {
        id: srow
        property string iconName: ""
        property string iconAlt: ""
        property color tone: st.core.teal
        property real value: 0
        property real maxValue: 1.0
        property string labelText: ""
        signal iconClicked()
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
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: srow.labelText
            font.family: st.core.monoFont
            font.pixelSize: 10
            font.weight: Font.Medium
            color: st.core.text
            elide: Text.ElideRight
        }
    }

    component ActionCircle: Rectangle {
        id: ac
        property string iconName: ""
        property string iconAlt: ""
        property bool danger: false
        property bool armed: false
        signal triggered()

        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: 18
        color: danger
            ? (armed ? st.core.coral : (acMa.containsMouse ? Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.34) : Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.22)))
            : (acMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
        border.width: 1
        border.color: danger ? Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.40) : Qt.rgba(1, 1, 1, 0.06)
        scale: acMa.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        Ico {
            anchors.centerIn: parent
            name: ac.iconName
            alt: ac.iconAlt
            font.pixelSize: 16
            color: ac.danger ? (ac.armed ? "#000000" : st.core.coral) : st.core.text
        }

        MouseArea {
            id: acMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ac.triggered()
        }
    }

    component FocusInput: ColumnLayout {
        id: focusInput
        property string labelText: ""
        property string valueText: ""
        property bool numeric: true
        signal valueEdited(string value)

        Layout.fillWidth: true
        spacing: 3

        onValueTextChanged: {
            if (input.text !== valueText) input.text = valueText
        }

        Text {
            text: focusInput.labelText
            color: st.core.dim
            font.family: st.core.monoFont
            font.pixelSize: 8
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.07)
            border.width: input.activeFocus ? 1 : 0
            border.color: st.core.teal

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: focusInput.valueText
                color: st.core.text
                selectionColor: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.35)
                font.family: st.core.monoFont
                font.pixelSize: 11
                selectByMouse: true
                inputMethodHints: focusInput.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
                onTextChanged: focusInput.valueEdited(text)
            }
        }
    }

    component FocusButton: Rectangle {
        id: focusButton
        property string labelText: ""
        property color tone: st.core.teal
        property bool primary: false
        signal triggered()

        implicitWidth: buttonLabel.implicitWidth + 18
        Layout.preferredHeight: 28
        radius: 9
        color: !enabled
            ? Qt.rgba(1, 1, 1, 0.04)
            : primary
                ? (buttonMouse.containsMouse ? Qt.lighter(tone, 1.08) : tone)
                : (buttonMouse.containsMouse ? Qt.rgba(tone.r, tone.g, tone.b, 0.18) : Qt.rgba(tone.r, tone.g, tone.b, 0.09))
        border.width: primary ? 0 : 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.30)
        opacity: enabled ? 1 : 0.42
        scale: buttonMouse.pressed ? 0.97 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: focusButton.labelText
            color: focusButton.primary ? "#00201c" : st.core.text
            font.family: st.core.monoFont
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: focusButton.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: focusButton.triggered()
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

        // Left: Wi-Fi + Bluetooth indicators
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Ico {
                visible: st.hasNmcli
                name: !st.wifiEnabled ? "wifi_off" : (st.wifiSsid !== "" ? "wifi" : "network_wifi")
                alt: "W"
                font.pixelSize: 14
                color: st.wifiEnabled ? st.core.teal : st.core.dim
            }

            Ico {
                visible: st.hasBt
                name: !st.btEnabled ? "bluetooth_disabled" : (st.btDevice !== "" ? "bluetooth_connected" : "bluetooth")
                alt: "B"
                font.pixelSize: 14
                color: st.btEnabled ? st.core.teal : st.core.dim
            }
        }

        // Center: Battery metric
        Row {
            anchors.centerIn: parent
            spacing: 2
            visible: st.core.hasBat

            Ico {
                name: (st.core.charging || st.core.full) ? "bolt" : "battery_5_bar"
                alt: "+"
                font.pixelSize: 13
                color: (!st.core.charging && st.core.batPct <= 20) ? st.core.coral : st.core.teal
            }

            Text {
                text: Math.round(st.core.batPct) + "%"
                font.family: st.core.monoFont
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: st.core.text
            }
        }

        // Right: Audio telemetry
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: st.core.sinkAudio !== null

            Ico {
                name: st.core.volIcon()
                alt: "V"
                font.pixelSize: 14
                color: st.core.dim
            }

            Text {
                text: st.core.muted ? "0" : String(Math.round(st.core.volume * 100))
                font.family: st.core.monoFont
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: st.core.dim
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.localExpanded = true
        }
    }

    // ───────────── STATE 02: Expanded Control Center (440x380) ─────────────
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
                spacing: 10

            // Top Row: Title + Battery/Profile Badge + Settings Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: st.core.teal
                }

                Text {
                    text: "CONTROL CENTER"
                    font.family: st.core.monoFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: st.core.text
                }

                Rectangle {
                    visible: st.headerBadgeText !== ""
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: Math.min(180, badgeRow.implicitWidth + 16)
                    radius: 10
                    color: badgeMa.containsMouse && st.hasPpd ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.06)

                    RowLayout {
                        id: badgeRow
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        Ico {
                            visible: st.core.hasBat
                            name: st.core.charging ? "battery_charging_full" : "battery_5_bar"
                            alt: "B"
                            font.pixelSize: 12
                            color: (!st.core.charging && st.core.batPct <= 20) ? st.core.coral : st.core.teal
                        }

                        Text {
                            Layout.fillWidth: true
                            text: st.headerBadgeText
                            font.family: st.core.monoFont
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            color: st.core.dim
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: badgeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: st.hasPpd ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (st.hasPpd) st.cyclePowerProfile()
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: settingsMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    scale: settingsMa.pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 90 } }

                    Ico {
                        anchors.centerIn: parent
                        name: "settings"
                        alt: "S"
                        font.pixelSize: 15
                        color: settingsMa.containsMouse ? st.core.text : st.core.dim
                    }

                    MouseArea {
                        id: settingsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.openSettings("")
                    }
                }
            }

            // Focus is part of the existing Control Center. Its setup form is
            // replaced by live session controls once the core starts a session.
            Rectangle {
                id: focusCard
                Layout.fillWidth: true
                implicitHeight: focusCardContent.implicitHeight + 24
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.045)
                border.width: 1
                border.color: Qt.rgba(st.focusTone.r, st.focusTone.g, st.focusTone.b, 0.22)

                ColumnLayout {
                    id: focusCardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 8
                            color: Qt.rgba(st.focusTone.r, st.focusTone.g, st.focusTone.b, 0.14)

                            Ico {
                                anchors.centerIn: parent
                                name: "timer"
                                alt: "F"
                                font.pixelSize: 15
                                color: st.focusTone
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "FOCUS"
                                color: st.core.text
                                font.family: st.core.uiFont
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: st.core.focusOn
                                    ? (st.core.focusBreak ? "Break in progress" : "Work in progress")
                                    : "Ready to start a session"
                                color: st.core.dim
                                font.family: st.core.monoFont
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: focusStatus.implicitWidth + 16
                            Layout.preferredHeight: 20
                            radius: 10
                            color: Qt.rgba(st.focusTone.r, st.focusTone.g, st.focusTone.b, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(st.focusTone.r, st.focusTone.g, st.focusTone.b, 0.28)

                            Text {
                                id: focusStatus
                                anchors.centerIn: parent
                                text: !st.core.focusOn
                                    ? "READY"
                                    : st.core.focusPaused
                                        ? "PAUSED"
                                        : st.core.focusBreak ? "BREAK" : "RUNNING"
                                color: st.focusTone
                                font.family: st.core.monoFont
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    ColumnLayout {
                        visible: !st.core.focusOn
                        Layout.fillWidth: true
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Text {
                                text: "PRESETS"
                                color: st.core.dim
                                font.family: st.core.monoFont
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }

                            FocusButton {
                                labelText: "25 / 5"
                                primary: st.focusPreset === "25/5"
                                tone: st.core.teal
                                onTriggered: st.applyFocusPreset(25, 5, "25/5")
                            }

                            FocusButton {
                                labelText: "50 / 10"
                                primary: st.focusPreset === "50/10"
                                tone: st.core.teal
                                onTriggered: st.applyFocusPreset(50, 10, "50/10")
                            }

                            FocusButton {
                                labelText: "90 / 15"
                                primary: st.focusPreset === "90/15"
                                tone: st.core.teal
                                onTriggered: st.applyFocusPreset(90, 15, "90/15")
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            FocusInput {
                                labelText: "WORK MIN"
                                valueText: st.focusWorkInput
                                onValueEdited: value => {
                                    st.focusWorkInput = value
                                    st.focusPreset = ""
                                    st.focusError = ""
                                }
                            }

                            FocusInput {
                                labelText: "BREAK MIN"
                                valueText: st.focusBreakInput
                                onValueEdited: value => {
                                    st.focusBreakInput = value
                                    st.focusPreset = ""
                                    st.focusError = ""
                                }
                            }

                            FocusInput {
                                labelText: "SESSIONS"
                                valueText: st.focusCountInput
                                onValueEdited: value => {
                                    st.focusCountInput = value
                                    st.focusError = ""
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            FocusInput {
                                Layout.fillWidth: true
                                labelText: "TITLE (OPTIONAL)"
                                numeric: false
                                valueText: st.focusTitleInput
                                onValueEdited: value => st.focusTitleInput = value
                            }

                            FocusButton {
                                Layout.alignment: Qt.AlignBottom
                                labelText: "START FOCUS"
                                primary: true
                                enabled: st.focusInputsValid
                                tone: st.core.teal
                                onTriggered: st.startFocusFromCard()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: st.focusError !== ""
                            text: st.focusError
                            color: st.core.coral
                            font.family: st.core.monoFont
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        visible: st.core.focusOn
                        Layout.fillWidth: true
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: st.core.focusBreak ? "BREAK" : "FOCUS"
                                color: st.focusTone
                                font.family: st.core.monoFont
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.8
                            }

                            Text {
                                Layout.fillWidth: true
                                text: st.core.focusPaused ? "Paused" : "Session " + st.core.focusSessionIndex + " / " + st.core.focusSessionCount
                                color: st.core.dim
                                font.family: st.core.monoFont
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            Text {
                                text: st.core.fmt(st.core.focusRemaining)
                                color: st.core.text
                                font.family: st.core.monoFont
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.09)

                            Rectangle {
                                width: parent.width * st.focusProgress
                                height: parent.height
                                radius: parent.radius
                                color: st.focusTone
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: st.core.focusTitle !== "" ? st.core.focusTitle : "FOCUS SESSION"
                                color: st.core.text
                                font.family: st.core.uiFont
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            FocusButton {
                                labelText: st.core.focusPaused ? "RESUME" : "PAUSE"
                                tone: st.core.teal
                                onTriggered: st.core.focusPaused ? st.core.resumeFocus() : st.core.pauseFocus()
                            }

                            FocusButton {
                                labelText: "SKIP"
                                tone: st.core.text
                                onTriggered: st.core.skipFocus()
                            }

                            FocusButton {
                                labelText: "STOP"
                                tone: st.core.coral
                                onTriggered: st.core.stopFocus()
                            }
                        }
                    }
                }
            }

            // 2x3 Grid of Toggle Tiles
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                uniformCellWidths: true

                ToggleTile {
                    iconName: st.wifiEnabled ? "wifi" : "wifi_off"
                    iconAlt: "W"
                    titleText: "Wi-Fi"
                    subText: !st.hasNmcli ? "" : (st.wifiEnabled ? (st.wifiSsid !== "" ? st.wifiSsid : "On") : "Off")
                    trailIcon: "chevron_right"
                    trailAlt: ">"
                    tileOn: st.wifiEnabled
                    tileAvailable: st.hasNmcli
                    onToggled: st.toggleWifi()
                    onTrailClicked: st.openSettings("network")
                }

                ToggleTile {
                    iconName: st.btEnabled ? "bluetooth" : "bluetooth_disabled"
                    iconAlt: "B"
                    titleText: "Bluetooth"
                    subText: !st.hasBt ? "" : (st.btEnabled ? (st.btDevice !== "" ? st.btDevice : "On") : "Off")
                    trailIcon: "chevron_right"
                    trailAlt: ">"
                    tileOn: st.btEnabled
                    tileAvailable: st.hasBt
                    onToggled: st.toggleBluetooth()
                    onTrailClicked: st.openSettings("network")
                }

                ToggleTile {
                    iconName: "nightlight"
                    iconAlt: "N"
                    titleText: "Night light"
                    subText: !st.hasSunset ? "" : (st.nightLightOn ? (st.nightKelvin > 0 ? (st.nightKelvin + "K Shift") : "On") : "Off")
                    trailIcon: "tune"
                    trailAlt: "*"
                    tileOn: st.nightLightOn
                    tileAvailable: st.hasSunset
                    onToggled: st.toggleNightLight()
                    onTrailClicked: st.cycleNightKelvin()
                }

                ToggleTile {
                    iconName: "notifications_off"
                    iconAlt: "D"
                    titleText: "Do not disturb"
                    subText: st.core.dnd ? (st.core.held.length > 0 ? (st.core.held.length + " held") : "On") : "Off"
                    tileOn: st.core.dnd
                    tileAvailable: true
                    onToggled: st.core.setDnd(!st.core.dnd)
                }

                ToggleTile {
                    iconName: "timer"
                    iconAlt: "I"
                    titleText: "Idle lock"
                    subText: st.idleSubtitle
                    tileOn: st.idleDaemonOn
                    tileAvailable: st.hasIdleTool
                    onToggled: st.toggleIdleLock()
                }

                ToggleTile {
                    iconName: "flight"
                    iconAlt: "F"
                    titleText: "Flight mode"
                    subText: st.flightMode ? "Enabled" : "Disabled"
                    tileOn: st.flightMode
                    tileAvailable: st.hasNmcli || st.hasBt
                    onToggled: st.toggleFlightMode()
                }
            }

            // Sliders Matrix (Volume & Brightness)
            Rectangle {
                visible: st.core.sinkAudio !== null || st.brightAvailable
                Layout.fillWidth: true
                implicitHeight: slidersCol.implicitHeight + 20
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.04)

                ColumnLayout {
                    id: slidersCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    SliderRow {
                        visible: st.core.sinkAudio !== null
                        iconName: st.core.volIcon()
                        iconAlt: "V"
                        tone: st.core.muted ? st.core.dim : st.core.teal
                        value: st.liveVol
                        maxValue: 1.5
                        labelText: st.core.muted ? "Mute" : (Math.round(st.liveVol * 100) + "%")
                        onIconClicked: if (st.core.sinkAudio) st.core.sinkAudio.muted = !st.core.sinkAudio.muted
                        onMoved: v => {
                            st.dragVol = v
                            st.applyVolume(v)
                        }
                        onReleased: v => {
                            st.applyVolume(v)
                            st.dragVol = -1
                        }
                    }

                    SliderRow {
                        visible: st.brightAvailable
                        iconName: "light_mode"
                        iconAlt: "L"
                        tone: st.core.amber
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

            // Bottom Session Strip
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
                        color: st.core.dim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: st.sessionSummary
                        font.family: st.core.monoFont
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        color: st.core.dim
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
                        onTriggered: st.lockScreen()
                    }

                    ActionCircle {
                        iconName: "bedtime"
                        iconAlt: "Z"
                        onTriggered: st.suspendSystem()
                    }

                    ActionCircle {
                        iconName: st.confirmPower ? "check" : "power_settings_new"
                        iconAlt: st.confirmPower ? "!" : "P"
                        danger: true
                        armed: st.confirmPower
                        onTriggered: st.triggerPower()
                    }
                }
            }
        }
    }
}
}
