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

    // Helper script path
    readonly property string toolboxScript: root.repoRoot
        ? (root.repoRoot + "/scripts/gps-toolbox")
        : "gps-toolbox"

    // Live system facts
    property string hostName: Quickshell.env("HOSTNAME") || Quickshell.env("HOST") || ""
    property string osName: "Linux"
    readonly property string compositorName: "Hyprland"
    readonly property string compositorState: (Hyprland.monitors && Hyprland.monitors.length > 0)
        ? "connected"
        : (Hyprland.activeToplevel !== null ? "connected" : "unknown")

    // Master integration flag - set to true when backend is loaded
    readonly property bool integrationAvailable: true

    // Available action IDs loaded from the reviewed whitelist
    property var availableActionIds: []

    // Show sample data flag: false for real data & honest empty states
    property bool showSampleData: false

    // Saved Space persistent properties
    property var savedItems: []
    property var collections: ["Development", "Linux", "Websites", "Personal"]

    // Activity & History journal events
    property var activityEvents: []

    // Device Bridge persistent and live facts (Phase 4)
    property var devices: []
    property var sharedLinks: []

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

    // --------------------------------------------------------------------------
    // Saved Space background processes
    // --------------------------------------------------------------------------

    Process {
        id: listSavedSpaceProc
        command: [root.toolboxScript, "saved-space", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        if (Array.isArray(res.items)) {
                            root.savedItems = res.items
                            if (root.toolbox) root.toolbox.savedItems = res.items
                        }
                        if (Array.isArray(res.collections)) {
                            root.collections = res.collections
                            if (root.toolbox) root.toolbox.collections = res.collections
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: saveItemProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.items)) {
                        root.savedItems = res.items
                        if (root.toolbox) root.toolbox.savedItems = res.items
                    } else if (res && !res.ok) {
                        root.notify("Failed to save item", res.error || "Unknown error", "err")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: deleteItemProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.items)) {
                        root.savedItems = res.items
                        if (root.toolbox) root.toolbox.savedItems = res.items
                    } else if (res && !res.ok) {
                        root.notify("Failed to delete item", res.error || "Unknown error", "err")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: saveCollsProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        if (Array.isArray(res.collections)) {
                            root.collections = res.collections
                            if (root.toolbox) root.toolbox.collections = res.collections
                        }
                        if (Array.isArray(res.items)) {
                            root.savedItems = res.items
                            if (root.toolbox) root.toolbox.savedItems = res.items
                        }
                    } else if (res && !res.ok) {
                        root.notify("Failed to update collections", res.error || "Unknown error", "err")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: openUrlProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && !res.ok) {
                        root.notify("Failed to open link", res.error || "URL is not allowed for security reasons.", "warn")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    // --------------------------------------------------------------------------
    // Action Whitelist & Activity background processes (Phase 3)
    // --------------------------------------------------------------------------

    Process {
        id: listActionsProc
        command: [root.toolboxScript, "action", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.available_ids)) {
                        root.availableActionIds = res.available_ids
                        if (root.toolbox) root.toolbox.availableActionIds = res.available_ids
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: listActivityProc
        command: [root.toolboxScript, "activity", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.events)) {
                        root.activityEvents = res.events
                        if (root.toolbox) root.toolbox.activityEvents = res.events
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: runActionProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        const evt = res.event || {}
                        const actName = evt.name || res.action || "Action"
                        root.notify(actName, "Completed successfully (" + (res.duration || "0.00s") + ")", "ok")
                        root.reloadActivity()
                    } else if (res && !res.ok) {
                        const errMsg = res.error || (res.requires_confirm ? "Action requires user confirmation" : "Execution failed")
                        root.notify("Action Failed", errMsg, "err")
                        root.playSound("warn")
                        root.reloadActivity()
                    }
                } catch (e) {
                    root.notify("Action Output Error", "Could not parse action response", "err")
                    root.playSound("warn")
                }
            }
        }
    }

    // --------------------------------------------------------------------------
    // Device Bridge background processes (Phase 4)
    // --------------------------------------------------------------------------

    Process {
        id: listDevicesProc
        command: [root.toolboxScript, "device", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.devices)) {
                        root.devices = res.devices
                        if (root.toolbox) root.toolbox.devices = res.devices
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: listLinksProc
        command: [root.toolboxScript, "device", "links"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.links)) {
                        root.sharedLinks = res.links
                        if (root.toolbox) root.toolbox.sharedLinks = res.links
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: deviceActionProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        root.notify("Device Action", "Action '" + res.action + "' executed successfully", "ok")
                        root.reloadActivity()
                    } else if (res && !res.ok) {
                        root.notify("Device Action Failed", res.error || "Device is currently unreachable", "err")
                        root.playSound("warn")
                    }
                } catch (e) {
                    root.notify("Device Action", "Command dispatched", "info")
                }
            }
        }
    }

    Process {
        id: dismissLinkProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.links)) {
                        root.sharedLinks = res.links
                        if (root.toolbox) root.toolbox.sharedLinks = res.links
                    }
                } catch (e) {}
            }
        }
    }

    // Periodic poll for connected devices (10 second interval, cached/background)
    Timer {
        id: devicePollTimer
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.reloadDevices()
    }

    // --------------------------------------------------------------------------
    // Helper functions
    // --------------------------------------------------------------------------

    function reloadSavedSpace() {
        if (!listSavedSpaceProc.running) {
            listSavedSpaceProc.running = true
        }
    }

    function reloadActions() {
        if (!listActionsProc.running) {
            listActionsProc.running = true
        }
    }

    function reloadActivity() {
        if (!listActivityProc.running) {
            listActivityProc.running = true
        }
    }

    function reloadDevices() {
        if (!listDevicesProc.running) {
            listDevicesProc.running = true
        }
    }

    function reloadSharedLinks() {
        if (!listLinksProc.running) {
            listLinksProc.running = true
        }
    }

    function saveItem(item) {
        if (!item) return
        saveItemProc.command = [root.toolboxScript, "saved-space", "save-item", JSON.stringify(item)]
        saveItemProc.running = true
    }

    function deleteItem(id) {
        if (!id) return
        deleteItemProc.command = [root.toolboxScript, "saved-space", "delete-item", String(id)]
        deleteItemProc.running = true
    }

    function saveCollections(colls, items) {
        const cmd = [root.toolboxScript, "saved-space", "save-collections", JSON.stringify(colls)]
        if (items) cmd.push(JSON.stringify(items))
        saveCollsProc.command = cmd
        saveCollsProc.running = true
    }

    function openUrl(url) {
        if (!url) return
        openUrlProc.command = [root.toolboxScript, "saved-space", "open-url", String(url)]
        openUrlProc.running = true
    }

    function copyText(text) {
        if (!text) return
        Quickshell.execDetached([root.toolboxScript, "saved-space", "copy", String(text)])
    }

    function runAction(actionId, params) {
        if (!actionId) return
        const p = params || {}
        runActionProc.command = [root.toolboxScript, "action", "run", String(actionId), JSON.stringify(p)]
        runActionProc.running = true
    }

    function runDeviceAction(deviceId, action, params) {
        if (!deviceId || !action) return
        const p = params || {}
        deviceActionProc.command = [root.toolboxScript, "device", "action", String(deviceId), String(action), JSON.stringify(p)]
        deviceActionProc.running = true
    }

    function dismissSharedLink(id) {
        if (!id) return
        dismissLinkProc.command = [root.toolboxScript, "device", "dismiss-link", String(id)]
        dismissLinkProc.running = true
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

    // Initialize state on load
    Component.onCompleted: {
        root.reloadSavedSpace()
        root.reloadActions()
        root.reloadActivity()
        root.reloadDevices()
        root.reloadSharedLinks()
    }

    onToolboxChanged: {
        if (root.toolbox) {
            if (root.savedItems.length > 0) root.toolbox.savedItems = root.savedItems
            if (root.collections.length > 0) root.toolbox.collections = root.collections
            if (root.availableActionIds.length > 0) root.toolbox.availableActionIds = root.availableActionIds
            if (root.activityEvents.length > 0) root.toolbox.activityEvents = root.activityEvents
            if (root.devices.length > 0) root.toolbox.devices = root.devices
            if (root.sharedLinks.length > 0) root.toolbox.sharedLinks = root.sharedLinks
            root.reloadSavedSpace()
            root.reloadActions()
            root.reloadActivity()
            root.reloadDevices()
            root.reloadSharedLinks()
        }
    }

    // --------------------------------------------------------------------------
    // Signal connections to Toolbox.qml
    // --------------------------------------------------------------------------

    Connections {
        target: root.toolbox

        function onActionRunRequested(actionId, params) {
            root.runAction(actionId, params)
            root.playSound("action")
        }

        function onSavedItemSaved(item) {
            root.saveItem(item)
            root.playSound("notice")
        }

        function onSavedItemDeleted(id) {
            root.deleteItem(id)
            root.playSound("notice")
        }

        function onCollectionsSaved(collections, items) {
            root.saveCollections(collections, items)
            root.playSound("notice")
        }

        function onCopyRequested(text) {
            root.copyText(text)
        }

        function onOpenUrlRequested(url) {
            root.openUrl(url)
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
            root.runDeviceAction(deviceId, action, params)
            root.playSound("action")
        }

        function onSharedLinkDismissed(id) {
            root.dismissSharedLink(id)
            root.playSound("notice")
        }
    }
}
