const assert = require("assert");
const Logic = require("../components/NotifCenterLogic.js");

console.log("=== Running NotifCenterLogic.js tests ===");

const NOW = 1793350000000; // Fixed timestamp for determinism

// 1. timeAgo tests
assert.strictEqual(Logic.timeAgo(NOW - 10000, NOW), "just now");
assert.strictEqual(Logic.timeAgo(NOW - 120000, NOW), "2m ago");
assert.strictEqual(Logic.timeAgo(NOW - 7200000, NOW), "2h ago");
assert.strictEqual(Logic.timeAgo(NOW - 172800000, NOW), "2d ago");
assert.strictEqual(Logic.timeAgo(0, NOW), "");
console.log("ok - timeAgo correctly formats relative time");

// 2. getAppNames
const sampleEntries = [
    { id: 1, appName: "Discord", summary: "Hello", ts: NOW },
    { id: 2, appName: "Firefox", summary: "Download done", ts: NOW - 1000 },
    { id: 3, app: "Discord", summary: "Another msg", ts: NOW - 2000 },
    { id: 4, appName: "Terminal", summary: "Build complete", ts: NOW - 50000 }
];
const apps = Logic.getAppNames(sampleEntries);
assert.deepStrictEqual(apps, ["Discord", "Firefox", "Terminal"]);
console.log("ok - getAppNames extracts unique sorted application names");

// 3. getUnreadCount
const countEntries = [
    { id: 1, read: false, dismissed: false },
    { id: 2, read: true, dismissed: false },
    { id: 3, read: false, dismissed: true },
    { id: 4, read: false, dismissed: false }
];
assert.strictEqual(Logic.getUnreadCount(countEntries), 2);
console.log("ok - getUnreadCount ignores dismissed and read items");

// 4. filterEntries
const filterTests = [
    { id: 1, appName: "Firefox", summary: "Download complete", body: "file.iso", read: false, dismissed: false },
    { id: 2, appName: "Firefox", summary: "Tab crashed", body: "memory error", read: true, dismissed: false },
    { id: 3, appName: "Discord", summary: "New mention", body: "Hey there!", read: false, dismissed: false },
    { id: 4, appName: "Slack", summary: "Meeting now", body: "standup link", read: false, dismissed: true }
];

// All (active)
assert.strictEqual(Logic.filterEntries(filterTests, {}).length, 3);
// Unread only
assert.strictEqual(Logic.filterEntries(filterTests, { unreadOnly: true }).length, 2);
// App filter
assert.strictEqual(Logic.filterEntries(filterTests, { appFilter: "Firefox" }).length, 2);
// Search query matching summary
assert.strictEqual(Logic.filterEntries(filterTests, { query: "download" }).length, 1);
// Search query matching body
assert.strictEqual(Logic.filterEntries(filterTests, { query: "standup" }).length, 0); // dismissed
assert.strictEqual(Logic.filterEntries(filterTests, { query: "mention" }).length, 1);
console.log("ok - filterEntries correctly handles unread, app, query and dismissal filters");

// 5. groupEntriesByDay
const date = new Date(NOW);
date.setHours(12, 0, 0, 0);
const todayTs = date.getTime();
const yesterdayTs = todayTs - 86400000;
const earlierTs = todayTs - (86400000 * 3);

const datedEntries = [
    { id: 1, appName: "A", summary: "Today", ts: todayTs },
    { id: 2, appName: "B", summary: "Yesterday", ts: yesterdayTs },
    { id: 3, appName: "C", summary: "Earlier", ts: earlierTs },
    { id: 4, appName: "D", summary: "Dismissed Today", ts: todayTs, dismissed: true }
];

const groups = Logic.groupEntriesByDay(datedEntries, todayTs);
assert.strictEqual(groups.today.length, 1);
assert.strictEqual(groups.today[0].id, 1);
assert.strictEqual(groups.yesterday.length, 1);
assert.strictEqual(groups.yesterday[0].id, 2);
assert.strictEqual(groups.earlier.length, 1);
assert.strictEqual(groups.earlier[0].id, 3);
console.log("ok - groupEntriesByDay splits correctly into today, yesterday, and earlier");

// 6. clearGroupFromEntries
const remainingAfterToday = Logic.clearGroupFromEntries(datedEntries, "today", todayTs);
assert.strictEqual(remainingAfterToday.length, 2);
assert.strictEqual(remainingAfterToday[0].id, 2);
assert.strictEqual(remainingAfterToday[1].id, 3);

const remainingAfterYesterday = Logic.clearGroupFromEntries(datedEntries, "yesterday", todayTs);
assert.strictEqual(remainingAfterYesterday.length, 3);
assert(remainingAfterYesterday.some(e => e.id === 1));
assert(remainingAfterYesterday.some(e => e.id === 3));
console.log("ok - clearGroupFromEntries selectively purges the requested group");

console.log("ALL 6 NOTIF CENTER LOGIC CHECKS PASSED!");
