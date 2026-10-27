import QtQuick
import Quickshell
import Quickshell.Io
import "PetSettings.js" as N

// Everything the pet remembers, saved as JSON next to your shell config.
Scope {
    id: s

    property string character: "cat"
    property string petName: ""
    property int scale: 3
    property real activity: 1.0
    property bool enabled: true
    property bool roam: true
    property bool windowEdges: true
    property bool followCursor: true
    property bool reactMusic: true
    property bool sleepWhenIdle: true
    property int sleepAfter: 90
    property bool hideFullscreen: true
    property bool respawnOnWorkspace: true
    property bool reactAlerts: true
    // vitals, written by Pet.qml every ~30 s
    property real energy: 100
    property real mood: 70
    property real steps: 0
    property int pets: 0
    property real sleepSeconds: 0

    property string path: {
        var cfg = Quickshell.env("XDG_CONFIG_HOME");
        if (!cfg) cfg = Quickshell.env("HOME") + "/.config";
        return cfg + "/quickshell/pet.json";
    }

    property bool ready: false
    signal loadedFromDisk()

    readonly property var keys: ["character", "petName", "scale", "activity", "enabled", "roam", "windowEdges",
        "followCursor", "reactMusic", "sleepWhenIdle", "sleepAfter", "hideFullscreen", "respawnOnWorkspace",
        "reactAlerts", "energy", "mood", "steps", "pets", "sleepSeconds"]

    function snapshotObject() {
        var o = {};
        for (var i = 0; i < keys.length; i++) o[keys[i]] = s[keys[i]];
        return o;
    }

    function snapshot() { return JSON.stringify(s.snapshotObject(), null, 2) }

    function apply(text) {
        var clean = N.parse(text, s.snapshotObject());
        if (clean === null) return;
        for (var i = 0; i < keys.length; i++) s[keys[i]] = clean[keys[i]];
    }

    // changing any of the persisted values (except the fast-moving vitals) schedules a save
    readonly property string saveKey: JSON.stringify([character, petName, scale, activity, enabled, roam, windowEdges,
        followCursor, reactMusic, sleepWhenIdle, sleepAfter, hideFullscreen, respawnOnWorkspace, reactAlerts])
    onSaveKeyChanged: if (ready) saveTimer.restart()

    function saveNow() { if (ready) file.setText(snapshot()) }

    Timer { id: saveTimer; interval: 500; onTriggered: s.saveNow() }

    FileView {
        id: file
        path: s.path
        printErrors: false
        onLoaded: { s.apply(file.text()); s.ready = true; s.loadedFromDisk() }
        onLoadFailed: { s.ready = true; s.loadedFromDisk() }   // first run: no file yet
    }
}
