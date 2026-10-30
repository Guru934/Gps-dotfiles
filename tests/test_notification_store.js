// Unit tests for NotificationStore.js and DND logic
const assert = require("assert");
const Store = require("../island/NotificationStore.js");

function runTests() {
    console.log("=== Running NotificationStore.js tests ===");

    // 1. Sanitization
    {
        const dirty = "<script>alert('xss')</script><b>Hello</b>\x00\x08 World!\nLine 2";
        const clean = Store.sanitizeText(dirty, 100);
        assert.strictEqual(clean, "alert('xss')Hello World!\nLine 2");

        const bounded = Store.sanitizeText("1234567890", 5);
        assert.strictEqual(bounded, "12345");

        assert.strictEqual(Store.sanitizeImageUri("/home/user/pic.png"), "/home/user/pic.png");
        assert.strictEqual(Store.sanitizeImageUri("file:///tmp/pic.png"), "file:///tmp/pic.png");
        assert.strictEqual(Store.sanitizeImageUri("../../../etc/passwd"), "");
        assert.strictEqual(Store.sanitizeImageUri("http://malicious.site/\x00evil"), "");
        console.log("ok - sanitization strips markup, control chars, and guards URIs");
    }

    // 2. Add and basic properties
    {
        let store = Store.createStore();
        const now = 1700000000000;
        const res = Store.add(store, {
            id: 101,
            appName: "Slack",
            summary: "New message",
            body: "Meeting in 5 mins",
            urgency: 1
        }, now);

        assert.strictEqual(res.store.entries.length, 1);
        assert.strictEqual(res.store.entries[0].appName, "Slack");
        assert.strictEqual(res.store.entries[0].summary, "New message");
        assert.strictEqual(res.store.entries[0].body, "Meeting in 5 mins");
        assert.strictEqual(res.store.entries[0].urgency, 1);
        assert.strictEqual(res.store.entries[0].read, false);
        assert.strictEqual(res.store.entries[0].dismissed, false);
        assert.strictEqual(res.store.entries[0].ts, now);
        console.log("ok - adding notification populates fields correctly");
    }

    // 3. Setting storeBody (default true, false stores empty body)
    {
        let store = Store.createStore({ settings: { storeBody: false } });
        const res = Store.add(store, {
            id: 102,
            appName: "Email",
            summary: "Confidential",
            body: "Top secret content"
        }, 1700000001000);

        assert.strictEqual(res.added.summary, "Confidential");
        assert.strictEqual(res.added.body, "", "Body must be empty when storeBody is false");
        console.log("ok - storeBody setting is respected");
    }

    // 4. Replace-by-id
    {
        let store = Store.createStore();
        const t1 = 1700000000000;
        Store.add(store, { id: 200, dbusId: 200, appName: "Music", summary: "Track 1", body: "Artist A" }, t1);
        assert.strictEqual(store.entries.length, 1);
        assert.strictEqual(store.entries[0].summary, "Track 1");

        const t2 = t1 + 5000;
        const res = Store.add(store, { replacesId: 200, appName: "Music", summary: "Track 2", body: "Artist A" }, t2);
        assert.strictEqual(res.replaced, true);
        assert.strictEqual(store.entries.length, 1, "Must update existing entry instead of appending");
        assert.strictEqual(store.entries[0].summary, "Track 2");
        assert.strictEqual(store.entries[0].ts, t2);
        console.log("ok - replacesId updates existing notification in place");
    }

    // 5. Deduplication within 2s window
    {
        let store = Store.createStore();
        const t1 = 1700000000000;
        Store.add(store, { appName: "App", summary: "Ping", body: "Pong" }, t1);
        assert.strictEqual(store.entries.length, 1);

        // Within 2000ms: deduplicated
        const t2 = t1 + 1000;
        const res = Store.add(store, { appName: "App", summary: "Ping", body: "Pong" }, t2);
        assert.strictEqual(res.replaced, true);
        assert.strictEqual(store.entries.length, 1);

        // After 2000ms: not deduplicated
        const t3 = t1 + 3000;
        const res2 = Store.add(store, { appName: "App", summary: "Ping", body: "Pong" }, t3);
        assert.strictEqual(res2.replaced, false);
        assert.strictEqual(store.entries.length, 2);
        console.log("ok - deduplication coalesces rapid identical notifications");
    }

    // 6. Caps (500 max, prefers dropping dismissed/read first)
    {
        let store = Store.createStore();
        const now = 1700000000000;
        for (let i = 0; i < 505; i++) {
            Store.add(store, { id: i + 1, appName: "App", summary: `Note ${i}`, body: "" }, now + i);
        }
        assert.strictEqual(store.entries.length, 500, "Store must cap at 500 entries");

        // Mark an old entry dismissed
        store.entries[450].dismissed = true;
        // Add a new entry
        Store.add(store, { id: 999, appName: "App", summary: "Newest", body: "" }, now + 1000);
        assert.strictEqual(store.entries.length, 500);
        assert.strictEqual(store.entries.some(e => e.id === 999), true);
        console.log("ok - 500 cap enforced with smart eviction");
    }

    // 7. Pruning older than 30 days
    {
        let store = Store.createStore();
        const now = 1700000000000;
        const dayMs = 86400000;
        const oldTs = now - (31 * dayMs);
        const freshTs = now - (5 * dayMs);

        Store.add(store, { id: 1, appName: "Old", summary: "Old", body: "" }, oldTs);
        Store.add(store, { id: 2, appName: "Fresh", summary: "Fresh", body: "" }, freshTs);

        // Next addition triggers pruning based on current time `now`
        Store.add(store, { id: 3, appName: "Now", summary: "Now", body: "" }, now);
        assert.strictEqual(store.entries.some(e => e.id === 1), false, "31-day-old entry must be pruned");
        assert.strictEqual(store.entries.some(e => e.id === 2), true, "5-day-old entry must be retained");
        console.log("ok - auto-pruning drops entries older than 30 days");
    }

    // 8. Read / Unread and Dismiss
    {
        let store = Store.createStore();
        const now = 1700000000000;
        Store.add(store, { id: 10, appName: "A", summary: "S1" }, now);
        Store.add(store, { id: 20, appName: "B", summary: "S2" }, now);

        assert.strictEqual(Store.markRead(store, 10, now), true);
        assert.strictEqual(store.entries.find(e => e.id === 10).read, true);
        assert.strictEqual(store.entries.find(e => e.id === 20).read, false);

        assert.strictEqual(Store.dismiss(store, 20, now), true);
        assert.strictEqual(store.entries.find(e => e.id === 20).dismissed, true);

        const marked = Store.markAllRead(store, now);
        assert.strictEqual(marked, 1);
        assert.strictEqual(store.entries.every(e => e.read), true);
        console.log("ok - markRead, markAllRead and dismiss work as expected");
    }

    // 9. Clear all and Clear by app
    {
        let store = Store.createStore();
        Store.add(store, { id: 1, appName: "Mail", summary: "M1" }, 100);
        Store.add(store, { id: 2, appName: "Chat", summary: "C1" }, 101);
        Store.add(store, { id: 3, appName: "Mail", summary: "M2" }, 102);

        const removed = Store.clearByApp(store, "Mail");
        assert.strictEqual(removed, 2);
        assert.strictEqual(store.entries.length, 1);
        assert.strictEqual(store.entries[0].appName, "Chat");

        Store.clearAll(store);
        assert.strictEqual(store.entries.length, 0, "clearAll must empty the entries completely");
        console.log("ok - clearAll and clearByApp function cleanly");
    }

    // 10. Grouping and Search
    {
        let store = Store.createStore();
        const base = new Date("2026-10-30T12:00:00Z").getTime();
        const todayTs = base - 3600000; // 1 hr ago
        const yesterdayTs = base - (25 * 3600000); // yesterday
        const olderTs = base - (50 * 3600000); // 2 days ago

        Store.add(store, { id: 1, appName: "Telegram", summary: "Deploy finished", body: "All tests green" }, todayTs);
        Store.add(store, { id: 2, appName: "GitHub", summary: "PR merged", body: "Awesome work" }, yesterdayTs);
        Store.add(store, { id: 3, appName: "Telegram", summary: "Server alarm", body: "CPU spike" }, olderTs);

        const byApp = Store.groupByApp(store.entries);
        assert.strictEqual(byApp["Telegram"].length, 2);
        assert.strictEqual(byApp["GitHub"].length, 1);

        const byDay = Store.groupByDay(store.entries, base);
        assert.strictEqual(byDay.today.length, 1);
        assert.strictEqual(byDay.yesterday.length, 1);
        assert.strictEqual(byDay.older.length, 1);

        const searchRes = Store.search(store.entries, "alarm");
        assert.strictEqual(searchRes.length, 1);
        assert.strictEqual(searchRes[0].summary, "Server alarm");
        console.log("ok - groupByApp, groupByDay and search return structured views");
    }

    // 11. Per-App Mute
    {
        let store = Store.createStore();
        assert.strictEqual(Store.isAppMuted(store, "SpamApp"), false);
        Store.setAppMuted(store, "SpamApp", true);
        assert.strictEqual(Store.isAppMuted(store, "SpamApp"), true);

        const res = Store.add(store, { appName: "SpamApp", summary: "Buy now!" }, 100);
        assert.strictEqual(res.muted, true);
        assert.strictEqual(res.added, null);
        assert.strictEqual(store.entries.length, 0);

        Store.setAppMuted(store, "SpamApp", false);
        assert.strictEqual(Store.isAppMuted(store, "SpamApp"), false);
        const res2 = Store.add(store, { appName: "SpamApp", summary: "Now allowed" }, 200);
        assert.strictEqual(res2.muted, false);
        assert.strictEqual(store.entries.length, 1);
        console.log("ok - per-app mute silences specified apps");
    }

    // 12. Serialization & Fault-tolerant deserialization
    {
        const store = Store.createStore();
        Store.add(store, { id: 42, appName: "Test", summary: "Hi" }, 1000);
        const json = Store.serialize(store);
        const restored = Store.deserialize(json);
        assert.strictEqual(restored.entries.length, 1);
        assert.strictEqual(restored.entries[0].id, 42);

        // Fault-tolerance on corrupted/invalid data
        assert.strictEqual(Store.deserialize("not valid json {").entries.length, 0);
        assert.strictEqual(Store.deserialize("").entries.length, 0);
        assert.strictEqual(Store.deserialize(null).entries.length, 0);
        assert.strictEqual(Store.deserialize("[]").entries.length, 0);
        console.log("ok - serialization round-trips and recovers from corrupted JSON");
    }

    // 13. DND Logic: Mode, AllowCritical, Snooze
    {
        const dnd = Store.createDefaultDnd();
        const now = 1700000000000;

        // Mode off
        assert.strictEqual(Store.isDndActive(dnd, now, 1), false);

        // Mode dnd
        dnd.mode = "dnd";
        assert.strictEqual(Store.isDndActive(dnd, now, 1), true, "Normal urgency must be blocked in DND");
        assert.strictEqual(Store.isDndActive(dnd, now, 2), false, "Critical urgency must bypass DND when allowCritical is true");

        dnd.allowCritical = false;
        assert.strictEqual(Store.isDndActive(dnd, now, 2), true, "Critical urgency blocked when allowCritical is false");
        dnd.allowCritical = true;

        // Mode snooze
        dnd.mode = "snooze";
        dnd.snoozeUntil = now + 10 * 60 * 1000; // 10 minutes from now
        assert.strictEqual(Store.isDndActive(dnd, now + 5 * 60 * 1000, 1), true, "Snooze active before expiry");
        assert.strictEqual(Store.isDndActive(dnd, now + 11 * 60 * 1000, 1), false, "Snooze inactive after expiry");
        console.log("ok - DND manual mode, critical bypass, and snooze expiry validated");
    }

    // 14. DND Schedule with Midnight Crossing
    {
        const dnd = Store.createDefaultDnd();
        dnd.mode = "schedule";
        dnd.schedule = {
            enabled: true,
            from: "22:00",
            to: "07:00",
            days: [1, 2, 3, 4, 5, 6, 7]
        };

        // Friday 21:59 -> inactive
        const t1 = new Date("2026-10-30T21:59:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t1, 1), false);

        // Friday 22:00 -> active
        const t2 = new Date("2026-10-30T22:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t2, 1), true);

        // Friday 23:45 -> active
        const t3 = new Date("2026-10-30T23:45:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t3, 1), true);

        // Saturday 02:30 (past midnight) -> active
        const t4 = new Date("2026-10-31T02:30:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t4, 1), true);

        // Saturday 06:59 -> active
        const t5 = new Date("2026-10-31T06:59:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t5, 1), true);

        // Saturday 07:00 -> inactive
        const t6 = new Date("2026-10-31T07:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t6, 1), false);

        // Saturday 14:00 -> inactive
        const t7 = new Date("2026-10-31T14:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, t7, 1), false);

        console.log("ok - midnight crossing schedule (22:00 to 07:00) verified across all hours");
    }

    // 15. DND Schedule with Day Filtering
    {
        const dnd = Store.createDefaultDnd();
        dnd.mode = "schedule";
        // Only Friday (day 5) enabled
        dnd.schedule = {
            enabled: true,
            from: "22:00",
            to: "07:00",
            days: [5] // Friday only
        };

        // Friday night 23:00 -> active
        const friNight = new Date("2026-10-30T23:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, friNight, 1), true);

        // Saturday 03:00 (part of Friday's schedule) -> active
        const satMorning = new Date("2026-10-31T03:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, satMorning, 1), true);

        // Saturday 23:00 (Saturday night not in days) -> inactive
        const satNight = new Date("2026-10-31T23:00:00").getTime();
        assert.strictEqual(Store.isDndActive(dnd, satNight, 1), false);
        console.log("ok - midnight crossing day selection correctly maps to origin night");
    }

    console.log("ALL 15 NOTIFICATION STORE CHECKS PASSED!");
}

runTests();
