// Pure logic notification store and DND manager for GPS Desktop.
// No QML types; all timestamps are injected for full determinism and testability.

const MAX_ENTRIES = 500;
const MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
const DEDUPE_WINDOW_MS = 2000; // 2 seconds
const MAX_SUMMARY_LEN = 200;
const MAX_BODY_LEN = 2000;
const MAX_IMAGE_URI_LEN = 512;

function sanitizeText(str, maxLen) {
    if (!str || typeof str !== "string") return "";
    // Strip HTML/markup tags: <script>, <b>, <a href="...">, etc.
    let clean = str.replace(/<[^>]*>/g, "");
    // Remove ASCII control characters (keep newline \n)
    clean = clean.replace(/[\x00-\x09\x0B-\x1F\x7F]/g, "");
    clean = clean.trim();
    if (maxLen && clean.length > maxLen) {
        clean = clean.slice(0, maxLen);
    }
    return clean;
}

function sanitizeImageUri(uri) {
    if (!uri || typeof uri !== "string") return "";
    let clean = uri.trim();
    if (clean.length > MAX_IMAGE_URI_LEN) return "";
    if (/^(file:\/\/|\/|[a-zA-Z0-9_\.\-]+$)/.test(clean)) {
        if (clean.includes("..") || /[\x00-\x1F]/.test(clean)) return "";
        return clean;
    }
    return "";
}

function createDefaultSettings() {
    return {
        storeBody: true,
        mutedApps: []
    };
}

function createDefaultDnd() {
    return {
        mode: "off", // "off" | "dnd" | "schedule" | "snooze"
        allowCritical: true,
        snoozeUntil: 0,
        schedule: {
            enabled: false,
            from: "22:00",
            to: "07:00",
            days: [1, 2, 3, 4, 5, 6, 7]
        }
    };
}

function createStore(initial) {
    const s = initial && typeof initial === "object" ? initial : {};
    return {
        version: 1,
        entries: Array.isArray(s.entries) ? s.entries.slice(0, MAX_ENTRIES) : [],
        settings: Object.assign(createDefaultSettings(), s.settings || {})
    };
}

function parseTimeToMinutes(timeStr) {
    if (!timeStr || typeof timeStr !== "string") return 0;
    const parts = timeStr.split(":");
    const h = parseInt(parts[0], 10) || 0;
    const m = parseInt(parts[1], 10) || 0;
    return Math.max(0, Math.min(23, h)) * 60 + Math.max(0, Math.min(59, m));
}

function isScheduleActive(schedule, now) {
    if (!schedule || !schedule.enabled) return false;
    const date = new Date(now);
    let day = date.getDay();
    if (day === 0) day = 7; // 1=Mon .. 7=Sun
    const days = Array.isArray(schedule.days) ? schedule.days : [1, 2, 3, 4, 5, 6, 7];

    const currentMin = date.getHours() * 60 + date.getMinutes();
    const fromMin = parseTimeToMinutes(schedule.from);
    const toMin = parseTimeToMinutes(schedule.to);

    if (fromMin === toMin) return false;

    if (fromMin < toMin) {
        // Standard daytime range (e.g. 09:00 to 17:00)
        if (!days.includes(day)) return false;
        return currentMin >= fromMin && currentMin < toMin;
    } else {
        // Midnight crossing range (e.g. 22:00 to 07:00)
        if (currentMin >= fromMin) {
            // Evening part before midnight: matches today's schedule
            return days.includes(day);
        } else if (currentMin < toMin) {
            // Early morning part after midnight: originated on yesterday's schedule
            const prevDay = (day === 1) ? 7 : (day - 1);
            return days.includes(prevDay);
        }
        return false;
    }
}

function isDndActive(dnd, now, urgency) {
    if (!dnd) return false;
    // Critical notifications bypass DND when allowCritical is true
    if (dnd.allowCritical && urgency === 2) {
        return false;
    }
    if (dnd.mode === "dnd") {
        return true;
    }
    if (dnd.mode === "snooze") {
        if (now < dnd.snoozeUntil) return true;
        // Snooze expired, fall through to schedule
        return isScheduleActive(dnd.schedule, now);
    }
    if (dnd.mode === "schedule" || (dnd.schedule && dnd.schedule.enabled)) {
        return isScheduleActive(dnd.schedule, now);
    }
    return false;
}

function enforceCap(store, maxEntries) {
    if (!store || !store.entries || store.entries.length <= maxEntries) return;
    let excess = store.entries.length - maxEntries;
    for (let i = store.entries.length - 1; i >= 0 && excess > 0; i--) {
        if (store.entries[i].dismissed || store.entries[i].read) {
            store.entries.splice(i, 1);
            excess--;
        }
    }
    if (store.entries.length > maxEntries) {
        store.entries = store.entries.slice(0, maxEntries);
    }
}

function pruneOlderThan(store, cutoffTs) {
    if (!store || !store.entries) return;
    store.entries = store.entries.filter(e => e.ts >= cutoffTs);
}

function add(store, rawNotif, now) {
    if (!store || !store.entries) store = createStore();
    const ts = typeof now === "number" ? now : Date.now();

    const appName = sanitizeText(rawNotif.appName || "Notification", 64);
    if (isAppMuted(store, appName)) {
        return { store, added: null, replaced: false, muted: true };
    }

    const summary = sanitizeText(rawNotif.summary, MAX_SUMMARY_LEN);
    const storeBody = store.settings ? store.settings.storeBody !== false : true;
    const body = storeBody ? sanitizeText(rawNotif.body, MAX_BODY_LEN) : "";
    const urgency = typeof rawNotif.urgency === "number" ? rawNotif.urgency : 1;
    const image = sanitizeImageUri(rawNotif.image || rawNotif.appIcon || "");
    const dbusId = typeof rawNotif.id === "number" ? rawNotif.id : (rawNotif.dbusId || 0);
    const replacesId = typeof rawNotif.replacesId === "number" ? rawNotif.replacesId : 0;

    const rawActions = Array.isArray(rawNotif.actions) ? rawNotif.actions : [];
    const actions = [];
    for (let i = 0; i < rawActions.length; i++) {
        const act = rawActions[i];
        if (act && act.identifier && act.identifier !== "default") {
            actions.push({
                identifier: sanitizeText(act.identifier, 32),
                text: sanitizeText(act.text || act.identifier, 48)
            });
        }
    }

    let existingIndex = -1;
    if (replacesId > 0) {
        existingIndex = store.entries.findIndex(e => e.dbusId === replacesId || e.id === replacesId);
    } else if (dbusId > 0) {
        existingIndex = store.entries.findIndex(e => e.dbusId === dbusId);
    }

    if (existingIndex < 0) {
        existingIndex = store.entries.findIndex(e =>
            e.appName === appName &&
            e.summary === summary &&
            e.body === body &&
            (ts - e.ts) < DEDUPE_WINDOW_MS
        );
    }

    let item;
    let replaced = false;

    if (existingIndex >= 0) {
        const prev = store.entries[existingIndex];
        item = {
            id: prev.id,
            dbusId: dbusId || prev.dbusId,
            appName: appName,
            app: appName,
            appIcon: sanitizeText(rawNotif.appIcon || prev.appIcon, 64),
            summary: summary,
            body: body,
            urgency: urgency,
            actions: actions.length > 0 ? actions : prev.actions,
            image: image || prev.image,
            ts: ts,
            createdTs: prev.createdTs || prev.ts,
            read: false,
            dismissed: false
        };
        store.entries.splice(existingIndex, 1);
        store.entries.unshift(item);
        replaced = true;
    } else {
        const newId = rawNotif.id || (dbusId > 0 ? dbusId : ts + Math.floor(Math.random() * 1000));
        item = {
            id: newId,
            dbusId: dbusId,
            appName: appName,
            app: appName,
            appIcon: sanitizeText(rawNotif.appIcon, 64),
            summary: summary,
            body: body,
            urgency: urgency,
            actions: actions,
            image: image,
            ts: ts,
            createdTs: ts,
            read: false,
            dismissed: false
        };
        store.entries.unshift(item);
    }

    pruneOlderThan(store, ts - MAX_AGE_MS);
    enforceCap(store, MAX_ENTRIES);

    return { store, added: item, replaced, muted: false };
}

function dismiss(store, id, now) {
    if (!store || !store.entries) return false;
    const entry = store.entries.find(e => e.id === id || e.dbusId === id);
    if (!entry) return false;
    entry.dismissed = true;
    entry.dismissedTs = typeof now === "number" ? now : Date.now();
    return true;
}

function markRead(store, id, now) {
    if (!store || !store.entries) return false;
    const entry = store.entries.find(e => e.id === id || e.dbusId === id);
    if (!entry) return false;
    entry.read = true;
    entry.readTs = typeof now === "number" ? now : Date.now();
    return true;
}

function markAllRead(store, now) {
    if (!store || !store.entries) return 0;
    const ts = typeof now === "number" ? now : Date.now();
    let count = 0;
    for (const e of store.entries) {
        if (!e.read) {
            e.read = true;
            e.readTs = ts;
            count++;
        }
    }
    return count;
}

function clearAll(store) {
    if (!store) return;
    store.entries = [];
}

function clearByApp(store, appName) {
    if (!store || !store.entries || !appName) return 0;
    const before = store.entries.length;
    store.entries = store.entries.filter(e => e.appName !== appName);
    return before - store.entries.length;
}

function groupByApp(entries) {
    const groups = {};
    if (!Array.isArray(entries)) return groups;
    for (const e of entries) {
        const app = e.appName || "Other";
        if (!groups[app]) groups[app] = [];
        groups[app].push(e);
    }
    return groups;
}

function groupByDay(entries, now) {
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);
    const todayMs = today.getTime();
    const yesterdayMs = todayMs - 86400000;

    const groups = {
        today: [],
        yesterday: [],
        older: []
    };
    if (!Array.isArray(entries)) return groups;
    for (const e of entries) {
        if (e.ts >= todayMs) groups.today.push(e);
        else if (e.ts >= yesterdayMs) groups.yesterday.push(e);
        else groups.older.push(e);
    }
    return groups;
}

function search(entries, query) {
    if (!Array.isArray(entries)) return [];
    if (!query || typeof query !== "string") return entries.slice();
    const q = query.toLowerCase().trim();
    if (!q) return entries.slice();
    return entries.filter(e =>
        (e.appName && e.appName.toLowerCase().includes(q)) ||
        (e.summary && e.summary.toLowerCase().includes(q)) ||
        (e.body && e.body.toLowerCase().includes(q))
    );
}

function isAppMuted(store, appName) {
    if (!store || !store.settings || !Array.isArray(store.settings.mutedApps)) return false;
    return store.settings.mutedApps.includes(appName);
}

function setAppMuted(store, appName, muted) {
    if (!store.settings) store.settings = createDefaultSettings();
    if (!Array.isArray(store.settings.mutedApps)) store.settings.mutedApps = [];
    const idx = store.settings.mutedApps.indexOf(appName);
    if (muted && idx < 0) {
        store.settings.mutedApps.push(appName);
    } else if (!muted && idx >= 0) {
        store.settings.mutedApps.splice(idx, 1);
    }
}

function serialize(store) {
    return JSON.stringify({
        version: 1,
        entries: store.entries || [],
        settings: store.settings || createDefaultSettings()
    }, null, 2);
}

function deserialize(raw) {
    try {
        if (!raw || typeof raw !== "string") return createStore();
        const parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return createStore();
        return createStore(parsed);
    } catch (err) {
        return createStore();
    }
}

function serializeDnd(dnd) {
    return JSON.stringify(dnd || createDefaultDnd(), null, 2);
}

function deserializeDnd(raw) {
    try {
        if (!raw || typeof raw !== "string") return createDefaultDnd();
        const parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return createDefaultDnd();
        return Object.assign(createDefaultDnd(), parsed);
    } catch (err) {
        return createDefaultDnd();
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MAX_ENTRIES,
        MAX_AGE_MS,
        DEDUPE_WINDOW_MS,
        MAX_SUMMARY_LEN,
        MAX_BODY_LEN,
        sanitizeText,
        sanitizeImageUri,
        createDefaultSettings,
        createDefaultDnd,
        createStore,
        parseTimeToMinutes,
        isScheduleActive,
        isDndActive,
        add,
        dismiss,
        markRead,
        markAllRead,
        clearAll,
        clearByApp,
        groupByApp,
        groupByDay,
        search,
        isAppMuted,
        setAppMuted,
        serialize,
        deserialize,
        serializeDnd,
        deserializeDnd
    };
}
