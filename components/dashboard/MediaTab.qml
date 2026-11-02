import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config
import qs.components.dashboard

// Media tab: live MPRIS player with circular artwork, real spectrum bars,
// metadata, seek/transport with capability gating, PipeWire output-sink
// selection, volume/mute and a user-triggered LRCLIB lyrics lookup.
// Every value shown is measured from the actual system or player; states
// with no real backing (queue, transcript) are omitted rather than faked.
Item {
    id: root
    property bool isOpen: false
    property var hub: null

    function openMediaHub() {
        if (root.hub && typeof root.hub.openMediaHub === "function")
            root.hub.openMediaHub()
    }

    // ------------------------------------------------------------------
    // MPRIS player: same selection policy as the Home now-playing card -
    // the playing player wins, otherwise the first connected one.
    // ------------------------------------------------------------------
    readonly property var player: MediaNowPlaying.player
    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: root.hasPlayer && root.player.isPlaying
    readonly property bool hasProgress: root.hasPlayer
        && root.player.positionSupported && root.player.lengthSupported
        && root.player.length > 0

    readonly property string stateLabel: !root.hasPlayer
        ? "IDLE"
        : (root.player.isPlaying ? "PLAYING"
            : (root.player.playbackState === MprisPlaybackState.Paused ? "PAUSED" : "STOPPED"))
    readonly property color stateColor: !root.hasPlayer
        ? Theme.textDim
        : (root.player.isPlaying ? Theme.accentPrimary
            : (root.player.playbackState === MprisPlaybackState.Paused ? Theme.accentTertiary : Theme.textDim))

    // ------------------------------------------------------------------
    // Position: real samples (seconds on the wire) anchored + interpolated
    // locally while playing, exactly like the Home card.
    // ------------------------------------------------------------------
    property real posBase: 0
    property real posStamp: 0
    property real tickNow: 0

    function syncPos() {
        if (root.player) {
            root.posBase = root.player.position * 1000
            root.posStamp = Date.now()
            root.tickNow = Date.now()
        }
    }
    onPlayerChanged: root.syncPos()

    readonly property real displayPos: {
        if (!root.hasPlayer || !root.player.positionSupported) return 0
        if (!root.player.isPlaying) return Math.max(0, root.player.position * 1000)
        let pos = root.posBase + Math.max(0, root.tickNow - root.posStamp)
        if (root.player.length > 0) pos = Math.min(pos, root.player.length * 1000)
        return Math.max(pos, root.player.position * 1000)
    }

    function fmt(ms) {
        const total = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const ss = (s < 10 ? "0" : "") + s
        return h > 0 ? (h + ":" + (m < 10 ? "0" : "") + m + ":" + ss) : (m + ":" + ss)
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.syncPos() }
        function onTrackTitleChanged() {
            root.syncPos()
            root.checkLyricsTrack()
        }
        function onTrackArtistChanged() { root.checkLyricsTrack() }
        function onTrackAlbumChanged() { root.checkLyricsTrack() }
        function onLengthChanged() { root.checkLyricsTrack() }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.isOpen && root.isPlaying
        onTriggered: root.tickNow = Date.now()
    }

    // ------------------------------------------------------------------
    // Seek: drag/tap the scrubber; only active when the player can seek.
    // ------------------------------------------------------------------
    property bool scrubActive: false
    property real scrubFrac: 0

    readonly property real progressFrac: root.hasProgress
        ? Math.max(0, Math.min(1, root.displayPos / (root.player.length * 1000)))
        : 0
    readonly property real shownFrac: root.scrubActive
        ? Math.max(0, Math.min(1, root.scrubFrac))
        : root.progressFrac

    function commitSeek() {
        if (root.scrubActive && root.hasPlayer && root.player.canSeek && root.hasProgress) {
            const lengthMs = root.player.length * 1000
            const targetMs = Math.max(0, Math.min(lengthMs, root.scrubFrac * lengthMs))
            if (typeof root.player.seekTo === "function") {
                root.player.seekTo(targetMs / 1000.0)
            } else if (root.player.positionSupported) {
                root.player.position = targetMs / 1000.0
            } else {
                root.player.seek((targetMs - Math.max(0, root.displayPos)) / 1000.0)
            }
            // Optimistic anchor; the player's next position report reconciles.
            root.posBase = targetMs
            root.posStamp = Date.now()
            root.tickNow = Date.now()
            seekReconcileTimer.restart()
        }
        root.scrubActive = false
    }

    Timer {
        id: seekReconcileTimer
        interval: 700
        repeat: false
        onTriggered: root.syncPos()
    }

    // ------------------------------------------------------------------
    // Transport helpers (capability-gated).
    // ------------------------------------------------------------------
    function togglePlay() {
        if (!root.hasPlayer) return
        if (root.player.canTogglePlaying) root.player.togglePlaying()
        else if (root.player.isPlaying && root.player.canPause) root.player.pause()
        else if (!root.player.isPlaying && root.player.canPlay) root.player.play()
    }

    function toggleShuffle() {
        if (!root.hasPlayer || !root.player.shuffleSupported) return
        root.player.shuffle = !root.player.shuffle
    }

    function cycleLoop() {
        if (!root.hasPlayer || !root.player.loopSupported) return
        const s = root.player.loopState
        if (s === MprisLoopState.None) root.player.loopState = MprisLoopState.Playlist
        else if (s === MprisLoopState.Playlist) root.player.loopState = MprisLoopState.Track
        else root.player.loopState = MprisLoopState.None
    }

    readonly property string loopIcon: root.hasPlayer && root.player.loopState === MprisLoopState.Track
        ? "repeat_one" : "repeat"
    readonly property bool loopActive: root.hasPlayer && root.player.loopSupported
        && root.player.loopState !== MprisLoopState.None

    // ------------------------------------------------------------------
    // Volume / mute of the real default sink (project-standard wpctl).
    // ------------------------------------------------------------------
    property bool volReady: false
    property real volUi: 0
    property bool volMuted: false
    property real volStamp: 0

    function volumeMoved(v) {
        root.volStamp = Date.now()
        root.volUi = v
        volApplyTimer.restart()
    }

    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        muteVerifyTimer.restart()
    }

    Timer {
        id: volApplyTimer
        interval: 160
        repeat: false
        onTriggered: Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(root.volUi * 100) + "%"])
    }

    Timer {
        id: muteVerifyTimer
        interval: 320
        repeat: false
        onTriggered: if (!volProc.running) volProc.running = true
    }

    Timer {
        id: volPollTimer
        interval: 2000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: if (!volProc.running) volProc.running = true
    }

    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /Volume:\s*([\d.]+)(\s*\[MUTED\])?/.exec(text)
                if (!m) return
                root.volReady = true
                root.volMuted = m[2] !== undefined
                const v = parseFloat(m[1])
                if (!isNaN(v) && Date.now() - root.volStamp > 1200)
                    root.volUi = v
            }
        }
    }

    // ------------------------------------------------------------------
    // Output sinks from the real PipeWire graph (wpctl, parsed by helper).
    // ------------------------------------------------------------------
    property var sinks: []
    property string engineLabel: ""
    property string sinkError: ""
    property string sinkActionError: ""
    property string sinkNotice: ""
    property bool sinkBusy: false
    property int pendingSinkId: 0
    property bool sinkExpanded: false

    readonly property var defaultSink: {
        const list = root.sinks || []
        for (let i = 0; i < list.length; i++) {
            if (list[i].default === true) return list[i]
        }
        return null
    }
    readonly property string outputSummary: {
        if (root.sinkError !== "") return "device list unavailable"
        if (root.sinks.length === 0)
            return sinksProc.running ? "querying devices\u2026" : "no output devices"
        if (!root.defaultSink) return "no default output"
        return root.defaultSink.name + (root.defaultSink.available === false ? " \u00b7 unavailable" : "")
    }
    readonly property color outputStatusColor: {
        if (root.sinkError !== "") return Theme.statusDanger
        if (!root.defaultSink) return Theme.textDim
        return root.defaultSink.available === false ? Theme.statusDanger : Theme.accentPrimary
    }

    function refreshSinks() {
        if (!sinksProc.running) sinksProc.running = true
    }

    function selectSink(id) {
        if (!id || root.sinkBusy) return
        const target = root.sinks.find(s => s.id === id)
        if (!target) return
        if (target.available === false) {
            root.sinkActionError = ""
            root.sinkNotice = target.name + " is not available right now (no display connected)."
            return
        }
        const cur = root.sinks.find(s => s.default)
        if (cur && cur.id === id) {
            root.sinkNotice = ""
            root.sinkActionError = ""
            return
        }
        root.sinkActionError = ""
        root.sinkNotice = ""
        root.sinkBusy = true
        root.pendingSinkId = id
        sinkSetProc.command = ["wpctl", "set-default", String(id)]
        sinkSetProc.running = true
    }

    Timer {
        id: sinkPollTimer
        interval: 5000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: root.refreshSinks()
    }

    Timer {
        id: sinkVerifyTimer
        interval: 900
        repeat: false
        onTriggered: {
            root.refreshSinks()
            sinkCheckTimer.restart()
        }
    }

    // Confirms the requested device actually became the default after the
    // set-default ran; WirePlumber may keep the previous sink (e.g. all other
    // outputs unplugged), in which case the user gets a truthful notice.
    Timer {
        id: sinkCheckTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (root.pendingSinkId === 0) return
            const target = root.sinks.find(s => s.id === root.pendingSinkId)
            if (!target || !target.default) {
                const cur = root.sinks.find(s => s.default)
                root.sinkNotice = cur
                    ? ("output stayed on " + cur.name + " \u2014 PipeWire kept the available device")
                    : "output unchanged"
            }
            root.pendingSinkId = 0
        }
    }

    Process {
        id: sinksProc
        command: ["python3", Qt.resolvedUrl("../../scripts/audio-sinks.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null
                try { data = JSON.parse(text.trim()) } catch (e) { data = null }
                if (!data) {
                    root.sinkError = "unreadable device list"
                    return
                }
                if (data.error) {
                    root.sinkError = data.error
                    return
                }
                root.sinkError = ""
                root.engineLabel = data.engine || ""
                root.sinks = data.sinks || []
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.sinkError === "")
                root.sinkError = "device list unavailable (exit " + code + ")"
        }
    }

    Process {
        id: sinkSetProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.sinkActionError = text.trim().split("\n")[0]
            }
        }
        onExited: (code, status) => {
            root.sinkBusy = false
            if (code !== 0) {
                root.pendingSinkId = 0
                if (root.sinkActionError === "")
                    root.sinkActionError = "set-default failed (exit " + code + ")"
            }
            root.refreshSinks()
            sinkVerifyTimer.restart()
        }
    }

    // ------------------------------------------------------------------
    // Lyrics: manual LRCLIB lookup only. Nothing is fetched or sent until
    // the user presses the button; the request is a one-shot read-only GET.
    // ------------------------------------------------------------------
    property string lyricsState: "idle" // idle | loading | ok | none | error
    property bool lyricsSynced: false
    property var lyricsLines: []
    property string lyricsPlain: ""
    property string lyricsMessage: ""
    property string lyricsTrackKey: ""
    property string lyricsRequestKey: ""
    readonly property string lyricsServiceKey: root.hasPlayer
        ? MediaLyrics.keyFor(
            root.player.trackArtist,
            root.player.trackTitle,
            root.player.trackAlbum,
            root.player.lengthSupported ? root.player.length : 0
        )
        : ""
    property bool lyricsFollow: true

    readonly property string trackKey: root.hasPlayer
        ? (root.player.uniqueId + "|" + root.player.trackTitle + "|" + root.player.trackArtist + "|"
            + root.player.trackAlbum + "|" + Math.round(root.player.length))
        : ""

    function resetLyrics() {
        root.lyricsState = "idle"
        root.lyricsSynced = false
        root.lyricsLines = []
        root.lyricsPlain = ""
        root.lyricsMessage = ""
        root.lyricsTrackKey = ""
        root.lyricsRequestKey = ""
        root.lyricsFollow = true
    }

    function checkLyricsTrack() {
        if (root.lyricsTrackKey !== "" && root.lyricsTrackKey !== root.trackKey)
            root.resetLyrics()
    }

    function lookupLyrics() {
        if (!root.hasPlayer || root.player.trackTitle.length === 0) return
        root.lyricsState = "loading"
        root.lyricsMessage = ""
        root.lyricsFollow = true
        root.lyricsRequestKey = root.trackKey
        MediaLyrics.lookup(
            root.player.trackArtist,
            root.player.trackTitle,
            root.player.trackAlbum,
            root.player.lengthSupported ? root.player.length : 0
        )
        root.syncLyricsFromService()
    }

    function syncLyricsFromService() {
        if (root.lyricsRequestKey !== root.trackKey || root.lyricsServiceKey === "") return
        if (MediaLyrics.resultKey === root.lyricsServiceKey) {
            const data = MediaLyrics.result
            root.lyricsTrackKey = root.lyricsRequestKey
            root.lyricsMessage = ""
            if (data.status === "synced") {
                root.lyricsState = "ok"
                root.lyricsSynced = true
                root.lyricsLines = data.lines
                root.lyricsPlain = ""
            } else if (data.status === "plain") {
                root.lyricsState = "ok"
                root.lyricsSynced = false
                root.lyricsLines = []
                root.lyricsPlain = data.plain
            } else {
                root.lyricsState = "none"
                root.lyricsSynced = false
                root.lyricsLines = []
                root.lyricsPlain = ""
            }
        } else if (MediaLyrics.errorKey === root.lyricsServiceKey) {
            root.lyricsState = "error"
            root.lyricsMessage = MediaLyrics.error ? MediaLyrics.error.message : "lyrics lookup failed"
        } else if (MediaLyrics.loading && MediaLyrics.requestKey === root.lyricsServiceKey) {
            root.lyricsState = "loading"
        }
    }

    Connections {
        target: MediaLyrics
        function onResultKeyChanged() { root.syncLyricsFromService() }
        function onRequestKeyChanged() { root.syncLyricsFromService() }
        function onErrorKeyChanged() { root.syncLyricsFromService() }
        function onLoadingChanged() { root.syncLyricsFromService() }
    }

    readonly property int currentLineIndex: {
        if (root.lyricsState !== "ok" || !root.lyricsSynced) return -1
        const sec = root.displayPos / 1000.0
        let idx = -1
        for (let i = 0; i < root.lyricsLines.length; i++) {
            if (root.lyricsLines[i].t <= sec) idx = i
            else break
        }
        return idx
    }

    function fmtLyricTime(t) {
        const total = Math.max(0, Math.floor(t))
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function seekToLine(t) {
        if (!root.hasPlayer || !root.player.canSeek) return
        if (typeof root.player.seekTo === "function") {
            root.player.seekTo(t)
        } else if (root.player.positionSupported) {
            root.player.position = t
        } else {
            const currentSec = root.displayPos / 1000.0
            root.player.seek(Math.max(0, t - currentSec))
        }
        root.posBase = t * 1000
        root.posStamp = Date.now()
        root.tickNow = Date.now()
        seekReconcileTimer.restart()
    }

    // ------------------------------------------------------------------
    // Shared spectrum capture: acquired while this tab exists.
    // ------------------------------------------------------------------
    Component.onCompleted: AudioSpectrum.acquire()
    Component.onDestruction: AudioSpectrum.release()

    // Compact round transport button (Home-card language + toggled state).
    component TransportButton: Item {
        id: tb
        property string icon: ""
        property bool interactable: false
        property bool highlight: false
        property bool active: false
        property int size: 30
        property int iconSize: 17

        signal triggered()

        implicitWidth: tb.size
        implicitHeight: tb.size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: tb.highlight
                ? Theme.accentPrimary
                : (tb.active
                    ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.16)
                    : (tb.interactable && tbh.hovered ? Theme.surfaceVariant
                        : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)))
            border.width: tb.active ? 1 : 0
            border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.4)
            opacity: tb.highlight && !tb.interactable ? 0.35 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        DashIcon {
            anchors.centerIn: parent
            name: tb.icon
            filled: tb.active || tb.highlight
            color: tb.highlight ? Theme.onAccent
                : (tb.active ? Theme.accentPrimary
                    : (tb.interactable ? Theme.textMain : Theme.textDim))
            opacity: tb.interactable || tb.highlight ? 1 : 0.4
            font.pixelSize: tb.iconSize
        }

        HoverHandler { id: tbh; enabled: tb.interactable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: tb.interactable; onTapped: tb.triggered() }
    }

    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content
            width: parent.width
            spacing: Theme.dashboardSpacingMd

            // 1. Player / source status row.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.dashboardSpacingSm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 24
                    implicitWidth: srcRow.implicitWidth + 20
                    radius: 12
                    color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)

                    RowLayout {
                        id: srcRow
                        anchors.centerIn: parent
                        spacing: Theme.dashboardSpacingSm

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "graphic_eq"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(13)
                        }

                        Text {
                            text: "PIPEWIRE"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            implicitWidth: 1
                            implicitHeight: 10
                            color: Theme.surfaceVariant
                        }

                        Text {
                            Layout.maximumWidth: 160
                            text: root.hasPlayer
                                ? (root.player.identity.length > 0 ? root.player.identity : "player")
                                : "no player"
                            color: root.hasPlayer ? Theme.textMuted : Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            elide: Text.ElideRight
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 24
                    implicitWidth: stRow.implicitWidth + 18
                    radius: 12
                    color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)

                    RowLayout {
                        id: stRow
                        anchors.centerIn: parent
                        spacing: Theme.dashboardSpacingSm

                        Rectangle {
                            id: stateDot
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: root.stateColor

                            SequentialAnimation on opacity {
                                running: root.isOpen && root.isPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 550 }
                                NumberAnimation { to: 1.0; duration: 550 }
                            }

                            Connections {
                                target: root
                                function onIsPlayingChanged() {
                                    if (!root.isPlaying) stateDot.opacity = 1
                                }
                            }
                        }

                        Text {
                            text: root.stateLabel
                            color: root.stateColor
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }
                }
            }

            // 2/3. Circular artwork + compact real spectrum.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: Theme.dashboardSpacingMd

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 192
                    implicitHeight: 192

                    Rectangle {
                        anchors.centerIn: parent
                        width: 192
                        height: 192
                        radius: 96
                        color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.05)
                    }

                    CircularArtwork {
                        anchors.centerIn: parent
                        diameter: 168
                        artUrl: root.hasPlayer ? root.player.trackArtUrl : ""
                        orbiting: root.isOpen && root.isPlaying
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 20
                    color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.38)

                    SpectrumBars {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        barCount: AudioSpectrum.barCount
                        levels: AudioSpectrum.levels
                    }
                }
            }

            // 4. Track metadata.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: !root.hasPlayer
                        ? "NO ACTIVE PLAYER"
                        : (root.player.trackTitle.length > 0 ? root.player.trackTitle : "Unknown title")
                    color: root.hasPlayer ? Theme.textMain : Theme.textMuted
                    font.family: root.hasPlayer ? Theme.fontUi : Theme.fontMono
                    font.pixelSize: root.hasPlayer ? 15 : 11
                    font.bold: true
                    font.letterSpacing: root.hasPlayer ? 0 : 1
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.hasPlayer
                    text: {
                        if (!root.hasPlayer) return ""
                        const artist = root.player.trackArtist
                        const album = root.player.trackAlbum
                        if (artist.length > 0 && album.length > 0) return artist + "  \u2022  " + album
                        if (artist.length > 0) return artist
                        if (album.length > 0) return album
                        return ""
                    }
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(9)
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: !root.hasPlayer
                    text: "playback details appear here when a player connects"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                }
            }

            // 5. Progress / seek.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.hasProgress

                Item {
                    id: seekRow
                    Layout.fillWidth: true
                    implicitHeight: 16

                    readonly property bool seekable: root.hasPlayer && root.player.canSeek

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * root.shownFrac
                        height: 4
                        radius: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.accentPrimary }
                            GradientStop { position: 1; color: Theme.accentSecondary }
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
                        x: Math.max(0, Math.min(seekRow.width - width, seekRow.width * root.shownFrac - width / 2))
                        color: Theme.surfaceDeep
                        border.width: 2
                        border.color: !seekRow.seekable
                            ? Theme.textDim
                            : (seekPointer.pressed || seekPointer.containsMouse ? Theme.accentPrimary : Theme.textMain)
                        Behavior on x { enabled: !seekPointer.pressed; NumberAnimation { duration: 90 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                    }

                    MouseArea {
                        id: seekPointer
                        anchors.fill: parent
                        anchors.topMargin: -4
                        anchors.bottomMargin: -4
                        enabled: seekRow.seekable
                        hoverEnabled: seekRow.seekable
                        cursorShape: seekRow.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        preventStealing: true

                        function fracAt(x) {
                            const w = seekRow.width
                            return w > 0 ? Math.max(0, Math.min(1, x / w)) : 0
                        }

                        onPressed: (mouse) => {
                            root.scrubFrac = fracAt(mouse.x)
                            root.scrubActive = true
                        }
                        onPositionChanged: (mouse) => {
                            if (pressed) root.scrubFrac = fracAt(mouse.x)
                        }
                        onReleased: root.commitSeek()
                        onCanceled: root.scrubActive = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: root.fmt(root.scrubActive
                            ? root.scrubFrac * (root.player ? root.player.length * 1000 : 0)
                            : root.displayPos)
                        color: Theme.accentPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(9)
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.fmt(root.hasPlayer ? root.player.length * 1000 : 0)
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(9)
                    }
                }
            }

            // 6. Transport + volume.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: Theme.dashboardSpacingSm
                visible: root.hasPlayer

                TransportButton {
                    icon: "shuffle"
                    active: root.hasPlayer && root.player.shuffleSupported && root.player.shuffle
                    interactable: root.hasPlayer && root.player.shuffleSupported
                    onTriggered: root.toggleShuffle()
                }

                TransportButton {
                    icon: root.loopIcon
                    active: root.loopActive
                    interactable: root.hasPlayer && root.player.loopSupported
                    onTriggered: root.cycleLoop()
                }

                Item { Layout.fillWidth: true }

                TransportButton {
                    icon: "skip_previous"
                    interactable: root.hasPlayer && root.player.canGoPrevious
                    onTriggered: if (root.player) root.player.previous()
                }

                TransportButton {
                    icon: root.isPlaying ? "pause" : "play_arrow"
                    highlight: true
                    size: 44
                    iconSize: 23
                    interactable: root.hasPlayer && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
                    onTriggered: root.togglePlay()
                }

                TransportButton {
                    icon: "skip_next"
                    interactable: root.hasPlayer && root.player.canGoNext
                    onTriggered: if (root.player) root.player.next()
                }

                Item { Layout.fillWidth: true }

                TransportButton {
                    icon: root.volMuted ? "volume_off" : "volume_up"
                    size: 28
                    iconSize: 16
                    interactable: root.volReady
                    onTriggered: root.toggleMute()
                }

                DashSlider {
                    Layout.preferredWidth: 58
                    Layout.alignment: Qt.AlignVCenter
                    from: 0
                    to: 1
                    value: root.volUi
                    interactive: root.volReady
                    accent: root.volMuted ? Theme.statusDanger : Theme.accentPrimary
                    onMoved: (v) => root.volumeMoved(v)
                }

                Text {
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignRight
                    text: root.volReady ? Math.round(root.volUi * 100) + "%" : "\u2014"
                    color: root.volMuted ? Theme.statusDanger : Theme.textMain
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(9)
                    font.bold: true
                }
            }

            // 7. Media Hub entry point (one hosted window, opened by hub).
            Rectangle {
                id: mediaHubCard
                Layout.fillWidth: true
                implicitHeight: 46
                radius: 12
                color: mediaHubHover.hovered
                    ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.10)
                    : Qt.rgba(Theme.surfaceBase.r, Theme.surfaceBase.g, Theme.surfaceBase.b, 0.85)
                border.width: 1
                border.color: mediaHubCard.activeFocus
                    ? Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.65)
                    : (mediaHubHover.hovered
                        ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.45)
                        : Theme.outlineSoft)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Media Hub"
                Accessible.description: "Open the standalone Media Hub"
                Accessible.onPressAction: root.openMediaHub()
                Keys.onSpacePressed: (event) => {
                    root.openMediaHub()
                    event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    root.openMediaHub()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    root.openMediaHub()
                    event.accepted = true
                }
                Behavior on color { ColorAnimation { duration: 110 } }
                Behavior on border.color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: Theme.dashboardSpacingMd

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 8
                        color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.14)

                        DashIcon {
                            anchors.centerIn: parent
                            name: "hub"
                            color: Theme.accentPrimary
                            font.pixelSize: Theme.dashboardText(16)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "MEDIA HUB"
                            color: Theme.textMain
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(10)
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Wallpapers, anime, manga and music"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 42
                        implicitHeight: 20
                        radius: 10
                        color: Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.32)

                        Text {
                            anchors.centerIn: parent
                            text: "OPEN"
                            color: Theme.accentSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            font.bold: true
                            font.letterSpacing: 0.7
                        }
                    }

                    DashIcon {
                        Layout.alignment: Qt.AlignVCenter
                        name: "arrow_forward"
                        color: mediaHubHover.hovered ? Theme.accentPrimary : Theme.textDim
                        font.pixelSize: Theme.dashboardText(15)
                    }
                }

                HoverHandler {
                    id: mediaHubHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.openMediaHub()
                }
            }

            // 8. Collapsible output sink selector (real PipeWire devices).
            DashSurface {
                Layout.fillWidth: true
                fill: Qt.rgba(Theme.surfaceBase.r, Theme.surfaceBase.g, Theme.surfaceBase.b, 0.85)
                radius: 14
                implicitHeight: sinkCol.implicitHeight + 20
                clip: true

                ColumnLayout {
                    id: sinkCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    Rectangle {
                        id: sinkHeader
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: sinkHeaderHover.hovered
                            ? Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.55)
                            : "transparent"
                        border.width: sinkHeader.activeFocus ? 1 : 0
                        border.color: Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.55)
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Audio output, " + root.outputSummary
                        Accessible.description: root.sinkExpanded
                            ? "Expanded. Activate to collapse the device list."
                            : "Collapsed. Activate to expand the device list."
                        Accessible.onPressAction: root.sinkExpanded = !root.sinkExpanded
                        Keys.onSpacePressed: (event) => {
                            root.sinkExpanded = !root.sinkExpanded
                            event.accepted = true
                        }
                        Keys.onReturnPressed: (event) => {
                            root.sinkExpanded = !root.sinkExpanded
                            event.accepted = true
                        }
                        Keys.onEnterPressed: (event) => {
                            root.sinkExpanded = !root.sinkExpanded
                            event.accepted = true
                        }
                        Behavior on color { ColorAnimation { duration: 110 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 6
                            spacing: Theme.dashboardSpacingSm

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "headphones"
                                color: Theme.accentSecondary
                                font.pixelSize: Theme.dashboardText(14)
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "AUDIO OUTPUT"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                font.bold: true
                                font.letterSpacing: 0.8
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: root.outputSummary
                                color: root.defaultSink ? Theme.textMuted : Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: 4
                                color: root.outputStatusColor
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }

                            DashIcon {
                                Layout.alignment: Qt.AlignVCenter
                                name: "expand_more"
                                color: sinkHeaderHover.hovered ? Theme.textMain : Theme.textDim
                                font.pixelSize: Theme.dashboardText(16)
                                rotation: root.sinkExpanded ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }
                        }

                        HoverHandler {
                            id: sinkHeaderHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: root.sinkExpanded = !root.sinkExpanded
                        }
                    }

                    Item {
                        id: sinkBody
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.sinkExpanded ? sinkBodyCol.implicitHeight : 0
                        visible: sinkBody.Layout.preferredHeight > 0.5
                        clip: true
                        opacity: root.sinkExpanded ? 1 : 0
                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        ColumnLayout {
                            id: sinkBodyCol
                            width: sinkCol.width
                            spacing: Theme.dashboardSpacingSm

                            Text {
                                Layout.fillWidth: true
                                visible: root.engineLabel.length > 0
                                text: root.engineLabel + (root.sinkError === "" ? " \u00b7 active" : "")
                                color: root.sinkError === "" ? Theme.accentPrimary : Theme.statusDanger
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                            }

                            Repeater {
                                model: root.sinks

                                delegate: Item {
                                    id: sinkRow
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    activeFocusOnTab: !root.sinkBusy
                                    Accessible.role: Accessible.Button
                                    Accessible.name: sinkRow.modelData.name
                                        + (sinkRow.isDefault ? ", default output" : "")
                                        + (sinkRow.available ? "" : ", unavailable")
                                    Accessible.description: sinkRow.available
                                        ? "Activate to make this the default output."
                                        : "This output is not available right now."
                                    Accessible.onPressAction: root.selectSink(sinkRow.modelData.id)
                                    Keys.onSpacePressed: (event) => {
                                        root.selectSink(sinkRow.modelData.id)
                                        event.accepted = true
                                    }
                                    Keys.onReturnPressed: (event) => {
                                        root.selectSink(sinkRow.modelData.id)
                                        event.accepted = true
                                    }
                                    Keys.onEnterPressed: (event) => {
                                        root.selectSink(sinkRow.modelData.id)
                                        event.accepted = true
                                    }

                                    readonly property bool isDefault: sinkRow.modelData.default === true
                                    readonly property bool available: sinkRow.modelData.available !== false

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: sinkRow.isDefault
                                            ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.12)
                                            : (sinkRow.available && sinkHover.hovered && !root.sinkBusy
                                                ? Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.8)
                                                : "transparent")
                                        border.width: sinkRow.isDefault || sinkRow.activeFocus ? 1 : 0
                                        border.color: sinkRow.activeFocus
                                            ? Qt.rgba(Theme.accentSecondary.r, Theme.accentSecondary.g, Theme.accentSecondary.b, 0.65)
                                            : Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.35)
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 7

                                        DashIcon {
                                            Layout.alignment: Qt.AlignVCenter
                                            name: "speaker"
                                            color: !sinkRow.available
                                                ? Theme.textDim
                                                : (sinkRow.isDefault ? Theme.accentPrimary : Theme.textDim)
                                            font.pixelSize: Theme.dashboardText(14)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: sinkRow.modelData.name
                                            color: !sinkRow.available
                                                ? Theme.textDim
                                                : (sinkRow.isDefault ? Theme.textMain : Theme.textMuted)
                                            font.family: Theme.fontUi
                                            font.pixelSize: Theme.dashboardText(10)
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: !sinkRow.available
                                            text: "UNAVAILABLE"
                                            color: Theme.textDim
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.dashboardText(7)
                                            font.bold: true
                                            font.letterSpacing: 0.8
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: sinkRow.isDefault
                                            text: "DEFAULT"
                                            color: Theme.accentPrimary
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.dashboardText(7)
                                            font.bold: true
                                            font.letterSpacing: 0.8
                                        }
                                    }

                                    HoverHandler {
                                        id: sinkHover
                                        enabled: !root.sinkBusy
                                        cursorShape: sinkRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    }

                                    TapHandler {
                                        enabled: !root.sinkBusy
                                        onTapped: root.selectSink(sinkRow.modelData.id)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.sinks.length === 0 || root.sinkError !== ""
                                text: root.sinkError !== ""
                                    ? ("device list unavailable: " + root.sinkError)
                                    : (sinksProc.running ? "querying devices\u2026" : "no output devices found")
                                color: root.sinkError !== "" ? Theme.statusDanger : Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.sinkActionError !== ""
                                text: root.sinkActionError
                                color: Theme.statusDanger
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.sinkNotice !== ""
                                text: root.sinkNotice
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(8)
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // 9. Lyrics (manual lookup; honest idle/loading/none/error states).
            DashSurface {
                Layout.fillWidth: true
                fill: Qt.rgba(Theme.surfaceBase.r, Theme.surfaceBase.g, Theme.surfaceBase.b, 0.85)
                radius: 14
                implicitHeight: lyrCol.implicitHeight + 20

                ColumnLayout {
                    id: lyrCol
                    anchors.fill: parent
                    anchors.margins: Theme.dashboardCardPadding
                    spacing: Theme.dashboardSpacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        DashIcon {
                            Layout.alignment: Qt.AlignVCenter
                            name: "subtitles"
                            color: Theme.accentSecondary
                            font.pixelSize: Theme.dashboardText(14)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "LYRICS"
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 64
                            implicitHeight: 18
                            radius: 9
                            color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.8)

                            Text {
                                anchors.centerIn: parent
                                text: "LRCLIB"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.dashboardText(7)
                                font.bold: true
                                font.letterSpacing: 0.6
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.hasPlayer
                        text: "No active player \u2014 lyrics can be looked up once a track is loaded."
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(8)
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.hasPlayer && root.lyricsState === "idle"

                        Text {
                            Layout.fillWidth: true
                            text: root.player.trackTitle.length > 0
                                ? "Lyrics are not loaded for this track."
                                : "This track has no title to look up."
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.dashboardText(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.player.trackTitle.length > 0
                            text: "Lookup is manual: the button sends the title, artist, album and duration to lrclib.net."
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            wrapMode: Text.WordWrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm
                        visible: root.lyricsState === "loading"

                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 4
                            color: Theme.accentSecondary

                            SequentialAnimation on opacity {
                                running: root.lyricsState === "loading"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 400 }
                                NumberAnimation { to: 1.0; duration: 400 }
                            }
                        }

                        Text {
                            text: "Searching lrclib.net\u2026"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(8)
                        }
                    }

                    ListView {
                        id: lyrView
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(150, Math.max(44, contentHeight))
                        visible: root.lyricsState === "ok" && root.lyricsSynced
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.lyricsLines
                        spacing: 2
                        interactive: contentHeight > height

                        onMovementStarted: root.lyricsFollow = false

                        delegate: Item {
                            id: lineItem
                            required property var modelData
                            required property int index

                            width: lyrView.width
                            implicitHeight: lineLayout.implicitHeight + 8

                            readonly property bool current: lineItem.index === root.currentLineIndex

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: lineItem.current
                                    ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.10)
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            RowLayout {
                                id: lineLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 7

                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 30
                                    text: root.fmtLyricTime(lineItem.modelData.t)
                                    color: lineItem.current ? Theme.accentPrimary : Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(8)
                                    font.bold: lineItem.current
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: lineItem.modelData.s
                                    color: lineItem.current ? Theme.accentPrimary : Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.dashboardText(11)
                                    font.bold: lineItem.current
                                    wrapMode: Text.WordWrap
                                }
                            }

                            HoverHandler {
                                cursorShape: root.hasPlayer && root.player.canSeek
                                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }

                            TapHandler {
                                enabled: root.hasPlayer && root.player.canSeek
                                onTapped: root.seekToLine(lineItem.modelData.t)
                            }
                        }

                        Connections {
                            target: root
                            function onCurrentLineIndexChanged() {
                                if (root.lyricsFollow && root.currentLineIndex >= 0)
                                    lyrView.positionViewAtIndex(root.currentLineIndex, ListView.Center)
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(120, plainText.implicitHeight + 8)
                        visible: root.lyricsState === "ok" && !root.lyricsSynced
                        clip: true
                        contentHeight: plainText.implicitHeight + 8
                        boundsBehavior: Flickable.StopAtBounds

                        Text {
                            id: plainText
                            x: 4
                            y: 4
                            width: parent.width - 8
                            text: root.lyricsPlain
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.dashboardText(11)
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.lyricsState === "none"

                        Text {
                            Layout.fillWidth: true
                            text: "No lyrics found on LRCLIB for this track."
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.dashboardText(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "The lookup searched by title, artist and album."
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.lyricsState === "error"

                        Text {
                            Layout.fillWidth: true
                            text: "Lyrics lookup failed."
                            color: Theme.statusDanger
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.dashboardText(10)
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.lyricsMessage
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                            wrapMode: Text.WordWrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dashboardSpacingSm

                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (!root.hasPlayer) return "lrclib.net \u00b7 manual lookup only"
                                if (root.lyricsState === "ok" && root.lyricsSynced) return "lrclib.net \u00b7 synced"
                                if (root.lyricsState === "ok") return "lrclib.net \u00b7 plain text"
                                if (root.lyricsState === "none") return "lrclib.net \u00b7 no match"
                                if (root.lyricsState === "error") return "lrclib.net \u00b7 error"
                                if (root.lyricsState === "loading") return "lrclib.net \u00b7 searching"
                                return "lrclib.net \u00b7 manual lookup only"
                            }
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.dashboardText(7)
                        }

                        Rectangle {
                            id: lookupBtn
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: lookupRow.implicitWidth + 18
                            implicitHeight: 22
                            radius: 11

                            readonly property bool usable: root.hasPlayer
                                && root.player.trackTitle.length > 0
                                && root.lyricsState !== "loading"

                            color: usable && lookHover.hovered
                                ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.24)
                                : Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.35)
                            opacity: usable ? 1 : 0.45
                            Behavior on color { ColorAnimation { duration: 110 } }

                            RowLayout {
                                id: lookupRow
                                anchors.centerIn: parent
                                spacing: 4

                                DashIcon {
                                    Layout.alignment: Qt.AlignVCenter
                                    name: (root.lyricsState === "ok" || root.lyricsState === "none" || root.lyricsState === "error")
                                        ? "refresh" : "search"
                                    color: Theme.accentPrimary
                                    font.pixelSize: Theme.dashboardText(12)
                                }

                                Text {
                                    text: (root.lyricsState === "ok" || root.lyricsState === "none" || root.lyricsState === "error")
                                        ? "AGAIN" : "LOOK UP"
                                    color: Theme.accentPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.dashboardText(7)
                                    font.bold: true
                                    font.letterSpacing: 0.6
                                }
                            }

                            HoverHandler {
                                id: lookHover
                                enabled: lookupBtn.usable
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                enabled: lookupBtn.usable
                                onTapped: root.lookupLyrics()
                            }
                        }
                    }
                }
            }
        }
    }
}
