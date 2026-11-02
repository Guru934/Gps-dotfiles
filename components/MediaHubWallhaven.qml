import QtQuick
import Quickshell
import Quickshell.Io

// Narrow bridge between the Media Hub UI and scripts/media-hub-wallhaven.py.
// This component only performs Wallhaven metadata searches and wallpaper
// downloads/applies. It is not a general command runner.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string projectPath: Quickshell.env("GPS_ROOT") || ""
    readonly property string helperPath: root.projectPath ? (root.projectPath + "/scripts/media-hub-wallhaven.py") : "media-hub-wallhaven.py"
    readonly property string themeScriptPath: root.projectPath ? (root.projectPath + "/scripts/extract-theme.py") : "extract-theme.py"

    property bool searching: false
    property bool applying: false
    property var pendingSearch: null
    property var activeSearch: null
    property var activeApply: null
    property var themeApply: null

    signal searchSucceeded(var payload, var request)
    signal searchFailed(string message, string code, var request)
    signal applySucceeded(var payload, var request)
    signal applyFailed(string message, string code, var request)
    signal themeSyncFinished(bool ok, string message)

    function search(request) {
        root.pendingSearch = request
        if (root.searching) return
        root.startQueuedSearch()
    }

    function startQueuedSearch() {
        if (root.pendingSearch === null) return
        root.activeSearch = root.pendingSearch
        root.pendingSearch = null
        root.searching = true
        searchProc.command = [
            root.helperPath, "search",
            "--query", String(root.activeSearch.query || ""),
            "--category", String(root.activeSearch.category || "all"),
            "--sorting", String(root.activeSearch.sorting || "relevance"),
            "--order", String(root.activeSearch.order || "desc"),
            "--atleast", String(root.activeSearch.atleast || ""),
            "--ratios", String(root.activeSearch.ratios || ""),
            "--color", String(root.activeSearch.color || ""),
            "--page", String(root.activeSearch.page || 1),
            "--seed", String(root.activeSearch.seed || "")
        ]
        searchProc.running = true
    }

    function apply(request) {
        if (root.applying || !request) return false
        root.activeApply = request
        root.applying = true
        applyProc.command = [
            root.helperPath, "apply",
            "--id", String(request.id || ""),
            "--path", String(request.path || ""),
            "--title", String(request.title || "Wallhaven wallpaper")
        ]
        applyProc.running = true
        return true
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
        if (exitCode !== 0) return "Wallhaven helper exited with code " + exitCode + "."
        return "Wallhaven returned an unexpected response."
    }

    Process {
        id: searchProc
        command: []
        stdout: StdioCollector { id: searchStdout }
        stderr: StdioCollector { id: searchStderr }
        onExited: (exitCode, exitStatus) => {
            const request = root.activeSearch
            const payload = root.parsePayload(searchStdout.text)
            if (exitCode === 0 && payload && payload.ok === true
                    && payload.results && typeof payload.results.length === "number") {
                root.searchSucceeded(payload, request)
            } else {
                const code = payload && typeof payload.code === "string" ? payload.code : "invalid_response"
                root.searchFailed(root.errorMessage(payload, searchStderr.text, exitCode), code, request)
            }
            root.searching = false
            root.activeSearch = null
            root.startQueuedSearch()
        }
    }

    Process {
        id: applyProc
        command: []
        stdout: StdioCollector { id: applyStdout }
        stderr: StdioCollector { id: applyStderr }
        onExited: (exitCode, exitStatus) => {
            const request = root.activeApply
            const payload = root.parsePayload(applyStdout.text)
            root.applying = false
            root.activeApply = null
            if (!(exitCode === 0 && payload && payload.ok === true)) {
                const code = payload && typeof payload.code === "string" ? payload.code : "apply_failed"
                root.applyFailed(root.errorMessage(payload, applyStderr.text, exitCode), code, request)
                return
            }
            root.applySucceeded(payload, request)
            if (request && request.syncTheme === true) {
                root.themeApply = request
                if (themeSyncProc.running) {
                    root.themeSyncFinished(false, "A theme sync is already running.")
                } else {
                    themeSyncProc.running = true
                }
            }
        }
    }

    Process {
        id: themeSyncProc
        command: ["python3", root.themeScriptPath]
        stdout: StdioCollector { id: themeStdout }
        stderr: StdioCollector { id: themeStderr }
        onExited: (exitCode, exitStatus) => {
            const request = root.themeApply
            root.themeApply = null
            if (exitCode === 0) {
                root.themeSyncFinished(true, request ? String(request.title || "") : "")
            } else {
                const message = String(themeStderr.text || themeStdout.text || "").trim().split("\n").slice(-1)[0]
                root.themeSyncFinished(false, message !== "" ? message : "extract-theme.py exited with code " + exitCode + ".")
            }
        }
    }
}
