const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

function load(file) {
    const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
    const context = { module: { exports: {} }, exports: {} };
    vm.createContext(context);
    vm.runInContext(source, context, { filename: file });
    return context.module.exports.evaluateVisibility ? context.module.exports : context;
}

const IV = load(path.join(__dirname, "..", "IslandVisibility.js"));
const PRIORITY = IV.PRIORITY;

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

// 1. Alert beats everything
check("alert priority beats fullscreen, user interaction, and transients", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        activeAlert: true,
        fullscreen: true,
        pinned: true,
        hovered: true,
        transientQueue: [{ kind: "osd", priority: PRIORITY.TRANSIENT, expiry: 2000 }],
        windowFocused: true
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "alert");
    assert.strictEqual(res.nextExpiry, null);
    assert.strictEqual(res.wantsKeyboard, true);
    assert.strictEqual(res.reason, "active_alert");
});

// 2. Fullscreen suppression
check("fullscreen hides non-critical events and states", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        activeAlert: false,
        fullscreen: true,
        pinned: true,
        hovered: true,
        transientQueue: [{ kind: "osd", priority: PRIORITY.TRANSIENT, expiry: 2000 }],
        windowFocused: true,
        workspaceEmpty: false
    });
    assert.strictEqual(res.visible, false);
    assert.strictEqual(res.state, "hidden");
    assert.strictEqual(res.nextExpiry, null);
    assert.strictEqual(res.wantsKeyboard, false);
    assert.strictEqual(res.reason, "fullscreen_suppressed");
});

// 3. Hover protects against timer expiry
check("hover expands to control and protects against timer expiry", () => {
    const t0 = 1000;
    const res = IV.evaluateVisibility({
        now: t0,
        hovered: true,
        transientQueue: [{ kind: "osd", priority: PRIORITY.TRANSIENT, expiry: t0 + 500 }],
        windowFocused: true
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "control");
    assert.strictEqual(res.nextExpiry, null);
    assert.strictEqual(res.reason, "hover_active");

    // Even after transient expiry has passed, hover keeps island visible with no expiry
    const resLater = IV.evaluateVisibility({
        now: t0 + 2000,
        hovered: true,
        transientQueue: [{ kind: "osd", priority: PRIORITY.TRANSIENT, expiry: t0 + 500 }],
        windowFocused: true
    });
    assert.strictEqual(resLater.visible, true);
    assert.strictEqual(resLater.state, "control");
    assert.strictEqual(resLater.nextExpiry, null);
});

// 4. Hover-leave delay and grace period
check("hover-leave arms 300ms grace delay before collapsing", () => {
    const t0 = 1000;
    const leaveGrace = t0 + 300;
    const res = IV.evaluateVisibility({
        now: t0,
        hovered: false,
        hoverLeaveExpiry: leaveGrace,
        windowFocused: true
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "control");
    assert.strictEqual(res.nextExpiry, leaveGrace);
    assert.strictEqual(res.reason, "hover_leave_grace");

    // Once grace period expires, collapses to resting state
    const resExpired = IV.evaluateVisibility({
        now: leaveGrace + 1,
        hovered: false,
        hoverLeaveExpiry: leaveGrace,
        windowFocused: true,
        workspaceEmpty: false
    });
    assert.strictEqual(resExpired.visible, false);
    assert.strictEqual(resExpired.state, "hidden");
});

// 5. Cancel on re-enter
check("re-entering during hover grace cancels collapse timer", () => {
    const t0 = 1000;
    const leaveGrace = t0 + 300;
    // Re-entered at t0 + 100
    const res = IV.evaluateVisibility({
        now: t0 + 100,
        hovered: true,
        hoverLeaveExpiry: 0,
        windowFocused: true
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "control");
    assert.strictEqual(res.nextExpiry, null);
    assert.strictEqual(res.reason, "hover_active");
});

// 6. Click to pin
check("pinned keeps control open indefinitely and requests keyboard", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        pinned: true,
        hovered: false,
        windowFocused: true
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "control");
    assert.strictEqual(res.nextExpiry, null);
    assert.strictEqual(res.wantsKeyboard, true);
    assert.strictEqual(res.reason, "pinned_open");
});

// 7. Window focus hides idle pill
check("window focus hides idle pill when windows present", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        windowFocused: true,
        workspaceEmpty: false,
        fullscreen: false,
        hovered: false,
        pinned: false,
        activeAlert: false,
        transientQueue: []
    });
    assert.strictEqual(res.visible, false);
    assert.strictEqual(res.state, "hidden");
    assert.strictEqual(res.reason, "window_focused_resting");
});

// 8. Empty workspace shows idle pill
check("empty workspace shows idle pill", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        windowFocused: false,
        workspaceEmpty: true,
        fullscreen: false,
        hovered: false,
        pinned: false,
        activeAlert: false,
        transientQueue: []
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "idle");
    assert.strictEqual(res.reason, "workspace_empty");
});

// 9. No window focused shows idle pill
check("no window focused shows idle pill", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        windowFocused: false,
        workspaceEmpty: false,
        fullscreen: false,
        hovered: false,
        pinned: false,
        activeAlert: false,
        transientQueue: []
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "idle");
    assert.strictEqual(res.reason, "no_window_focused");
});

// 10. Workspace change transient
check("workspace change shows transient for 1.5s", () => {
    const t0 = 1000;
    const queue = [{ kind: "idle", priority: PRIORITY.TRANSIENT, expiry: t0 + 1500 }];
    const res = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        workspaceEmpty: false,
        transientQueue: queue
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "idle");
    assert.strictEqual(res.nextExpiry, t0 + 1500);
    assert.strictEqual(res.reason, "transient_idle");

    // After 1.5s expires, window focus hides it
    const resAfter = IV.evaluateVisibility({
        now: t0 + 1501,
        windowFocused: true,
        workspaceEmpty: false,
        transientQueue: queue
    });
    assert.strictEqual(resAfter.visible, false);
    assert.strictEqual(resAfter.state, "hidden");
});

// 11. OSD timer restarts on repeated changes
check("OSD timer restarts on repeated changes", () => {
    let queue = [];
    const t0 = 1000;
    queue = IV.postEvent(queue, { kind: "osd", duration: 1500 }, t0);
    assert.strictEqual(queue.length, 1);
    assert.strictEqual(queue[0].expiry, t0 + 1500);

    // Repeated change 800ms later restarts timer
    const t1 = t0 + 800;
    queue = IV.postEvent(queue, { kind: "osd", duration: 1500 }, t1);
    assert.strictEqual(queue.length, 1);
    assert.strictEqual(queue[0].expiry, t1 + 1500);

    // Check visibility at t0 + 1600 (would have expired without restart)
    const res = IV.evaluateVisibility({
        now: t0 + 1600,
        windowFocused: true,
        transientQueue: queue
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "osd");
    assert.strictEqual(res.nextExpiry, t1 + 1500);
});

// 12. Event queue replacement rules: same-priority replaces previous
check("same-priority event replaces previous active event", () => {
    let queue = [];
    const t0 = 1000;
    queue = IV.postEvent(queue, { kind: "osd", priority: PRIORITY.TRANSIENT, duration: 1500 }, t0);
    assert.strictEqual(queue[0].kind, "osd");

    // New same-priority event (e.g. clip) arrives
    queue = IV.postEvent(queue, { kind: "clip", priority: PRIORITY.TRANSIENT, duration: 2500 }, t0 + 100);
    assert.strictEqual(queue.length, 1);
    assert.strictEqual(queue[0].kind, "clip");

    const res = IV.evaluateVisibility({
        now: t0 + 100,
        windowFocused: true,
        transientQueue: queue
    });
    assert.strictEqual(res.state, "clip");
});

// 13. Event queue replacement rules: lower-priority never overrides higher-priority
check("lower-priority event never overrides higher-priority active event", () => {
    let queue = [];
    const t0 = 1000;
    // Higher priority event in transient tier (e.g. priority 2 vs priority 3)
    queue = IV.postEvent(queue, { kind: "critical_feedback", priority: 2, duration: 4000 }, t0);
    // Lower priority event arrives
    queue = IV.postEvent(queue, { kind: "osd", priority: 3, duration: 1500 }, t0 + 200);

    const res = IV.evaluateVisibility({
        now: t0 + 200,
        windowFocused: true,
        transientQueue: queue
    });
    assert.strictEqual(res.state, "critical_feedback");
    assert.strictEqual(res.nextExpiry, t0 + 4000);
});

// 14. Persistent music pill setting
check("persistent music pill displays when enabled and music is playing", () => {
    const resActive = IV.evaluateVisibility({
        now: 1000,
        windowFocused: true,
        workspaceEmpty: false,
        settings: { persistentMusicPill: true },
        isMusicPlaying: true
    });
    assert.strictEqual(resActive.visible, true);
    assert.strictEqual(resActive.state, "music");
    assert.strictEqual(resActive.reason, "persistent_music");

    const resDisabled = IV.evaluateVisibility({
        now: 1000,
        windowFocused: true,
        workspaceEmpty: false,
        settings: { persistentMusicPill: false },
        isMusicPlaying: true
    });
    assert.strictEqual(resDisabled.visible, false);
    assert.strictEqual(resDisabled.state, "hidden");

    const resStopped = IV.evaluateVisibility({
        now: 1000,
        windowFocused: true,
        workspaceEmpty: false,
        settings: { persistentMusicPill: true },
        isMusicPlaying: false
    });
    assert.strictEqual(resStopped.visible, false);
    assert.strictEqual(resStopped.state, "hidden");
});

// 15. Dual export test: Node require / module.exports
check("dual export module.exports pattern is valid", () => {
    assert.ok(IV.evaluateVisibility);
    assert.ok(IV.postEvent);
    assert.ok(IV.DEFAULT_SETTINGS);
    assert.ok(IV.resolveIslandSettings);
    assert.strictEqual(IV.PRIORITY.ALERT, 1);
    assert.strictEqual(IV.PRIORITY.RESTING, 5);
});

// 16. Settings resolution: defaults and safe fallback
check("settings resolution falls back safely on null, empty, or malformed JSON", () => {
    const sNull = IV.resolveIslandSettings(null);
    assert.strictEqual(sNull.persistentMusicPill, false);
    assert.strictEqual(sNull.hoverDelay, 300);
    assert.strictEqual(sNull.hoverZoneWidth, 300);
    assert.strictEqual(sNull.hoverZoneHeight, 5);
    assert.strictEqual(sNull.durations.workspace, 1500);
    assert.strictEqual(sNull.durations.clipboard, 2500);
    assert.strictEqual(sNull.durations.notification, 4000);
    assert.strictEqual(sNull.durations.osd, 1500);
    assert.strictEqual(sNull.durations.musicChange, 3000);
    assert.strictEqual(sNull.durations.charge, 3000);

    const sMalformed = IV.resolveIslandSettings("not a json string {{{");
    assert.strictEqual(sMalformed.persistentMusicPill, false);
    assert.strictEqual(sMalformed.hoverDelay, 300);

    // Existing rice-settings.json without "island" key
    const sExternal = IV.resolveIslandSettings(JSON.stringify({ hypr: {}, monitors: {}, ai: {} }));
    assert.strictEqual(sExternal.persistentMusicPill, false);
    assert.strictEqual(sExternal.hoverDelay, 300);
});

// 17. Settings resolution: loading under "island" key
check("settings resolution correctly parses and merges 'island' configuration", () => {
    const jsonStr = JSON.stringify({
        hypr: {},
        island: {
            persistentMusicPill: true,
            hoverDelay: 450,
            hoverZoneWidth: 350,
            hoverZoneHeight: 8,
            durations: {
                notification: 6000,
                osd: 2000
            }
        }
    });
    const s = IV.resolveIslandSettings(jsonStr);
    assert.strictEqual(s.persistentMusicPill, true);
    assert.strictEqual(s.hoverDelay, 450);
    assert.strictEqual(s.hoverZoneWidth, 350);
    assert.strictEqual(s.hoverZoneHeight, 8);
    assert.strictEqual(s.durations.notification, 6000);
    assert.strictEqual(s.durations.osd, 2000);
    // Unspecified durations retain defaults
    assert.strictEqual(s.durations.workspace, 1500);
    assert.strictEqual(s.durations.clipboard, 2500);
    assert.strictEqual(s.durations.musicChange, 3000);
    assert.strictEqual(s.durations.charge, 3000);
});

// 18. Settings resolution: type safety and boundary validation
check("settings resolution rejects invalid types and negative dimensions", () => {
    const s = IV.resolveIslandSettings({
        island: {
            persistentMusicPill: "yes", // invalid type
            hoverDelay: -100,           // negative
            hoverZoneWidth: "wide",     // invalid type
            hoverZoneHeight: 0,         // zero height
            durations: {
                osd: "slow",
                notification: -500
            }
        }
    });
    assert.strictEqual(s.persistentMusicPill, false);
    assert.strictEqual(s.hoverDelay, 300);
    assert.strictEqual(s.hoverZoneWidth, 300);
    assert.strictEqual(s.hoverZoneHeight, 5);
    assert.strictEqual(s.durations.osd, 1500);
    assert.strictEqual(s.durations.notification, 4000);
});

// 19. Pet-alert Priority 1 inviolability: never expires by timer
check("pet-alert never expires by timer and retains keyboard focus", () => {
    const res = IV.evaluateVisibility({
        now: 1000,
        activeAlert: true,
        windowFocused: false,
        fullscreen: false,
        transientQueue: [
            { kind: "osd", priority: PRIORITY.TRANSIENT, expiry: 2500 },
            { kind: "notify", priority: PRIORITY.TRANSIENT, expiry: 5000 }
        ]
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "alert");
    assert.strictEqual(res.nextExpiry, null); // Inviolable: NO expiry timer
    assert.strictEqual(res.wantsKeyboard, true); // Retains keyboard focus
});

// 20. Pet-alert Priority 1 inviolability: cannot be replaced by routine events
check("pet-alert cannot be replaced by routine events, hover, or fullscreen", () => {
    const t0 = 1000;
    // Post routine events
    let q = IV.postEvent([], { kind: "osd", priority: PRIORITY.TRANSIENT, duration: 1500 }, t0);
    q = IV.postEvent(q, { kind: "notify", priority: PRIORITY.TRANSIENT, duration: 4000 }, t0 + 100);

    const res = IV.evaluateVisibility({
        now: t0 + 200,
        activeAlert: true,
        fullscreen: true,
        hovered: true,
        pinned: true,
        transientQueue: q,
        isMusicPlaying: true,
        settings: { persistentMusicPill: true }
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "alert");
    assert.strictEqual(res.wantsKeyboard, true);
    assert.strictEqual(res.nextExpiry, null);
});

// 21. Event wiring: Notification duration and priority
check("notification transient uses default 4000ms duration", () => {
    const t0 = 1000;
    const q = IV.postEvent([], { kind: "notify", priority: PRIORITY.TRANSIENT, duration: 4000 }, t0);
    assert.strictEqual(q.length, 1);
    assert.strictEqual(q[0].kind, "notify");
    assert.strictEqual(q[0].expiry, t0 + 4000);

    const res = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        transientQueue: q
    });
    assert.strictEqual(res.visible, true);
    assert.strictEqual(res.state, "notify");
    assert.strictEqual(res.nextExpiry, t0 + 4000);
});

// 22. Event wiring: Clipboard (2500ms) and Charging (3000ms)
check("clipboard and charging transients use configured durations", () => {
    const t0 = 1000;
    let q = IV.postEvent([], { kind: "clip", priority: PRIORITY.TRANSIENT, duration: 2500 }, t0);
    assert.strictEqual(q[0].expiry, t0 + 2500);

    // Charge replaces clip at same priority
    q = IV.postEvent(q, { kind: "charge", priority: PRIORITY.TRANSIENT, duration: 3000 }, t0 + 500);
    assert.strictEqual(q.length, 1);
    assert.strictEqual(q[0].kind, "charge");
    assert.strictEqual(q[0].expiry, t0 + 500 + 3000);

    const res = IV.evaluateVisibility({
        now: t0 + 500,
        windowFocused: true,
        transientQueue: q
    });
    assert.strictEqual(res.state, "charge");
    assert.strictEqual(res.nextExpiry, t0 + 3500);
});

// 23. Event wiring: Music track change transient (3000ms)
check("music track change transient shows for 3000ms when persistentMusicPill is false", () => {
    const t0 = 1000;
    const q = IV.postEvent([], { kind: "music", priority: PRIORITY.TRANSIENT, duration: 3000 }, t0);

    // During the 3000ms, pill is visible
    const resActive = IV.evaluateVisibility({
        now: t0 + 1000,
        windowFocused: true,
        isMusicPlaying: true,
        settings: { persistentMusicPill: false },
        transientQueue: q
    });
    assert.strictEqual(resActive.visible, true);
    assert.strictEqual(resActive.state, "music");
    assert.strictEqual(resActive.nextExpiry, t0 + 3000);

    // After 3000ms expires, persistentMusicPill is false so island returns to hidden
    const resExpired = IV.evaluateVisibility({
        now: t0 + 3001,
        windowFocused: true,
        isMusicPlaying: true,
        settings: { persistentMusicPill: false },
        transientQueue: q
    });
    assert.strictEqual(resExpired.visible, false);
    assert.strictEqual(resExpired.state, "hidden");
});

// 24. Transient interrupt over persistent music pill
check("transient OSD interrupts persistent music pill and reverts after expiry", () => {
    const t0 = 1000;
    // Music is playing persistently
    const resMusic = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        isMusicPlaying: true,
        settings: { persistentMusicPill: true },
        transientQueue: []
    });
    assert.strictEqual(resMusic.state, "music");
    assert.strictEqual(resMusic.nextExpiry, null);

    // User adjusts volume (OSD Priority 3 transient for 1500ms)
    const q = IV.postEvent([], { kind: "osd", priority: PRIORITY.TRANSIENT, duration: 1500 }, t0);
    const resOsd = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        isMusicPlaying: true,
        settings: { persistentMusicPill: true },
        transientQueue: q
    });
    assert.strictEqual(resOsd.state, "osd");
    assert.strictEqual(resOsd.nextExpiry, t0 + 1500);

    // When OSD expires, cleanly reverts to persistent music pill
    const resReverted = IV.evaluateVisibility({
        now: t0 + 1501,
        windowFocused: true,
        isMusicPlaying: true,
        settings: { persistentMusicPill: true },
        transientQueue: q
    });
    assert.strictEqual(resReverted.visible, true);
    assert.strictEqual(resReverted.state, "music");
    assert.strictEqual(resReverted.reason, "persistent_music");
});

// 25. Privacy state integration with controller
check("privacy indicator displays persistently and yields to transient system feedback", () => {
    const t0 = 1000;
    const resPrivacy = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        privacyVisible: true,
        transientQueue: []
    });
    assert.strictEqual(resPrivacy.visible, true);
    assert.strictEqual(resPrivacy.state, "privacy");
    assert.strictEqual(resPrivacy.nextExpiry, null);

    // Transient notification arrives while mic/cam is in use
    const q = IV.postEvent([], { kind: "notify", priority: PRIORITY.TRANSIENT, duration: 4000 }, t0);
    const resTransient = IV.evaluateVisibility({
        now: t0,
        windowFocused: true,
        privacyVisible: true,
        transientQueue: q
    });
    assert.strictEqual(resTransient.state, "notify");
    assert.strictEqual(resTransient.nextExpiry, t0 + 4000);

    // When notification expires, returns to privacy indicator
    const resRevert = IV.evaluateVisibility({
        now: t0 + 4001,
        windowFocused: true,
        privacyVisible: true,
        transientQueue: q
    });
    assert.strictEqual(resRevert.visible, true);
    assert.strictEqual(resRevert.state, "privacy");
});

// 26. DND and Focus resting states vs window focus
check("DND and Focus states show in resting mode when workspace has no focused window", () => {
    // Empty workspace with DND enabled
    const resDnd = IV.evaluateVisibility({
        now: 1000,
        windowFocused: false,
        workspaceEmpty: true,
        dnd: true
    });
    assert.strictEqual(resDnd.visible, true);
    assert.strictEqual(resDnd.state, "dnd");
    assert.strictEqual(resDnd.reason, "dnd_active");

    // Empty workspace with active focus session
    const resFocus = IV.evaluateVisibility({
        now: 1000,
        windowFocused: false,
        workspaceEmpty: true,
        focusOn: true
    });
    assert.strictEqual(resFocus.visible, true);
    assert.strictEqual(resFocus.state, "focus");
    assert.strictEqual(resFocus.reason, "focus_active");

    // Once a window is focused and resting, DND/Focus pill hides
    const resHidden = IV.evaluateVisibility({
        now: 1000,
        windowFocused: true,
        workspaceEmpty: false,
        dnd: true
    });
    assert.strictEqual(resHidden.visible, false);
    assert.strictEqual(resHidden.state, "hidden");
});

console.log("ALL PASS (" + passed + " island visibility checks)");

