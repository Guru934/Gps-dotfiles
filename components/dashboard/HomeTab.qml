import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.config
import qs.components.dashboard
import "../WifiStatus.js" as WifiStatus
import "../BluetoothStatus.js" as BluetoothStatus

// Home tab: live system overview, quick controls, now playing and clock.
// All data comes from native services or the SysProbe (one shared shell tick
// per second, started/stopped with the drawer). Nothing is fabricated: while
// a service is still connecting the cell renders a neutral placeholder.
Item {
    id: root
    property bool isOpen: false
    property var hub: null

    readonly property string projectPath: Quickshell.env("GPS_ROOT") || ""

    // ----------------------------------------------------------------
    // Night Light state (synchronized with Island via IPC)
    // ----------------------------------------------------------------
    property bool nightLightAvailable: false
    property bool nightLightOn: false
    property int nightLightKelvin: 0
    property int nightLightTargetKelvin: 4000
    property bool nightLightIpcError: false
    property bool nightLightLoaded: false

    function refreshNightLight() {
        if (!nightLightStatusProc.running) {
            nightLightStatusProc.running = true
        }
    }

    function toggleNightLight() {
        if (!nightLightAvailable || nightLightIpcError || nightLightToggleProc.running) return
        nightLightToggleProc.running = true
    }

    function parseNightLightStatus(raw) {
        if (!raw || raw.trim() === "") return
        try {
            const data = JSON.parse(raw.trim())
            if (data && (data.ok === true || typeof data.available !== "undefined")) {
                root.nightLightIpcError = false
                root.nightLightLoaded = true
                root.nightLightAvailable = (data.available === true)
                root.nightLightOn = (data.enabled === true)
                root.nightLightKelvin = Number(data.kelvin) || 0
                root.nightLightTargetKelvin = Number(data.targetKelvin) || 4000
                return
            }
        } catch (e) {}
        root.nightLightIpcError = true
        root.nightLightLoaded = true
    }

    Process {
        id: nightLightStatusProc
        running: false
        command: [
            root.projectPath + "/scripts/gps-ipc",
            "nightlight",
            "status"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseNightLightStatus(text)
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.nightLightIpcError = true
                root.nightLightLoaded = true
            }
        }
    }

    Process {
        id: nightLightToggleProc
        running: false
        command: [
            root.projectPath + "/scripts/gps-ipc",
            "nightlight",
            "toggle"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseNightLightStatus(text)
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.nightLightIpcError = true
            } else {
                nightLightReconcileTimer.restart()
            }
        }
    }

    Timer {
        id: nightLightReconcileTimer
        interval: 450
        repeat: false
        onTriggered: root.refreshNightLight()
    }

    onIsOpenChanged: {
        if (root.isOpen) root.refreshNightLight()
    }

    Component.onCompleted: {
        root.refreshNightLight()
    }

    SystemClock {
        id: clock
        enabled: root.isOpen
        precision: SystemClock.Seconds
    }

    SysProbe {
        id: probe
        active: root.isOpen
        tickMs: root.hub ? root.hub.telemetryTickMs : 1000
    }

    readonly property var wifiStatus: WifiStatus.resolve(
        Networking.backend !== NetworkBackendType.None,
        Networking.devices ? Networking.devices.values : [],
        Networking.wifiEnabled,
        DeviceType.Wifi
    )
    readonly property var wifiNet: root.wifiStatus.connected
        ? root.wifiStatus
        : null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btStatus: BluetoothStatus.resolve(root.btAdapter)
    readonly property var btDevice: root.btAdapter && root.btAdapter.devices
        ? (root.btAdapter.devices.values.find(d => d.connected) || null)
        : null
    readonly property var bat: UPower.displayDevice
    readonly property bool batPresent: root.bat !== null && root.bat.isPresent

    readonly property string activeClient: {
        const t = Hyprland.activeToplevel
        if (!t) return "Desktop"
        const cls = t.lastIpcObject ? (t.lastIpcObject["class"] || "") : ""
        if (cls.length > 0) return cls.charAt(0).toUpperCase() + cls.slice(1)
        return t.title.length > 0 ? t.title : "Desktop"
    }

    function fmtUptime(s) {
        if (s < 0) return "up \u2014"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return "up " + d + "d " + h + "h"
        if (h > 0) return "up " + h + "h " + m + "m"
        return "up " + Math.max(1, m) + "m"
    }

    function fmtDuration(seconds) {
        const s = Math.max(0, Math.round(seconds))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    // Volume slider state: user drags win for a moment, then the probe's
    // measured value takes over again.
    property real volUi: 0
    property real volStamp: 0

    Connections {
        target: probe
        function onVolumeChanged() {
            if (probe.volumeAvailable && Date.now() - root.volStamp > 1200)
                root.volUi = probe.volume
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

    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content
            width: parent.width
            spacing: Theme.dashboardSpacingMd

            // Clock and battery strip.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.dashboardSpacingSm

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Text {
                        text: Qt.formatTime(clock.date, "HH:mm:ss")
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(21)
                        font.bold: true
                    }

                    Text {
                        text: (Qt.formatDate(clock.date, "dddd") + " \u00b7 " + Qt.formatDate(clock.date, "MMM d")).toUpperCase()
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(8)
                        font.letterSpacing: 1
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: batRow.implicitWidth + 16
                    implicitHeight: 34
                    radius: 10
                    color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)
                    opacity: root.batPresent ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    RowLayout {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: 7

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: {
                                if (!root.batPresent) return "battery_full"
                                if (root.bat.state === UPowerDeviceState.Charging) return "battery_charging_full"
                                if (root.bat.percentage <= 0.15) return "battery_alert"
                                return root.bat.percentage >= 0.95 ? "battery_full" : "battery_5_bar"
                            }
                            color: root.batPresent && root.bat.state === UPowerDeviceState.Charging
                                ? Theme.accentPrimary
                                : (root.batPresent && root.bat.percentage <= 0.15 ? Theme.statusDanger : Theme.textMain)
                            font.pixelSize: Theme.dashboardText(17)
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            Text {
                                text: root.batPresent ? Math.round(root.bat.percentage * 100) + "%" : "\u2014"
                                color: Theme.textMain
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(11)
                                font.bold: true
                            }

                            Text {
                                text: {
                                    if (!root.batPresent) return "no battery"
                                    if (root.bat.state === UPowerDeviceState.Charging) return "charging"
                                    if (root.bat.state === UPowerDeviceState.FullyCharged) return "charged"
                                    if (root.bat.state === UPowerDeviceState.Discharging)
                                        return root.bat.timeToEmpty > 0 ? root.fmtDuration(root.bat.timeToEmpty) + " left" : "on battery"
                                    return "on ac"
                                }
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.letterSpacing: 0.5
                            }
                        }
                    }
                }
            }

            FocusCard {
                Layout.fillWidth: true
                isOpen: root.isOpen
            }

            // Telemetry chips.
            DashSurface {
                Layout.fillWidth: true
                fill: Theme.surfaceBase
                radius: 14
                implicitHeight: telemetry.implicitHeight + 20

                ColumnLayout {
                    id: telemetry
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "SYSTEM TELEMETRY"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "POLLING " + Math.round(probe.tickMs / 1000) + "S"
                            color: Theme.accentPrimaryDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        StatCard {
                            Layout.fillWidth: true
                            label: "CPU"
                            value: probe.cpuModel.length > 0 ? probe.cpuModel : "\u2014"
                            pill: probe.cpuTempC >= 0 ? probe.cpuTempC + "\u00b0C" : ""
                            fraction: probe.cpuReady ? probe.cpuUsage / 100 : 0
                            accent: Theme.accentPrimary
                        }

                        StatCard {
                            Layout.fillWidth: true
                            visible: probe.gpuAvailable
                            label: "DGPU"
                            value: probe.gpuName.length > 0 ? probe.gpuName.replace(/^NVIDIA\s+/, "") : "\u2014"
                            pill: probe.gpuTempC >= 0 ? probe.gpuTempC + "\u00b0C" : ""
                            fraction: probe.gpuUsage >= 0 ? probe.gpuUsage / 100 : 0
                            accent: Theme.accentSecondary
                        }

                        StatCard {
                            Layout.fillWidth: true
                            label: "RAM"
                            value: probe.memReady
                                ? (probe.memUsedGiB.toFixed(1) + " / " + probe.memTotalGiB.toFixed(1) + "G")
                                : "\u2014"
                            pill: probe.memPct >= 0 ? probe.memPct + "%" : ""
                            fraction: probe.memPct >= 0 ? probe.memPct / 100 : 0
                            accent: Theme.accentTertiary
                        }
                    }
                }
            }

            // Active session and uptime.
            DashSurface {
                Layout.fillWidth: true
                fill: Theme.surfaceBase
                radius: 14
                implicitHeight: session.implicitHeight + 20

                ColumnLayout {
                    id: session
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "schedule"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(14)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "ACTIVE SESSION & UPTIME"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: kernelText.implicitWidth + 12
                            implicitHeight: 16
                            radius: 8
                            color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.8)

                            Text {
                                id: kernelText
                                anchors.centerIn: parent
                                text: probe.kernel.length > 0 ? probe.kernel : "\u2014"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 10
                        color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.6)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: Theme.dashboardSpacingMd

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    text: "SYSTEM UPTIME"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                    font.letterSpacing: 0.5
                                }

                                Text {
                                    text: root.fmtUptime(probe.uptimeSec)
                                    color: Theme.accentPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(14)
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 1
                                implicitHeight: 24
                                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
                            }

                            Item { Layout.fillWidth: true }

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: "ACTIVE CLIENT"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                    font.letterSpacing: 0.5
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: 5

                                    Text {
                                        text: root.activeClient
                                        color: Theme.textMain
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.dashboardText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 120
                                    }

                                    Rectangle {
                                        visible: Hyprland.focusedWorkspace !== null
                                        implicitWidth: wsText.implicitWidth + 10
                                        implicitHeight: 14
                                        radius: 7
                                        color: Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.18)

                                        Text {
                                            id: wsText
                                            anchors.centerIn: parent
                                            text: Hyprland.focusedWorkspace ? ("ws: " + Hyprland.focusedWorkspace.id) : ""
                                            color: Theme.accentSecondary
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.dashboardText(8)
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Quick controls.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                QuickToggleCard {
                    Layout.fillWidth: true
                    icon: root.wifiStatus.connected
                        ? "wifi"
                        : (root.wifiStatus.available && root.wifiStatus.enabled ? "wifi_find" : "wifi_off")
                    title: root.wifiStatus.connected
                        ? root.wifiStatus.ssid
                        : (!root.wifiStatus.available
                            ? "Wi-Fi unavailable"
                            : (root.wifiStatus.enabled ? "No network" : "Wi-Fi"))
                    subtitle: {
                        if (!root.wifiStatus.available) return "unavailable"
                        if (root.wifiNet !== null) {
                            const strength = Math.round((root.wifiNet.signalStrength || 0) * 100)
                            return strength > 0 ? "connected \u00b7 " + strength + "%" : "connected"
                        }
                        return root.wifiStatus.enabled ? "not connected" : "radio disabled"
                    }
                    accent: Theme.accentPrimary
                    dotColor: root.wifiStatus.connected
                        ? Theme.accentPrimary
                        : (root.wifiStatus.available && root.wifiStatus.enabled
                            ? Theme.accentTertiary
                            : Theme.textDim)
                    interactive: root.wifiStatus.available
                    dimmed: !root.wifiStatus.available
                    onActivated: {
                        if (root.wifiStatus.available) {
                            Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }
                }

                QuickToggleCard {
                    Layout.fillWidth: true
                    icon: !root.btStatus.available
                        ? "bluetooth_disabled"
                        : (root.btStatus.enabled ? "bluetooth" : "bluetooth_disabled")
                    title: !root.btStatus.available
                        ? "Bluetooth unavailable"
                        : (root.btStatus.connected
                            ? root.btStatus.connectedName
                            : (root.btStatus.enabled
                                ? (root.btStatus.discovering ? "Scanning\u2026" : "No device")
                                : "Bluetooth"))
                    subtitle: !root.btStatus.available
                        ? "unavailable"
                        : (root.btStatus.connected
                            ? ("connected" + (root.btDevice && root.btDevice.batteryAvailable ? " \u00b7 " + Math.round(root.btDevice.battery <= 1.0 ? root.btDevice.battery * 100 : root.btDevice.battery) + "%" : ""))
                            : (root.btStatus.connecting
                                ? "connecting\u2026"
                                : (root.btStatus.disconnecting
                                    ? "disconnecting\u2026"
                                    : (root.btStatus.enabled ? "radio on" : "radio off"))))
                    accent: Theme.accentSecondary
                    dotColor: !root.btStatus.available
                        ? Theme.textDim
                        : (root.btStatus.connected
                            ? Theme.accentSecondary
                            : (root.btStatus.enabled ? Theme.accentTertiary : Theme.textDim))
                    interactive: root.btStatus.available
                    dimmed: !root.btStatus.available
                    onActivated: {
                        if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                    }
                }

                QuickToggleCard {
                    Layout.fillWidth: true
                    icon: probe.volumeMuted ? "volume_off" : "volume_up"
                    title: "Audio Output"
                    subtitle: !probe.volumeAvailable
                        ? "\u2026"
                        : (probe.volumeMuted ? "muted \u00b7 " + Math.round(root.volUi * 100) + "%" : "unmuted \u00b7 " + Math.round(root.volUi * 100) + "%")
                    accent: Theme.accentPrimary
                    dotColor: probe.volumeMuted ? Theme.statusDanger : Theme.textDim
                    onActivated: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                }

                QuickToggleCard {
                    Layout.fillWidth: true
                    icon: "nightlight"
                    title: "Night Light"
                    subtitle: {
                        if (root.nightLightIpcError) return "unavailable \u00b7 island offline"
                        if (!root.nightLightLoaded) return "probing\u2026"
                        if (!root.nightLightAvailable) return "unavailable \u00b7 no hyprsunset"
                        if (root.nightLightOn) {
                            return root.nightLightKelvin > 0
                                ? ("on \u00b7 " + root.nightLightKelvin + "K")
                                : "on"
                        }
                        return "off"
                    }
                    accent: Theme.accentTertiary
                    dotColor: {
                        if (root.nightLightIpcError) return Theme.statusDanger
                        if (!root.nightLightAvailable) return Theme.textDim
                        return root.nightLightOn ? Theme.accentTertiary : Theme.textDim
                    }
                    dimmed: !root.nightLightAvailable || root.nightLightIpcError
                    interactive: root.nightLightAvailable && !root.nightLightIpcError
                    onActivated: root.toggleNightLight()
                }
            }

            // Master volume strip.
            DashSurface {
                Layout.fillWidth: true
                fill: Theme.surfaceBase
                radius: 10
                implicitHeight: 34
                visible: probe.volumeAvailable
                opacity: probe.volumeMuted ? 0.6 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: Theme.dashboardSpacingSm

                    DashIcon {
                        Layout.alignment: Qt.AlignVCenter
                        name: probe.volumeMuted ? "volume_off" : "volume_down"
                        color: Theme.textDim
                        font.pixelSize: Theme.dashboardText(15)
                    }

                    DashSlider {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        from: 0
                        to: 1
                        value: root.volUi
                        accent: probe.volumeMuted ? Theme.statusDanger : Theme.accentPrimary
                        onMoved: (v) => root.volumeMoved(v)
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 26
                        text: Math.round(root.volUi * 100) + "%"
                        color: Theme.textMain
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(9)
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            SpectrumCard {
                Layout.fillWidth: true
                isOpen: root.isOpen
            }

            NowPlayingCard {
                Layout.fillWidth: true
                isOpen: root.isOpen
            }

            ScreenTimeCard {
                Layout.fillWidth: true
                isOpen: root.isOpen
            }
        }
    }
}
