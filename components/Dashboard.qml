import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import Quickshell.Services.Pipewire
import qs.config

PanelWindow {
    id: root

    property var hub: null
    property bool isOpen: false
    property string activeTab: "Home"
    property string vibe: "Chill"
    property bool wifiOn: true
    property bool bluetoothOn: true
    property bool replayOn: false
    property bool dndOn: false
    property bool sunsetOn: false
    property bool flightOn: false
    property string cpuModel: "Detecting CPU…"
    property string cpuTemp: "—"
    property string cpuUsage: "—"
    property string gpuModel: "Detecting GPU…"
    property string ramUsage: "Detecting RAM…"
    property string wifiSsid: "Offline"
    property string audioSink: "Detecting audio sink…"
    property string mediaArtist: ""
    property string mediaTitle: "No media playing"
    property string mediaStatus: "Stopped"
    readonly property var tabs: ["Home", "Media", "System", "Tools"]

    function toggle() { root.isOpen = !root.isOpen }
    function close() { root.isOpen = false }
    function setVibe(mode) {
        root.vibe = mode
        Quickshell.execDetached(["/home/rice/Projects/my-rice/scripts/vibe_switch.sh", mode.toLowerCase()])
    }
    function toggleFlag(name) { root[name] = !root[name] }

    anchors { top: true; bottom: true; right: true }
    margins { top: 8; bottom: 8; right: 10 }
    implicitWidth: 440
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Process {
        id: cpuProbe
        command: ["sh", "-c", "awk -F: '/^model name/{gsub(/^ /, \"\", $2); print $2; exit}' /proc/cpuinfo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const model = this.text.trim()
                if (model !== "") root.cpuModel = model
            }
        }
    }

    Process {
        id: gpuProbe
        command: ["sh", "-c", "lspci | grep -Ei 'vga|3d|display' | head -n 1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const model = this.text.trim()
                if (model !== "") root.gpuModel = model
            }
        }
    }

    Process {
        id: cpuTelemetryProbe
        command: ["sh", "-c", "temp=\"\"; for zone in /sys/class/thermal/thermal_zone*/temp; do [ -r \"$zone\" ] || continue; value=$(cat \"$zone\"); case \"$value\" in ''|*[!0-9]*) continue;; esac; [ \"$value\" -gt 1000 ] && temp=\"$((value / 1000))°C\" && break; done; awk -v temp=\"$temp\" '/^cpu /{total=$2+$3+$4+$5+$6+$7+$8+$9; idle=$5+$6; printf \"%s|%d%%\\n\", temp, (total > 0 ? (100 * (total - idle) / total) : 0); exit}' /proc/stat"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = this.text.trim().split("|")
                if (fields.length === 2) {
                    root.cpuTemp = fields[0] !== "" ? fields[0] : "—"
                    root.cpuUsage = fields[1]
                }
            }
        }
    }

    Process {
        id: ramProbe
        command: ["sh", "-c", "awk '/MemTotal:/{total=$2} /MemAvailable:/{available=$2} END {used=total-available; printf \"%.1f / %.1f GB|%d%%\\n\", used/1024/1024, total/1024/1024, (total > 0 ? 100*used/total : 0)}' /proc/meminfo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                if (value !== "") root.ramUsage = value
            }
        }
    }

    Process {
        id: wifiProbe
        command: ["sh", "-c", "nmcli -t -f active,ssid dev wifi | awk -F: '$1 == \"yes\" {print $2; exit}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                root.wifiSsid = value !== "" ? value : "Offline"
            }
        }
    }

    Process {
        id: audioProbe
        command: ["sh", "-c", "wpctl status | awk '/Sources:/ {section=0} /Sinks:/ {section=1; next} section && /[0-9]+\\./ {gsub(/[│├─*]/, \"\", $0); print; exit}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                if (value !== "") root.audioSink = value
            }
        }
    }

    Process {
        id: mediaProbe
        command: ["playerctl", "metadata", "--format", "{{status}}|{{artist}}|{{title}}"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = this.text.trim().split("|")
                if (fields.length >= 3) {
                    root.mediaStatus = fields[0]
                    root.mediaArtist = fields[1]
                    root.mediaTitle = fields[2] !== "" ? fields[2] : "Unknown track"
                } else {
                    root.mediaStatus = "Stopped"
                    root.mediaArtist = ""
                    root.mediaTitle = "No media playing"
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (!cpuTelemetryProbe.running) cpuTelemetryProbe.running = true
            if (!ramProbe.running) ramProbe.running = true
            if (!wifiProbe.running) wifiProbe.running = true
            if (!audioProbe.running) audioProbe.running = true
            if (!mediaProbe.running) mediaProbe.running = true
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 350
        repeat: false
        onTriggered: root.isOpen = false
    }

    Shortcut { sequence: "Super+D"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.isOpen; onActivated: root.close() }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        MouseArea {
            anchors.fill: parent
            z: 20
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: autoCloseTimer.stop()
            onExited: autoCloseTimer.start()
        }

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            Row {
                width: parent.width
                Text { text: "AETHERIC DASHBOARD"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 14; font.bold: true }
                Item { width: parent.width - 190; height: 1 }
                Text { text: "SUPER+D"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
            }

            Row {
                width: parent.width
                height: 34
                spacing: 4
                Repeater {
                    model: root.tabs
                    delegate: Rectangle {
                        required property string modelData
                        width: (parent.width - 12) / 4
                        height: 34
                        radius: Theme.radiusPill
                        color: root.activeTab === modelData ? Theme.brandAccent : Theme.card
                        Text { anchors.centerIn: parent; text: modelData; color: root.activeTab === modelData ? Theme.brandAccentFg : Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.activeTab = modelData }
                    }
                }
            }

            Loader {
                width: parent.width
                height: parent.height - 96
                sourceComponent: root.activeTab === "Home" ? homeTab : root.activeTab === "Media" ? mediaTab : root.activeTab === "System" ? systemTab : toolsTab
            }
        }
    }

    Component {
        id: homeTab
        Flickable {
            contentWidth: width
            contentHeight: homeColumn.implicitHeight
            clip: true
            Column {
                id: homeColumn
                width: parent.width
                spacing: 12

                SectionLabel { text: "COMPOSITOR VIBE" }
                Row {
                    spacing: 5
                    Repeater {
                        model: ["Study", "Gaming", "Chill", "Night"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 82; height: 30; radius: Theme.radiusPill
                            color: root.vibe === modelData ? Theme.brandAccent : Theme.card
                            Text { anchors.centerIn: parent; text: modelData; color: root.vibe === modelData ? Theme.brandAccentFg : Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: root.setVibe(modelData) }
                        }
                    }
                }

                SectionLabel { text: "SCREEN TIME · TODAY" }
                Rectangle {
                    width: parent.width; height: 122; radius: 12; color: Theme.card; border.width: 1; border.color: Theme.border
                    Column {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                        Row {
                            width: parent.width
                            Text { text: "5h 42m"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 25; font.bold: true }
                            Item { width: parent.width - 170; height: 1 }
                            Text { text: "target 7h"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
                        }
                        Text { text: "+12m vs yesterday"; color: Theme.statusGood; font.family: Theme.fontUi; font.pixelSize: 10 }
                        Row {
                            width: parent.width; height: 12; spacing: 2
                            BarSegment { ratio: .48; color: Theme.brandAccent }
                            BarSegment { ratio: .28; color: "#C084FC" }
                            BarSegment { ratio: .15; color: "#FFD47B" }
                            BarSegment { ratio: .09; color: "#F28FAD" }
                        }
                        Text { text: "ghostty 48%   ·   zen-browser 28%   ·   spotify 15%   ·   obsidian 9%"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                    }
                }

                SectionLabel { text: "HARDWARE TELEMETRY" }
                Row {
                    width: parent.width; spacing: 6
                    TelemetryCard { title: "CPU"; device: root.cpuModel; value: root.cpuUsage; detail: root.cpuTemp }
                    TelemetryCard { title: "GPU"; device: root.gpuModel; value: "active"; detail: "lspci" }
                    TelemetryCard { title: "RAM"; device: "Memory"; value: root.ramUsage.split("|")[1] || "—"; detail: root.ramUsage.split("|")[0] || "—" }
                }

                SectionLabel { text: "QUICK TOGGLES" }
                Grid {
                    width: parent.width; columns: 2; rowSpacing: 6; columnSpacing: 6
                    ToggleCard { label: "Wi-Fi"; value: root.wifiSsid; enabledState: root.wifiOn; onToggled: root.toggleFlag("wifiOn") }
                    ToggleCard { label: "Bluetooth"; value: root.hub && root.hub.btConnectedName !== "" ? root.hub.btConnectedName : "No device connected"; enabledState: root.bluetoothOn; onToggled: root.toggleFlag("bluetoothOn") }
                    ToggleCard { label: "Replay Buffer"; value: "OBS capture"; enabledState: root.replayOn; onToggled: root.toggleFlag("replayOn") }
                    ToggleCard { label: "Do Not Disturb"; value: "Notifications"; enabledState: root.dndOn; onToggled: root.toggleFlag("dndOn") }
                    ToggleCard { label: "Hyprsunset"; value: "3200K"; enabledState: root.sunsetOn; onToggled: root.toggleFlag("sunsetOn") }
                    ToggleCard { label: "Flight Mode"; value: "All radios"; enabledState: root.flightOn; onToggled: root.toggleFlag("flightOn") }
                }

                SectionLabel { text: "NOW PLAYING" }
                MediaMini {}
            }
        }
    }

    Component {
        id: mediaTab
        Column {
            width: parent.width; spacing: 14
            SectionLabel { text: "PIPEWIRE MEDIA" }
            MediaMini { expanded: true }
            Rectangle { width: parent.width; height: 8; radius: 4; color: Theme.card; Rectangle { width: parent.width * .42; height: parent.height; radius: 4; color: Theme.brandAccent } }
            Row {
                width: parent.width
                Text { text: "01:42"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
                Item { width: parent.width - 90; height: 1 }
                Text { text: "04:18"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
            }
            Text { text: "LIVE LYRIC FEED"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }
            Rectangle {
                width: parent.width; height: 250; radius: 12; color: Theme.card; border.width: 1; border.color: Theme.border
                Column {
                    anchors.centerIn: parent; spacing: 12
                    Text { text: root.mediaStatus === "Playing" ? root.mediaTitle : "No synchronized lyrics"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 13 }
                    Text { text: root.mediaArtist !== "" ? root.mediaArtist : root.mediaStatus; color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: 17; font.bold: true }
                    Text { text: "Lyrics provider unavailable"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 13 }
                }
            }
        }
    }

    Component {
        id: systemTab
        Column {
            width: parent.width; spacing: 12
            SectionLabel { text: "WIREPLUMBER ROUTING" }
            RouteCard { title: root.audioSink; detail: "Default output from wpctl status"; active: true }
            RouteCard { title: "PipeWire device graph"; detail: "Run wpctl status for routing"; active: false }
            SectionLabel { text: "LIVE STATE" }
            InfoRow { label: "PipeWire"; value: "Running"; accent: Theme.statusGood }
            InfoRow { label: "Audio sink"; value: root.audioSink; accent: Theme.brandAccent }
            InfoRow { label: "Power profile"; value: root.hub ? root.hub.powerProfile : "balanced"; accent: Theme.statusWarn }
            InfoRow { label: "Network"; value: root.hub ? root.hub.netName : "Offline"; accent: Theme.textMuted }
        }
    }

    Component {
        id: toolsTab
        Column {
            width: parent.width; spacing: 10
            SectionLabel { text: "FAST UTILITIES" }
            ToolButton { label: "Screenshot"; command: "grimblast"; onTriggered: if (root.hub) root.hub.triggerScreenshot() }
            ToolButton { label: "Color picker"; command: "hyprpicker"; onTriggered: Quickshell.execDetached(["hyprpicker", "-a"]) }
            ToolButton { label: "Extract wallpaper theme"; command: "extract-theme.py"; onTriggered: Quickshell.execDetached(["/home/rice/Projects/my-rice/scripts/extract-theme.py"]) }
            SectionLabel { text: "DASHBOARD STATE" }
            InfoRow { label: "Geometry"; value: "440 × full-height"; accent: Theme.brandAccent }
            InfoRow { label: "Animation"; value: "OutCubic · 280ms"; accent: Theme.textMuted }
            InfoRow { label: "Notification bus"; value: "Tide Island owner"; accent: Theme.statusGood }
        }
    }

    component SectionLabel: Text { color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }
    component BarSegment: Rectangle { property real ratio: .25; width: parent ? parent.width * ratio - 2 : 20; height: 12; radius: 4 }
    component TelemetryCard: Rectangle {
        property string title: ""; property string device: ""; property string value: ""; property string detail: ""
        width: 126; height: 74; radius: 10; color: Theme.card; border.width: 1; border.color: Theme.border
        Column {
            anchors.fill: parent; anchors.margins: 8; spacing: 3
            Text { text: title; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }
            Text { text: device; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
            Text { text: value + "  ·  " + detail; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 }
        }
    }
    component ToggleCard: Rectangle {
        property string label: ""; property string value: ""; property bool enabledState: false; signal toggled()
        width: 195; height: 48; radius: 10; color: enabledState ? "#243B3A" : Theme.card; border.width: 1; border.color: enabledState ? Theme.brandAccent : Theme.border
        Column {
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 2
            Text { text: label; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }
            Text { text: value; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 16; radius: 8; color: enabledState ? Theme.brandAccent : Theme.border
            Rectangle { x: enabledState ? 14 : 2; y: 2; width: 12; height: 12; radius: 6; color: enabledState ? Theme.brandAccentFg : Theme.textMuted; Behavior on x { NumberAnimation { duration: 120 } } }
        }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }
    component RouteCard: Rectangle {
        property string title: ""; property string detail: ""; property bool active: false
        width: parent ? parent.width : 400; height: 58; radius: 10; color: Theme.card; border.width: 1; border.color: active ? Theme.brandAccent : Theme.border
        Column {
            anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Text { text: title; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
            Text { text: detail; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
        }
        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: active ? "DEFAULT" : "STANDBY"; color: active ? Theme.brandAccent : Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }
    }
    component InfoRow: Row {
        property string label: ""; property string value: ""; property color accent: Theme.textMuted
        width: parent ? parent.width : 400; height: 28
        Text { text: label; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10 }
        Item { width: parent.width - valueText.implicitWidth - 8; height: 1 }
        Text { id: valueText; text: value; color: accent; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true }
    }
    component ToolButton: Rectangle {
        property string label: ""; property string command: ""; signal triggered()
        width: parent ? parent.width : 400; height: 48; radius: 10; color: mouse.containsMouse ? Theme.cardHover : Theme.card; border.width: 1; border.color: mouse.containsMouse ? Theme.brandAccent : Theme.border
        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: label; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }
        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: command; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 9 }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.triggered() }
    }
    component MediaMini: Rectangle {
        property bool expanded: false
        width: parent ? parent.width : 400; height: expanded ? 220 : 116; radius: 12; color: Theme.card; border.width: 1; border.color: Theme.border
        Row {
            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 14
            Rectangle {
                width: expanded ? 110 : 70; height: expanded ? 110 : 70; radius: width / 2; color: "#172D32"; border.width: 2; border.color: Theme.brandAccent
                Text { anchors.centerIn: parent; text: "◉"; color: Theme.brandAccent; font.pixelSize: expanded ? 42 : 28 }
            }
            Column {
                width: parent.width - (expanded ? 160 : 100); anchors.verticalCenter: parent.verticalCenter; spacing: 7
                Text { text: root.mediaTitle; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; width: parent.width }
                Text { text: root.mediaArtist !== "" ? root.mediaArtist : root.mediaStatus; color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                Text { text: expanded ? (root.mediaStatus === "Playing" ? "♫  playing · synchronized lyrics unavailable" : "♫  " + root.mediaStatus) : "♫  " + root.mediaStatus; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; wrapMode: Text.WordWrap; width: parent.width }
            }
        }
    }
}
