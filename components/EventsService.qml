import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config
import "EventsLogic.js" as EventsLogic

Scope {
    id: root

    property var hub: null
    readonly property string home: Quickshell.env("HOME")
    readonly property string storePath: home + "/.config/quickshell/rice-settings.json"
    readonly property string dndPath: home + "/.local/state/gps/dnd.json"

    property var eventsSettings: EventsLogic.DEFAULT_EVENTS_SETTINGS
    property var powerState: EventsLogic.createInitialPowerState()
    property bool dndActive: false

    // UPower telemetry bindings
    readonly property var batDevice: UPower.displayDevice
    readonly property bool batPresent: batDevice !== null && batDevice.isPresent
    readonly property int batPercentage: {
        if (!batPresent) return -1
        return EventsLogic.normalizePercentage(batDevice.percentage)
    }
    readonly property bool onBattery: UPower.onBattery
    readonly property int devState: batDevice !== null ? batDevice.state : 0

    // Settings loader
    FileWatcher {
        id: settingsWatcher
        path: root.storePath
        onFileChanged: root.loadSettings()
    }

    FileWatcher {
        id: dndWatcher
        path: root.dndPath
        onFileChanged: root.loadDnd()
    }

    Component.onCompleted: {
        root.loadSettings()
        root.loadDnd()
        root.checkPower()
    }

    onBatPercentageChanged: root.checkPower()
    onOnBatteryChanged: root.checkPower()
    onDevStateChanged: root.checkPower()

    function checkPower() {
        if (!root.batPresent) return
        const current = {
            percentage: root.batPercentage,
            onBattery: root.onBattery,
            state: root.devState,
            isPresent: true
        }
        const res = EventsLogic.evaluatePower(current, root.powerState, root.eventsSettings, root.dndActive)
        root.powerState = res.state
        root.executeActions(res.actions)
    }

    function executeActions(actions) {
        if (!actions || !actions.length) return
        for (let i = 0; i < actions.length; i++) {
            const act = actions[i]
            if (act.type === "notification") {
                Quickshell.execDetached([
                    "notify-send",
                    "-a", act.app || "System",
                    "-u", act.urgency || "normal",
                    "-i", act.icon || "dialog-information",
                    act.summary || "",
                    act.body || ""
                ])
            } else if (act.type === "sound") {
                Quickshell.execDetached(["gps-sound", "play", act.event])
            } else if (act.type === "system") {
                if (act.action === "suspend") {
                    Quickshell.execDetached(["systemctl", "suspend"])
                }
            }
        }
    }

    function loadSettings() {
        Quickshell.exec(["cat", root.storePath], proc => {
            if (proc.exitCode !== 0) return
            try {
                const data = JSON.parse(proc.stdout)
                if (data && typeof data === "object") {
                    const merged = Object.assign({}, EventsLogic.DEFAULT_EVENTS_SETTINGS)
                    if (data.events && typeof data.events === "object") {
                        for (const k in data.events) {
                            if (data.events[k] !== undefined) merged[k] = data.events[k]
                        }
                    }
                    root.eventsSettings = merged
                }
            } catch (e) {}
        })
    }

    function loadDnd() {
        Quickshell.exec(["cat", root.dndPath], proc => {
            if (proc.exitCode !== 0) return
            try {
                const data = JSON.parse(proc.stdout)
                if (data && typeof data === "object") {
                    root.dndActive = data.mode === "dnd" || data.mode === "snooze" || !!(data.schedule && data.schedule.enabled)
                }
            } catch (e) {}
        })
    }

    function updateSetting(key, val) {
        const next = Object.assign({}, root.eventsSettings)
        next[key] = val
        root.eventsSettings = next

        const pyCode = "import json, os, sys, tempfile\n"
            + "p, k, v = sys.argv[1], sys.argv[2], sys.argv[3]\n"
            + "d = {}\n"
            + "if os.path.isfile(p):\n"
            + "    try:\n"
            + "        with open(p, 'r', encoding='utf-8') as f: d = json.load(f)\n"
            + "    except Exception: pass\n"
            + "if not isinstance(d, dict): d = {}\n"
            + "ev = d.setdefault('events', {})\n"
            + "try: val = json.loads(v)\n"
            + "except Exception: val = v\n"
            + "ev[k] = val\n"
            + "d_dir = os.path.dirname(p)\n"
            + "os.makedirs(d_dir, exist_ok=True)\n"
            + "fd, tmp = tempfile.mkstemp(dir=d_dir, prefix='.rice-settings.tmp-')\n"
            + "with os.fdopen(fd, 'w', encoding='utf-8') as f:\n"
            + "    json.dump(d, f, indent=2)\n"
            + "    f.flush(); os.fsync(f.fileno())\n"
            + "os.replace(tmp, p)\n"

        Quickshell.execDetached(["python3", "-c", pyCode, root.storePath, key, JSON.stringify(val)])
    }

    IpcHandler {
        target: "events"

        function status(): string {
            return JSON.stringify({
                powerState: root.powerState,
                settings: root.eventsSettings,
                dndActive: root.dndActive,
                batPresent: root.batPresent,
                batPercentage: root.batPercentage,
                onBattery: root.onBattery,
                devState: root.devState
            })
        }

        function testPower(pct: real, state: int, onBat: bool): string {
            const current = {
                percentage: pct,
                onBattery: onBat,
                state: state,
                isPresent: true
            }
            const res = EventsLogic.evaluatePower(current, root.powerState, root.eventsSettings, root.dndActive)
            root.powerState = res.state
            root.executeActions(res.actions)
            return JSON.stringify({ actions: res.actions, state: res.state })
        }

        function testEvent(event: string): string {
            Quickshell.execDetached(["gps-sound", "play", event, "--force"])
            return JSON.stringify({ ok: true, event: event })
        }

        function setThreshold(kind: string, val: int) {
            root.updateSetting(kind, val)
        }

        function setCriticalAction(action: string) {
            root.updateSetting("criticalAction", action)
        }
    }
}
