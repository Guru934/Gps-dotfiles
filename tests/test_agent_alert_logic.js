// Unit tests for AgentAlertLogic.js (classification, dedupe key, reminder scheduling and cancellation)
const assert = require("assert");
const AgentAlert = require("../island/AgentAlertLogic.js");

console.log("=== Running AgentAlertLogic.js tests ===");

// 1. Classification by known agent app names
const notifAntigravity = {
    appName: "Antigravity",
    summary: "Requesting your permission: run command",
    body: "npm test"
};
const cls1 = AgentAlert.classifyAgentNotification(notifAntigravity);
assert(cls1 !== null, "Antigravity notification must be classified as an agent notification");
assert.strictEqual(cls1.event, "agent-permission");
assert.strictEqual(cls1.isPermission, true);
console.log("ok - Antigravity notification classified as agent-permission");

const notifCodex = {
    appName: "Codex",
    summary: "Turn completed successfully",
    body: "All tests passed"
};
const cls2 = AgentAlert.classifyAgentNotification(notifCodex);
assert.strictEqual(cls2.event, "agent-done");
console.log("ok - Codex completion notification classified as agent-done");

const notifOpencodeErr = {
    appName: "opencode",
    summary: "Tool execution failed with error",
    body: "exit status 1"
};
const cls3 = AgentAlert.classifyAgentNotification(notifOpencodeErr);
assert.strictEqual(cls3.event, "agent-error");
console.log("ok - opencode error notification classified as agent-error");

// 2. Classification by permission regex on summary even with unknown app name
const notifGenericApp = {
    appName: "terminal-agent",
    summary: "Needs approval to execute script",
    body: "rm -rf build"
};
const cls4 = AgentAlert.classifyAgentNotification(notifGenericApp);
assert(cls4 !== null);
assert.strictEqual(cls4.event, "agent-permission");
console.log("ok - notification with 'approval' summary classified as agent-permission");

// 3. Non-agent notification returns null
const notifWeb = {
    appName: "Firefox",
    summary: "Download finished",
    body: "video.mp4"
};
const cls5 = AgentAlert.classifyAgentNotification(notifWeb);
assert.strictEqual(cls5, null, "Standard app notification must not be classified as agent notification");
console.log("ok - standard application notification returns null");

// 4. Deduplication key normalization
const keyA = AgentAlert.normalizeAgentKey("Antigravity", "Requesting your permission: rm -rf /tmp/foo");
const keyB = AgentAlert.normalizeAgentKey("antigravity", "Requesting your permission:   rm -rf /tmp/foo  ");
assert.strictEqual(keyA, keyB, "Normalised dedupe keys must match regardless of whitespace and casing");
assert(keyA.startsWith("agent:antigravity:"));
console.log("ok - deduplication key normalizes agent name and payload text");

// 5. Injected Clock: Reminder scheduling, 45s interval, at most 3 times
const tracker = AgentAlert.createReminderTracker();
let playCount = 0;
const playCallback = (id, count) => { playCount++; };
const isActive = (id) => true; // Always active for this test

let t = 100000;
AgentAlert.addPermissionReminder(tracker, "req-1", "Antigravity", "Bash command", t);

// At t + 20s (20000ms): tick -> no reminder yet (45s not elapsed)
let fired = AgentAlert.tickPermissionReminders(tracker, t + 20000, isActive, playCallback);
assert.strictEqual(fired.length, 0);
assert.strictEqual(playCount, 0);

// At t + 45s (45000ms): tick -> Reminder #1 fires!
fired = AgentAlert.tickPermissionReminders(tracker, t + 45000, isActive, playCallback);
assert.strictEqual(fired.length, 1);
assert.strictEqual(fired[0].count, 1);
assert.strictEqual(playCount, 1);

// At t + 80s: tick -> not yet 90s, no reminder
fired = AgentAlert.tickPermissionReminders(tracker, t + 80000, isActive, playCallback);
assert.strictEqual(fired.length, 0);

// At t + 90s: tick -> Reminder #2 fires!
fired = AgentAlert.tickPermissionReminders(tracker, t + 90000, isActive, playCallback);
assert.strictEqual(fired.length, 1);
assert.strictEqual(fired[0].count, 2);
assert.strictEqual(playCount, 2);

// At t + 135s: tick -> Reminder #3 fires! (max reached)
fired = AgentAlert.tickPermissionReminders(tracker, t + 135000, isActive, playCallback);
assert.strictEqual(fired.length, 1);
assert.strictEqual(fired[0].count, 3);
assert.strictEqual(playCount, 3);

// At t + 180s: tick -> must NOT fire any more (capped at 3)
fired = AgentAlert.tickPermissionReminders(tracker, t + 180000, isActive, playCallback);
assert.strictEqual(fired.length, 0);
assert.strictEqual(playCount, 3);
assert.strictEqual(Object.keys(tracker.active).length, 0, "Tracker entry must be removed after 3 repetitions");
console.log("ok - reminder repeats every 45s exactly 3 times then ceases");

// 6. Cancellation on answer or dismissal
const tracker2 = AgentAlert.createReminderTracker();
AgentAlert.addPermissionReminder(tracker2, "req-2", "Codex", "Write file", t);

// Cancel at t + 30s because user responded allow/deny
AgentAlert.cancelPermissionReminder(tracker2, "req-2");

// At t + 45s: tick -> must NOT fire because cancelled
fired = AgentAlert.tickPermissionReminders(tracker2, t + 45000, isActive, playCallback);
assert.strictEqual(fired.length, 0);
console.log("ok - reminder cancels immediately upon answer/dismissal");

// 7. Cancellation on expiration / inactive check
const tracker3 = AgentAlert.createReminderTracker();
AgentAlert.addPermissionReminder(tracker3, "req-3", "OpenCode", "Read directory", t);

// At t + 45s, isStillActive returns false (alert expired or removed)
let isExpired = (id) => false;
fired = AgentAlert.tickPermissionReminders(tracker3, t + 45000, isExpired, playCallback);
assert.strictEqual(fired.length, 0);
assert.strictEqual(Object.keys(tracker3.active).length, 0);
console.log("ok - reminder cancels when alert is no longer active or expired");

console.log("ALL 7 AGENT ALERT LOGIC CHECKS PASSED!");
