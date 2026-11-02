import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string projectPath: Quickshell.env("GPS_ROOT") || ""
    readonly property string helperPath: root.projectPath ? (root.projectPath + "/scripts/media-hub-tools.py") : "media-hub-tools.py"

    property bool checkingStatus: false
    property bool busy: false
    property bool statusReady: false
    property var toolStatus: ({})
    property string error: ""
    property string errorCode: ""
    property string activeAction: ""

    signal statusFinished(var status)
    signal commandReady(var payload, string action)
    signal commandFailed(string message, string code, string action)

    function checkStatus() {
        if (root.checkingStatus || statusProc.running) return
        root.checkingStatus = true
        statusProc.running = true
    }

    function prepareAniCli() {
        if (root.busy || commandProc.running) return false
        root.activeAction = "ani-cli"
        root.busy = true
        root.error = ""
        root.errorCode = ""
        commandProc.command = [root.helperPath, "ani-command"]
        commandProc.running = true
        return true
    }

    function prepareLocalVideo(path) {
        if (root.busy || commandProc.running) return false
        root.activeAction = "local-video"
        root.busy = true
        root.error = ""
        root.errorCode = ""
        commandProc.command = [root.helperPath, "video-command", "--path", String(path || "")]
        commandProc.running = true
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
        if (exitCode !== 0) return "Playback helper exited with code " + exitCode + "."
        return "The playback helper returned an unexpected response."
    }

    function validCommand(value) {
        if (!Array.isArray(value) || value.length < 1 || value.length > 16) return false
        for (let i = 0; i < value.length; i++) {
            if (typeof value[i] !== "string" || value[i] === "" || value[i].length > 4096)
                return false
        }
        return true
    }

    Process {
        id: statusProc
        command: [root.helperPath, "status"]
        stdout: StdioCollector { id: statusStdout }
        stderr: StdioCollector { id: statusStderr }
        onExited: (exitCode, exitStatus) => {
            const payload = root.parsePayload(statusStdout.text)
            root.checkingStatus = false
            if (exitCode === 0 && payload && payload.ok === true) {
                root.toolStatus = payload
                root.statusReady = true
                root.statusFinished(payload)
            } else {
                root.error = root.errorMessage(payload, statusStderr.text, exitCode)
                root.errorCode = payload && payload.code ? String(payload.code) : "tool_status_failed"
                root.statusFinished(null)
            }
        }
    }

    Process {
        id: commandProc
        command: []
        stdout: StdioCollector { id: commandStdout }
        stderr: StdioCollector { id: commandStderr }
        onExited: (exitCode, exitStatus) => {
            const action = root.activeAction
            const payload = root.parsePayload(commandStdout.text)
            root.busy = false
            root.activeAction = ""
            if (exitCode === 0 && payload && payload.ok === true && root.validCommand(payload.command)) {
                root.commandReady(payload, action)
            } else {
                root.error = root.errorMessage(payload, commandStderr.text, exitCode)
                root.errorCode = payload && payload.code ? String(payload.code) : "launch_failed"
                root.commandFailed(root.error, root.errorCode, action)
            }
        }
    }
}
