pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    property var localPlayer: null
    property var sharedLocalState: null
    property var controlQueue: []
    property bool controlRunning: false
    readonly property string localStatePath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR")
        if (runtime) return runtime + "/gps-media-hub-nowplaying.json"
        const cache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
        return cache + "/gps/media/media-hub-nowplaying.json"
    }
    readonly property string projectPath: Quickshell.env("GPS_ROOT")
        || Quickshell.env("GPS_DESKTOP_ROOT") || ""
    readonly property var localCandidate: root.localPlayer && root.localPlayer.trackTitle
        ? root.localPlayer
        : (root.sharedLocalState ? sharedLocalPlayer : null)
    readonly property var players: {
        const available = Mpris.players ? Mpris.players.values.slice() : []
        if (root.localCandidate) available.unshift(root.localCandidate)
        return available
    }
    property string preferredPlayerId: ""
    readonly property var player: selectPlayer()

    function parseSharedState(text) {
        try {
            const value = JSON.parse(String(text || ""))
            const updatedAt = value && typeof value.updatedAt === "number" ? value.updatedAt : 0
            if (!value || value.active !== true || typeof value.id !== "string"
                    || !value.id.startsWith("local:") || typeof value.title !== "string"
                    || value.title.trim() === "" || !isFinite(updatedAt)
                    || Date.now() - updatedAt > 2500 || updatedAt - Date.now() > 5000) {
                root.sharedLocalState = null
                return
            }
            root.sharedLocalState = {
                id: value.id.slice(0, 120),
                title: value.title.slice(0, 180),
                artist: typeof value.artist === "string" ? value.artist.slice(0, 120) : "",
                album: typeof value.album === "string" ? value.album.slice(0, 120) : "",
                art: typeof value.art === "string" ? value.art.slice(0, 2048) : "",
                playing: value.playing === true,
                position: typeof value.position === "number" && isFinite(value.position)
                    ? Math.max(0, value.position) : 0,
                length: typeof value.length === "number" && isFinite(value.length)
                    ? Math.max(0, value.length) : 0,
                canPrevious: value.canPrevious === true,
                canNext: value.canNext === true,
                updatedAt: updatedAt
            }
        } catch (error) {
            // Keep the last valid snapshot if a concurrent write is incomplete.
        }
    }

    function callHub(method, argument) {
        const allowed = ["togglePlayback", "nextTrack", "previousTrack", "stopPlayback", "seekPlayback"]
        if (allowed.indexOf(method) < 0) return false
        let command = [
            "qs", "ipc", "--path", root.projectPath + "/shell.qml",
            "call", "mediahub", method
        ]
        if (argument !== undefined) command.push(String(argument))
        root.controlQueue = root.controlQueue.concat([command])
        root.startControl()
        return true
    }

    function startControl() {
        if (root.controlRunning || root.controlQueue.length === 0) return
        const command = root.controlQueue[0]
        root.controlQueue = root.controlQueue.slice(1)
        root.controlRunning = true
        controlProcess.command = command
        controlProcess.running = true
    }

    FileView {
        id: localStateFile
        path: root.localStatePath
        watchChanges: true
        printErrors: false
        onLoaded: root.parseSharedState(text())
        onFileChanged: reload()
        onLoadFailed: root.sharedLocalState = null
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.sharedLocalState !== null
        onTriggered: {
            if (Date.now() - root.sharedLocalState.updatedAt > 2500)
                root.sharedLocalState = null
        }
    }

    Process {
        id: controlProcess
        command: []
        stderr: StdioCollector { id: controlStderr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("Media Hub playback control failed: " + String(controlStderr.text || "IPC command failed.").trim())
            root.controlRunning = false
            root.startControl()
        }
    }

    QtObject {
        id: sharedLocalPlayer
        readonly property string dbusName: "gps.media-hub"
        readonly property string identity: "GPS Media Hub"
        readonly property string desktopEntry: "gps-media-hub"
        readonly property string uniqueId: root.sharedLocalState ? root.sharedLocalState.id : ""
        readonly property string trackTitle: root.sharedLocalState ? root.sharedLocalState.title : ""
        readonly property string trackArtist: root.sharedLocalState ? root.sharedLocalState.artist : ""
        readonly property string trackAlbum: root.sharedLocalState ? root.sharedLocalState.album : ""
        readonly property string trackAlbumArtist: trackArtist
        readonly property string trackArtUrl: root.sharedLocalState ? root.sharedLocalState.art : ""
        readonly property string trackArtists: trackArtist
        readonly property bool isPlaying: root.sharedLocalState ? root.sharedLocalState.playing : false
        readonly property real position: root.sharedLocalState ? root.sharedLocalState.position : 0
        readonly property real length: root.sharedLocalState ? root.sharedLocalState.length : 0
        readonly property bool positionSupported: length > 0
        readonly property bool lengthSupported: positionSupported
        readonly property bool canSeek: positionSupported
        readonly property bool canControl: root.sharedLocalState !== null
        readonly property bool canPlay: canControl
        readonly property bool canPause: canControl && isPlaying
        readonly property bool canTogglePlaying: canControl
        readonly property bool canGoPrevious: canControl && root.sharedLocalState.canPrevious
        readonly property bool canGoNext: canControl && root.sharedLocalState.canNext
        readonly property var playbackState: isPlaying
            ? MprisPlaybackState.Playing
            : (canControl ? MprisPlaybackState.Paused : MprisPlaybackState.Stopped)

        function play() { if (!isPlaying) root.callHub("togglePlayback") }
        function pause() { if (isPlaying) root.callHub("togglePlayback") }
        function togglePlaying() { root.callHub("togglePlayback") }
        function next() { root.callHub("nextTrack") }
        function previous() { root.callHub("previousTrack") }
        function stop() { root.callHub("stopPlayback") }
        function seekTo(seconds) { root.callHub("seekPlayback", Number(seconds)) }
        function seek(offset) { seekTo(position + Number(offset)) }
    }

    function idFor(candidate) {
        return candidate ? String(candidate.dbusName || candidate.uniqueId || candidate.identity || "") : ""
    }

    function selectPlayer() {
        const available = root.players
        if (!available || available.length === 0) return null
        if (root.preferredPlayerId !== "") {
            for (const candidate of available) {
                if (root.idFor(candidate) === root.preferredPlayerId) return candidate
            }
        }
        if (root.localCandidate && root.localCandidate.isPlaying)
            return root.localCandidate
        for (const candidate of available) {
            if (candidate.isPlaying) return candidate
        }
        if (root.localCandidate)
            return root.localCandidate
        for (const candidate of available) {
            if (candidate.trackTitle) return candidate
        }
        return available[0]
    }

    function choosePlayer(candidate) {
        if (!candidate || root.players.indexOf(candidate) < 0) return false
        root.preferredPlayerId = root.idFor(candidate)
        return true
    }

    function automaticPlayerSelection() {
        root.preferredPlayerId = ""
    }
}
