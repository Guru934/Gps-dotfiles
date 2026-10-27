import QtQuick
import Quickshell
import Quickshell.Io
import "PetGeometry.js" as G

// Reads the compositor: monitor size, the windows on the current workspace, the cursor.
// Everything comes from hyprctl, nothing is assumed. Hyprland-only by design.
Item {
    id: world
    visible: false

    property real spriteW: 66
    property real spriteH: 60
    property real floorInset: 0
    property bool active: true
    property bool pollCursor: true

    // results
    property bool ok: false
    property var monitor: ({ xMin: 0, xMax: 1280, yMin: 0, floorY: 800, w: 1280, h: 800, x: 0, y: 0, name: "" })
    property var surfaces: []
    property bool fullscreen: false
    property int workspaceId: -1
    property int windowCount: 0
    property string monitorName: monitor.name || ""
    property real cursorX: -1
    property real cursorY: -1
    property bool cursorValid: false
    property real cursorIdleSec: 0
    property real _lastMove: Date.now()
    property real _lx: -1
    property real _ly: -1

    function apply(text) {
        var parts = text.split("\n@@\n");
        if (parts.length < 2) return;
        var r = G.parse(parts[0], parts[1], spriteH, spriteW, floorInset);
        if (!r.ok) { ok = false; return; }
        ok = true;
        monitor = r.monitor;
        fullscreen = r.fullscreen;
        windowCount = r.windows;
        // only publish a new list when it really changed, so the brain is not re-evaluated every second
        var sig = JSON.stringify(r.surfaces);
        if (sig !== _sig) { _sig = sig; surfaces = r.surfaces; }
        if (workspaceId !== r.monitor.ws) workspaceId = r.monitor.ws;
    }
    property string _sig: ""

    function applyCursor(text) {
        var c = G.parseCursor(text, monitor);
        if (!c) { cursorValid = false; return; }
        cursorValid = true;
        cursorX = c.x; cursorY = c.y;
        var now = Date.now();
        if (Math.abs(c.x - _lx) > 2 || Math.abs(c.y - _ly) > 2) { _lastMove = now; _lx = c.x; _ly = c.y; }
        cursorIdleSec = (now - _lastMove) / 1000;
    }

    Process {
        id: probe
        command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@\\n'; hyprctl -j clients"]
        stdout: StdioCollector { onStreamFinished: world.apply(text) }
    }
    Timer {
        interval: 1000; repeat: true; running: world.active; triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }

    Process {
        id: cur
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector { onStreamFinished: world.applyCursor(text) }
    }
    Timer {
        interval: 300; repeat: true; running: world.active && world.pollCursor
        onTriggered: if (!cur.running) cur.running = true
    }
}
