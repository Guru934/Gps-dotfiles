pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Single shared audio capture pipeline for the dashboard. Consumers (the Home
// SpectrumCard and the Media tab) acquire() when they exist and release()
// when destroyed; the parec/python capture process runs only while at least
// one consumer needs it, so switching between tabs never leaves a duplicate
// or leaked capture behind. Real signal only - silence reports zeros and the
// bars settle to a still baseline.
Singleton {
    id: root

    readonly property int barCount: 18
    property int clients: 0
    property var levels: []
    property bool streaming: false
    property double lastFrameAt: 0

    readonly property bool active: root.clients > 0

    function acquire() {
        root.clients += 1
    }

    function release() {
        root.clients = Math.max(0, root.clients - 1)
    }

    Process {
        id: spectrumProc
        command: [
            "python3",
            "/home/rice/Projects/my-rice/scripts/audio-spectrum.py",
            String(root.barCount)
        ]
        running: root.active
        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.trim().split(/\s+/)
                if (parts.length === 0) return
                const vals = []
                for (const p of parts) {
                    const v = parseFloat(p)
                    vals.push(isNaN(v) ? 0 : Math.max(0, Math.min(1, v)))
                }
                root.levels = vals
                root.streaming = true
                root.lastFrameAt = Date.now()
            }
        }
        onExited: root.streaming = false
    }

    // If the capture pipeline dies (no frames arrive), fall back to idle.
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            if (root.streaming && Date.now() - root.lastFrameAt > 2500)
                root.streaming = false
        }
    }
}
