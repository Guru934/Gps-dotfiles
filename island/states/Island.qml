// Island core — dynamic island for QuickShell / Hyprland
// This file owns: the window, the morphing pill, live data (Hyprland, MPRIS, UPower, PipeWire,
// clipboard, alerts) and the state priority. Each state lives in its own file in states/:
//   Idle · Music · Charge · Clip · Osd · Alert        (add a file + one name in `stateFiles`)
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
// Priority: alert > volume > charging > clipboard > music > idle
//
// Tide Island and PetAlert both draw at the top-centre — disable them while testing this.
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

Scope {
    id: root

    // ───────────── settings you can change ─────────────
    property bool followWallpaper: true      // accent colours from pywal / Caelestia palette
    property bool glow: true                 // soft coloured glow behind the pill
    property bool clipPreview: true          // set false to hide copied text (passwords!)
    property bool showTemp: true
    property bool lyricsEnabled: true        // fetch synced lyrics from lrclib.net (sends song title online)
    property int topMargin: 6
    property int expireSeconds: 900          // agent alerts expire after this long
    property string debugMode: ""            // force a state: idle music charge clip osd alert

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
    property var wsList: Hyprland.workspaces.values.map(w => w.id).filter(i => i > 0).sort((a, b) => a - b)
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
    readonly property var sinkAudio: sink ? sink.audio : null
    property real volume: sinkAudio ? sinkAudio.volume : 0
    property bool muted: sinkAudio ? sinkAudio.muted : false
    property string sinkName: sink ? (sink.description || sink.nickname || sink.name) : ""

    property var alerts: []
    property string clipText: ""
    property int clipChars: 0
    property var bars: [0, 0, 0, 0, 0, 0, 0, 0]
    property bool cavaOk: true
    property bool hovered: hover.hovered

    // ───────────── state registry (each state file registers its size here) ─────────────
    readonly property var stateFiles: ["Idle", "Music", "Charge", "Clip", "Osd", "Alert"]
    property var registry: ({})
    function register(key, item) { const r = Object.assign({}, registry); r[key] = item; registry = r }
    readonly property var cur: registry[mode] || null
    readonly property color accent: cur && cur.accent ? cur.accent : teal

    // ───────────── state machine ─────────────
    property bool osdOn: false
    property bool chargeOn: false
    property bool clipOn: false
    readonly property bool musicVisible: hasMedia && (playing || warm)
    readonly property string autoMode: alerts.length > 0 ? "alert" : osdOn ? "osd" : chargeOn ? "charge" : clipOn ? "clip" : musicVisible ? "music" : "idle"
    readonly property string mode: debugMode !== "" ? debugMode : autoMode

    onPlayingChanged: {
        if (playing) { warm = true; coolDown.stop() } else { coolDown.restart(); bars = [0, 0, 0, 0, 0, 0, 0, 0] }
    }
    Timer { id: coolDown; interval: 60000; onTriggered: root.warm = false }
    Timer { running: true; interval: 3000; onTriggered: root.ready = true }
    Timer { id: osdTimer; interval: 1600; onTriggered: root.osdOn = false }
    Timer { id: chargeTimer; interval: 4200; onTriggered: root.chargeOn = false }
    Timer { id: clipTimer; interval: 3200; onTriggered: root.clipOn = false }

    function pokeOsd() { if (!ready) return; osdOn = true; osdTimer.restart() }
    Connections { target: root.sinkAudio; function onVolumeChanged() { root.pokeOsd() } function onMutedChanged() { root.pokeOsd() } }
    onSinkChanged: pokeOsd()

    property bool lowShown20: false
    property bool lowShown10: false
    property bool lowShown5: false
    function flashCharge(kind) { if (!ready) return; chargeKind = kind; chargeOn = true; chargeTimer.restart() }
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
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // ───────────── helpers ─────────────
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }
    function fmtEta(s) { s = Math.floor(s / 60); return s >= 60 ? Math.floor(s / 60) + "h " + (s % 60) + "m" : s + "m" }
    function label(t) { return t === "opencode" ? "OpenCode" : t === "codex" ? "Codex" : (t || "Agent").charAt(0).toUpperCase() + (t || "Agent").slice(1) }
    function project(cwd) { const p = (cwd || "").split("/").filter(x => x !== ""); return p.length ? p[p.length - 1] : "" }
    function waited(ts) { const s = Math.max(0, Math.floor(now - ts)); return s < 60 ? s + "s" : Math.floor(s / 60) + "m" }
    function volIcon() { return muted || volume <= 0.001 ? "volume_off" : volume < 0.5 ? "volume_down" : "volume_up" }
    function removeAlert(id) { alerts = alerts.filter(a => a.id !== id) }
    function jump(a) {
        if (a.addr) Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + a.addr])
        removeAlert(a.id)
    }
    function handleAlert(line) {
        let o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o.type === "ask") alerts = [o].concat(alerts.filter(a => a.id !== o.id)).slice(0, 5)
        else if (o.type === "clear")
            alerts = alerts.filter(a => !((o.id && a.id === o.id) || (!o.id && o.session && a.session === o.session && a.tool === o.tool)))
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
        command: ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/pet"; mkdir -p "$d"; touch "$d/alerts.jsonl"; exec tail -n0 -F "$d/alerts.jsonl" 2>/dev/null']
        stdout: SplitParser { onRead: line => root.handleAlert(line) }
        onExited: alertRestart.start()
    }
    Timer { id: alertRestart; interval: 2000; onTriggered: alertFeed.running = true }
    Timer {
        interval: 1000; repeat: true; running: root.alerts.length > 0
        onTriggered: {
            root.now = Date.now() / 1000
            if (root.alerts.some(a => root.now - a.ts > root.expireSeconds))
                root.alerts = root.alerts.filter(a => root.now - a.ts <= root.expireSeconds)
        }
    }

    // clipboard: one line "chars<TAB>preview" per copy
    property double clipStart: 0
    Process {
        id: clipFeed
        running: true
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
                  't=$(cat); n=$(printf %s "$t" | wc -m); p=$(printf %s "$t" | tr "\\n\\t" "  " | head -c 300); printf "%s\\t%s\\n" "$n" "$p"']
        stdout: SplitParser {
            onRead: line => {
                if (!root.ready || Date.now() - root.clipStart < 2500) return
                const i = line.indexOf("\t")
                const n = parseInt(line.slice(0, i))
                if (!n) return
                root.clipChars = n
                root.clipText = line.slice(i + 1).trim()
                root.clipOn = true
                clipTimer.restart()
            }
        }
        onExited: clipRestart.start()
    }
    Timer { id: clipRestart; interval: 5000; onTriggered: { root.clipStart = Date.now(); clipFeed.running = true } }
    Component.onCompleted: clipStart = Date.now()

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
        visible: true
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
        implicitHeight: 320
        mask: Region { item: pill }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "island"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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
            HoverHandler { id: hover }

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
}
