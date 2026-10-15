import Quickshell
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
    visible: opacity > 0.01
    opacity: root.isOpen ? 1 : 0
    x: root.isOpen ? 0 : 460
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Shortcut { sequence: "Super+D"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.isOpen; onActivated: root.close() }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

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
                        Row { width: parent.width; Text { text: "5h 42m"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 25; font.bold: true }; Item { width: parent.width - 170; height: 1 }; Text { text: "target 7h"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 } }
                        Text { text: "+12m vs yesterday"; color: Theme.statusGood; font.family: Theme.fontUi; font.pixelSize: 10 }
                        Row { width: parent.width; height: 12; spacing: 2; BarSegment { ratio: .48; color: Theme.brandAccent }; BarSegment { ratio: .28; color: "#C084FC" }; BarSegment { ratio: .15; color: "#FFD47B" }; BarSegment { ratio: .09; color: "#F28FAD" } }
                        Text { text: "ghostty 48%   ·   zen-browser 28%   ·   spotify 15%   ·   obsidian 9%"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                    }
                }

                SectionLabel { text: "HARDWARE TELEMETRY" }
                Row {
                    width: parent.width; spacing: 6
                    TelemetryCard { title: "CPU"; device: "Ryzen 9"; value: "24.8%"; detail: "48°C" }
                    TelemetryCard { title: "GPU"; device: "RTX 4080"; value: "144 FPS"; detail: "51°C" }
                    TelemetryCard { title: "RAM"; device: "DDR5"; value: "13%"; detail: "4.2 / 32GB" }
                }

                SectionLabel { text: "QUICK TOGGLES" }
                Grid {
                    width: parent.width; columns: 2; rowSpacing: 6; columnSpacing: 6
                    ToggleCard { label: "Wi-Fi"; value: "Zenith_5G"; enabledState: root.wifiOn; onToggled: root.toggleFlag("wifiOn") }
                    ToggleCard { label: "Bluetooth"; value: "WH-1000XM5"; enabledState: root.bluetoothOn; onToggled: root.toggleFlag("bluetoothOn") }
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
            Row { width: parent.width; Text { text: "01:42"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }; Item { width: parent.width - 90; height: 1 }; Text { text: "04:18"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 } }
            Text { text: "LIVE LYRIC FEED"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }
            Rectangle { width: parent.width; height: 250; radius: 12; color: Theme.card; border.width: 1; border.color: Theme.border; Column { anchors.centerIn: parent; spacing: 12; Text { text: "I know the night is young"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 13 }; Text { text: "but I can feel the morning"; color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: 17; font.bold: true }; Text { text: "moving through the city lights"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 13 } } }
        }
    }

    Component {
        id: systemTab
        Column {
            width: parent.width; spacing: 12
            SectionLabel { text: "WIREPLUMBER ROUTING" }
            RouteCard { title: "Topping E30 II DAC"; detail: "Default output sink"; active: true }
            RouteCard { title: "Sony WH-1000XM5"; detail: "Standby Bluetooth sink"; active: false }
            SectionLabel { text: "LIVE STATE" }
            InfoRow { label: "PipeWire"; value: "Running"; accent: Theme.statusGood }
            InfoRow { label: "Default volume"; value: root.hub ? root.hub.volumePct + "%" : "—"; accent: Theme.brandAccent }
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
    component TelemetryCard: Rectangle { property string title: ""; property string device: ""; property string value: ""; property string detail: ""; width: 126; height: 74; radius: 10; color: Theme.card; border.width: 1; border.color: Theme.border; Column { anchors.fill: parent; anchors.margins: 8; spacing: 3; Text { text: title; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true }; Text { text: device; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }; Text { text: value + "  ·  " + detail; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 } } }
    component ToggleCard: Rectangle { property string label: ""; property string value: ""; property bool enabledState: false; signal toggled(); width: 195; height: 48; radius: 10; color: enabledState ? "#243B3A" : Theme.card; border.width: 1; border.color: enabledState ? Theme.brandAccent : Theme.border; Column { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: label; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; font.bold: true }; Text { text: value; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 } }; Rectangle { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 16; radius: 8; color: enabledState ? Theme.brandAccent : Theme.border; Rectangle { x: enabledState ? 14 : 2; y: 2; width: 12; height: 12; radius: 6; color: enabledState ? Theme.brandAccentFg : Theme.textMuted; Behavior on x { NumberAnimation { duration: 120 } } } }; MouseArea { anchors.fill: parent; onClicked: parent.toggled() } }
    component RouteCard: Rectangle { property string title: ""; property string detail: ""; property bool active: false; width: parent ? parent.width : 400; height: 58; radius: 10; color: Theme.card; border.width: 1; border.color: active ? Theme.brandAccent : Theme.border; Column { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 3; Text { text: title; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }; Text { text: detail; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 } }; Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: active ? "DEFAULT" : "STANDBY"; color: active ? Theme.brandAccent : Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; font.bold: true } }
    component InfoRow: Row { property string label: ""; property string value: ""; property color accent: Theme.textMuted; width: parent ? parent.width : 400; height: 28; Text { text: label; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10 }; Item { width: parent.width - valueText.implicitWidth - 8; height: 1 }; Text { id: valueText; text: value; color: accent; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true } }
    component ToolButton: Rectangle { property string label: ""; property string command: ""; signal triggered(); width: parent ? parent.width : 400; height: 48; radius: 10; color: mouse.containsMouse ? Theme.cardHover : Theme.card; border.width: 1; border.color: mouse.containsMouse ? Theme.brandAccent : Theme.border; Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: label; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 11; font.bold: true }; Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: command; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 9 }; MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.triggered() } }
    component MediaMini: Rectangle { property bool expanded: false; width: parent ? parent.width : 400; height: expanded ? 220 : 116; radius: 12; color: Theme.card; border.width: 1; border.color: Theme.border; Row { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 14; Rectangle { width: expanded ? 110 : 70; height: expanded ? 110 : 70; radius: width / 2; color: "#172D32"; border.width: 2; border.color: Theme.brandAccent; Text { anchors.centerIn: parent; text: "◉"; color: Theme.brandAccent; font.pixelSize: expanded ? 42 : 28 } }; Column { width: parent.width - (expanded ? 160 : 100); anchors.verticalCenter: parent.verticalCenter; spacing: 7; Text { text: "HOME"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 14; font.bold: true }; Text { text: "Odyssey"; color: Theme.brandAccent; font.family: Theme.fontUi; font.pixelSize: 10 }; Text { text: expanded ? "We are moving through the night…\nA synchronized lyric feed is ready." : "♫  live lyrics · PipeWire"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; wrapMode: Text.WordWrap } } } }
}
