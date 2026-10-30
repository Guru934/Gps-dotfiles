// Unit tests for NotificationSoundLogic.js
const assert = require("assert");
const SoundLogic = require("../island/NotificationSoundLogic.js");

console.log("=== Running NotificationSoundLogic.js tests ===");

const opts = {
    homeDir: "/home/testuser",
    repoRoot: "/home/testuser/Projects/my-rice"
};

// 1. Standard low/normal notification plays "notification"
const normalRes = SoundLogic.resolveNotificationSound({
    id: 1,
    urgency: 1,
    hints: {}
}, opts);
assert.strictEqual(normalRes.event, "notification");
assert.strictEqual(normalRes.soundFile, null);
assert.strictEqual(normalRes.isCritical, false);
console.log("ok - normal notification maps to event 'notification'");

// 2. Critical urgency plays "notification-critical"
const critRes = SoundLogic.resolveNotificationSound({
    id: 2,
    urgency: 2,
    hints: {}
}, opts);
assert.strictEqual(critRes.event, "notification-critical");
assert.strictEqual(critRes.isCritical, true);
console.log("ok - critical notification maps to event 'notification-critical'");

// 3. suppress-sound hint suppresses playback completely
const suppressed1 = SoundLogic.resolveNotificationSound({
    id: 3,
    urgency: 1,
    hints: { "suppress-sound": true }
}, opts);
assert.strictEqual(suppressed1, null);

const suppressed2 = SoundLogic.resolveNotificationSound({
    id: 4,
    urgency: 2,
    hints: { "suppress-sound": "true" }
}, opts);
assert.strictEqual(suppressed2, null);
console.log("ok - suppress-sound hint (boolean or string) suppresses playback completely");

// 4. sound-name mapping
const emailRes = SoundLogic.resolveNotificationSound({
    id: 5,
    urgency: 1,
    hints: { "sound-name": "message-new-instant" }
}, opts);
assert.strictEqual(emailRes.event, "notification");

// Planner reminder maps to event 'reminder'
const plannerRes = SoundLogic.resolveNotificationSound({
    id: 50,
    appName: "Planner",
    summary: "Task Reminder",
    hints: {}
}, opts);
assert.strictEqual(plannerRes.event, "reminder");

const errorRes = SoundLogic.resolveNotificationSound({
    id: 6,
    urgency: 1,
    hints: { "sound-name": "dialog-error" }
}, opts);
assert.strictEqual(errorRes.event, "error");

const unknownRes = SoundLogic.resolveNotificationSound({
    id: 7,
    urgency: 1,
    hints: { "sound-name": "non-existent-theme-sound" }
}, opts);
assert.strictEqual(unknownRes.event, "notification"); // Falls back to default
console.log("ok - sound-name maps standard freedesktop names and falls back to default");

// 5. sound-file validation & allowlisting
const validSystemFile = SoundLogic.resolveNotificationSound({
    id: 8,
    urgency: 1,
    hints: { "sound-file": "/usr/share/sounds/freedesktop/stereo/bell.oga" }
}, opts);
assert.strictEqual(validSystemFile.soundFile, "/usr/share/sounds/freedesktop/stereo/bell.oga");

const validRepoFile = SoundLogic.resolveNotificationSound({
    id: 9,
    urgency: 1,
    hints: { "sound-file": "file:///home/testuser/Projects/my-rice/assets/sounds/custom.ogg" }
}, opts);
assert.strictEqual(validRepoFile.soundFile, "/home/testuser/Projects/my-rice/assets/sounds/custom.ogg");

// Malicious / arbitrary paths MUST be rejected
const rejectedEtc = SoundLogic.resolveNotificationSound({
    id: 10,
    urgency: 1,
    hints: { "sound-file": "/etc/shadow" }
}, opts);
assert.strictEqual(rejectedEtc.soundFile, null);

const rejectedTraversal = SoundLogic.resolveNotificationSound({
    id: 11,
    urgency: 1,
    hints: { "sound-file": "/usr/share/sounds/../../etc/passwd" }
}, opts);
assert.strictEqual(rejectedTraversal.soundFile, null);

const rejectedTmp = SoundLogic.resolveNotificationSound({
    id: 12,
    urgency: 1,
    hints: { "sound-file": "/tmp/payload.wav" }
}, opts);
assert.strictEqual(rejectedTmp.soundFile, null);
console.log("ok - sound-file allowlists valid directories and rejects arbitrary/traversal paths");

console.log("ALL 5 NOTIFICATION SOUND LOGIC CHECKS PASSED!");
