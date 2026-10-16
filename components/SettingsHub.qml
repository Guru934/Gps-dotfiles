import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.config

PanelWindow {
    id: root

    property bool isOpen: false
    property string cpuModel: "Detecting CPU…"
    property string gpuModel: "Detecting GPU…"
    property string displayInfo: "Detecting display…"
    property string audioInfo: "Detecting audio…"
    property string ollamaState: "Checking local Ollama…"

    function toggle() {
        root.isOpen = !root.isOpen
        if (root.isOpen) root.refresh()
    }

    function close() { root.isOpen = false }

    function refresh() {
        if (!cpuProbe.running) cpuProbe.running = true
        if (!gpuProbe.running) gpuProbe.running = true
        if (!displayProbe.running) displayProbe.running = true
        if (!audioProbe.running) audioProbe.running = true
        if (!ollamaProbe.running) ollamaProbe.running = true
    }

    function parseMonitors(raw) {
        try {
            const monitors = JSON.parse(raw)
            if (!Array.isArray(monitors) || monitors.length === 0) {
                root.displayInfo = "No Hyprland monitor detected"
                return
            }
            const monitor = monitors[0]
            const mode = monitor.width && monitor.height ? monitor.width + " × " + monitor.height : "Unknown resolution"
            const refresh = monitor.refreshRate ? " @ " + Math.round(monitor.refreshRate) + " Hz" : ""
            root.displayInfo = (monitor.name || "Monitor") + " · " + mode + refresh
        } catch (error) {
            root.displayInfo = "Hyprland monitor data unavailable"
        }
    }

    function parseOllama(raw) {
        ollamaModels.clear()
        const payload = raw.trim()
        if (payload === "") {
            root.ollamaState = "Ollama offline or unreachable"
            return
        }
        try {
            const models = JSON.parse(payload).models
            if (!Array.isArray(models) || models.length === 0) {
                root.ollamaState = "No local models installed"
                return
            }
            for (let i = 0; i < models.length; i++) {
                const model = models[i]
                const size = model.size ? formatBytes(Number(model.size)) : ""
                ollamaModels.append({
                    name: model.name || model.model || "Unnamed model",
                    detail: size !== "" ? size : (model.details && model.details.family ? model.details.family : "Local model")
                })
            }
            root.ollamaState = models.length + (models.length === 1 ? " local model" : " local models")
        } catch (error) {
            root.ollamaState = "Ollama returned invalid data"
        }
    }

    function formatBytes(bytes) {
        if (!Number.isFinite(bytes) || bytes <= 0) return ""
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = bytes
        let unit = 0
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024
            unit += 1
        }
        return value.toFixed(value >= 10 || unit === 0 ? 0 : 1) + " " + units[unit]
    }

    anchors { top: true; bottom: true; right: true }
    margins { top: 12; bottom: 12; right: 12 }
    implicitWidth: 520
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Process {
        id: cpuProbe
        command: ["sh", "-c", "awk -F: '/^model name/{gsub(/^ /, \"\", $2); print $2; exit}' /proc/cpuinfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                if (value !== "") root.cpuModel = value
            }
        }
    }

    Process {
        id: gpuProbe
        command: ["sh", "-c", "lspci | grep -Ei 'vga|3d|display' | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                root.gpuModel = value !== "" ? value : "No active GPU reported by lspci"
            }
        }
    }

    Process {
        id: displayProbe
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { onStreamFinished: root.parseMonitors(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "") root.displayInfo = "Hyprland monitor data unavailable"
            }
        }
    }

    Process {
        id: audioProbe
        command: ["sh", "-c", "wpctl status | awk '/Sinks:/ {section=1; next} /Sources:/ {section=0} section && /[0-9]+\\./ {gsub(/[│├─*]/, \"\", $0); print; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                root.audioInfo = value !== "" ? value : "No PipeWire sink detected"
            }
        }
    }

    Process {
        id: ollamaProbe
        command: ["curl", "-s", "--max-time", "2", "http://127.0.0.1:11434/api/tags"]
        stdout: StdioCollector { onStreamFinished: root.parseOllama(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "") {
                    ollamaModels.clear()
                    root.ollamaState = "Ollama offline or unreachable"
                }
            }
        }
    }

    ListModel { id: ollamaModels }

    Timer {
        interval: 10000
        running: root.isOpen
        repeat: true
        onTriggered: root.refresh()
    }

    Shortcut { sequence: "Super+comma"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.isOpen; onActivated: root.close() }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; hoverEnabled: true }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Row {
                width: parent.width
                Text { text: "SYSTEM SETTINGS"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 15; font.bold: true }
                Item { width: parent.width - 210; height: 1 }
                Text { text: "SUPER + ,"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
            }

            Text { text: "Live host overview and local AI models"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10 }

            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: [
                        { label: "CPU", value: root.cpuModel },
                        { label: "GPU", value: root.gpuModel },
                        { label: "DISPLAY", value: root.displayInfo },
                        { label: "AUDIO", value: root.audioInfo }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 8) / 2
                        height: 76
                        radius: Theme.radiusCard
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.border
                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 5
                            Text { text: modelData.label; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 9; font.bold: true }
                            Text { width: parent.width; text: modelData.value; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                Text { text: "LOCAL OLLAMA MODELS"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 12; font.bold: true }
                Item { width: parent.width - 190; height: 1 }
                Text { text: root.ollamaState; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8; elide: Text.ElideRight }
            }

            Rectangle {
                width: parent.width
                height: Math.max(100, Math.min(220, ollamaModels.count * 42 + 24))
                radius: Theme.radiusCard
                color: Theme.card
                border.width: 1
                border.color: Theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    Text {
                        width: parent.width
                        visible: ollamaModels.count === 0
                        text: root.ollamaState
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Repeater {
                        model: ollamaModels
                        delegate: Row {
                            required property string name
                            required property string detail
                            width: parent.width
                            height: 34
                            spacing: 8
                            Text { text: "◈"; color: Theme.brandAccent; font.pixelSize: 14 }
                            Column {
                                width: parent.width - 26
                                Text { width: parent.width; text: name; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 10; elide: Text.ElideRight }
                                Text { text: detail; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 1 }
        }
    }
}
