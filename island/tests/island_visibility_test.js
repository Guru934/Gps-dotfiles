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
    assert.strictEqual(IV.PRIORITY.ALERT, 1);
    assert.strictEqual(IV.PRIORITY.RESTING, 5);
});

console.log("ALL PASS (" + passed + " island visibility checks)");
