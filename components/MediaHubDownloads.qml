import QtQuick
import Quickshell
import Quickshell.Io
import "DownloadsQueue.js" as DownloadsQueue

// Downloads controller for the Media Hub Downloads page.
//
// Owns all download state: the job model, queue orchestration,
// inspection/download lifecycle, persistence, restart recovery and every
// QML-facing signal. It is a narrow bridge to scripts/media-hub-downloads.py
// and is not a general command runner. MediaHub.qml binds to this
// controller's model, properties and signals and keeps only the Downloads
// page visual markup.
//
// UI-level side effects (toast notifications, activity log, opening a file
// location) are emitted as signals and handled by MediaHub.qml.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string projectPath: Quickshell.env("GPS_ROOT")
        || Quickshell.env("GPS_DESKTOP_ROOT") || ""
    readonly property string helperPath: root.projectPath ? (root.projectPath + "/scripts/media-hub-downloads.py") : "media-hub-downloads.py"
    readonly property string soundBin: root.projectPath + "/scripts/gps-sound"

    property bool checkingStatus: false
    property bool statusReady: false
    property var toolStatus: ({})
    property string statusError: ""

    property bool inspecting: false
    property string inspectRequestId: ""
    property string inspectError: ""
    property string inspectErrorCode: ""

    property bool downloading: false
    property string activeJobId: ""
    property bool cancelRequested: false
    property string lastDownloadLine: ""
    property string stderrLine: ""
    property string downloadError: ""
    property string downloadErrorCode: ""
    property bool terminalEventSeen: false

    property bool utilityBusy: false
    property string utilityAction: ""

    // ================================================================
    //  DOWNLOADS STATE + PERSISTENCE (owned by this controller)
    // ================================================================
    property bool downloadsStateReady: false
    property bool downloadsDirty: false
    property bool downloadsQueuePaused: false
    property var downloads: []

    property var dlInspection: null
    property string dlInspectedUrl: ""
    property string dlInspectRequestId: ""
    property int dlInspectSeq: 0
    property string dlError: ""
    property string dlErrorCode: ""

    property string dlUrlText: ""
    property string dlMode: "video"
    property string dlFormatId: ""
    property bool dlFormatHasAudio: false
    property string dlQuality: "Best"
    property string dlContainer: "Auto"
    property string dlAudioFormat: "original"
    property string dlAudioQuality: "best"
    property string dlScope: "single"
    property string dlPlaylistItems: ""
    property bool dlFullConfirmed: false
    property string dlDirectory: root.downloadVideoDir

    property var dlDestInfo: null
    property var dlPendingEnqueue: null
    property string dlDestError: ""
    property bool dlOpenVerifyPending: false
    property string dlOpenPath: ""
    property bool dlRestoreVerifyPending: false
    property string dlStatusError: ""

    readonly property bool dlInspecting: inspecting
    readonly property bool dlBusy: downloading || inspecting
    readonly property bool dlCanMerge: toolStatus.ffmpegReady === true

    readonly property string downloadStateDir: {
        var stateHome = Quickshell.env("XDG_STATE_HOME")
        if (!stateHome) stateHome = Quickshell.env("HOME") + "/.local/state"
        return stateHome + "/gps"
    }
    readonly property string downloadStatePath: root.downloadStateDir + "/media-hub-downloads.json"
    readonly property string downloadVideoDir: {
        var videos = Quickshell.env("XDG_VIDEOS_DIR")
        if (videos && videos !== Quickshell.env("HOME")) return videos + "/GPS"
        return Quickshell.env("HOME") + "/Videos/GPS"
    }
    readonly property string downloadAudioDir: {
        var music = Quickshell.env("GPS_MUSIC_DIR")
        if (!music) music = Quickshell.env("HOME") + "/Music"
        return music + "/GPS"
    }

    readonly property string downloadsSaveKey: JSON.stringify([downloads, downloadsQueuePaused])
    onDownloadsSaveKeyChanged: {
        if (!downloadsStateReady) return
        downloadsDirty = true
        if (!downloadSaveTimer.running) downloadSaveTimer.start()
    }

    Timer {
        id: downloadSaveTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (!root.downloadsStateReady) return
            downloadsStateFile.setText(DownloadsQueue.serialize(root.downloads, root.downloadsQueuePaused))
            root.downloadsDirty = false
        }
    }

    Timer {
        id: dlQueueTimer
        interval: 160
        repeat: false
        onTriggered: root.pumpDownloadQueue()
    }

    Process {
        id: downloadStateDirProc
        command: ["mkdir", "-p", root.downloadStateDir]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.downloadsStateReady = true
                root.downloadStateFolderFailed()
                return
            }
            downloadsStateFile.path = root.downloadStatePath
        }
    }

    FileView {
        id: downloadsStateFile
        path: ""
        printErrors: false
        onLoaded: {
            var state = DownloadsQueue.parseState(downloadsStateFile.text())
            if (state === null) {
                var raw = downloadsStateFile.text()
                downloadsStateBackup.path = root.downloadStatePath.replace(/\.json$/, ".corrupt-" + Date.now() + ".json")
                downloadsStateBackup.setText(raw)
                root.downloads = []
                root.downloadsQueuePaused = false
                root.downloadsStateReady = true
                root.downloadHistoryUnreadable()
                return
            }
            root.applyDownloadsState(state)
        }
        onLoadFailed: root.downloadsStateReady = true
    }

    FileView {
        id: downloadsStateBackup
        printErrors: false
    }

    Component.onCompleted: {
        downloadStateDirProc.running = true
    }

    // ================================================================
    //  SIGNALS (QML-facing controller events; MediaHub.qml connects them)
    // ================================================================
    signal statusFinished(var payload)
    signal inspectSucceeded(var payload, string requestId)
    signal inspectFailed(string message, string code, string requestId)
    signal downloadStarted(string jobId)
    signal downloadProgress(var payload, string jobId)
    signal downloadPostprocess(var payload, string jobId)
    signal downloadFile(string path, string jobId)
    signal downloadFinished(var payload, string jobId)
    signal downloadFailed(string message, string code, string jobId)
    signal downloadCancelled(string jobId)
    signal downloadEnded(string jobId)
    signal utilitySucceeded(var payload, string action)
    signal utilityFailed(string message, string code, string action)

    onStatusFinished: (payload) => root.handleDownloadStatus(payload)
    onInspectSucceeded: (payload, requestId) => root.handleDownloadInspection(payload, requestId)
    onInspectFailed: (message, code, requestId) => root.handleDownloadInspectFailure(message, code, requestId)
    onDownloadStarted: (jobId) => root.handleDownloadStarted(jobId)
    onDownloadProgress: (payload, jobId) => root.handleDownloadProgress(payload, jobId)
    onDownloadPostprocess: (payload, jobId) => root.handleDownloadPostprocess(payload, jobId)
    onDownloadFile: (path, jobId) => root.handleDownloadFile(path, jobId)
    onDownloadFinished: (payload, jobId) => root.handleDownloadFinished(payload, jobId)
    onDownloadFailed: (message, code, jobId) => root.handleDownloadFailure(message, code, jobId)
    onDownloadCancelled: (jobId) => root.handleDownloadCancelled(jobId)
    onUtilitySucceeded: (payload, action) => root.handleDownloadUtilitySuccess(payload, action)
    onUtilityFailed: (message, code, action) => root.handleDownloadUtilityFailure(message, code, action)

    // UI-level side effects handled by MediaHub.qml
    signal notify(string text, string kind)
    signal logActivity(string message)
    signal openLocationRequested(string path)
    signal downloadStateFolderFailed()
    signal downloadHistoryUnreadable()

    // ================================================================
    //  HELPER FUNCTIONS
    // ================================================================
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

    function errorMessage(payload, stderrText, exitCode, fallback) {
        if (payload && typeof payload.message === "string" && payload.message !== "")
            return DownloadsQueue.redact(payload.message);
        const err = String(stderrText || "").trim()
        if (err !== "") return DownloadsQueue.redact(err.split("\n").slice(-1)[0]);
        if (exitCode !== 0) return fallback + " exited with code " + exitCode + "."
        return fallback + " returned an unexpected response."
    }

    function expandHomePath(value) {
        var path = String(value || "").trim()
        if (path === "~") return Quickshell.env("HOME")
        if (path.indexOf("~/") === 0) return Quickshell.env("HOME") + path.slice(1)
        return path
    }

    function downloadDirForMode(mode) {
        return mode === "audio" ? root.downloadAudioDir : root.downloadVideoDir
    }

    function findIn(list, id) {
        if (!list) return null
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }

    function updateDownload(id, patch) {
        downloads = downloads.map(function (d) {
            return d.id === id ? Object.assign({}, d, patch, { updatedAt: Date.now() }) : d
        })
    }
    function removeDownload(id) { downloads = downloads.filter(function (d) { return d.id !== id }) }
    function dlCount(status) {
        var n = 0
        for (var i = 0; i < downloads.length; i++) if (status === "all" || downloads[i].status === status) n++
        return n
    }
    function dlActiveCount() {
        var n = 0
        for (var i = 0; i < downloads.length; i++)
            if (DownloadsQueue.isActiveStatus(downloads[i].status)) n++
        return n
    }
    function downloadJob(id) { return findIn(downloads, id) }

    // ================================================================
    //  BACKEND LIFECYCLE
    // ================================================================
    function checkStatus() {
        if (root.checkingStatus || statusProc.running) return false
        root.checkingStatus = true
        root.statusError = ""
        statusProc.running = true
        return true
    }

    function inspect(url, requestId) {
        if (root.inspecting || inspectProc.running) {
            root.inspectFailed("Another link is already being inspected.", "inspect_busy", String(requestId || ""))
            return false
        }
        if (root.downloading || downloadProc.running) {
            root.inspectFailed("Wait for the active download to finish before inspecting another link.", "download_busy", String(requestId || ""))
            return false
        }
        const safeUrl = DownloadsQueue.cleanUrl(url)
        if (safeUrl === "") {
            root.inspectFailed("That is not a valid public HTTP or HTTPS URL.", "invalid_url", String(requestId || ""))
            return false
        }
        if (!root.statusReady) root.checkStatus()
        root.inspecting = true
        root.inspectRequestId = String(requestId || "")
        root.inspectError = ""
        root.inspectErrorCode = ""
        inspectProc.command = [root.helperPath, "inspect", "--url", safeUrl]
        inspectProc.running = true
        return true
    }

    function cancelInspect() {
        if (!root.inspecting || !inspectProc.running) return false
        inspectProc.signal(15)
        return true
    }

    function startDownload(rawJob) {
        if (root.downloading || downloadProc.running) {
            root.downloadFailed("Another download is already running.", "download_busy", rawJob && rawJob.id ? String(rawJob.id) : "")
            return false
        }
        if (root.inspecting || inspectProc.running) {
            root.downloadFailed("Wait for link inspection to finish before starting a download.", "inspect_busy", rawJob && rawJob.id ? String(rawJob.id) : "")
            return false
        }
        const job = DownloadsQueue.sanitizeJob(rawJob)
        if (job === null) {
            root.downloadFailed("The download job is invalid.", "invalid_job", rawJob && rawJob.id ? String(rawJob.id) : "")
            return false
        }
        if (job.scope === "selected" && DownloadsQueue.validatePlaylistSpec(job.playlistItems).ok !== true) {
            root.downloadFailed("The playlist selection is invalid.", "invalid_playlist", job.id)
            return false
        }
        root.downloading = true
        root.activeJobId = job.id
        root.cancelRequested = false
        root.terminalEventSeen = false
        root.lastDownloadLine = ""
        root.stderrLine = ""
        root.downloadError = ""
        root.downloadErrorCode = ""
        downloadProc.command = [
            root.helperPath, "download",
            "--url", job.url,
            "--job-id", job.id,
            "--mode", job.mode,
            "--output-dir", job.dest,
            "--scope", job.scope,
            "--format-id", job.formatId,
            "--format-has-audio", job.formatHasAudio ? "true" : "false",
            "--quality-cap", String(job.qualityCap),
            "--container", job.container,
            "--audio-format", job.audioFormat,
            "--audio-quality", job.audioQuality,
            "--playlist-items", job.playlistItems,
            "--playlist-count", String(job.playlistCount)
        ]
        downloadProc.running = true
        return true
    }

    function cancelDownload() {
        if (!root.downloading || !downloadProc.running) return false
        if (root.cancelRequested) return true
        root.cancelRequested = true
        downloadProc.signal(15)
        return true
    }

    function checkDestination(path) {
        const safePath = DownloadsQueue.cleanPath(path)
        if (safePath === "") {
            root.utilityFailed("Choose an absolute output folder.", "invalid_destination", "check-destination")
            return false
        }
        return root.runUtility("check-destination", ["--path", safePath])
    }

    function createDestination(path) {
        const safePath = DownloadsQueue.cleanPath(path)
        if (safePath === "") {
            root.utilityFailed("Choose an absolute output folder.", "invalid_destination", "create-destination")
            return false
        }
        if (safePath === "/") {
            root.utilityFailed("Choose a dedicated download folder, not the filesystem root.", "invalid_destination", "create-destination")
            return false
        }
        return root.runUtility("create-destination", ["--path", safePath])
    }

    function verify(paths) {
        if (!Array.isArray(paths) || paths.length < 1 || paths.length > 100) {
            root.utilityFailed("No saved output files to verify.", "invalid_request", "verify")
            return false
        }
        const command = []
        for (let i = 0; i < paths.length; i++) {
            const safePath = DownloadsQueue.cleanPath(paths[i])
            if (safePath === "") continue
            command.push("--path", safePath)
        }
        if (command.length < 2) {
            root.utilityFailed("No valid saved output files to verify.", "invalid_request", "verify")
            return false
        }
        return root.runUtility("verify", command)
    }

    function runUtility(action, args) {
        if (root.utilityBusy || utilityProc.running) {
            root.utilityFailed("Another folder check is already running.", "utility_busy", action)
            return false
        }
        root.utilityBusy = true
        root.utilityAction = action
        utilityProc.command = [root.helperPath, action].concat(args)
        utilityProc.running = true
        return true
    }

    function handleDownloadLine(line) {
        root.lastDownloadLine = String(line || "")
        const payload = root.parsePayload(line)
        if (payload === null) return
        const jobId = root.activeJobId
        if (payload.event === "started") {
            root.downloadStarted(jobId)
        } else if (payload.event === "progress") {
            root.downloadProgress(payload, jobId)
        } else if (payload.event === "postprocess") {
            root.downloadPostprocess(payload, jobId)
        } else if (payload.event === "file") {
            if (typeof payload.path === "string" && payload.path !== "")
                root.downloadFile(payload.path, jobId)
        } else if (payload.event === "finished") {
            root.terminalEventSeen = true
            root.downloadFinished(payload, jobId)
        } else if (payload.event === "failed") {
            root.terminalEventSeen = true
            root.downloadFailed(
                typeof payload.message === "string" ? DownloadsQueue.redact(payload.message) : "The download failed.",
                typeof payload.code === "string" ? payload.code : "download_failed",
                jobId
            )
        } else if (payload.event === "cancelled") {
            root.terminalEventSeen = true
            root.downloadCancelled(jobId)
        }
    }

    // ================================================================
    //  DOWNLOAD PAGE ACTIONS
    // ================================================================
    readonly property bool downloadBackendConnected: root.statusReady
        && root.toolStatus.ytDlpReady === true

    function inspectDownloadUrl() {
        var url = DownloadsQueue.cleanUrl(root.dlUrlText)
        if (url === "") {
            root.dlError = "Paste a public HTTP or HTTPS media URL first."
            root.dlErrorCode = "invalid_url"
            return false
        }
        for (var i = 0; i < downloads.length; i++) {
            var job = downloads[i]
            if (job.url === url && (job.status === "queued" || DownloadsQueue.isActiveStatus(job.status))) {
                root.dlError = "This URL is already queued or downloading."
                root.dlErrorCode = "duplicate"
                return false
            }
        }
        if (!root.downloadBackendConnected) {
            root.checkStatus()
            root.dlError = root.dlStatusError || "yt-dlp is not available. Install it, then press Recheck."
            root.dlErrorCode = "yt_dlp_missing"
            return false
        }
        root.dlInspectSeq++
        root.dlInspectRequestId = "inspect-" + root.dlInspectSeq
        root.dlInspection = null
        root.dlInspectedUrl = ""
        root.dlError = ""
        root.dlErrorCode = ""
        return root.inspect(url, root.dlInspectRequestId)
    }
    function cancelDownloadInspection() {
        if (!root.inspecting) return
        root.cancelInspect()
        root.dlError = "Cancelling inspection\u2026"
    }
    function handleDownloadInspection(payload, requestId) {
        if (requestId !== "" && root.dlInspectRequestId !== "" && requestId !== root.dlInspectRequestId) return
        root.dlInspection = payload
        root.dlInspectedUrl = DownloadsQueue.cleanUrl(payload.url)
        root.dlFormatId = ""
        root.dlFormatHasAudio = false
        root.dlQuality = "Best"
        root.dlContainer = "Auto"
        root.dlAudioFormat = "original"
        root.dlAudioQuality = "best"
        root.dlScope = "single"
        root.dlFullConfirmed = false
        root.dlError = ""
        root.dlErrorCode = ""
        root.dlDestInfo = null
        root.dlDestError = ""
    }
    function handleDownloadInspectFailure(message, code, requestId) {
        if (requestId !== "" && requestId !== root.dlInspectRequestId) return
        root.dlInspection = null
        root.dlInspectedUrl = ""
        root.dlError = String(message || "Link inspection failed.")
        root.dlErrorCode = String(code || "inspect_failed")
        if (code === "yt_dlp_missing" || code === "ffmpeg_missing") root.checkStatus()
        dlQueueTimer.restart()
    }
    function handleDownloadStatus(payload) {
        if (payload === null) {
            root.dlStatusError = root.statusError
            return
        }
        root.dlStatusError = ""
    }
    function downloadDestinationReady() {
        return root.dlDestInfo !== null
            && root.dlDestInfo.exists === true && root.dlDestInfo.writable === true
    }
    function downloadDestinationLabel() {
        if (root.dlDestError !== "") return root.dlDestError
        if (!root.dlDestInfo) return ""
        if (root.dlDestInfo.exists !== true) return "Folder does not exist. Create it before downloading."
        if (root.dlDestInfo.writable !== true) return "Folder is not writable."
        return "Folder ready."
    }
    function checkDownloadDestination() {
        var dest = expandHomePath(root.dlDirectory)
        if (DownloadsQueue.cleanPath(dest) === "") {
            root.dlDestError = "Choose an absolute output folder."
            root.dlDestInfo = null
            return false
        }
        root.dlPendingEnqueue = null
        root.dlDestInfo = null
        root.dlDestError = ""
        return root.checkDestination(dest)
    }
    function createDownloadDestination() {
        var dest = expandHomePath(root.dlDirectory)
        if (DownloadsQueue.cleanPath(dest) === "") {
            root.dlDestError = "Choose an absolute output folder."
            return false
        }
        root.dlDestError = ""
        return root.createDestination(dest)
    }
    function buildDownloadRequest() {
        var meta = root.dlInspection
        if (!meta) return null
        var playlist = meta.playlist || ({})
        var item = meta.item || ({})
        var dest = expandHomePath(root.dlDirectory)
        if (DownloadsQueue.cleanPath(dest) === "") {
            root.dlError = "Choose an absolute output folder."
            return null
        }
        if (!root.downloadPlaylistValid()) {
            root.dlError = root.dlScope === "full"
                ? "Confirm the full playlist download first."
                : "Enter valid playlist item numbers."
            return null
        }
        if (root.dlMode === "audio" && root.dlAudioFormat !== "original" && !root.dlCanMerge) {
            root.dlError = "FFmpeg is required to convert audio to that format."
            return null
        }
        if (root.dlMode === "video" && !root.dlCanMerge
                && (root.dlContainer !== "Auto" || (root.dlFormatId !== "" && !root.dlFormatHasAudio))) {
            root.dlError = "FFmpeg is required to merge that video format or container."
            return null
        }
        var scope = playlist.isPlaylist === true ? root.dlScope : "single"
        var playlistCount = 0
        if (scope === "full") playlistCount = Math.min(Number(playlist.count) || 0, DownloadsQueue.MAX_PLAYLIST_ITEMS)
        var cap = 0
        if (root.dlMode === "video" && root.dlFormatId === "") {
            var match = /^([0-9]{1,5})p$/.exec(root.dlQuality)
            if (match) cap = Number(match[1])
        }
        var qualityLabel = root.dlMode === "audio"
            ? (root.dlFormatId !== "" ? root.dlQuality : (root.dlAudioFormat === "original" ? "Original" : root.dlAudioFormat.toUpperCase() + (root.dlAudioQuality === "best" ? "" : " " + root.dlAudioQuality)))
            : root.dlQuality
        return {
            url: root.dlInspectedUrl,
            title: item.title || meta.title || "Untitled media",
            source: meta.source || "",
            extractor: meta.source || "",
            uploader: item.uploader || meta.uploader || "",
            thumbnail: item.thumbnail || meta.thumbnail || "",
            duration: item.duration || meta.duration || 0,
            mode: root.dlMode,
            formatId: root.dlFormatId,
            formatHasAudio: root.dlFormatHasAudio,
            qualityCap: cap,
            quality: qualityLabel,
            container: root.dlMode === "video" ? root.dlContainer : "Auto",
            audioFormat: root.dlMode === "audio" ? root.dlAudioFormat : "original",
            audioQuality: root.dlMode === "audio" ? root.dlAudioQuality : "best",
            scope: scope,
            playlistItems: scope === "selected" ? root.dlPlaylistItems.trim() : "",
            playlistCount: playlistCount,
            playlistTitle: playlist.isPlaylist === true ? (meta.title || "") : "",
            dest: dest
        }
    }
    function enqueueInspectedDownload() {
        if (root.dlInspecting) {
            root.dlError = "Wait for link inspection to finish."
            return false
        }
        if (!root.downloadBackendConnected) {
            root.dlError = root.dlStatusError || "yt-dlp is not available. Install it, then press Recheck."
            return false
        }
        var request = root.buildDownloadRequest()
        if (request === null) return false
        for (var i = 0; i < downloads.length; i++) {
            if (downloads[i].url === request.url
                    && (downloads[i].status === "queued" || DownloadsQueue.isActiveStatus(downloads[i].status))) {
                root.dlError = "This URL is already queued or downloading."
                return false
            }
        }
        root.dlPendingEnqueue = request
        root.dlError = ""
        root.dlDestError = ""
        return root.checkDestination(request.dest)
    }
    function commitDownloadEnqueue(request) {
        if (!request) return false
        var job = DownloadsQueue.createJob(request, Date.now())
        if (job === null) {
            root.dlError = "That download request is invalid."
            root.dlPendingEnqueue = null
            return false
        }
        downloads = [job].concat(downloads)
        root.dlPendingEnqueue = null
        root.dlError = ""
        root.dlErrorCode = ""
        root.dlUrlText = ""
        root.dlInspection = null
        root.dlInspectedUrl = ""
        root.dlScope = "single"
        root.dlFullConfirmed = false
        root.dlFormatId = ""
        root.dlFormatHasAudio = false
        root.dlQuality = "Best"
        root.dlError = ""
        root.dlErrorCode = ""
        root.notify("Queued \u201c" + job.title + "\u201d.", "info")
        root.logActivity("Queued download: " + job.title)
        dlQueueTimer.restart()
        return true
    }
    function handleDownloadUtilitySuccess(payload, action) {
        if (action === "check-destination") {
            root.dlDestInfo = payload
            root.dlDestError = ""
            var pending = root.dlPendingEnqueue
            if (pending) {
                if (payload.exists === true && payload.writable === true) {
                    root.commitDownloadEnqueue(pending)
                } else if (payload.exists !== true) {
                    root.dlError = "That folder does not exist. Create it before adding the download."
                } else {
                    root.dlError = "That folder is not writable. Choose another folder."
                }
            }
            return
        }
        if (action === "create-destination") {
            root.dlDestInfo = ({ path: payload.path, exists: true, directory: true, writable: true, message: "" })
            root.dlDestError = ""
            var waiting = root.dlPendingEnqueue
            if (waiting) root.commitDownloadEnqueue(waiting)
            return
        }
        if (action === "verify") {
            var results = DownloadsQueue.toArray(payload.results)
            if (root.dlOpenVerifyPending) {
                root.dlOpenVerifyPending = false
                var openOk = true
                for (var i = 0; i < results.length; i++) {
                    if (results[i].ok !== true) {
                        openOk = false
                        root.markDownloadMissing(results[i].path, results[i].message)
                    }
                }
                if (openOk) root.openLocationRequested(root.dlOpenPath)
                else root.notify("The saved output file is missing. The job was marked failed.", "warn")
                root.dlOpenPath = ""
                return
            }
            if (root.dlRestoreVerifyPending) {
                root.dlRestoreVerifyPending = false
                var missing = 0
                for (var j = 0; j < results.length; j++) {
                    if (results[j].ok !== true) {
                        missing++
                        root.markDownloadMissing(results[j].path, results[j].message)
                    }
                }
                if (missing > 0)
                    root.notify(missing + " saved download" + (missing === 1 ? " is" : "s are") + " no longer available.", "warn")
            }
        }
    }
    function handleDownloadUtilityFailure(message, code, action) {
        if (action === "check-destination") {
            root.dlDestInfo = null
            root.dlDestError = String(message || "Could not check that folder.")
            if (root.dlPendingEnqueue) root.dlError = root.dlDestError
            root.dlPendingEnqueue = null
        } else if (action === "create-destination") {
            root.dlDestError = String(message || "Could not create that folder.")
        } else if (action === "verify") {
            root.dlOpenVerifyPending = false
            root.dlRestoreVerifyPending = false
            root.dlOpenPath = ""
            root.notify(String(message || "Could not verify the saved download."), "warn")
        }
    }
    function markDownloadMissing(path, message) {
        var target = DownloadsQueue.cleanPath(path)
        if (target === "") return false
        var found = false
        downloads = downloads.map(function (job) {
            if (job.status !== "completed") return job
            var files = job.files || []
            if (files.indexOf(target) < 0 && job.finalPath !== target) return job
            found = true
            return Object.assign({}, job, {
                status: "failed",
                statusDetail: "Output missing",
                error: String(message || "The saved output file is missing."),
                errorCode: "file_missing",
                interrupted: false,
                updatedAt: Date.now()
            })
        })
        return found
    }
    function applyDownloadsState(state) {
        var jobs = []
        var interrupted = 0
        var queued = 0
        var changed = false
        for (var i = 0; i < state.jobs.length; i++) {
            var job = DownloadsQueue.sanitizeJob(state.jobs[i])
            if (job === null) continue
            if (DownloadsQueue.isActiveStatus(job.status)) {
                job.status = "failed"
                job.statusDetail = "Interrupted"
                job.error = "GPS closed before this download finished. Retry to resume it."
                job.errorCode = "interrupted"
                job.interrupted = true
                job.updatedAt = Date.now()
                interrupted++
                changed = true
            } else if (job.status === "paused") {
                job.status = "queued"
                job.statusDetail = "Queued after restart"
                job.updatedAt = Date.now()
                changed = true
            }
            if (job.status === "queued") {
                queued++
                job.statusDetail = "Paused after restart"
            }
            if (job.status === "completed") {
                var files = (job.files || []).slice()
                if (job.finalPath !== "" && files.indexOf(job.finalPath) < 0) files.unshift(job.finalPath)
                if (files.length === 0) {
                    job.status = "failed"
                    job.statusDetail = "Output missing"
                    job.error = "No output file was recorded for this download."
                    job.errorCode = "file_missing"
                    changed = true
                } else {
                    job.files = files
                }
            }
            jobs.push(job)
        }
        root.downloads = jobs
        root.downloadsQueuePaused = state.queuePaused === true || queued > 0
        root.downloadsStateReady = true
        if (changed || (queued > 0 && state.queuePaused !== true)) downloadSaveTimer.restart()
        if (interrupted > 0)
            root.notify(interrupted + " interrupted download" + (interrupted === 1 ? " was" : "s were") + " marked failed.", "warn")
        if (queued > 0)
            root.notify("Restored " + queued + " queued download" + (queued === 1 ? "" : "s") + ". The queue is paused.", "info")
        root.verifyRestoredDownloads()
    }
    function verifyRestoredDownloads() {
        var paths = []
        for (var i = 0; i < downloads.length && paths.length < 100; i++) {
            var job = downloads[i]
            if (job.status !== "completed") continue
            var files = job.files || []
            for (var j = 0; j < files.length && paths.length < 100; j++) {
                var path = DownloadsQueue.cleanPath(files[j])
                if (path !== "" && paths.indexOf(path) < 0) paths.push(path)
            }
        }
        if (paths.length === 0) return
        root.dlRestoreVerifyPending = true
        if (!root.verify(paths)) root.dlRestoreVerifyPending = false
    }
    function pumpDownloadQueue() {
        if (!root.downloadsStateReady || root.downloadsQueuePaused || root.dlInspecting) return
        if (root.downloading || root.dlActiveCount() > 0) return
        if (!root.downloadBackendConnected) return
        var index = DownloadsQueue.nextQueuedIndex(downloads)
        if (index < 0) return
        root.startDownloadAt(index)
    }
    function startDownloadAt(index) {
        var current = downloads[index]
        if (!current || current.status !== "queued") return false
        var job = DownloadsQueue.sanitizeJob(current)
        if (job === null) {
            root.updateDownload(current.id, { status: "failed", statusDetail: "Invalid job",
                error: "This job is invalid and cannot be started.", errorCode: "invalid_job" })
            dlQueueTimer.restart()
            return false
        }
        if (job.attempts >= DownloadsQueue.MAX_ATTEMPTS) {
            root.updateDownload(job.id, { status: "failed", statusDetail: "Retry limit",
                error: "This job reached the retry limit.", errorCode: "retry_limit" })
            return false
        }
        job.status = "downloading"
        job.statusDetail = "Starting"
        job.attempts += 1
        job.startedAt = Date.now()
        job.completedAt = 0
        job.error = ""
        job.errorCode = ""
        job.interrupted = false
        job.progress = 0
        job.downloadedBytes = 0
        job.totalBytes = 0
        job.speed = 0
        job.eta = 0
        job.fragmentIndex = 0
        job.fragmentCount = 0
        job.postprocessor = ""
        job.updatedAt = Date.now()
        downloads = downloads.map(function (d) { return d.id === job.id ? job : d })
        if (!root.startDownload(job)) dlQueueTimer.restart()
        return true
    }
    function handleDownloadStarted(jobId) {
        root.updateDownload(jobId, { status: "downloading", statusDetail: "Downloading" })
    }
    function handleDownloadProgress(payload, jobId) {
        var job = root.downloadJob(jobId)
        if (!job) return
        var downloaded = Number(payload.downloadedBytes) || 0
        var total = Number(payload.totalBytes) || Number(payload.totalBytesEstimate) || 0
        var patch = {
            status: job.status === "postprocessing" ? "postprocessing" : "downloading",
            downloadedBytes: downloaded,
            totalBytes: total,
            speed: Number(payload.speed) || 0,
            eta: Number(payload.eta) || 0,
            fragmentIndex: Number(payload.fragmentIndex) || 0,
            fragmentCount: Number(payload.fragmentCount) || 0,
            statusDetail: root.cancelRequested ? "Cancelling\u2026" : "Downloading"
        }
        patch.progress = DownloadsQueue.progressFraction(Object.assign({}, job, patch))
        root.updateDownload(jobId, patch)
    }
    function handleDownloadPostprocess(payload, jobId) {
        var job = root.downloadJob(jobId)
        if (!job) return
        var name = String(payload.postprocessor || "")
        root.updateDownload(jobId, {
            status: "postprocessing",
            progress: 1,
            postprocessor: name,
            statusDetail: name !== "" ? ("Processing with " + name) : "Processing"
        })
    }
    function handleDownloadFile(path, jobId) {
        var clean = DownloadsQueue.cleanPath(path)
        if (clean === "") return
        var job = root.downloadJob(jobId)
        if (!job) return
        var files = (job.files || []).slice()
        if (files.indexOf(clean) < 0) files.push(clean)
        root.updateDownload(jobId, { files: files, finalPath: files[0] || clean, statusDetail: "Saving file" })
    }
    function handleDownloadFinished(payload, jobId) {
        var files = []
        var payloadFiles = DownloadsQueue.toArray(payload.files)
        for (var i = 0; i < payloadFiles.length; i++) {
            var clean = DownloadsQueue.cleanPath(payloadFiles[i])
            if (clean !== "" && files.indexOf(clean) < 0) files.push(clean)
        }
        var job = root.downloadJob(jobId)
        if (job && files.length === 0) files = (job.files || []).slice()
        if (files.length === 0) {
            root.handleDownloadFailure("The download finished without a verified file.", "file_unverified", jobId)
            return
        }
        root.updateDownload(jobId, {
            status: "completed",
            statusDetail: "Completed",
            progress: 1,
            files: files,
            finalPath: files[0],
            completedAt: Date.now(),
            interrupted: false,
            error: "",
            errorCode: "",
            postprocessor: ""
        })
        var finished = root.downloadJob(jobId)
        root.notify("Downloaded \u201c" + (finished ? finished.title : "media") + "\u201d.", "info")
        root.logActivity("Download complete: " + (finished ? finished.title : jobId))
        Quickshell.execDetached([root.soundBin, "play", "download-done"])
        dlQueueTimer.restart()
    }
    function handleDownloadFailure(message, code, jobId) {
        var job = root.downloadJob(jobId)
        if (!job) return
        root.updateDownload(jobId, {
            status: "failed",
            statusDetail: "Failed",
            error: String(message || "The download failed."),
            errorCode: String(code || "download_failed"),
            interrupted: false,
            speed: 0,
            eta: 0
        })
        root.dlError = String(message || "The download failed.")
        root.dlErrorCode = String(code || "download_failed")
        root.notify("Download failed: " + root.dlError, "warn")
        root.logActivity("Download failed: " + root.dlErrorCode)
        Quickshell.execDetached([root.soundBin, "play", "download-failed"])
        dlQueueTimer.restart()
    }
    function handleDownloadCancelled(jobId) {
        var job = root.downloadJob(jobId)
        if (!job) return
        root.updateDownload(jobId, {
            status: "cancelled",
            statusDetail: "Cancelled",
            error: "Cancelled by user.",
            errorCode: "cancelled",
            interrupted: false,
            speed: 0,
            eta: 0
        })
        root.notify("Download cancelled.", "info")
        dlQueueTimer.restart()
    }
    function retryDownload(id) {
        var job = root.downloadJob(id)
        if (!job || !DownloadsQueue.canRetry(job)) {
            root.notify("This job cannot be retried.", "warn")
            return false
        }
        root.updateDownload(id, {
            status: "queued",
            statusDetail: "Queued for retry",
            progress: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            speed: 0,
            eta: 0,
            fragmentIndex: 0,
            fragmentCount: 0,
            postprocessor: "",
            error: "",
            errorCode: "",
            interrupted: false,
            completedAt: 0
        })
        if (root.downloadsQueuePaused) root.notify("Retry queued. Resume the queue to start it.", "info")
        dlQueueTimer.restart()
        return true
    }
    function openDownload(id) {
        var job = root.downloadJob(id)
        if (!job) return
        var files = (job.files || []).slice()
        if (job.finalPath && files.indexOf(job.finalPath) < 0) files.unshift(job.finalPath)
        if (files.length === 0) {
            root.notify("No saved output file is recorded for this job.", "warn")
            return
        }
        root.dlOpenVerifyPending = true
        root.dlOpenPath = job.dest
        if (!root.verify(files.slice(0, 100))) {
            root.dlOpenVerifyPending = false
            root.dlOpenPath = ""
        }
    }
    function setDownloadMode(mode) {
        if (mode !== "video" && mode !== "audio") return
        var previous = root.downloadDirForMode(root.dlMode)
        var old = root.dlMode
        root.dlMode = mode
        if (root.dlDirectory === previous || root.dlDirectory === "")
            root.dlDirectory = root.downloadDirForMode(mode)
        root.dlFormatId = ""
        root.dlFormatHasAudio = false
        root.dlQuality = "Best"
        root.dlContainer = "Auto"
        root.dlAudioFormat = "original"
        root.dlAudioQuality = "best"
        root.dlScope = "single"
        root.dlFullConfirmed = false
        root.dlError = ""
        root.dlDestInfo = null
        root.dlDestError = ""
        root.dlPendingEnqueue = null
        if (old === mode) return
    }
    function setDownloadDirectory(value) {
        root.dlDirectory = String(value || "")
        root.dlDestInfo = null
        root.dlDestError = ""
        root.dlPendingEnqueue = null
        root.dlError = ""
    }
    function setDownloadScope(scope) {
        if (["single", "selected", "full"].indexOf(scope) < 0) return
        root.dlScope = scope
        root.dlFullConfirmed = false
        root.dlError = ""
    }
    function setDownloadQuality(value) {
        root.dlQuality = String(value || "Best")
        root.dlFormatId = ""
        root.dlFormatHasAudio = false
        root.dlError = ""
    }
    function selectDownloadFormat(format) {
        if (!format || typeof format.format_id !== "string") {
            root.dlFormatId = ""
            root.dlFormatHasAudio = false
            root.dlQuality = "Best"
            return
        }
        root.dlFormatId = DownloadsQueue.cleanFormatId(format.format_id)
        root.dlFormatHasAudio = format.hasAudio === true
        root.dlQuality = DownloadsQueue.formatLabel(format)
        root.dlError = ""
    }
    function selectAudioSource(format) { root.selectDownloadFormat(format) }
    function downloadQualityChoices() {
        var heights = root.dlInspection && root.dlInspection.qualityHeights
            ? root.dlInspection.qualityHeights : []
        var out = ["Best"]
        if (heights && heights.length > 0) {
            for (var i = 0; i < heights.length; i++) {
                var label = String(Math.round(Number(heights[i]))) + "p"
                if (heights[i] > 0 && out.indexOf(label) < 0) out.push(label)
            }
        } else {
            out = out.concat(["2160p", "1440p", "1080p", "720p", "480p"])
        }
        return out
    }
    function downloadVideoFormats() {
        if (!root.dlInspection) return []
        return DownloadsQueue.toArray(root.dlInspection.videoFormats).slice(0, 5)
    }
    function downloadAudioSources() {
        if (!root.dlInspection) return []
        return DownloadsQueue.toArray(root.dlInspection.audioFormats).slice(0, 4)
    }
    function downloadPlaylist() {
        return root.dlInspection && root.dlInspection.playlist
            ? root.dlInspection.playlist : null
    }
    function downloadPlaylistSelectedCount() {
        if (root.dlScope !== "selected") return 0
        var checked = DownloadsQueue.validatePlaylistSpec(root.dlPlaylistItems)
        return checked.ok ? checked.count : 0
    }
    function downloadPlaylistValid() {
        var playlist = root.downloadPlaylist()
        if (!playlist || playlist.isPlaylist !== true) return true
        if (root.dlScope === "selected") return DownloadsQueue.validatePlaylistSpec(root.dlPlaylistItems).ok
        if (root.dlScope === "full") {
            return root.dlFullConfirmed && playlist.count > 0
        }
        return true
    }
    function clearDownloadPreview() {
        root.dlInspection = null
        root.dlInspectedUrl = ""
        root.dlInspectRequestId = ""
        root.dlError = ""
        root.dlErrorCode = ""
        root.dlFormatId = ""
        root.dlFormatHasAudio = false
        root.dlQuality = "Best"
        root.dlScope = "single"
        root.dlFullConfirmed = false
    }
    function setDownloadQueuePaused(paused) {
        root.downloadsQueuePaused = paused === true
        if (!root.downloadsQueuePaused) dlQueueTimer.restart()
    }
    function toggleDownloadQueue() {
        root.setDownloadQueuePaused(!root.downloadsQueuePaused)
        root.notify(root.downloadsQueuePaused ? "Queue paused. The active download keeps running." : "Queue resumed.", "info")
    }
    function clearFinishedDownloads() {
        downloads = downloads.filter(function (d) {
            return d.status !== "completed" && d.status !== "failed" && d.status !== "cancelled"
        })
        root.notify("Finished download history cleared.", "info")
    }
    function dlAction(d, action) {
        var job = root.downloadJob(d.id)
        if (!job) return
        if (action === "cancel") {
            if (DownloadsQueue.isActiveStatus(job.status)) {
                if (root.downloading) {
                    root.cancelDownload()
                    root.updateDownload(job.id, { statusDetail: "Cancelling\u2026" })
                } else {
                    root.handleDownloadFailure("This job is not running.", "not_running", job.id)
                }
            } else {
                root.removeDownload(job.id)
                root.notify("Removed from the queue.", "info")
            }
        } else if (action === "remove") {
            if (DownloadsQueue.isActiveStatus(job.status)) {
                root.notify("Cancel the active download before removing it.", "warn")
                return
            }
            root.removeDownload(job.id)
        } else if (action === "retry") {
            root.retryDownload(job.id)
        } else if (action === "open") {
            root.openDownload(job.id)
        } else if (action === "pause" || action === "resume") {
            root.notify("Individual downloads cannot be paused safely. Pause the queue instead.", "info")
        }
    }

    // ================================================================
    //  PROCESSES
    // ================================================================
    Process {
        id: statusProc
        command: [root.helperPath, "status"]
        stdout: StdioCollector { id: statusStdout }
        stderr: StdioCollector { id: statusStderr }
        onExited: (exitCode, exitStatus) => {
            const payload = root.parsePayload(statusStdout.text)
            root.checkingStatus = false
            if (exitCode === 0 && payload && payload.ok === true && typeof payload.ytDlpReady === "boolean") {
                root.toolStatus = payload
                root.statusReady = true
                root.statusError = ""
                root.statusFinished(payload)
            } else {
                root.statusError = root.errorMessage(payload, statusStderr.text, exitCode, "Downloads helper")
                root.statusFinished(null)
            }
        }
    }

    Process {
        id: inspectProc
        command: []
        stdout: StdioCollector { id: inspectStdout }
        stderr: StdioCollector { id: inspectStderr }
        onExited: (exitCode, exitStatus) => {
            const requestId = root.inspectRequestId
            const payload = root.parsePayload(inspectStdout.text)
            root.inspecting = false
            root.inspectRequestId = ""
            if (exitCode === 0 && payload && payload.ok === true
                    && payload.item && typeof payload.item === "object"
                    && payload.playlist && typeof payload.playlist === "object"
                    && DownloadsQueue.isArrayLike(payload.videoFormats)
                    && DownloadsQueue.isArrayLike(payload.audioFormats)) {
                root.inspectSucceeded(payload, requestId)
            } else {
                const code = payload && typeof payload.code === "string" ? payload.code : "invalid_response"
                const message = root.errorMessage(payload, inspectStderr.text, exitCode, "Link inspection")
                root.inspectError = message
                root.inspectErrorCode = code
                root.inspectFailed(message, code, requestId)
            }
        }
    }

    Process {
        id: downloadProc
        command: []
        stdout: SplitParser {
            onRead: line => root.handleDownloadLine(line)
        }
        stderr: SplitParser {
            onRead: line => { if (String(line || "").trim() !== "") root.stderrLine = String(line) }
        }
        onExited: (exitCode, exitStatus) => {
            const jobId = root.activeJobId
            const wasCancelled = root.cancelRequested
            const seen = root.terminalEventSeen
            root.downloading = false
            root.activeJobId = ""
            root.cancelRequested = false
            root.terminalEventSeen = false
            if (!seen) {
                if (wasCancelled || exitCode === 130) {
                    root.downloadCancelled(jobId)
                } else {
                    const payload = root.parsePayload(root.lastDownloadLine)
                    const message = root.errorMessage(payload, root.stderrLine, exitCode, "Download")
                    const code = payload && typeof payload.code === "string" ? payload.code : "download_failed"
                    root.downloadError = message
                    root.downloadErrorCode = code
                    root.downloadFailed(message, code, jobId)
                }
            }
            root.downloadEnded(jobId)
        }
    }

    Process {
        id: utilityProc
        command: []
        stdout: StdioCollector { id: utilityStdout }
        stderr: StdioCollector { id: utilityStderr }
        onExited: (exitCode, exitStatus) => {
            const action = root.utilityAction
            const payload = root.parsePayload(utilityStdout.text)
            root.utilityBusy = false
            root.utilityAction = ""
            if (exitCode === 0 && payload && payload.ok === true) {
                root.utilitySucceeded(payload, action)
            } else {
                const code = payload && typeof payload.code === "string" ? payload.code : "utility_failed"
                root.utilityFailed(root.errorMessage(payload, utilityStderr.text, exitCode, "Download helper"), code, action)
            }
        }
    }
}
