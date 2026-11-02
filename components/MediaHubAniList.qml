import QtQuick
import Quickshell
import Quickshell.Io

// Narrow bridge between the Media Hub catalogue pages and
// scripts/media-hub-anilist.py. Only public AniList catalogue searches can run
// here; credentials, account mutations and arbitrary command execution are not
// part of this surface.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string projectPath: Quickshell.env("GPS_ROOT") || ""
    readonly property string helperPath: root.projectPath ? (root.projectPath + "/scripts/media-hub-anilist.py") : "media-hub-anilist.py"

    property bool searching: false
    property var pendingRequest: null
    property var activeRequest: null

    signal searchSucceeded(var payload, var request)
    signal searchFailed(string message, string code, var request, int retryAfter)

    function search(request) {
        if (!request) return false
        if (request.kind !== "anime" && request.kind !== "manga") {
            root.searchFailed("Unsupported catalogue type.", "invalid_request", request, 0)
            return false
        }
        root.pendingRequest = request
        if (root.searching) return true
        root.startQueuedSearch()
        return true
    }

    function commandFor(request) {
        const command = [
            root.helperPath, "search",
            "--type", String(request.kind || "anime"),
            "--query=" + String(request.query || ""),
            "--genre", String(request.genre || ""),
            "--status", String(request.status || ""),
            "--country", String(request.country || ""),
            "--sort", String(request.sort || "POPULARITY_DESC"),
            "--page", String(request.page || 1),
            "--per-page", String(request.perPage || 24)
        ]
        if (request.seasonal === true) command.push("--seasonal")
        return command
    }

    function startQueuedSearch() {
        if (root.pendingRequest === null) return
        root.activeRequest = root.pendingRequest
        root.pendingRequest = null
        root.searching = true
        searchProc.command = root.commandFor(root.activeRequest)
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
        if (exitCode !== 0) return "AniList helper exited with code " + exitCode + "."
        return "AniList returned an unexpected response."
    }

    Process {
        id: searchProc
        command: []
        stdout: StdioCollector { id: searchStdout }
        stderr: StdioCollector { id: searchStderr }
        onExited: (exitCode, exitStatus) => {
            const request = root.activeRequest
            const payload = root.parsePayload(searchStdout.text)
            root.searching = false
            root.activeRequest = null
            if (exitCode === 0 && payload && payload.ok === true
                    && payload.results && typeof payload.results.length === "number") {
                root.searchSucceeded(payload, request)
            } else {
                const code = payload && typeof payload.code === "string" ? payload.code : "invalid_response"
                const retryAfter = payload && typeof payload.retryAfter === "number"
                    ? Math.max(0, Math.min(86400, Math.floor(payload.retryAfter))) : 0
                root.searchFailed(root.errorMessage(payload, searchStderr.text, exitCode), code, request, retryAfter)
            }
            root.startQueuedSearch()
        }
    }
}
