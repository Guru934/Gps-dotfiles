import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import qs.config

// Compact Power & Battery popup docked immediately right of the Left Rail,
// vertically anchored near the rail battery pill (hub.popupAnchorY, clamped
// on-screen). Battery telemetry comes from the shared UPower service; the
// profile list and writes come from the live power-profiles-daemon via
// powerprofilesctl (the same backend the System tab drives) and every write
// is re-read before it is reported as active. No fabricated values.
PanelWindow {
    id: root
    property var hub: null

    // --- Battery telemetry (UPower) -------------------------------------
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
    readonly property string battTimeText: {
        if (!root.batPresent) return ""
        if (root.battCharging && !root.battFull && batDevice.timeToFull > 0)
            return root.fmtDuration(batDevice.timeToFull) + " to full"
        if (batDevice.state === UPowerDeviceState.Discharging && batDevice.timeToEmpty > 0)
            return root.fmtDuration(batDevice.timeToEmpty) + " remaining"
        return ""
    }
    readonly property string battHealthText: {
        if (!root.batPresent) return ""
        const hp = batDevice.healthPercentage
        if (!(hp > 0)) return ""
        const h = hp <= 1.0 ? Math.round(hp * 100) : Math.round(hp)
        return "Health " + h + "%"
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
        if (root.battCharging || root.battFull) return Theme.brandAccent
        if (root.battPct <= 15) return Theme.statusDanger
        if (root.battPct <= 30) return Theme.statusWarn
        return Theme.statusGood
    }

    function fmtDuration(sec) {
        if (!sec || sec <= 0 || !isFinite(sec)) return ""
        const h = Math.floor(sec / 3600)
        const m = Math.round((sec % 3600) / 60)
        return h > 0 ? (h + "h " + m + "m") : (m + "m")
    }

    function profileAccent(id) {
        if (id === "performance") return Theme.statusDanger
        if (id === "balanced") return Theme.brandAccent
        if (id === "power-saver") return Theme.statusGood
        return Theme.accentSecondary
    }

    function profileLabel(id) {
        return id.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
    }

    // --- Power profiles (live powerprofilesctl, verified writes) --------
    property var profiles: []
    property string activeProfile: ""
    property string profileDriver: ""
    property string pendingProfile: ""
    property bool profileBusy: false
    property string profileError: ""
    property int verifyTries: 0

    function refreshProfiles() {
        if (!listProc.running) listProc.running = true
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
        if (act) root.activeProfile = act.id
        // Confirmation only after the daemon reports the requested profile
        // active; the verify timer keeps re-reading until then or gives up.
        if (root.pendingProfile !== "" && root.activeProfile === root.pendingProfile) {
            root.pendingProfile = ""
            root.profileBusy = false
            root.profileError = ""
            verifyTimer.stop()
        }
    }

    function setProfile(id) {
        if (!id || root.profileBusy || id === root.activeProfile) return
        root.profileBusy = true
        root.profileError = ""
        root.pendingProfile = id
        root.verifyTries = 0
        setProc.command = ["powerprofilesctl", "set", id]
        setProc.running = true
    }

    function powerProfilesJson() {
        return JSON.stringify({
            current: root.activeProfile,
            driver: root.profileDriver,
            configured: root.hub ? root.hub.powerProfile : "",
            pending: root.pendingProfile,
            error: root.profileError,
            profiles: root.profiles.map(p => ({ id: p.id, active: p.active, degraded: p.degraded }))
        })
    }

    // --- Popup plumbing (same router as Wifi/BT/clock popups) -----------
    readonly property bool isOpen: root.hub
        ? (root.hub.dashboardOpen && root.hub.activePopup === "battery")
        : false
    readonly property var targetScreen: (root.hub && root.hub.popupScreen)
        ? root.hub.popupScreen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    function close() {
        hideTimer.stop()
        if (root.hub) root.hub.closePopup()
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root.profileError = ""
            root.refreshProfiles()
        } else {
            hideTimer.stop()
            verifyTimer.stop()
            root.pendingProfile = ""
            root.profileBusy = false
        }
    }

    screen: targetScreen
    anchors { top: true; left: true }
    margins {
        // Rail is 54 wide; dock with an 8px gap and clamp vertically.
        left: 62
        top: {
            const h = root.height > 0 ? root.height : 400
            const sh = root.targetScreen ? root.targetScreen.height : 900
            const ay = (root.hub && root.hub.popupAnchorY >= 0) ? root.hub.popupAnchorY : Math.round(sh / 2)
            return Math.max(8, Math.min(Math.max(8, sh - h - 8), ay - h / 2))
        }
    }
    implicitWidth: Theme.systemPopupWidth
    implicitHeight: Math.min(430, Math.max(180, mainCol.implicitHeight + 24))
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.isOpen; onActivated: root.close() }

    // Cursor-leave dismissal with a grace period (same as the Wi-Fi popup).
    Timer {
        id: hideTimer
        interval: 350
        repeat: false
        onTriggered: root.close()
    }

    // Re-reads the profile list after a write until the daemon confirms.
    Timer {
        id: verifyTimer
        interval: 350
        repeat: true
        onTriggered: {
            root.verifyTries += 1
            if (root.verifyTries >= 8) {
                stop()
                if (root.pendingProfile !== "") {
                    root.profileBusy = false
                    root.pendingProfile = ""
                    if (root.profileError === "")
                        root.profileError = "could not confirm profile switch"
                }
                return
            }
            root.refreshProfiles()
        }
    }

    Process {
        id: listProc
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
        id: setProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.profileError === "")
                    root.profileError = text.trim().split("\n")[0]
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.verifyTries = 0
                verifyTimer.start()
            } else {
                root.profileBusy = false
                root.pendingProfile = ""
                if (root.profileError === "")
                    root.profileError = "powerprofilesctl set failed (exit " + code + ")"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: root.batteryColor()

        MouseArea {
            anchors.fill: parent
            z: 20
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: hideTimer.stop()
            onExited: hideTimer.start()
        }

        Column {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header: title + current profile chip
            Item {
                width: parent.width
                height: 26

                Text {
                    text: "POWER & BATTERY"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.scaled(14)
                    font.bold: true
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }

                Rectangle {
                    visible: root.activeProfile !== ""
                    width: chipText.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Theme.card
                    border.width: 1
                    border.color: root.profileAccent(root.activeProfile)
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: root.activeProfile.toUpperCase()
                        color: root.profileAccent(root.activeProfile)
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.scaled(9)
                        font.bold: true
                    }
                }
            }

            // Battery block (real telemetry; hidden when no battery present)
            Rectangle {
                visible: root.batPresent
                width: parent.width
                height: batInner.implicitHeight + 22
                radius: 10
                color: Theme.card
                border.width: 1
                border.color: Theme.border

                Row {
                    id: batInner
                    anchors.centerIn: parent
                    spacing: 14

                    Text {
                        text: root.batteryGlyph()
                        color: root.batteryColor()
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.scaled(30)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: root.battPct + "%"
                            color: Theme.textMain
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.scaled(20)
                            font.bold: true
                        }

                        Text {
                            text: {
                                let line = root.battStatusText
                                if (root.battTimeText !== "") line += " · " + root.battTimeText
                                return line
                            }
                            color: root.batteryColor()
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.scaled(11)
                        }

                        Text {
                            visible: root.battHealthText !== ""
                            text: root.battHealthText
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.scaled(10)
                        }
                    }
                }
            }

            // No-battery honest notice
            Text {
                visible: !root.batPresent
                width: parent.width
                text: "No battery detected on this device."
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.scaled(11)
                wrapMode: Text.WordWrap
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // Section header + real driver
            Item {
                width: parent.width
                height: 16

                Text {
                    text: "POWER PROFILE"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.scaled(10)
                    font.bold: true
                    font.letterSpacing: 1.2
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }

                Text {
                    visible: root.profileDriver !== ""
                    text: "driver: " + root.profileDriver
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.scaled(9)
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                }
            }

            // Profile rows (live list from powerprofilesctl)
            Repeater {
                model: root.profiles

                Rectangle {
                    id: profRow
                    required property var modelData
                    width: mainCol.width
                    height: 36
                    radius: 9
                    color: profRow.modelData.active
                        ? Qt.rgba(root.profileAccent(profRow.modelData.id).r, root.profileAccent(profRow.modelData.id).g, root.profileAccent(profRow.modelData.id).b, 0.16)
                        : (profMouse.containsMouse ? Theme.cardHover : Theme.card)
                    border.width: 1
                    border.color: profRow.modelData.active
                        ? root.profileAccent(profRow.modelData.id)
                        : (profMouse.containsMouse ? root.profileAccent(profRow.modelData.id) : Theme.border)

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
                            text: "●"
                            color: root.profileAccent(profRow.modelData.id)
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.scaled(12)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.profileLabel(profRow.modelData.id)
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.scaled(12)
                            font.bold: profRow.modelData.active || profMouse.containsMouse
                        }

                        Rectangle {
                            visible: profRow.modelData.degraded
                            anchors.verticalCenter: parent.verticalCenter
                            width: degText.implicitWidth + 10
                            height: 16
                            radius: Theme.radiusSm
                            color: Qt.alpha(Theme.statusWarn, 0.16)
                            border.width: Theme.borderWidth
                            border.color: Theme.statusWarn

                            Text {
                                id: degText
                                anchors.centerIn: parent
                                text: "degraded"
                                color: Theme.statusWarn
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.scaled(8)
                            }
                        }
                    }

                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.pendingProfile === profRow.modelData.id ? "…" : (profRow.modelData.active ? "✓" : "")
                        color: root.pendingProfile === profRow.modelData.id
                            ? "#F5C17A"
                            : root.profileAccent(profRow.modelData.id)
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.scaled(12)
                        font.bold: true
                    }

                    MouseArea {
                        id: profMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfile(profRow.modelData.id)
                    }
                }
            }

            // Empty state (honest) when the daemon lists nothing
            Text {
                visible: root.profiles.length === 0 && root.profileError === ""
                width: parent.width
                text: "No power profiles available — is power-profiles-daemon running?"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.scaled(11)
                wrapMode: Text.WordWrap
            }

            // Error line (real stderr / exit status only)
            Text {
                visible: root.profileError !== ""
                width: parent.width
                text: root.profileError
                color: "#FF5C77"
                font.family: Theme.fontUi
                font.pixelSize: Theme.scaled(11)
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "applied via powerprofilesctl · power-profiles-daemon"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.scaled(9)
            }
        }
    }
}
