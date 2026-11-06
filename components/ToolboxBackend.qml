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

    // Automations persistent state (Phase 5)
    property var automations: []

    // Workspace Presets persistent state (Phase 5)
    property var presets: []

    // Routine Builder & Workflows persistent state (Phase 6)
    property var routines: []

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
    // Automations & Presets background processes (Phase 5)
    // --------------------------------------------------------------------------

    Process {
        id: listAutomationsProc
        command: [root.toolboxScript, "automation", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.automations)) {
                        root.automations = res.automations
                        if (root.toolbox) root.toolbox.automations = res.automations
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: saveAutomationProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && res.automation) {
                        root.notify("Automation Saved", "“" + res.automation.name + "” saved and systemd timer synced.", "ok")
                        root.reloadAutomations()
                    } else if (res && !res.ok) {
                        root.notify("Failed to Save Automation", res.error || "Unknown error", "err")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: deleteAutomationProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        root.notify("Automation Deleted", "Automation removed and timer disabled.", "info")
                        root.reloadAutomations()
                    } else if (res && !res.ok) {
                        root.notify("Delete Failed", res.error || "Unknown error", "err")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: autoStateProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        const isEn = res.state === "enabled"
                        root.notify(isEn ? "Automation Enabled" : "Automation Paused",
                                    isEn ? ("Systemd timer scheduled (" + (res.nextRun || "active") + ")") : "Timer stopped.",
                                    isEn ? "ok" : "info")
                        root.reloadAutomations()
                    } else if (res && !res.ok) {
                        root.notify("State Change Failed", res.error || "Unknown error", "err")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: autoTestProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        root.notify("Automation Test", res.result || "Test run succeeded.", "ok")
                        root.reloadAutomations()
                        root.reloadActivity()
                    } else if (res && !res.ok) {
                        root.notify("Automation Test Failed", res.result || res.error || "Actions failed", "err")
                        root.playSound("warn")
                        root.reloadAutomations()
                        root.reloadActivity()
                    }
                } catch (e) {
                    root.reloadAutomations()
                    root.reloadActivity()
                }
            }
        }
    }

    Process {
        id: listPresetsProc
        command: [root.toolboxScript, "preset", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.presets)) {
                        root.presets = res.presets
                        if (root.toolbox) root.toolbox.presets = res.presets
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: presetProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && res.preset) {
                        root.notify("Preset Activated", "“" + res.preset.name + "” activated.", "ok")
                        root.reloadActivity()
                    } else if (res && !res.ok) {
                        root.notify("Preset Failed", res.error || "Activation failed", "err")
                        root.playSound("warn")
                    }
                } catch (e) {}
            }
        }
    }

    // --------------------------------------------------------------------------
    // Routine Builder & Workflows background processes (Phase 6)
    // --------------------------------------------------------------------------

    Process {
        id: listRoutinesProc
        command: [root.toolboxScript, "workflow", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && Array.isArray(res.routines)) {
                        root.routines = res.routines
                        if (root.toolbox) root.toolbox.routines = res.routines
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: saveRoutineProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok && res.workflow) {
                        root.notify("Workflow Saved", "“" + res.workflow.name + "” stored to persistent state.", "ok")
                        root.reloadRoutines()
                    } else if (res && !res.ok) {
                        root.notify("Save Failed", res.error || "Unknown error", "err")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: deleteRoutineProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        root.notify("Workflow Deleted", "Workflow definition removed.", "info")
                        root.reloadRoutines()
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: runRoutineProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const res = JSON.parse(text)
                    if (res && res.ok) {
                        root.notify("Workflow Finished", "Workflow “" + res.workflow + "” completed (" + res.steps_executed + " steps).", "ok")
                        root.reloadRoutines()
                        root.reloadActivity()
                    } else if (res && !res.ok) {
                        root.notify("Workflow Stopped", res.error || "Step execution encountered an error", "err")
                        root.playSound("warn")
                        root.reloadRoutines()
                        root.reloadActivity()
                    }
                } catch (e) {
                    root.reloadRoutines()
                    root.reloadActivity()
                }
            }
        }
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

    function reloadAutomations() {
        if (!listAutomationsProc.running) {
            listAutomationsProc.running = true
        }
    }

    function reloadPresets() {
        if (!listPresetsProc.running) {
            listPresetsProc.running = true
        }
    }

    function reloadRoutines() {
        if (!listRoutinesProc.running) {
            listRoutinesProc.running = true
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

    function saveAutomation(automation) {
        if (!automation) return
        saveAutomationProc.command = [root.toolboxScript, "automation", "save", JSON.stringify(automation)]
        saveAutomationProc.running = true
    }

    function deleteAutomation(id) {
        if (!id) return
        deleteAutomationProc.command = [root.toolboxScript, "automation", "delete", String(id)]
        deleteAutomationProc.running = true
    }

    function setAutomationState(id, enabled) {
        if (!id) return
        autoStateProc.command = [root.toolboxScript, "automation", "set-state", String(id), enabled ? "enabled" : "paused"]
        autoStateProc.running = true
    }

    function testAutomation(id) {
        if (!id) return
        autoTestProc.command = [root.toolboxScript, "automation", "test", String(id)]
        autoTestProc.running = true
    }

    function activatePreset(id) {
        if (!id) return
        presetProc.command = [root.toolboxScript, "preset", "activate", String(id)]
        presetProc.running = true
    }

    function saveRoutine(routine) {
        if (!routine) return
        saveRoutineProc.command = [root.toolboxScript, "workflow", "save", JSON.stringify(routine)]
        saveRoutineProc.running = true
    }

    function deleteRoutine(id) {
        if (!id) return
        deleteRoutineProc.command = [root.toolboxScript, "workflow", "delete", String(id)]
        deleteRoutineProc.running = true
    }

    function runWorkflow(id) {
        if (!id) return
        runRoutineProc.command = [root.toolboxScript, "workflow", "run", String(id)]
        runRoutineProc.running = true
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
        root.reloadAutomations()
        root.reloadPresets()
        root.reloadRoutines()
    }

    onToolboxChanged: {
        if (root.toolbox) {
            if (root.savedItems.length > 0) root.toolbox.savedItems = root.savedItems
            if (root.collections.length > 0) root.toolbox.collections = root.collections
            if (root.availableActionIds.length > 0) root.toolbox.availableActionIds = root.availableActionIds
            if (root.activityEvents.length > 0) root.toolbox.activityEvents = root.activityEvents
            if (root.devices.length > 0) root.toolbox.devices = root.devices
            if (root.sharedLinks.length > 0) root.toolbox.sharedLinks = root.sharedLinks
            if (root.automations.length > 0) root.toolbox.automations = root.automations
            if (root.presets.length > 0) root.toolbox.presets = root.presets
            if (root.routines.length > 0) root.toolbox.routines = root.routines
            root.reloadSavedSpace()
            root.reloadActions()
            root.reloadActivity()
            root.reloadDevices()
            root.reloadSharedLinks()
            root.reloadAutomations()
            root.reloadPresets()
            root.reloadRoutines()
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
            root.saveAutomation(automation)
            root.playSound("notice")
        }

        function onAutomationDeleted(id) {
            root.deleteAutomation(id)
            root.playSound("notice")
        }

        function onAutomationStateChangeRequested(id, enabled) {
            root.setAutomationState(id, enabled)
            root.playSound("notice")
        }

        function onAutomationTestRequested(id) {
            root.testAutomation(id)
            root.playSound("action")
        }

        function onScheduleCancelRequested(id) {
            root.setAutomationState(id, false)
            root.playSound("warn")
        }

        function onWorkflowSaved(routine) {
            root.saveRoutine(routine)
            root.playSound("notice")
        }

        function onWorkflowRunRequested(id) {
            root.runWorkflow(id)
            root.playSound("action")
        }

        function onPresetActivateRequested(id) {
            root.activatePreset(id)
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
