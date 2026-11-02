pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string projectPath: Quickshell.env("GPS_ROOT")
        || Quickshell.env("GPS_DESKTOP_ROOT") || ""
    readonly property string scriptsPath: root.projectPath + "/scripts"

    property bool loading: false
    property var error: null
    property int requestSerial: 0
    property var activeRequest: null
    property var pendingRequest: null

    signal succeeded(int requestId, var payload)
    signal failed(int requestId, var error)
    signal cancelled(int requestId)

    function run(script, args) {
        const name = String(script || "")
        if (!/^media-hub-[a-z0-9-]+\.py$/.test(name) || !Array.isArray(args)) {
            root.error = { kind: "invalid", message: "Invalid provider script or arguments." }
            root.failed(root.requestSerial, root.error)
            return -1
        }
        const cleanArgs = []
        for (let i = 0; i < args.length; i++) {
            if (typeof args[i] !== "string") {
                root.error = { kind: "invalid", message: "Provider arguments must be strings." }
                root.failed(root.requestSerial, root.error)
                return -1
            }
            cleanArgs.push(args[i])
        }
        root.requestSerial += 1
        root.pendingRequest = {
            id: root.requestSerial,
            command: ["python3", root.scriptsPath + "/" + name].concat(cleanArgs)
        }
        root.error = null
        root.loading = true
        if (root.activeRequest !== null) {
            if (providerProc.running)
                providerProc.running = false
        } else {
            root.startPending()
        }
        return root.requestSerial
    }

    function cancel() {
        const cancelledId = root.pendingRequest !== null
            ? root.pendingRequest.id
            : (root.activeRequest !== null ? root.activeRequest.id : root.requestSerial)
        root.requestSerial += 1
        root.pendingRequest = null
        root.error = null
        root.loading = false
        if (providerProc.running)
            providerProc.running = false
        root.cancelled(cancelledId)
    }

    function startPending() {
        if (root.pendingRequest === null || root.activeRequest !== null) return
        root.activeRequest = root.pendingRequest
        root.pendingRequest = null
        providerProc.command = root.activeRequest.command
        providerProc.running = true
    }

    function parsePayload(text) {
        const trimmed = String(text || "").trim()
        if (!trimmed) return null
        try {
            const parsed = JSON.parse(trimmed)
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null
        } catch (parseError) {
            return null
        }
    }

    function errorFor(payload, stderrText, exitCode) {
        if (payload && payload.error && typeof payload.error === "object") {
            const kind = ["network", "rate_limited", "unavailable", "invalid"].indexOf(payload.error.kind) >= 0
                ? payload.error.kind : "invalid"
            const message = typeof payload.error.message === "string" && payload.error.message
                ? payload.error.message : "The provider returned an invalid error."
            return { kind: kind, message: message }
        }
        const stderr = String(stderrText || "").trim()
        const message = payload && typeof payload.message === "string" && payload.message
            ? payload.message
            : (stderr ? stderr.split("\n").slice(-1)[0].slice(0, 240)
                      : "The provider returned an invalid response (exit " + exitCode + ").")
        const code = payload && typeof payload.code === "string" ? payload.code : ""
        const kind = code.indexOf("rate") >= 0 ? "rate_limited"
            : (code.indexOf("network") >= 0 ? "network"
               : (code.indexOf("unavailable") >= 0 ? "unavailable" : "invalid"))
        return { kind: kind, message: message }
    }

    Process {
        id: providerProc
        command: []
        stdout: StdioCollector { id: providerStdout }
        stderr: StdioCollector { id: providerStderr }

        onExited: (exitCode, exitStatus) => {
            const request = root.activeRequest
            const payload = root.parsePayload(providerStdout.text)
            root.activeRequest = null
            if (request && request.id === root.requestSerial) {
                if (exitCode === 0 && payload && payload.ok === true) {
                    root.error = null
                    root.loading = false
                    root.succeeded(request.id, payload)
                } else {
                    root.error = root.errorFor(payload, providerStderr.text, exitCode)
                    root.loading = false
                    root.failed(request.id, root.error)
                }
            }
            root.startPending()
        }
    }
}
