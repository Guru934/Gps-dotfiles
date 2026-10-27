import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "PetSprites.js" as S

// Desktop pet: roams on your windows, reacts to music / cursor / agent alerts, has its own panel.
//
//   import "pet"            // folder containing these files
//   Pet {}                  // in shell.qml
//
// Hooks for the rest of the shell:
//   pet.perch = { enabled: true, x1: .., x2: .., y: .. }   // island top edge in logical px (optional)
//   pet.wave()                                              // e.g. when a notification toast shows
//   pet.alert(true) / pet.clear()                           // agent permission asked / answered
Scope {
    id: root

    property var perch: null
    readonly property alias settings: settings
    readonly property alias brain: brain
    readonly property bool panelVisible: panel.visible

    function wave() { brain.wave() }
    function alert(sticky) { if (settings.reactAlerts) brain.raiseAlert(sticky) }
    function clear() { brain.dismissAlert() }
    function openPanel() {
        if (panel.visible) return;
        panel.visible = false;
        panel.visible = true;
    }
    function togglePanel() {
        if (panel.visible) panel.visible = false;
        else openPanel();
    }

    readonly property real spriteW: (S.W + 2) * settings.scale
    readonly property real spriteH: (S.H + 2) * settings.scale

    readonly property bool musicPlaying: {
        var l = Mpris.players ? Mpris.players.values : [];
        for (var i = 0; i < l.length; i++) if (l[i].isPlaying) return true;
        return false;
    }

    PetTheme { id: theme }
    PetSettings { id: settings
        onLoadedFromDisk: {
            brain.energy = settings.energy; brain.mood = settings.mood;
            brain.steps = settings.steps; brain.pets = settings.pets; brain.sleepSeconds = settings.sleepSeconds;
        }
    }

    PetWorld {
        id: world
        spriteW: root.spriteW
        spriteH: root.spriteH
        floorInset: settings.scale
        active: settings.enabled
        pollCursor: settings.enabled && (settings.followCursor || settings.sleepWhenIdle)
        onWorkspaceIdChanged: if (settings.respawnOnWorkspace && settings.enabled && brain.settled) brain.respawn()
    }

    PetBrain {
        id: brain
        property bool settled: false
        spriteW: root.spriteW
        spriteH: root.spriteH
        surfaces: world.surfaces
        xMin: world.monitor.xMin; xMax: world.monitor.xMax
        yMin: world.monitor.yMin; floorY: world.monitor.floorY
        perch: root.perch
        cursorX: world.cursorX; cursorY: world.cursorY; cursorValid: world.cursorValid
        cursorIdleSec: world.cursorIdleSec
        musicPlaying: root.musicPlaying
        paused: !settings.enabled || (settings.hideFullscreen && world.fullscreen)
        roam: settings.roam
        edges: settings.windowEdges
        followCursor: settings.followCursor
        reactMusic: settings.reactMusic
        sleepWhenIdle: settings.sleepWhenIdle
        sleepAfter: settings.sleepAfter
        activity: settings.activity
        onEffect: (kind, x, y) => win.addEffect(kind, x, y)
        Component.onCompleted: { spawn(world.monitor.w ? world.monitor.w / 2 : 600); settled = true }
    }

    // persist vitals now and then
    Timer {
        interval: 30000; repeat: true; running: settings.enabled
        onTriggered: root.saveVitals()
    }
    function saveVitals() {
        settings.energy = Math.round(brain.energy * 10) / 10;
        settings.mood = Math.round(brain.mood * 10) / 10;
        settings.steps = Math.round(brain.steps);
        settings.pets = brain.pets;
        settings.sleepSeconds = Math.round(brain.sleepSeconds);
        settings.saveNow();
    }
    Component.onDestruction: saveVitals()

    PetWindow {
        id: win
        brain: brain
        settings: settings
        theme: theme
        wantScreenName: world.monitorName
        shown: settings.enabled && !(settings.hideFullscreen && world.fullscreen) && world.ok
        onOpenPanel: root.openPanel()
    }

    readonly property var petActions: ({
        callHere: function () {
            if (!world.cursorValid) { brain.respawn(); return; }
            brain.spawn(world.cursorX, Math.max(world.monitor.yMin, world.cursorY - 120));
        },
        perch: function () { brain.goPerch() }
    })

    PetPanel {
        id: panel
        visible: false
        brain: brain
        settings: settings
        theme: theme
        perchAvailable: root.perch !== null && root.perch !== undefined && root.perch.enabled === true
        actions: root.petActions
    }

    IpcHandler {
        target: "pet"
        function panel(): void { root.togglePanel() }
        function toggle(): void { settings.enabled = !settings.enabled }
        function wave(): void { brain.wave() }
        function dance(): void { brain.dance() }
        function hop(): void { brain.hop() }
        function nap(): void { brain.doSleep() }
        function respawn(): void { brain.respawn() }
        function callHere(): void { root.petActions.callHere() }
        function perch(): void { brain.goPerch() }
        function alert(sticky: bool): void { root.alert(sticky) }
        function clear(): void { root.clear() }
        function skin(id: string): void { if (S.skins[id]) settings.character = id }
        function status(): string {
            return JSON.stringify({ mode: brain.mode, ground: brain.groundId, x: Math.round(brain.px), y: Math.round(brain.py),
                energy: Math.round(brain.energy), mood: Math.round(brain.mood), music: root.musicPlaying,
                windows: world.windowCount, workspace: world.workspaceId, monitor: world.monitorName });
        }
    }
}
