import QtQuick

// The pet's mind and body: a small physics + behaviour mode machine.
// No Quickshell imports here, so it can be tested with plain Qt.
//
// Coordinates are logical px on the pet's monitor. px = horizontal centre, py = feet.
Item {
    id: brain
    visible: false

    // ---- inputs ---------------------------------------------------------------
    property var surfaces: []            // [{id, x1, x2, y}] from PetGeometry (no floor)
    property real xMin: 0
    property real xMax: 1280
    property real yMin: 0
    property real floorY: 800
    property real spriteW: 66
    property real spriteH: 60
    property var perch: null             // {enabled, x1, x2, y} (e.g. top of the island), optional
    property real cursorX: -1
    property real cursorY: -1
    property bool cursorValid: false
    property real cursorIdleSec: 0
    property bool musicPlaying: false
    property bool paused: false          // e.g. fullscreen app in front: freeze
    property bool autoRun: true          // false = the owner calls step(dt) itself (tests)

    // behaviour switches (bound to settings)
    property bool roam: true
    property bool edges: true            // stand on window edges
    property bool followCursor: true
    property bool reactMusic: true
    property bool sleepWhenIdle: true
    property real sleepAfter: 90
    property real activity: 1.0          // 0.4 lazy .. 2 hyper
    property var rng: Math.random

    // ---- outputs --------------------------------------------------------------
    property real px: 200
    property real py: -100
    property int facing: 1
    readonly property bool facingRight: facing > 0
    property bool focusMode: false
    property int zoomieDir: 1
    property string mode: "fall"
    property int tick: 0
    property string groundId: ""
    readonly property string pose: {
        switch (mode) {
        case "sit": return "sit"
        case "walk": return "walk"
        case "run": return "run"
        case "sleep": return "sleep"
        case "fall": case "jump": return "air"
        case "drag": return "drag"
        case "happy": return "happy"
        case "wave": return "wave"
        case "groove": return "groove"
        case "alert": return "alert"
        case "spin": return "spin"
        case "feed": return "feed"
        case "stretch": return "stretch"
        case "celebrate": return "celebrate"
        case "fetch": return "fetch"
        case "peek": return "peek"
        case "focus": return "focus"
        case "curious": return "curious"
        case "sweat": return "sweat"
        case "zoomies": return "run"
        }
        return "sit"
    }
    readonly property bool moving: mode === "walk" || mode === "run" || mode === "fall" || mode === "jump" || mode === "drag" || mode === "zoomies"
    readonly property bool alertActive: mode === "alert"

    // vitals (restored/persisted by the owner)
    property real energy: 100
    property real mood: 70
    property real steps: 0
    property int pets: 0
    property real sleepSeconds: 0

    signal effect(string kind, real x, real y)

    // ---- internals ------------------------------------------------------------
    property real vx: 0
    property real vy: 0
    property var ground: null
    property real timer: 0
    property real accTick: 0
    property real lookTimer: 0
    property real fxTimer: 0
    property real stepAcc: 0
    property real sleepClock: 0
    property string sleepReason: "idle"
    property real chaseTarget: 0
    property bool alertSticky: false
    property real alertClock: 0
    property real dragVx: 0
    property real lastDragX: 0
    readonly property real gravity: 1500
    readonly property real jumpMax: 150

    function rand(a, b) { return a + rng() * (b - a) }

    function all() {
        var l = [];
        if (edges) for (var i = 0; i < surfaces.length; i++) l.push(surfaces[i]);
        l.push({ id: "floor", x1: xMin, x2: xMax, y: floorY });
        if (perch && perch.enabled) l.push({ id: "perch", x1: perch.x1, x2: perch.x2, y: perch.y });
        return l;
    }

    function clampX() {
        if (px < xMin + spriteW / 2) px = xMin + spriteW / 2;
        if (px > xMax - spriteW / 2) px = xMax - spriteW / 2;
    }

    function landing(oldY, newY, x) {
        var best = null, l = all();
        for (var i = 0; i < l.length; i++) {
            var s = l[i];
            if (x < s.x1 || x > s.x2) continue;
            if (s.y >= oldY - 0.5 && s.y <= newY + 0.5) { if (!best || s.y < best.y) best = s; }
        }
        if (!best && newY >= floorY) best = { id: "floor", x1: xMin, x2: xMax, y: floorY };
        return best;
    }

    function land(s) {
        ground = s; groundId = s.id; py = s.y; vx = 0; vy = 0;
        if (alertSticky || alertClock > 0) { mode = "alert"; fxTimer = 0; return; }
        mode = "sit"; timer = rand(0.8, 2.0) / activity;
    }

    function startFall(sx) {
        ground = null; groundId = ""; vx = sx || 0; vy = 0; mode = "fall";
    }

    function spawn(x, y) {
        px = x; py = (y === undefined) ? yMin - spriteH - 30 : y;
        clampX(); startFall(0);
    }

    function respawn() {
        effect("poof", px, py - spriteH / 2);
        spawn(rand(xMin + spriteW, xMax - spriteW));
    }

    // put the pet right on the perch (e.g. the island). Returns false when there is none.
    function goPerch() {
        if (!perch || !perch.enabled) return false;
        effect("poof", px, py - spriteH / 2);
        px = (perch.x1 + perch.x2) / 2; py = perch.y - 2; clampX();
        startFall(0);
        return true;
    }

    // ---- user interactions ----------------------------------------------------
    function pet() {
        if (mode === "drag" || mode === "fall" || mode === "jump") return;
        if (mode === "alert") return;
        pets++; mood = Math.min(100, mood + 12);
        mode = "happy"; timer = 1.8; fxTimer = 0;
        effect("heart", px, py - spriteH);
    }

    function wave() { if (ground && mode !== "alert") { mode = "wave"; timer = 2.4; } }
    function doSleep() { if (ground && mode !== "alert") { mode = "sleep"; sleepReason = "tired"; sleepClock = 0; fxTimer = 0; } }
    function dance() { if (ground && mode !== "alert") { mode = "groove"; timer = 8; fxTimer = 0; } }
    function hop() { if (ground && mode !== "alert") { vy = -430; vx = facing * 40; ground = null; groundId = ""; mode = "jump"; } }

    function spin() {
        if (!ground || mode === "alert") return;
        mode = "spin";
        timer = 2.0;
        effect("sparkle", px, py - spriteH);
    }

    function feed() {
        if (!ground || mode === "alert") return;
        mode = "feed";
        timer = 2.6;
        energy = Math.min(100, energy + 25);
        mood = Math.min(100, mood + 15);
        effect("crumb", px + facing * spriteW * 0.45, py - spriteH * 0.35);
        effect("heart", px, py - spriteH);
    }

    function stretch() {
        if (!ground || mode === "alert") return;
        mode = "stretch";
        timer = 2.2;
        mood = Math.min(100, mood + 4);
    }

    function celebrate() {
        if (mode === "alert") return;
        mode = "celebrate";
        timer = 2.4;
        mood = Math.min(100, mood + 10);
        effect("confetti", px, py - spriteH);
        effect("sparkle", px, py - spriteH * 0.8);
    }

    function fetch() {
        if (!ground || mode === "alert") return;
        focusMode = false;
        mode = "fetch";
        timer = 2.8;
        mood = Math.min(100, mood + 10);
        energy = Math.max(0, energy - 5);
        effect("ball", px + (facing > 0 ? spriteW * 0.45 : -spriteW * 0.45), py - spriteH * 0.5);
        effect("sparkle", px, py - spriteH);
    }

    function peek() {
        if (!ground || mode === "alert") return;
        mode = "peek";
        timer = 3.5;
    }

    function focus(enable) {
        var next = (typeof enable === "boolean") ? enable : !focusMode;
        focusMode = next;
        if (focusMode) {
            if (mode !== "alert") {
                mode = "focus";
                vx = 0;
                timer = 0;
                effect("focus", px, py - spriteH);
            }
        } else if (mode === "focus") {
            mode = "sit";
            timer = rand(1.5, 3.0);
        }
    }

    function curious() {
        if (!ground || mode === "alert") return;
        mode = "curious";
        timer = 2.0;
        effect("question", px, py - spriteH);
    }

    function sweat() {
        if (mode === "alert") return;
        mode = "sweat";
        timer = 2.5;
        effect("sweat", px + (facing > 0 ? 10 : -10), py - spriteH * 0.9);
    }

    function startZoomies() {
        if (!ground || mode === "alert" || focusMode) return;
        mode = "zoomies";
        timer = 4.0;
        zoomieDir = facing > 0 ? 1 : -1;
        effect("sparkle", px, py - spriteH);
    }

    function beginDrag() {
        focusMode = false;
        mode = "drag"; ground = null; groundId = ""; vx = 0; vy = 0; dragVx = 0; lastDragX = px;
    }
    function dragTo(x, y) {
        dragVx = (x - lastDragX) * 20; lastDragX = x;
        px = x; py = y; clampX();
    }
    function endDrag() {
        vx = Math.max(-380, Math.min(380, dragVx)); vy = 0; mode = "fall";
    }

    // alert: startle, then stay put and fidget until dismissed (or timeout when not sticky)
    function raiseAlert(sticky) {
        alertSticky = !!sticky;
        alertClock = sticky ? 0 : 6;
        if (mode === "drag") return;
        if (ground) { vy = -380; vx = 0; ground = null; groundId = ""; mode = "jump"; }
        else mode = "fall";
        effect("bang", px, py - spriteH);
    }
    function dismissAlert() {
        alertSticky = false; alertClock = 0;
        if (mode === "alert") { mode = "wave"; timer = 1.6; }
    }

    // ---- decisions ------------------------------------------------------------
    function jumpTarget() {
        if (!ground) return null;
        var l = all(), c = [];
        for (var i = 0; i < l.length; i++) {
            var s = l[i];
            if (s.id === ground.id) continue;
            var dy = s.y - py;
            if (dy < -jumpMax || dy > 380) continue;
            var dx = px < s.x1 ? s.x1 - px : (px > s.x2 ? px - s.x2 : 0);
            if (dx > 150) continue;
            c.push(s);
        }
        if (!c.length) return null;
        return c[Math.floor(rng() * c.length) % c.length];
    }

    function jumpTo(s) {
        var lo = s.x1 + 12, hi = s.x2 - 12;
        var tx = hi < lo ? (s.x1 + s.x2) / 2 : Math.max(lo, Math.min(hi, px));
        var T = 0.55;
        var dy = s.y - py;
        vy = (dy - 0.5 * gravity * T * T) / T;
        vx = (tx - px) / T;
        if (vx !== 0) facing = vx > 0 ? 1 : -1;
        ground = null; groundId = ""; mode = "jump";
    }

    function wake() {
        mode = "sit"; timer = rand(0.6, 1.4);
    }

    function decide() {
        if (focusMode) {
            mode = "focus";
            vx = 0;
            return;
        }

        // High-energy autonomous zoomies on sufficiently wide horizontal ledges
        if (ground && energy > 85 && mood > 80 && Math.random() < 0.08) {
            var minX = ground.x1 !== undefined ? ground.x1 : xMin;
            var maxX = ground.x2 !== undefined ? ground.x2 : xMax;
            if ((maxX - minX) >= spriteW * 2.5) {
                startZoomies();
                return;
            }
        }

        // Occasional autonomous head-tilt inspection
        if (ground && Math.random() < 0.10) {
            curious();
            return;
        }

        var act = activity * (mood < 30 ? 0.7 : 1);
        var tired = sleepWhenIdle && energy < 20;
        var idle = sleepWhenIdle && cursorValid && cursorIdleSec > sleepAfter;
        if (reactMusic && musicPlaying) {
            if (rng() < 0.7) { mode = "groove"; timer = rand(6, 12); fxTimer = 0; return; }
        } else if (tired || idle) {
            mode = "sleep"; sleepReason = tired ? "tired" : "idle"; sleepClock = 0; fxTimer = 0; return;
        }
        var opts = [];
        function add(n, w) { if (w > 0) opts.push([n, w]); }
        add("stay", 3);
        add("look", 2);
        add("wave", 0.5);
        if (roam) {
            add("walk", 6 * act);
            if (jumpTarget()) add("jump", 2 * act);
        }
        if (roam && followCursor && cursorValid && Math.abs(cursorX - px) > 90 && Math.abs(cursorX - px) < 800
                && Math.abs(cursorY - (py - spriteH / 2)) < 260 && energy > 25)
            add("chase", 3.5 * act);
        var total = 0, i;
        for (i = 0; i < opts.length; i++) total += opts[i][1];
        var r = rng() * total, pick = "stay";
        for (i = 0; i < opts.length; i++) { r -= opts[i][1]; if (r <= 0) { pick = opts[i][0]; break; } }
        switch (pick) {
        case "walk": facing = rng() < 0.5 ? -1 : 1; mode = "walk"; timer = rand(1.5, 5) ; break;
        case "look": facing = -facing; mode = "sit"; timer = rand(1.2, 3) / act; break;
        case "wave": mode = "wave"; timer = 2.2; break;
        case "jump": { var t = jumpTarget(); if (t) jumpTo(t); else { mode = "sit"; timer = 1; } break; }
        case "chase": facing = cursorX >= px ? 1 : -1; chaseTarget = cursorX; mode = "run"; timer = 6; break;
        default: mode = "sit"; timer = rand(1.5, 4.5) / act; break;
        }
    }

    function edgeDecision() {
        var r = rng();
        var jt = jumpTarget();
        var canDrop = ground && ground.id !== "floor";
        if (r < 0.45 || (!jt && !canDrop)) { facing = -facing; return; }
        if (r < 0.8 && jt) { jumpTo(jt); return; }
        if (canDrop) { startFall(facing * 60); return; }
        facing = -facing;
    }

    // ---- main loop ------------------------------------------------------------
    function refreshGround() {
        if (!ground) return;
        var l = all(), found = null;
        for (var i = 0; i < l.length; i++) if (l[i].id === ground.id) { found = l[i]; break; }
        if (!found) { startFall(0); return; }
        ground = found; py = found.y;
        if (px < found.x1 - 6 || px > found.x2 + 6) { startFall(0); return; }
    }

    function step(dt) {
        accTick += dt;
        while (accTick >= 0.125) { accTick -= 0.125; tick++; }
        if (paused) return;

        // slow vitals
        mood = Math.max(15, mood - dt * 0.02);

        if (alertClock > 0 && mode !== "drag") {
            alertClock -= dt;
            if (alertClock <= 0 && !alertSticky) dismissAlert();
        }

        switch (mode) {
        case "drag":
            return;
        case "fall":
        case "jump": {
            vy += gravity * dt;
            var ny = py + vy * dt;
            px += vx * dt; clampX();
            if (vy > 0) {
                var s = landing(py, ny, px);
                if (s) { land(s); return; }
            }
            py = ny;
            if (py > floorY + 400) { py = floorY; land({ id: "floor", x1: xMin, x2: xMax, y: floorY }); }
            return;
        }
        }

        // grounded states
        refreshGround();
        if (mode === "fall") return;

        // wake-ups
        if (mode === "sleep") {
            sleepClock += dt; sleepSeconds += dt;
            energy = Math.min(100, energy + dt * 1.2);
            fxTimer -= dt;
            if (fxTimer <= 0) { fxTimer = 2.2; effect("zzz", px + facing * spriteW * 0.2, py - spriteH * 0.5); }
            var userBack = sleepReason === "idle" && cursorValid && cursorIdleSec < 1.5 && sleepClock > 3;
            var musicStart = reactMusic && musicPlaying && sleepClock > 1;
            var rested = sleepReason === "tired" && energy >= 100;
            if (rested) stretch(); else if (userBack || musicStart || !sleepWhenIdle) wake();
            return;
        }

        if (mode === "alert") {
            fxTimer -= dt;
            if (fxTimer <= 0) { fxTimer = 1.3; effect("bang", px, py - spriteH); }
            return;
        }

        if (mode === "walk" || mode === "run") {
            var sp = mode === "run" ? 105 * (0.7 + 0.3 * activity) : 38 * activity;
            var nx = px + facing * sp * dt;
            energy = Math.max(0, energy - dt * (mode === "run" ? 0.3 : 0.1));
            if (mode === "run") {
                if ((facing > 0 && nx >= chaseTarget) || (facing < 0 && nx <= chaseTarget)) {
                    px = chaseTarget; clampX();
                    effect("sparkle", px, py - spriteH);
                    vy = -380; vx = facing * 30; ground = null; groundId = ""; mode = "jump"; mood = Math.min(100, mood + 3);
                    return;
                }
            }
            if (ground && (nx - spriteW * 0.25 < ground.x1 || nx + spriteW * 0.25 > ground.x2)) {
                edgeDecision();
                if (mode !== "walk" && mode !== "run") return;
            } else {
                px = nx; clampX();
                stepAcc += sp * dt;
                if (stepAcc >= spriteW * 0.5) { steps += Math.floor(stepAcc / (spriteW * 0.5)); stepAcc = stepAcc % (spriteW * 0.5); }
            }
            timer -= dt;
            if (timer <= 0) { mode = "sit"; timer = rand(1, 3) / activity; }
            return;
        }

        if (mode === "groove") {
            fxTimer -= dt;
            if (fxTimer <= 0) { fxTimer = 0.9; effect("note", px + facing * spriteW * 0.1, py - spriteH * 0.9); }
            timer -= dt;
            if (timer <= 0 || (reactMusic && !musicPlaying && timer < 6 && false)) { mode = "sit"; timer = rand(1, 2.5); }
            if (!musicPlaying && reactMusic && timer > 3) timer = 1;
            return;
        }

        if (mode === "happy") {
            fxTimer -= dt;
            if (fxTimer <= 0) { fxTimer = 0.5; effect("heart", px + rand(-8, 8), py - spriteH); }
            timer -= dt;
            if (timer <= 0) { mode = "sit"; timer = rand(1.5, 3); }
            return;
        }

        if (mode === "focus") {
            vx = 0;
            return;
        }

        if (mode === "zoomies") {
            timer -= dt;
            energy = Math.max(0, energy - 0.4 * dt);
            var speed = 135 * (0.7 + 0.3 * activity);
            vx = zoomieDir * speed;
            facing = zoomieDir > 0 ? 1 : -1;
            px += vx * dt;

            // Bounce cleanly at horizontal ledge or monitor bounds
            var leftBound  = (ground && ground.x1 !== undefined) ? ground.x1 + spriteW * 0.5 : xMin + spriteW * 0.5;
            var rightBound = (ground && ground.x2 !== undefined) ? ground.x2 - spriteW * 0.5 : xMax - spriteW * 0.5;
            if (px <= leftBound) {
                px = leftBound;
                zoomieDir = 1;
                effect("sparkle", px, py - spriteH * 0.6);
            } else if (px >= rightBound) {
                px = rightBound;
                zoomieDir = -1;
                effect("sparkle", px, py - spriteH * 0.6);
            }

            if (timer <= 0) {
                vx = 0;
                spin();
            }
            return;
        }

        if (mode === "fetch" || mode === "peek" || mode === "curious" || mode === "sweat") {
            timer -= dt;
            if (mode === "fetch" && Math.random() < dt * 1.8) {
                effect("ball", px + rand(-14, 14), py - spriteH * 0.6);
            } else if (mode === "sweat" && Math.random() < dt * 1.4) {
                effect("sweat", px + rand(-10, 10), py - spriteH * 0.9);
            }
            if (timer <= 0) {
                mode = focusMode ? "focus" : "sit";
                timer = rand(1.5, 3.0);
            }
            return;
        }

        if (mode === "spin" || mode === "feed" || mode === "stretch" || mode === "celebrate") {
            timer -= dt;
            if (mode === "celebrate" && Math.random() < dt * 2.0) {
                effect("confetti", px + rand(-14, 14), py - spriteH);
            } else if (mode === "feed" && Math.random() < dt * 1.5) {
                effect("crumb", px + rand(-10, 10), py - spriteH * 0.4);
            }
            if (timer <= 0) {
                mode = "sit";
                timer = rand(1.5, 3.0);
            }
            return;
        }

        // sit / wave
        energy = Math.max(0, energy - dt * 0.01);
        if (mode === "sit" && followCursor && cursorValid) {
            lookTimer -= dt;
            if (lookTimer <= 0) {
                lookTimer = 0.7;
                if (Math.abs(cursorX - px) > 50 && Math.abs(cursorX - px) < 900) facing = cursorX > px ? 1 : -1;
            }
        }
        timer -= dt;
        if (timer <= 0) { if (mode === "wave") { mode = "sit"; timer = rand(1, 2); } else decide(); }
    }

    property real _last: 0
    Timer {
        id: loop
        interval: brain.moving ? 33 : (brain.mode === "sleep" ? 250 : 125)
        repeat: true
        running: brain.autoRun && !brain.paused
        onTriggered: {
            var now = Date.now();
            var dt = brain._last ? Math.min(0.25, (now - brain._last) / 1000) : interval / 1000;
            brain._last = now;
            brain.step(dt);
        }
        onRunningChanged: if (!running) brain._last = 0
    }
}
