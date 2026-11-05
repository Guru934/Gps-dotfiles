import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root

    // Reference to the Toolbox.qml instance to monitor signals and notify
    property var toolbox: null

    // Project root directory
    readonly property string repoRoot: Quickshell.env("GPS_ROOT")
        || Quickshell.env("GPS_DESKTOP_ROOT")
        || ""

    // Live system facts
    property string hostName: Quickshell.env("HOSTNAME") || Quickshell.env("HOST") || ""
    property string osName: "Linux"
    readonly property string compositorName: "Hyprland"
    readonly property string compositorState: (Hyprland.monitors && Hyprland.monitors.length > 0)
        ? "connected"
        : (Hyprland.activeToplevel !== null ? "connected" : "unknown")

    // Master integration flag - set to true when backend is loaded
    readonly property bool integrationAvailable: true

    // Available action IDs (empty array initially, will be populated from whitelist in Phase 3)
    property var availableActionIds: []

    // Show sample data flag (true in Phase 1, will default to false in Phase 2)
    property bool showSampleData: true

    // Internal tracker for sysinfo line parser
    property int _sysInfoLine: 0

    // Fetch accurate host and OS names asynchronously without shell interpolation
    Process {
        id: sysInfoProc
        command: [
            "python3", "-c",
            "import platform, os\n" +
            "print(platform.node())\n" +
            "name = 'Linux'\n" +
            "if os.path.exists('/etc/os-release'):\n" +
            "    for line in open('/etc/os-release'):\n" +
            "        if line.startswith('PRETTY_NAME='):\n" +
            "            name = line.split('=', 1)[1].strip('\"\\n')\n" +
            "            break\n" +
            "        elif line.startswith('NAME='):\n" +
            "            name = line.split('=', 1)[1].strip('\"\\n')\n" +
            "print(name)\n"
        ]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (!line) return
                if (root._sysInfoLine === 0) {
                    root.hostName = line
                    root._sysInfoLine = 1
                } else if (root._sysInfoLine === 1) {
                    root.osName = line
                    root._sysInfoLine = 2
                }
            }
        }
    }

    // Sound effect trigger (reuses existing gps-sound script)
    function playSound(eventKind) {
        if (!root.repoRoot) return
        Quickshell.execDetached([root.repoRoot + "/scripts/gps-sound", eventKind || "notice"])
    }

    // Helper to send a user notification inside the Toolbox UI
    function notify(title, message, tone) {
        if (root.toolbox && typeof root.toolbox.notify === "function") {
            root.toolbox.notify(title, message, tone || "info")
        }
    }

    // Signal connections to Toolbox.qml
    Connections {
        target: root.toolbox

        function onActionRunRequested(actionId, params) {
            root.notify("Action Requested", "Action '" + actionId + "' execution engine will be wired in Phase 3.", "info")
            root.playSound("action")
        }

        function onSavedItemSaved(item) {
            root.notify("Saved Space", "Saving item '" + (item && item.title ? item.title : "") + "' will persist to JSON in Phase 2.", "info")
            root.playSound("notice")
        }

        function onSavedItemDeleted(id) {
            root.notify("Saved Space", "Deleting item will persist to JSON in Phase 2.", "info")
            root.playSound("notice")
        }

        function onOpenUrlRequested(url) {
            root.notify("URL Requested", "Opening '" + url + "' will be enabled in Phase 2.", "info")
            root.playSound("notice")
        }

        function onAutomationSaved(automation) {
            root.notify("Automations", "Saving automation '" + (automation && automation.name ? automation.name : "") + "' will be wired in Phase 5.", "info")
            root.playSound("notice")
        }

        function onAutomationDeleted(id) {
            root.notify("Automations", "Deleting automation will be wired in Phase 5.", "info")
            root.playSound("notice")
        }

        function onAutomationStateChangeRequested(id, enabled) {
            root.notify("Automations", (enabled ? "Enabling" : "Pausing") + " automation will be wired in Phase 5.", "info")
            root.playSound("notice")
        }

        function onAutomationTestRequested(id) {
            root.notify("Automations", "Testing automation '" + id + "' will be wired in Phase 5.", "info")
            root.playSound("action")
        }

        function onScheduleCancelRequested(id) {
            root.notify("Automations", "Cancelling schedule '" + id + "' will be wired in Phase 5.", "warn")
            root.playSound("warn")
        }

        function onWorkflowSaved(routine) {
            root.notify("Routine Builder", "Workflow '" + (routine && routine.name ? routine.name : "") + "' persistence will be wired in Phase 6.", "info")
            root.playSound("notice")
        }

        function onWorkflowRunRequested(id) {
            root.notify("Routine Builder", "Running workflow '" + id + "' will be wired in Phase 6.", "info")
            root.playSound("action")
        }

        function onPresetActivateRequested(id) {
            root.notify("Workspace Presets", "Activating preset '" + id + "' will be wired in Phase 5.", "info")
            root.playSound("action")
        }

        function onDeviceActionRequested(deviceId, action, params) {
            root.notify("Device Bridge", "Device action '" + action + "' for device '" + deviceId + "' will be wired in Phase 4.", "info")
            root.playSound("action")
        }

        function onSharedLinkDismissed(id) {
            root.notify("Device Bridge", "Dismissing link '" + id + "' will be wired in Phase 4.", "info")
            root.playSound("notice")
        }
    }
}

