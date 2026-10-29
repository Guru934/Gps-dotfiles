pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool loading: false
    property var result: null
    property string resultKey: ""
    property string requestKey: ""
    property string errorKey: ""
    property var error: null
    property int requestSerial: 0
    property var activeRequest: null
    property var pendingRequest: null

    function keyFor(artist, title, album, duration) {
        const seconds = Number(duration)
        const normalizedDuration = Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : 0
        return JSON.stringify([
            String(artist || "").trim(),
            String(title || "").trim(),
            String(album || "").trim(),
            normalizedDuration
        ])
    }

    function lookup(artist, title, album, duration) {
        const key = root.keyFor(artist, title, album, duration)
        if (key === root.resultKey) return true
        if (root.activeRequest && root.activeRequest.key === key) return true
        if (root.pendingRequest && root.pendingRequest.key === key) return true

        root.requestSerial += 1
        root.pendingRequest = {
            id: root.requestSerial,
            key: key,
            command: [
                "python3",
                HubProvider.scriptsPath + "/media-hub-lyrics.py",
                String(artist || ""),
                String(title || ""),
                String(album || ""),
                Number(duration) > 0 ? String(Math.round(Number(duration))) : ""
            ]
        }
        root.loading = true
        root.requestKey = key
        root.errorKey = ""
        root.result = null
        root.resultKey = ""
        root.error = null
        if (root.activeRequest !== null) {
            if (lyricsProc.running) lyricsProc.running = false
        } else {
            root.startPending()
        }
        return true
    }

    function cancel() {
        root.requestSerial += 1
        root.pendingRequest = null
        root.loading = false
        root.requestKey = ""
        root.errorKey = ""
        root.result = null
        root.resultKey = ""
        root.error = null
        if (lyricsProc.running) lyricsProc.running = false
    }

    function startPending() {
        if (root.pendingRequest === null || root.activeRequest !== null) return
        root.activeRequest = root.pendingRequest
        root.pendingRequest = null
        lyricsProc.command = root.activeRequest.command
        lyricsProc.running = true
    }

    function parsePayload(text) {
        try {
            const payload = JSON.parse(String(text || "").trim())
            if (payload && typeof payload === "object" && !Array.isArray(payload))
                return payload
        } catch (parseError) {
            return null
        }
        return null
    }

    function validLyrics(value) {
        if (!value || typeof value !== "object" || Array.isArray(value)) return false
        if (value.status === "none") return true
        if (value.status === "plain") return typeof value.plain === "string" && value.plain.trim() !== ""
        if (value.status !== "synced" || !Array.isArray(value.lines) || value.lines.length === 0) return false
        return value.lines.every(function (line) {
            return line && typeof line === "object"
                && typeof line.t === "number" && Number.isFinite(line.t) && line.t >= 0
                && typeof line.s === "string" && line.s.trim() !== ""
        })
    }

    function failureFor(payload, stderrText, exitCode) {
        if (payload && payload.error && typeof payload.error === "object") {
            const kind = ["network", "rate_limited", "unavailable", "invalid"].indexOf(payload.error.kind) >= 0
                ? payload.error.kind : "invalid"
            const message = typeof payload.error.message === "string" && payload.error.message
                ? payload.error.message : "The lyrics provider returned an invalid error."
            return { kind: kind, message: message }
        }
        const stderr = String(stderrText || "").trim()
        return {
            kind: "invalid",
            message: stderr ? stderr.split("\n").slice(-1)[0].slice(0, 240)
                : "The lyrics provider returned an invalid response (exit " + exitCode + ")."
        }
    }

    Process {
        id: lyricsProc
        command: []
        stdout: StdioCollector { id: lyricsStdout }
        stderr: StdioCollector { id: lyricsStderr }

        onExited: (exitCode, exitStatus) => {
            const request = root.activeRequest
            const payload = root.parsePayload(lyricsStdout.text)
            root.activeRequest = null
            if (request && request.id === root.requestSerial) {
                if (exitCode === 0 && payload && payload.ok === true && root.validLyrics(payload.lyrics)) {
                    root.result = payload.lyrics
                    root.resultKey = request.key
                    root.requestKey = ""
                    root.errorKey = ""
                    root.error = null
                    root.loading = false
                } else {
                    root.requestKey = ""
                    root.errorKey = request.key
                    root.error = root.failureFor(payload, lyricsStderr.text, exitCode)
                    root.loading = false
                }
            }
            root.startPending()
        }
    }
}
