import QtQuick
import Quickshell
import Quickshell.Io

// Narrow bridge between the Media Hub music page and
// scripts/media-hub-music.py. Only credential status, Jamendo searches and
// Radio Browser searches can run here. It is not a general command runner.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string projectPath: Quickshell.env("HOME") + "/Projects/my-rice"
    readonly property string helperPath: root.projectPath + "/scripts/media-hub-music.py"

    property bool checkingStatus: false
    property bool searching: false
    property var pendingSearch: null
    property var activeSearch: null

    signal statusFinished(bool configured, string configPath, string message)
    signal searchSucceeded(var payload, var request)
    signal searchFailed(string message, string code, var request)

    function checkStatus() {
        if (root.checkingStatus || statusProc.running) return
        root.checkingStatus = true
        statusProc.running = true
    }

    function search(request) {
        if (!request) return false
        if (request.source !== "jamendo" && request.source !== "radio") {
            root.searchFailed("Unsupported music source.", "invalid_request", request)
            return false
        }
        root.pendingSearch = request
        if (root.searching) return true
        root.startQueuedSearch()
        return true
    }

    function commandFor(request) {
        if (request.source === "radio") {
            return [
                root.helperPath, "radio",
                "--name", String(request.query || ""),
                "--tag", String(request.tag || ""),
                "--country", String(request.country || ""),
                "--order", String(request.order || "clickcount"),
                "--limit", String(request.limit || 40),
                "--offset", String(request.offset || 0)
            ]
        }
        return [
            root.helperPath, "jamendo",
            "--query", String(request.query || ""),
            "--tag", String(request.tag || ""),
            "--order", String(request.order || "popularity_total"),
            "--limit", String(request.limit || 40),
            "--offset", String(request.offset || 0)
        ]
    }

    function startQueuedSearch() {
        if (root.pendingSearch === null) return
        root.activeSearch = root.pendingSearch
        root.pendingSearch = null
        root.searching = true
        searchProc.command = root.commandFor(root.activeSearch)
        searchProc.running = true
    }

    function parsePayload(text) {
        const trimmed = String(text || "").trim()
        if (trimmed === "") return null
        try {
            const parsed = JSON.parse(trimmed)
            return parsed && typeof parsed === "object" ? parsed : null
        } catch (error) {
            return null
        }
    }

    function errorMessage(payload, stderrText, exitCode) {
        if (payload && typeof payload.message === "string" && payload.message !== "")
            return payload.message
        const err = String(stderrText || "").trim()
        if (err !== "") return err.split("\n").slice(-1)[0].slice(0, 240)
        if (exitCode !== 0) return "Music helper exited with code " + exitCode + "."
        return "The music service returned an unexpected response."
    }

    Process {
        id: statusProc
        command: [root.helperPath, "status"]
        stdout: StdioCollector { id: statusStdout }
        stderr: StdioCollector { id: statusStderr }
        onExited: (exitCode, exitStatus) => {
            const payload = root.parsePayload(statusStdout.text)
            root.checkingStatus = false
            if (exitCode === 0 && payload && payload.ok === true
                    && typeof payload.configured === "boolean") {
                root.statusFinished(payload.configured,
                                    typeof payload.configPath === "string" ? payload.configPath : "",
                                    typeof payload.message === "string" ? payload.message : "")
            } else {
                root.statusFinished(false, "", root.errorMessage(payload, statusStderr.text, exitCode))
            }
        }
    }

    Process {
        id: searchProc
        command: []
        stdout: StdioCollector { id: searchStdout }
        stderr: StdioCollector { id: searchStderr }
        onExited: (exitCode, exitStatus) => {
            const request = root.activeSearch
            const payload = root.parsePayload(searchStdout.text)
            root.searching = false
            root.activeSearch = null
            if (exitCode === 0 && payload && payload.ok === true
                    && payload.results && typeof payload.results.length === "number") {
                root.searchSucceeded(payload, request)
            } else {
                const code = payload && typeof payload.code === "string" ? payload.code : "invalid_response"
                root.searchFailed(root.errorMessage(payload, searchStderr.text, exitCode), code, request)
            }
            root.startQueuedSearch()
        }
    }
}
