pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // =========================================================================
    // Public API
    // =========================================================================
    readonly property int percent: _percent
    readonly property bool available: _available
    property string device: ""
    readonly property int currentBrightness: _currentBrightness
    readonly property int maxBrightness: _maxBrightness

    // =========================================================================
    // Internal State
    // =========================================================================
    property int _percent: 0
    property bool _available: false
    property int _currentBrightness: 0
    property int _maxBrightness: 0
    property bool _pendingRefresh: false

    // =========================================================================
    // Canonical Calculation Function
    // =========================================================================
    function calcPercent(current, max) {
        var c = Number(current);
        var m = Number(max);
        if (isNaN(c) || isNaN(m) || m <= 0) return 0;
        var raw = Math.round((c / m) * 100);
        return Math.max(0, Math.min(100, raw));
    }

    // =========================================================================
    // Public Mutators
    // =========================================================================
    function setPercent(targetPct) {
        if (!root._available || root._maxBrightness <= 0) return;
        const val = Number(targetPct);
        if (isNaN(val)) return;
        const clamped = Math.max(1, Math.min(100, Math.round(val)));
        root._percent = clamped;
        const cmd = (root.device && root.device !== "")
            ? ["brightnessctl", "-d", root.device, "-q", "set", clamped + "%"]
            : ["brightnessctl", "-q", "set", clamped + "%"];
        Quickshell.execDetached(cmd);
        reReadTimer.restart();
    }

    function step(deltaPct) {
        setPercent(root.percent + deltaPct);
    }

    function refresh() {
        if (!brightReadProc.running) {
            brightReadProc.running = true;
        } else {
            root._pendingRefresh = true;
        }
    }

    // =========================================================================
    // Internal Output Parser
    // =========================================================================
    function _parseOutput(raw) {
        if (!raw) {
            root._available = false;
            return;
        }
        const line = raw.trim().split("\n")[0];
        if (!line) {
            root._available = false;
            return;
        }
        const parts = line.split(",");
        // Expected CSV: device,class,current,percentage,max
        if (parts.length >= 5) {
            const dev = parts[0].trim();
            const cur = parseInt(parts[2], 10);
            const max = parseInt(parts[4], 10);

            if (isNaN(cur) || isNaN(max) || max <= 0) {
                root._available = false;
                return;
            }

            if (root.device === "" && dev !== "") {
                root.device = dev;
            }

            root._currentBrightness = cur;
            root._maxBrightness = max;
            root._percent = calcPercent(cur, max);
            root._available = true;
        } else {
            root._available = false;
        }
    }

    // =========================================================================
    // Hardware Query Process
    // =========================================================================
    Process {
        id: brightReadProc
        command: (root.device && root.device !== "")
            ? ["brightnessctl", "-d", root.device, "-m"]
            : ["brightnessctl", "-c", "backlight", "-m"]
        running: true

        stdout: StdioCollector {
            id: collector
            onStreamFinished: root._parseOutput(collector.text)
        }

        onExited: (code, status) => {
            if (code !== 0) {
                root._available = false;
            }
            if (root._pendingRefresh) {
                root._pendingRefresh = false;
                brightReadProc.running = true;
            }
        }
    }

    // =========================================================================
    // Timers
    // =========================================================================
    // Periodic slow poll (2500ms) for external hotkey/driver changes
    Timer {
        id: pollTimer
        interval: 2500
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    // Short confirmation timer (100ms) following a slider or step change
    Timer {
        id: reReadTimer
        interval: 100
        repeat: false
        onTriggered: root.refresh()
    }
}
