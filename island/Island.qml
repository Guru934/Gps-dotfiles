// Island core — dynamic island for QuickShell / Hyprland
// This file owns: the window, the morphing pill, live data (Hyprland, MPRIS, UPower, PipeWire,
// clipboard, alerts) and the state priority. Each state lives in its own file in states/:
//   Idle · Music · Charge · Clip · Osd · Alert · Notify · Focus · Dnd · Launcher · Privacy · Control
// Every value is read live: nothing on screen is hard-coded, and a field with no
// data simply hides. Drop into components/ and add `Island {}` inside your ShellRoot,
// or test alone:  qs -p IslandTest.qml
//
// Data sources
//   idle      Hyprland workspaces · SystemClock · CPU temperature from /sys
//   music     MPRIS (Quickshell.Services.Mpris) · optional `cava` for the real spectrum
//   charging  UPower (percentage, state, watts, time to full, health)
//   clipboard wl-paste --watch
//   volume    PipeWire default sink (level, mute, device name)
//   alert     $XDG_RUNTIME_DIR/pet/alerts.jsonl  (written by ~/.local/bin/pet-alert)
//   mascot    selected Pet skin from ~/.config/quickshell/pet.json (read-only; cat fallback)
// Priority: alert > privacy > launcher > control > volume/OSD > notification > focus > charging > clipboard > music > do-not-disturb > idle
//
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import qs.config
import "IslandVisibility.js" as IslandVisibility

Scope {
    id: root

    // ───────────── settings you can change ─────────────
    property bool followWallpaper: true      // accent colours from pywal / Caelestia palette
    property bool glow: true                 // soft coloured glow behind the pill
    property bool clipPreview: true          // set false to hide copied text (passwords!)
    property bool showTemp: true
    property bool notifsEnabled: true        // island owns org.freedesktop.Notifications (stop mako/dunst/swaync first!)
    property int maxToasts: 6
    property bool lyricsEnabled: true        // fetch synced lyrics from lrclib.net (sends song title online)
    property int topMargin: 6
    // ───────────── island settings integration ─────────────
    readonly property string settingsPath: {
        const cfg = Quickshell.env("XDG_CONFIG_HOME")
        return (cfg ? cfg : Quickshell.env("HOME") + "/.config") + "/quickshell/rice-settings.json"
    }
    property var islandSettings: IslandVisibility.resolveIslandSettings(null)
    readonly property var durations: islandSettings.durations
    property bool persistentMusicPill: islandSettings.persistentMusicPill
    onPersistentMusicPillChanged: root.updateVisibility()
    property int hoverGraceMs: islandSettings.hoverDelay
    property int hoverZoneWidth: islandSettings.hoverZoneWidth
    property int hoverZoneHeight: islandSettings.hoverZoneHeight
    property int workspaceFlashMs: durations.workspace

    onIslandSettingsChanged: {
        root.persistentMusicPill = islandSettings.persistentMusicPill
        root.hoverGraceMs = islandSettings.hoverDelay
        root.hoverZoneWidth = islandSettings.hoverZoneWidth
        root.hoverZoneHeight = islandSettings.hoverZoneHeight
        root.workspaceFlashMs = islandSettings.durations.workspace
        root.updateVisibility()
    }

    FileView {
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: {
            root.islandSettings = IslandVisibility.resolveIslandSettings(null)
            root.updateVisibility()
        }
        onLoaded: {
            root.islandSettings = IslandVisibility.resolveIslandSettings(text())
            root.updateVisibility()
        }
    }

    property bool isResting: false
    property bool isPinned: false
    property bool manualShow: false
    property bool manualHide: false
    property double hoverLeaveExpiry: 0
    property var transientQueue: []
    property string currentMode: "idle"
    property string currentReason: "initial"
    property int expireSeconds: 900          // agent alerts expire after this long
    property string searchUrl: "https://duckduckgo.com/?q="
    property string debugMode: ""            // force a state: idle music charge clip osd alert focus launcher
    property bool alertExpanded: false
    property var alertResponseIds: []
    property bool alertResolvedOn: false
    onAlertResolvedOnChanged: root.updateVisibility()
    property double alertResolvedAt: 0
    property string alertResolvedLabel: ""
    readonly property string alertResolvedElapsed: alertResolvedOn && alertResolvedAt > 0 ? waited(alertResolvedAt) : ""
    property var privacyItems: []
    property bool privacyDetectorAvailable: false
    property string privacyDetectorDiagnostic: "starting PipeWire monitor"
    property bool privacyExpanded: false
    property bool privacySuppressed: false

    // ───────────── look ─────────────
    property color pillColor: "#000000"
    property color text: "#e0e2ed"
    property color dim: "#859490"
    property color teal: "#57f1db"
    property color lav: "#ddb8ff"
    property color amber: "#ffd47b"
    property color coral: "#ff5d7a"
    property string uiFont: Qt.application.font.family
    property string monoFont: "monospace"
    property string iconFont: "Material Symbols Rounded"
    property bool iconOk: true

    // ───────────── live data (all derived, override only for tests) ─────────────
    property bool ready: false
    property real now: Date.now() / 1000

    readonly property var clock: SystemClock { precision: SystemClock.Minutes }
    property string timeText: Qt.formatTime(clock.date, "hh:mm")
    property int wsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
    onWsIdChanged: {
        if (ready) {
            root.postEvent("idle", IslandVisibility.PRIORITY.TRANSIENT, root.durations.workspace)
        }
        root.updateVisibility()
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.updateVisibility() }
        function onFocusedWorkspaceChanged() { root.updateVisibility() }
    }
    Connections {
        target: Hyprland.focusedWorkspace
        function onHasFullscreenChanged() { root.updateVisibility() }
    }
    property var wsList: Hyprland.workspaces.values.map(w => w.id).filter(i => i > 0).sort((a, b) => a - b)
    readonly property bool isFullscreen: Boolean(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen)
    property int temp: 0

    readonly property var player: pickPlayer()
    function pickPlayer() {
        let best = null
        for (const p of Mpris.players.values) {
            if (p.isPlaying) return p
            if (!best && p.trackTitle) best = p
        }
        return best
    }
    property bool hasMedia: player !== null && player.trackTitle !== ""
    property bool playing: player !== null && player.isPlaying
    property string title: player ? player.trackTitle : ""
    property string artist: player ? player.trackArtist : ""
    property string artUrl: player ? player.trackArtUrl : ""
    property real position: player ? player.position : 0
    property real length: player ? player.length : 0
    property bool warm: false                // keep showing a paused player for a while
    property string lastTrackKey: ""
    readonly property string trackKey: (title || "") + " - " + (artist || "")
    onTrackKeyChanged: {
        if (ready && trackKey !== "" && trackKey !== " - " && trackKey !== lastTrackKey) {
            lastTrackKey = trackKey
            root.postEvent("music", IslandVisibility.PRIORITY.TRANSIENT, root.durations.musicChange)
        }
    }

    readonly property var bat: UPower.displayDevice
    property bool hasBat: bat !== null && bat.energyCapacity > 0
    property real batPct: hasBat ? (bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage) : 0
    property bool charging: hasBat && (bat.state === UPowerDeviceState.Charging)
    property bool full: hasBat && (bat.state === UPowerDeviceState.FullyCharged)
    property real watts: hasBat ? Math.abs(bat.changeRate) : 0
    property real ttf: hasBat ? bat.timeToFull : 0
    property real health: hasBat && bat.healthSupported ? (bat.healthPercentage <= 1 ? bat.healthPercentage * 100 : bat.healthPercentage) : 0
    property string chargeKind: "plug"       // plug · unplug · low

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: sink ? sink.audio : null
    readonly property var sourceAudio: source ? source.audio : null
    property real volume: sinkAudio ? sinkAudio.volume : 0
    property bool muted: sinkAudio ? sinkAudio.muted : false
    property string sinkName: sink ? (sink.description || sink.nickname || sink.name) : ""
    property real micVolume: sourceAudio ? sourceAudio.volume : 0
    property bool micMuted: sourceAudio ? sourceAudio.muted : false
    property string sourceName: source ? (source.description || source.nickname || source.name) : ""

    readonly property bool hasBrightness: Brightness.available
    readonly property real brightness: Brightness.available ? (Brightness.percent / 100.0) : 0.0
    readonly property int brightnessPct: Brightness.percent
    onBrightnessPctChanged: {
        if (ready) requestOsd("bright")
    }

    property var alerts: []
    onAlertsChanged: root.updateVisibility()
    property string clipText: ""
    property int clipChars: 0
    property string clipKind: ""
    property string clipMime: ""
    property string clipImgPath: ""
    property int clipBytes: 0
    property real clipTs: 0
    property bool clipHistoryOn: false
    property var bars: [0, 0, 0, 0, 0, 0, 0, 0]
    property bool cavaOk: true
    property bool topHovered: false
    property bool hovered: hover.hovered || topHovered
    onHoveredChanged: {
        root.controlPanelChanged(root.hovered)
        root.updateVisibility()
    }

    // ───────────── island mascot ─────────────
    // Read the desktop pet's selected skin but never write settings. The single
    // clock below drives every visible mascot; hidden states do not animate.
    readonly property string petConfigPath: {
        const cfg = Quickshell.env("XDG_CONFIG_HOME")
        return (cfg ? cfg : Quickshell.env("HOME") + "/.config") + "/quickshell/pet.json"
    }
    readonly property var petSkins: ["cat", "shadow", "snow", "fox", "robot", "slime", "ghost"]
    property string petSkin: "cat"
    property double petTick: 0
    readonly property bool petAnimating: mode === "idle"
        || (mode === "alert" && alerts.length > 0)
        || (mode === "notify" && !hovered && notifQueue.length > 0)
        || (mode === "music" && playing && !hovered)
    FileView {
        path: root.petConfigPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.petSkin = "cat"
        onLoaded: {
            let cfg
            try { cfg = JSON.parse(text()) } catch (e) { root.petSkin = "cat"; return }
            const id = cfg && typeof cfg.character === "string" ? cfg.character : "cat"
            root.petSkin = root.petSkins.indexOf(id) >= 0 ? id : "cat"
        }
    }
    Timer {
        interval: 125
        repeat: true
        running: root.petAnimating
        onTriggered: root.petTick += 1
    }

    // ───────────── focus session engine ─────────────
    // The deadline uses Date.now() because this QuickShell build does not expose a
    // monotonic clock to QML. A wall-clock adjustment can therefore move a deadline;
    // the short timer refreshes the displayed value and phase transitions safely.
    property bool focusOn: false
    property bool focusPaused: false
    property bool focusBreak: false
    property real focusRemaining: -1
    property int focusPhaseSeconds: 0
    property int focusWorkSeconds: 0
    property int focusBreakSeconds: 0
    property int focusSessionIndex: 0
    property int focusSessionCount: 0
    property string focusTitle: ""
    property double focusDeadlineMs: 0

    // ───────────── state registry (each state file registers its size here) ─────────────
    readonly property var stateFiles: ["Idle", "Music", "Charge", "Clip", "Osd", "Alert", "Notify", "Focus", "Dnd", "Launcher", "Privacy", "Control","FaceLock","Priority"]
    property var registry: ({})
    function register(key, item) { const r = Object.assign({}, registry); r[key] = item; registry = r }
    readonly property var cur: registry[mode] || null
    readonly property color accent: cur && cur.accent ? cur.accent : teal

    // ───────────── state machine ─────────────
    property bool osdOn: currentMode === "osd"
    property bool chargeOn: currentMode === "charge"
    property bool clipOn: currentMode === "clip"
    property bool launcherOpen: false
    property bool controlOpen: false
    property bool controlExpanded: false
    property bool controlEdgeHovered: false
    property bool controlPanelEntered: false
    readonly property int controlAutoHideMs: 300
    readonly property int controlTransitMs: 1200
    function setLauncher(open) {
        if (open && alerts.length > 0) return
        launcherOpen = Boolean(open)
        root.updateVisibility()
    }
    function openControl() {
        root.manualHide = false
        controlOpen = true
        controlExpanded = true
        controlPanelEntered = hovered
        root.hoverLeaveExpiry = 0
        root.updateVisibility()
    }
    function closeControl() {
        root.isPinned = false
        root.manualShow = false
        root.hoverLeaveExpiry = 0
        controlOpen = false
        controlExpanded = false
        controlPanelEntered = false
        root.updateVisibility()
    }
    function scheduleControlHide(delay) {
        if (!controlOpen && !root.isPinned) return
        if (root.isPinned) return
        root.hoverLeaveExpiry = Date.now() + (delay || root.hoverGraceMs)
        root.updateVisibility()
    }
    function controlTriggerEntered() {
        root.manualHide = false
        controlEdgeHovered = true
        root.hoverLeaveExpiry = 0
        controlPanelEntered = false
        controlOpen = true
        controlExpanded = true
        root.updateVisibility()
    }
    function controlTriggerExited() {
        controlEdgeHovered = false
        if (!controlOpen && !root.isPinned) return
        if (hovered) {
            root.hoverLeaveExpiry = 0
            return
        }
        if (!root.isPinned) {
            scheduleControlHide(controlPanelEntered ? root.hoverGraceMs : controlTransitMs)
        }
    }
    function controlPanelChanged(inside) {
        if (inside) {
            controlPanelEntered = true
            root.hoverLeaveExpiry = 0
            controlOpen = true
            controlExpanded = true
            root.updateVisibility()
        } else if (!controlEdgeHovered) {
            if (!root.isPinned) {
                scheduleControlHide(root.hoverGraceMs)
            }
        }
    }
    function setControl(action) {
        if (["toggle", "open", "off", "close", "expand", "collapse"].indexOf(action) < 0) return false
        if (action === "toggle") {
            if (controlOpen || root.isPinned) closeControl()
            else openControl()
        } else if (action === "open" || action === "expand") {
            openControl()
        } else if (action === "collapse") {
            controlExpanded = false
            root.updateVisibility()
        } else {
            closeControl()
        }
        return true
    }
    readonly property string repoRoot: Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    function openMediaHub() {
        Quickshell.execDetached([root.repoRoot + "/scripts/gps-ipc", "mediahub", "toggle"])
    }
    function openToolbox() {
        Quickshell.execDetached([root.repoRoot + "/scripts/gps-ipc", "toolbox", "toggle"])
    }
    readonly property bool privacyVisible: !privacySuppressed && privacyItems.length > 0
    onPrivacyVisibleChanged: root.updateVisibility()
    function handlePrivacy(line) {
        let payload
        try { payload = JSON.parse(line) } catch (e) { return }
        if (!payload || typeof payload !== "object" || !Array.isArray(payload.items)) return
        privacyDetectorAvailable = payload.available === true
        privacyDetectorDiagnostic = typeof payload.diagnostic === "string" ? payload.diagnostic : ""
        privacyItems = payload.items.filter(i => i && ["mic", "cam", "screen"].indexOf(i.kind) >= 0)
            .slice(0, 32).map(i => ({
                kind: String(i.kind),
                app: typeof i.app === "string" && i.app !== "" ? i.app : "Unknown application",
                detail: typeof i.detail === "string" && i.detail !== "" ? i.detail : "Unknown device",
                pid: Number.isInteger(Number(i.pid)) && Number(i.pid) > 0 ? Number(i.pid) : 0,
                id: typeof i.id === "string" && i.id !== "" ? i.id : String(i.kind)
            }))
        if (privacyItems.length === 0) privacyExpanded = false
        root.updateVisibility()
    }
    function setPrivacy(action) {
        if (action === "off") { privacySuppressed = true; privacyExpanded = false }
        else if (action === "toggle") {
            privacySuppressed = false
            privacyExpanded = privacyVisible ? !privacyExpanded : false
        } else if (action === "expand") {
            privacySuppressed = false
            privacyExpanded = privacyVisible
        }
        root.updateVisibility()
    }

    function validFocusInteger(value, minimum, maximum) {
        const n = Number(value)
        return Number.isInteger(n) && n >= minimum && n <= maximum
    }

    function focusBeginPhase(isBreak, atMs) {
        focusBreak = isBreak
        focusPhaseSeconds = isBreak ? focusBreakSeconds : focusWorkSeconds
        focusRemaining = focusPhaseSeconds
        focusDeadlineMs = atMs + focusPhaseSeconds * 1000
    }

    function finishFocus() {
        focusOn = false
        focusPaused = false
        focusBreak = false
        focusRemaining = -1
        focusPhaseSeconds = 0
        focusSessionIndex = 0
        focusSessionCount = 0
        focusTitle = ""
        focusDeadlineMs = 0
    }

    function advanceFocus(atMs) {
        let guard = 0
        while (focusOn && !focusPaused && atMs >= focusDeadlineMs && guard++ < 100) {
            if (focusBreak) {
                if (focusSessionIndex >= focusSessionCount) {
                    finishFocus()
                    return
                }
                focusSessionIndex += 1
                focusBeginPhase(false, focusDeadlineMs)
            } else if (focusSessionIndex < focusSessionCount && focusBreakSeconds > 0) {
                focusBeginPhase(true, focusDeadlineMs)
            } else if (focusSessionIndex < focusSessionCount) {
                focusSessionIndex += 1
                focusBeginPhase(false, focusDeadlineMs)
            } else {
                finishFocus()
                return
            }
        }
        if (focusOn) focusRemaining = Math.max(0, (focusDeadlineMs - atMs) / 1000)
    }

    function updateFocusClock() {
        if (!focusOn || focusPaused) return
        advanceFocus(Date.now())
    }

    function startFocus(workSeconds, breakSeconds, sessionCount, title) {
        const work = Number(workSeconds)
        const rest = Number(breakSeconds)
        const count = Number(sessionCount)
        if (!validFocusInteger(work, 1, 604800)
                || !validFocusInteger(rest, 0, 604800)
                || !validFocusInteger(count, 1, 1000)) return false

        focusWorkSeconds = work
        focusBreakSeconds = rest
        focusSessionCount = count
        focusSessionIndex = 1
        focusTitle = typeof title === "string" ? title.trim().slice(0, 100) : ""
        focusOn = true
        focusPaused = false
        focusBeginPhase(false, Date.now())
        root.postEvent("focus", IslandVisibility.PRIORITY.TRANSIENT, 3000)
        root.updateVisibility()
        return true
    }

    function pauseFocus() {
        if (!focusOn || focusPaused) return false
        updateFocusClock()
        if (!focusOn) return false
        focusPaused = true
        focusDeadlineMs = 0
        root.updateVisibility()
        return true
    }

    function resumeFocus() {
        if (!focusOn || !focusPaused || focusRemaining <= 0) return false
        focusDeadlineMs = Date.now() + focusRemaining * 1000
        focusPaused = false
        root.updateVisibility()
        return true
    }

    function skipFocus() {
        if (!focusOn) return false
        if (!focusPaused) updateFocusClock()
        if (!focusOn) return true

        const atMs = Date.now()
        focusPaused = false
        if (focusBreak) {
            if (focusSessionIndex >= focusSessionCount) {
                finishFocus()
                root.clearEvent("focus")
                root.updateVisibility()
                return true
            }
            focusSessionIndex += 1
            focusBeginPhase(false, atMs)
        } else if (focusSessionIndex < focusSessionCount && focusBreakSeconds > 0) {
            focusBeginPhase(true, atMs)
        } else if (focusSessionIndex < focusSessionCount) {
            focusSessionIndex += 1
            focusBeginPhase(false, atMs)
        } else {
            finishFocus()
            root.clearEvent("focus")
            root.updateVisibility()
            return true
        }
        root.postEvent("focus", IslandVisibility.PRIORITY.TRANSIENT, 3000)
        root.updateVisibility()
        return true
    }

    function stopFocus() {
        if (!focusOn && focusRemaining < 0) return false
        finishFocus()
        focusWorkSeconds = 0
        focusBreakSeconds = 0
        focusTitle = ""
        root.clearEvent("focus")
        root.updateVisibility()
        return true
    }

    readonly property bool musicVisible: hasMedia && (playing || warm)
    readonly property string autoMode: (alerts.length > 0 || alertResolvedOn) ? "alert" : privacyVisible ? "privacy" : launcherOpen ? "launcher" : controlOpen ? "control" : osdOn ? "osd" : notifQueue.length > 0 ? "notify" : focusOn ? "focus" : chargeOn ? "charge" : (clipHistoryOn || clipOn) ? "clip" : musicVisible ? "music" : dnd ? "dnd" : "idle"
    readonly property string mode: debugMode !== "" && !controlOpen ? debugMode : (currentMode || autoMode)
    readonly property bool wantsKeyboardFocus: root.isPinned
        || (mode === "clip" && (clipHistoryOn || hovered))
        || (mode === "alert" && (alertExpanded || hovered || alerts.length > 0))
        || (mode === "control" && (controlExpanded || hovered || isPinned))
        || (mode === "launcher")

    onPlayingChanged: {
        if (playing) {
            warm = true
        } else {
            bars = [0, 0, 0, 0, 0, 0, 0, 0]
        }
        root.updateVisibility()
    }
    Timer {
        running: true
        interval: 3000
        onTriggered: {
            root.ready = true
            root.audioInitialized = true
            root.lastTrackKey = root.trackKey
            root.updateVisibility()
        }
    }
    Timer {
        id: visibilityTimer
        interval: 100
        repeat: false
        onTriggered: root.updateVisibility()
    }
    Timer {
        id: osdRequestTimer
        interval: 40
        onTriggered: root.pokeOsd(root.pendingOsdKind)
    }
    Timer {
        id: focusTimer
        interval: 250
        repeat: true
        running: root.focusOn && !root.focusPaused
        onTriggered: root.updateFocusClock()
    }

    function postEvent(kind, priority, duration) {
        if (!ready) return
        root.manualHide = false
        var dur = typeof duration === "number" ? duration : 1500
        var prio = priority !== undefined ? priority : IslandVisibility.PRIORITY.TRANSIENT
        root.transientQueue = IslandVisibility.postEvent(root.transientQueue, {
            kind: kind,
            priority: prio,
            duration: dur
        }, Date.now())
        root.updateVisibility()
    }

    function clearEvent(kind) {
        root.transientQueue = (root.transientQueue || []).filter(function(ev) {
            return ev && ev.kind !== kind
        })
        root.updateVisibility()
    }

    function gatherInputs() {
        var wsEmpty = false
        if (!Hyprland.focusedWorkspace) {
            wsEmpty = true
        } else if (Hyprland.focusedWorkspace.toplevels && Hyprland.focusedWorkspace.toplevels.values) {
            wsEmpty = Hyprland.focusedWorkspace.toplevels.values.length === 0
        }

        return {
            now: Date.now(),
            windowFocused: Hyprland.activeToplevel !== null,
            fullscreen: Boolean(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen),
            workspaceEmpty: wsEmpty,
            hovered: root.hovered,
            pinned: root.isPinned,
            manualShow: root.manualShow,
            manualHide: root.manualHide,
            activeAlert: Boolean(root.alerts && root.alerts.length > 0) || root.alertResolvedOn,
            transientQueue: root.transientQueue,
            hoverLeaveExpiry: root.hoverLeaveExpiry,
            settings: {
                persistentMusicPill: root.persistentMusicPill,
                hoverDelay: root.hoverGraceMs,
                hoverZoneWidth: root.hoverZoneWidth,
                hoverZoneHeight: root.hoverZoneHeight,
                durations: root.durations
            },
            isMusicPlaying: root.playing,
            privacyVisible: root.privacyVisible,
            launcherOpen: root.launcherOpen,
            dnd: root.dnd,
            focusOn: root.focusOn
        }
    }

    function updateVisibility() {
        var decision = IslandVisibility.evaluateVisibility(gatherInputs())
        var oldState = root.currentMode
        var newState = decision.state
        var reason = decision.reason

        if (Quickshell.env("GPS_DEBUG") === "1" && oldState !== newState) {
            console.log(IslandVisibility.formatTransitionLog(oldState, newState, reason))
        }

        root.isResting = !decision.visible
        root.currentMode = decision.state
        root.currentReason = decision.reason

        var now = Date.now()
        root.transientQueue = (root.transientQueue || []).filter(function(ev) {
            return ev && typeof ev.expiry === "number" && ev.expiry > now
        })

        if (decision.nextExpiry !== null && decision.nextExpiry !== undefined) {
            var remaining = Math.max(10, decision.nextExpiry - now)
            visibilityTimer.stop()
            visibilityTimer.interval = remaining
            visibilityTimer.start()
        } else {
            visibilityTimer.stop()
        }
    }

    function holdClip() {
        if (!ready) return
        root.postEvent("clip", IslandVisibility.PRIORITY.TRANSIENT, root.durations.clipboard)
    }
    property string osdKind: "vol"
    property string pendingOsdKind: "vol"
    property bool audioInitialized: false
    readonly property var osdKinds: ["vol", "mute", "bright", "route", "mic"]

    function pokeOsd(kind) {
        const requested = kind || "vol"
        if (!ready || osdKinds.indexOf(requested) < 0) return false
        if (requested === "bright" && !hasBrightness) return false
        if ((requested === "vol" || requested === "mute" || requested === "route") && !sinkAudio) return false
        if (requested === "mic" && !sourceAudio) return false
        osdKind = requested
        root.postEvent("osd", IslandVisibility.PRIORITY.TRANSIENT, root.durations.osd)
        return true
    }
    function requestOsd(kind) {
        if (!ready || !audioInitialized) return
        pendingOsdKind = kind
        osdRequestTimer.restart()
    }
    Connections {
        target: root.sinkAudio
        function onVolumeChanged() { root.requestOsd("vol") }
        function onMutedChanged() { root.requestOsd(root.muted ? "mute" : "vol") }
    }
    Connections {
        target: root.sourceAudio
        function onVolumeChanged() { root.requestOsd("mic") }
        function onMutedChanged() { root.requestOsd("mic") }
    }
    onSinkChanged: requestOsd("route")
    onSourceChanged: requestOsd("mic")

    property bool lowShown20: false
    property bool lowShown10: false
    property bool lowShown5: false
    function flashCharge(kind) {
        if (!ready) return
        chargeKind = kind
        root.postEvent("charge", IslandVisibility.PRIORITY.TRANSIENT, root.durations.charge)
    }
    Connections {
        target: root.bat
        function onStateChanged() {
            if (root.charging) { root.lowShown20 = false; root.lowShown10 = false; root.lowShown5 = false; root.flashCharge("plug") }
            else if (root.bat.state === UPowerDeviceState.Discharging) root.flashCharge("unplug")
        }
        function onPercentageChanged() {
            if (root.charging || !root.hasBat) return
            if (root.batPct <= 5 && !root.lowShown5) { root.lowShown5 = true; root.flashCharge("low") }
            else if (root.batPct <= 10 && !root.lowShown10) { root.lowShown10 = true; root.flashCharge("low") }
            else if (root.batPct <= 20 && !root.lowShown20) { root.lowShown20 = true; root.flashCharge("low") }
        }
    }
    PwObjectTracker {
        objects: root.sink && root.source ? [root.sink, root.source]
               : root.sink ? [root.sink]
               : root.source ? [root.source]
               : []
    }

    // ───────────── notifications (D-Bus server) + do-not-disturb ─────────────
    property bool dnd: false
    property var notifQueue: []              // [{n: Notification, ts, age, timeout}] newest first
    property var held: []                    // queued silently while DND is on
    function addNotif(n) {
        n.tracked = true
        n.closed.connect(function () { root.dropNotif(n) })
        const crit = n.urgency === NotificationUrgency.Critical
        const item = { n: n, ts: Date.now() / 1000, age: 0, timeout: crit ? 0 : (n.expireTimeout > 0 ? Math.min(n.expireTimeout, 15) : 6) }
        if (dnd && !crit) { held = [item].concat(held).slice(0, 30); return }
        notifQueue = [item].concat(notifQueue.filter(q => q.n !== n)).slice(0, maxToasts)
        root.postEvent("notify", IslandVisibility.PRIORITY.TRANSIENT, root.durations.notification)
    }
    function dropNotif(n) {
        notifQueue = notifQueue.filter(q => q.n !== n)
        held = held.filter(q => q.n !== n)
        if (notifQueue.length === 0) {
            root.clearEvent("notify")
        }
    }
    function dismissNotif(item) {
        const n = item.n
        notifQueue = notifQueue.filter(q => q !== item)
        n.dismiss()
        if (notifQueue.length === 0) {
            root.clearEvent("notify")
        }
    }
    function dismissAllNotifs() {
        const l = notifQueue
        notifQueue = []
        l.forEach(q => q.n.dismiss())
        root.clearEvent("notify")
    }
    function invokeAction(item, action) {
        action.invoke()
        if (!item.n.resident) notifQueue = notifQueue.filter(q => q !== item)
    }
    function setDnd(on) {
        dnd = on
        if (!on && held.length > 0) {                 // release what piled up as a reviewable stack
            held.forEach(q => { q.age = 0 })
            notifQueue = held.concat(notifQueue).slice(0, maxToasts)
            held = []
        }
        root.postEvent("dnd", IslandVisibility.PRIORITY.TRANSIENT, root.durations.workspace)
        root.updateVisibility()
    }
    function ago(ts) { const s = Math.max(0, Math.floor(now - ts)); return s < 10 ? "now" : s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h" }
    function iconSrc(n) {
        if (n.image && n.image !== "") return n.image.charAt(0) === "/" ? "file://" + n.image : n.image
        if (n.appIcon && n.appIcon !== "") return n.appIcon.charAt(0) === "/" ? "file://" + n.appIcon : Quickshell.iconPath(n.appIcon, true)
        return ""
    }
    Loader {
        active: root.notifsEnabled
        sourceComponent: Component {
            NotificationServer {
                bodySupported: true
                actionsSupported: true
                imageSupported: true
                onNotification: n => root.addNotif(n)
            }
        }
    }
    // age toasts only while the pointer is away; critical ones stay until dismissed
    Timer {
        interval: 1000; repeat: true; running: root.notifQueue.length > 0
        onTriggered: {
            root.now = Date.now() / 1000
            if (root.hovered) return
            const keep = []
            for (const q of root.notifQueue) {
                q.age += 1
                if (q.timeout > 0 && q.age >= q.timeout) q.n.expire()
                else keep.push(q)
            }
            if (keep.length !== root.notifQueue.length) {
                root.notifQueue = keep
                if (keep.length === 0) root.clearEvent("notify")
            }
        }
    }
    // control from a keybind:  qs -p <path> ipc call island control toggle
    // DND:                     qs -p <path> ipc call island dnd toggle
    // clipboard history:       qs -p <path> ipc call island clip
    // focus preview:           qs -p <path> ipc call island debug focus
    IpcHandler {
        target: "island"
        function dnd(state: string): void { root.setDnd(state === "toggle" ? !root.dnd : state === "on") }
        function launcher(state: string): void { root.setLauncher(state === "toggle" ? !root.launcherOpen : state !== "close") }
        function control(action: string): void { root.setControl(action) }
        function show(): void {
            root.manualHide = false
            root.manualShow = true
            root.openControl()
            root.updateVisibility()
        }
        function hide(): void {
            root.manualShow = false
            root.manualHide = true
            root.closeControl()
            root.updateVisibility()
        }
        function pin(): void {
            root.manualHide = false
            root.manualShow = false
            root.isPinned = true
            root.openControl()
            root.updateVisibility()
        }
        function unpin(): void {
            root.isPinned = false
            root.manualShow = false
            root.closeControl()
            root.updateVisibility()
        }
        function status(): string {
            return IslandVisibility.formatStatus(root.currentMode, root.currentReason, !root.isResting, root.isPinned)
        }
        function clear(): void { root.dismissAllNotifs() }
        function debug(mode: string): void { root.debugMode = mode }
        function mediaHub(action: string): void { root.openMediaHub() }
        function toolbox(action: string): void { root.openToolbox() }
        function focusStart(workSeconds: int, breakSeconds: int, sessionCount: int, title: string): void {
            root.startFocus(workSeconds, breakSeconds, sessionCount, title)
        }
        function focusPause(): void { root.pauseFocus() }
        function focusResume(): void { root.resumeFocus() }
        function focusSkip(): void { root.skipFocus() }
        function focusStop(): void { root.stopFocus() }
        function focusState(): string {
            return JSON.stringify({
                available: true,
                focusOn: root.focusOn,
                paused: root.focusPaused,
                isBreak: root.focusBreak,
                remaining: root.focusOn ? Math.max(0, Math.floor(root.focusRemaining)) : -1,
                phaseSeconds: root.focusPhaseSeconds,
                workSeconds: root.focusWorkSeconds,
                breakSeconds: root.focusBreakSeconds,
                sessionIndex: root.focusSessionIndex,
                sessionCount: root.focusSessionCount,
                title: root.focusTitle
            })
        }
        function osd(kind: string): void {
            if (kind === "bright") Brightness.refresh()
            root.pokeOsd(kind)
        }
        function alert(action: string): void {
            if (["expand", "toggle", "jump", "dismiss"].indexOf(action) < 0) return
            if (action === "expand") root.alertExpanded = root.alerts.length > 0
            else if (action === "toggle") root.alertExpanded = root.alerts.length > 0 && !root.alertExpanded
            else if (action === "jump" && root.alerts.length > 0) root.jump(root.alerts[0])
            else if (action === "dismiss" && root.alerts.length > 0) root.removeAlert(root.alerts[0].id)
        }
        function privacy(action: string): void {
            if (["toggle", "expand", "off"].indexOf(action) >= 0) root.setPrivacy(action)
        }
        function clip(): void {
            root.clipHistoryOn = !root.clipHistoryOn
            if (root.clipHistoryOn) {
                root.holdClip()
            } else {
                root.clipOn = false
                if (root.debugMode === "clip") root.debugMode = ""
            }
        }
        function clipboard(action: string): void {
            if (action === "close" || action === "off") {
                root.clipHistoryOn = false
                root.clipOn = false
                if (root.debugMode === "clip") root.debugMode = ""
            } else if (action === "open" || action === "on") {
                root.clipHistoryOn = true
                root.holdClip()
            } else {
                clip()
            }
        }
    }

    // PipeWire is event-driven; the helper polls direct V4L2 file descriptors every 1.5s.
    property string privacyDetectorPath: Quickshell.env("HOME") + "/Projects/my-rice/scripts/privacy_detector.py"
    Process {
        id: privacyFeed
        running: true
        command: ["python3", root.privacyDetectorPath]
        stdout: SplitParser {
            onRead: line => {
                console.log("[privacy-feed]", line)
                root.handlePrivacy(line)
            }
        }
        onExited: {
            root.privacyItems = []
            root.privacyDetectorAvailable = false
            root.privacyDetectorDiagnostic = "privacy detector stopped; retrying"
            privacyRestart.start()
        }
    }
    Timer {
        id: privacyRestart
        interval: 3000
        onTriggered: if (!privacyFeed.running) privacyFeed.running = true
    }

    // ───────────── helpers ─────────────
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }
    function fmtEta(s) { s = Math.floor(s / 60); return s >= 60 ? Math.floor(s / 60) + "h " + (s % 60) + "m" : s + "m" }
    function label(t) { return t === "opencode" ? "OpenCode" : t === "codex" ? "Codex" : (t || "Agent").charAt(0).toUpperCase() + (t || "Agent").slice(1) }
    function project(cwd) { const p = (cwd || "").split("/").filter(x => x !== ""); return p.length ? p[p.length - 1] : "" }
    function waited(ts) { const s = Math.max(0, Math.floor(now - ts)); return s < 60 ? s + "s" : Math.floor(s / 60) + "m" }
    function volIcon() { return muted || volume <= 0.001 ? "volume_off" : volume < 0.5 ? "volume_down" : "volume_up" }
    function removeAlert(id) {
        if (typeof id !== "string" || id === "") return false
        const next = alerts.filter(a => a.id !== id)
        if (next.length === alerts.length) return false
        alerts = next
        return true
    }
    function validAddress(addr) { return typeof addr === "string" && /^0x[0-9a-fA-F]+$/.test(addr) }
    function validWorkspace(ws) {
        const value = Number(ws)
        return Number.isInteger(value) && value > 0 && value <= 2147483647
    }
    function canJump(a) { return !!a && (validAddress(a.addr) || validWorkspace(a.ws)) }
    function jump(a) {
        if (!a || !canJump(a)) return false
        if (validAddress(a.addr))
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + a.addr])
        else
            Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(Number(a.ws))])
        removeAlert(a.id)
        return true
    }
    function respondAlert(a, decision) {
        if (!a || typeof a.id !== "string" || a.id === ""
                || typeof a.token !== "string" || a.token === ""
                || (decision !== "allow" && decision !== "deny")) return false
        if (alertResponseIds.indexOf(a.id) >= 0) return false
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/pet-alert", "respond",
                                 a.token, decision])
        alertResponseIds = alertResponseIds.concat([a.id])
        return true
    }
    function validAsk(o) {
        return o && o.type === "ask" && typeof o.id === "string" && o.id !== ""
            && typeof o.ts === "number" && o.ts <= now + 60 && now - o.ts <= expireSeconds
    }
    function clearMatches(a, o) {
        const idMatch = typeof o.id === "string" && o.id !== "" && a.id === o.id
        const sessionToolMatch = typeof o.session === "string" && o.session !== ""
            && a.session === o.session
            && (typeof o.tool !== "string" || o.tool === "" || a.tool === o.tool)
        return idMatch || sessionToolMatch
    }
    function genuineResolution(o) {
        return o.resolved === true || o.resolution === "resolved" || o.event === "PostToolUse" || o.kind === "resolved"
    }
    function handleAlert(line) {
        let o
        try { o = JSON.parse(line) } catch (e) { return }
        if (!o || typeof o !== "object") return
        if (o.type === "ask" && validAsk(o)) {
            alertResolvedOn = false
            alertExpanded = true
            alertResponseIds = alertResponseIds.filter(id => id !== o.id)
            alerts = [o].concat(alerts.filter(a => a.id !== o.id)).slice(0, 5)
        } else if (o.type === "clear") {
            const before = alerts.length
            const next = alerts.filter(a => !clearMatches(a, o))
            if (next.length === before) return
            alerts = next
            if (typeof o.id === "string" && o.id !== "")
                alertResponseIds = alertResponseIds.filter(id => id !== o.id)
            if (before > 0 && next.length === 0 && genuineResolution(o)) {
                alertResolvedOn = true
                alertResolvedAt = Date.now() / 1000
                alertResolvedLabel = "Resolved"
            }
        }
    }

    // ───────────── palette (optional) ─────────────
    function applyPalette(txt) {
        if (!followWallpaper) return
        let j
        try { j = JSON.parse(txt) } catch (e) { return }
        const hex = s => Qt.color(String(s).charAt(0) === "#" ? s : "#" + s)
        if (j.colours) {
            if (j.colours.primary) teal = hex(j.colours.primary)
            if (j.colours.secondary) lav = hex(j.colours.secondary)
            if (j.colours.tertiary) amber = hex(j.colours.tertiary)
        } else if (j.colors) {
            const list = Object.keys(j.colors).filter(k => ["color0", "color7", "color8", "color15"].indexOf(k) < 0).map(k => Qt.color(j.colors[k]))
            list.sort((a, b) => b.hsvSaturation * b.hsvValue - a.hsvSaturation * a.hsvValue)
            const lift = c => Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, Math.min(1, Math.max(c.hsvSaturation, 0.45)), Math.max(c.hsvValue, 0.88), 1)
            if (list.length > 0) teal = lift(list[0])
            const sec = list.find(c => Math.abs(c.hsvHue - list[0].hsvHue) > 0.12)
            if (sec) lav = lift(sec)
            const ter = list.find(c => sec && Math.abs(c.hsvHue - list[0].hsvHue) > 0.12 && Math.abs(c.hsvHue - sec.hsvHue) > 0.12)
            if (ter) amber = lift(ter)
        }
    }
    property string palettePath: ""
    FileView { path: root.palettePath; watchChanges: true; onFileChanged: reload(); onLoaded: root.applyPalette(text()) }
    Process {
        running: root.followWallpaper
        command: ["sh", "-c", 'for f in "$HOME/.cache/wal/colors.json" "$HOME/.local/state/caelestia/scheme.json"; do [ -f "$f" ] && { echo "$f"; break; }; done']
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.palettePath = text.trim() }
    }
    Process {
        running: true
        command: ["sh", "-c", "fc-list : family 2>/dev/null | tr ',' '\\n' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.split("\n").map(s => s.trim())
                const ico = f.find(s => /^Material Symbols (Rounded|Outlined)/.test(s))
                root.iconOk = !!ico
                if (ico) root.iconFont = ico
                if (f.indexOf("Inter") >= 0) root.uiFont = "Inter"
                const mono = f.find(s => /^JetBrains ?Mono( Nerd Font)?$/.test(s)) || f.find(s => /Mono/.test(s) && /Nerd/.test(s))
                if (mono) root.monoFont = mono
            }
        }
    }

    // ───────────── data feeds ─────────────
    // agent alerts
    Process {
        id: alertFeed
        running: true
        command: ["sh", "-c", 'umask 077; d="${XDG_RUNTIME_DIR:-/tmp}/pet"; mkdir -p "$d" || exit 1; [ ! -L "$d" ] || exit 1; chmod 700 "$d" || exit 1; p="$d/alerts.jsonl"; [ ! -L "$p" ] || exit 1; touch "$p" || exit 1; chmod 600 "$p" || exit 1; cat "$p"; exec tail -n0 -F "$p" 2>/dev/null']
        stdout: SplitParser { onRead: line => root.handleAlert(line) }
        onExited: alertRestart.start()
    }
    Timer { id: alertRestart; interval: 2000; onTriggered: alertFeed.running = true }
    Timer {
        interval: 1000; repeat: true; running: root.alerts.length > 0 || root.alertResolvedOn
        onTriggered: {
            root.now = Date.now() / 1000
            if (root.alertResolvedOn && root.now - root.alertResolvedAt >= 1) {
                root.alertResolvedOn = false
                root.alertResolvedAt = 0
                root.alertResolvedLabel = ""
            }
            if (root.alerts.some(a => root.now - a.ts > root.expireSeconds))
                root.alerts = root.alerts.filter(a => root.now - a.ts <= root.expireSeconds)
        }
    }

    // clipboard: one line "chars<TAB>preview" per text copy. Image selections are left to the
    // image watcher below so the two feeds cannot overwrite one another for the same copy.
    property double clipStart: 0
    Process {
        id: clipFeed
        running: true
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
                  't=$(cat); if wl-paste --list-types 2>/dev/null | grep -q "^image/"; then exit 0; fi; ' +
                  'n=$(printf %s "$t" | wc -m); p=$(printf %s "$t" | tr "\\n\\t" "  " | head -c 300); printf "%s\\t%s\\n" "$n" "$p"']
        stdout: SplitParser {
            onRead: line => {
                if (!root.ready || Date.now() - root.clipStart < 2500) return
                const i = line.indexOf("\t")
                const n = parseInt(line.slice(0, i))
                if (!n) return
                root.clipKind = "text"
                root.clipMime = "text/plain"
                root.clipImgPath = ""
                root.clipBytes = 0
                root.clipTs = Date.now() / 1000
                root.now = root.clipTs
                root.clipChars = n
                root.clipText = line.slice(i + 1).trim()
                root.postEvent("clip", IslandVisibility.PRIORITY.TRANSIENT, root.durations.clipboard)
            }
        }
        onExited: clipRestart.start()
    }
    Timer { id: clipRestart; interval: 5000; onTriggered: { root.clipStart = Date.now(); clipFeed.running = true } }

    // image clipboard: publish path + metadata only after a complete, non-empty atomic file write.
    property double clipImgStart: 0
    Process {
        id: clipImgFeed
        running: true
        command: ["wl-paste", "--watch", "sh", "-c",
                  'cat >/dev/null; d="${XDG_RUNTIME_DIR:-/tmp}"; umask 077; ' +
                  'imgm=$(wl-paste --list-types 2>/dev/null | grep -m1 "^image/"); ' +
                  '[ -n "$imgm" ] || exit 0; ' +
                  'imgp="$d/island-clip-image"; ' +
                  'tmp=$(mktemp "$d/island-clip-image.XXXXXX") || exit 1; ' +
                  'if wl-paste --type "$imgm" > "$tmp" 2>/dev/null; then ' +
                  '  sz=$(wc -c < "$tmp" 2>/dev/null || echo 0); ' +
                  '  if [ "${sz:-0}" -gt 0 ]; then mv -f "$tmp" "$imgp" && printf "IMG\\t%s\\t%s\\t%s\\n" "$imgm" "$sz" "$imgp"; else rm -f "$tmp"; fi; ' +
                  'else rm -f "$tmp"; fi']
        stdout: SplitParser {
            onRead: line => {
                if (!root.ready || Date.now() - root.clipImgStart < 2500) return
                const p = line.split("\t")
                if (p[0] !== "IMG" || !p[3]) return
                const n = parseInt(p[2]) || 0
                if (n <= 0) return
                root.clipKind = "image"
                root.clipMime = p[1] || "image/png"
                root.clipImgPath = p[3]
                root.clipBytes = n
                root.clipTs = Date.now() / 1000
                root.now = root.clipTs
                root.clipText = ""
                root.clipChars = 0
                root.postEvent("clip", IslandVisibility.PRIORITY.TRANSIENT, root.durations.clipboard)
            }
        }
        onExited: clipImgRestart.start()
    }
    Timer { id: clipImgRestart; interval: 5000; onTriggered: { root.clipImgStart = Date.now(); clipImgFeed.running = true } }
    Component.onCompleted: {
        clipStart = Date.now()
        clipImgStart = Date.now()
        root.updateVisibility()
    }

    // CPU temperature (idle pill)
    Process {
        id: tempProc
        command: ["sh", "-c", 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat "$z/type" 2>/dev/null); case "$t" in x86_pkg_temp|k10temp|coretemp|cpu*) echo $(( $(cat "$z/temp") / 1000 )); exit;; esac; done']
        stdout: StdioCollector { onStreamFinished: root.temp = parseInt(text) || 0 }
    }
    Timer { interval: 5000; repeat: true; running: root.showTemp && root.mode === "idle"; triggeredOnStart: true; onTriggered: if (!tempProc.running) tempProc.running = true }

    // MPRIS position tick (only while the expanded player is visible)
    Timer {
        interval: 1000; repeat: true
        running: root.player !== null && root.playing && root.mode === "music" && root.hovered
        onTriggered: root.player.positionChanged()
    }

    // real audio spectrum if `cava` exists, otherwise a soft animation — only while playing
    property bool gotCava: false
    Process {
        id: cava
        running: root.playing && root.cavaOk && root.mode === "music"
        command: ["sh", "-c", 'command -v cava >/dev/null || exit 127; c="${XDG_RUNTIME_DIR:-/tmp}/island-cava.conf"; printf "[general]\\nbars = 8\\nframerate = 30\\n[input]\\nmethod = pipewire\\n[output]\\nmethod = raw\\ndata_format = ascii\\nascii_max_range = 100\\nbar_delimiter = 59\\nframe_delimiter = 10\\n" > "$c"; exec cava -p "$c"']
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(s => s !== "").map(Number)
                if (v.length >= 8) { root.gotCava = true; root.bars = v.slice(0, 8) }
            }
        }
        onExited: { if (!root.gotCava) root.cavaOk = false; root.bars = [0, 0, 0, 0, 0, 0, 0, 0] }
    }
    Timer {
        interval: 110; repeat: true; running: root.playing && !root.cavaOk && root.mode === "music"
        onTriggered: root.bars = root.bars.map((v, i) => 18 + Math.random() * 72)
    }

    // ───────────── window ─────────────
    PanelWindow {
        id: win
        visible: !root.isResting
        screen: {
            const m = Hyprland.focusedMonitor
            const hit = m ? Quickshell.screens.find(s => s.name === m.name) : null
            return hit ? hit : Quickshell.screens[0]
        }
        anchors.top: true
        margins.top: root.topMargin
        exclusiveZone: 0
        color: "transparent"
        implicitWidth: 560
        implicitHeight: 420
        mask: Region { item: pill }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "island"
        WlrLayershell.keyboardFocus: root.mode === "launcher"
            ? WlrKeyboardFocus.Exclusive
            : root.wantsKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Shortcut {
            sequence: "Escape"
            enabled: win.visible && (root.isPinned || root.mode === "control" || root.controlOpen || root.manualShow)
            onActivated: root.closeControl()
        }

        Rectangle {
            visible: root.glow
            anchors.fill: pill; radius: pill.radius
            color: root.accent; opacity: 0.16
            Behavior on color { ColorAnimation { duration: 250 } }
            layer.enabled: root.glow
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40 }
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            color: root.pillColor
            radius: Math.min(height / 2, 28)
            width: root.cur ? root.cur.w : 170
            height: root.cur ? root.cur.h : 34
            Behavior on width { SpringAnimation { spring: 3.4; damping: 0.3; epsilon: 0.4 } }
            Behavior on height { SpringAnimation { spring: 3.4; damping: 0.3; epsilon: 0.4 } }

            Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08) }
            HoverHandler {
                id: hover
                onHoveredChanged: root.controlPanelChanged(hovered)
            }
            TapHandler {
                id: pillTap
                acceptedButtons: Qt.LeftButton
                gesturePolicy: TapHandler.WithinBounds
                onTapped: {
                    if (root.isPinned) {
                        root.closeControl()
                    } else {
                        root.isPinned = true
                        root.openControl()
                    }
                }
            }

            Repeater {
                model: root.stateFiles
                delegate: Loader {
                    required property string modelData
                    anchors.fill: parent
                    Component.onCompleted: setSource("states/" + modelData + ".qml", { core: root })
                }
            }
        }
    }

    PanelWindow {
        id: controlEdgeSensor
        screen: win.screen
        anchors { bottom: true; right: true }
        implicitWidth: 20
        implicitHeight: 20
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "island-control-edge"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: root.controlTriggerEntered()
            onExited: root.controlTriggerExited()
        }
    }

    PanelWindow {
        id: hoverTrigger
        screen: win.screen
        anchors.top: true
        margins.top: 0
        exclusiveZone: 0
        color: "transparent"
        implicitWidth: root.hoverZoneWidth
        implicitHeight: root.hoverZoneHeight
        width: root.hoverZoneWidth
        height: root.hoverZoneHeight
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "island-hover"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: !root.isFullscreen

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (root.isPinned) {
                    root.closeControl()
                } else {
                    root.isPinned = true
                    root.openControl()
                }
            }
            onEntered: {
                root.topHovered = true
                root.controlTriggerEntered()
                root.controlPanelChanged(true)
            }
            onExited: {
                root.topHovered = false
                root.controlTriggerExited()
                root.controlPanelChanged(false)
            }
        }
    }
}
