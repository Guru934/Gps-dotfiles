import QtQuick
import ".."

Item {
    id: root
    property int fails: 0
    property var effects: []
    function check(name, cond) { console.log((cond ? "PASS " : "FAIL ") + name); if (!cond) fails++ }
    PetBrain {
        id: b
        xMin: 60; xMax: 1280; yMin: 0; floorY: 800; spriteW: 66; spriteH: 60
        surfaces: [{id:"w1", x1:100, x2:600, y:300}, {id:"w2", x1:700, x2:1200, y:500}]
        rng: function() { return Math.random() }
        autoRun: false   // we drive step() by hand
        onEffect: (kind, x, y) => root.effects.push(kind)
    }
    function run(sec) { for (var i = 0; i < sec * 30; i++) b.step(1/30) }
    Component.onCompleted: {
        // 1. spawn above, falls onto the floor if no surface below its x
        b.spawn(1250); run(3)
        check("lands on floor at x=1250 (not under any window)", b.groundId === "floor" && b.py === 800)
        // 2. spawn above window w1: lands on its edge
        b.spawn(300); run(3)
        check("lands on window w1 edge", b.groundId === "w1" && b.py === 300)
        // 3. window disappears -> falls to floor
        b.surfaces = [{id:"w2", x1:700, x2:1200, y:500}]; run(3)
        check("falls to floor when window closes", b.groundId === "floor")
        // 4. window moves: pet rides it
        b.spawn(900); run(3)
        check("on w2", b.groundId === "w2")
        b.surfaces = [{id:"w2", x1:700, x2:1200, y:450}]; b.step(1/30)
        check("rides moved window (py 450)", b.py === 450)
        // 5. edges off -> only floor
        b.edges = false; b.spawn(900); run(3)
        check("edges=false: lands on floor", b.groundId === "floor")
        b.edges = true
        // 6. long soak: never leaves bounds, never NaN
        b.surfaces = [{id:"w1", x1:100, x2:600, y:300}, {id:"w2", x1:700, x2:1200, y:500}]
        b.spawn(400); var bad = false, seen = {}, grounds = {}
        for (var i = 0; i < 30 * 600; i++) {
            b.step(1/30); seen[b.mode] = true; grounds[b.groundId] = true
            if (isNaN(b.px) || isNaN(b.py) || b.px < 60 || b.px > 1280 || b.py > 801 || b.py < -200) { bad = true; console.log("bad at", i, b.px, b.py, b.mode); break }
        }
        check("10 min soak stays in bounds", !bad)
        check("visited several modes: " + Object.keys(seen).join(","), seen.walk && seen.sit && seen.jump)
        check("used several surfaces: " + Object.keys(grounds).join(","), Object.keys(grounds).length >= 3)
        // 7. drag + release
        b.beginDrag(); b.dragTo(650, 150); check("drag pose", b.pose === "drag"); b.endDrag(); run(3)
        check("after drop lands somewhere", b.groundId !== "")
        // 8. pet / alert / dismiss
        b.spawn(300); run(3); b.pet(); check("pet -> happy", b.mode === "happy" && b.pets === 1)
        run(3)
        b.raiseAlert(true); run(2)
        check("sticky alert reaches alert mode", b.mode === "alert")
        run(20); check("sticky alert persists", b.mode === "alert")
        b.dismissAlert(); check("dismiss -> wave", b.mode === "wave")
        b.raiseAlert(false); run(2); check("timed alert on", b.mode === "alert"); run(7)
        check("timed alert ends", b.mode !== "alert")
        // 9. music grooves, sleep when idle
        root.effects = []
        b.reactMusic = true; b.musicPlaying = true; b.spawn(300); run(60)
        check("groove while music plays (note effect)", root.effects.indexOf("note") >= 0)
        b.musicPlaying = false; b.cursorValid = true; b.cursorIdleSec = 200; run(40)
        check("sleeps when idle", b.mode === "sleep")
        b.cursorIdleSec = 0; run(6)
        check("wakes when user is back", b.mode !== "sleep")
        // 10. goPerch
        b.perch = {enabled:true, x1:550, x2:730, y:44}; b.surfaces = []
        // perch y=44 means headroom < spriteH, only used if island leaves room; just verify landing
        b.goPerch(); run(3); check("perch landing", b.groundId === "perch")
        console.log(fails === 0 ? "ALL PASS" : ("FAILS: " + fails))
        Qt.quit()
    }
}
