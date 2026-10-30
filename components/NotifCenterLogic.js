// Pure logic for Notification Center UI
// Compatible with both QML and Node.js testing environments

function timeAgo(ts, now) {
    if (!ts || typeof ts !== "number") return "";
    const current = typeof now === "number" ? now : Date.now();
    const s = Math.max(0, Math.floor((current - ts) / 1000));
    if (s < 60) return "just now";
    if (s < 3600) return Math.floor(s / 60) + "m ago";
    if (s < 86400) return Math.floor(s / 3600) + "h ago";
    return Math.floor(s / 86400) + "d ago";
}

function getAppNames(entries) {
    if (!Array.isArray(entries)) return [];
    const set = {};
    const list = [];
    for (let i = 0; i < entries.length; i++) {
        const app = entries[i].appName || entries[i].app || "Other";
        if (!set[app]) {
            set[app] = true;
            list.push(app);
        }
    }
    return list.sort();
}

function getUnreadCount(entries) {
    if (!Array.isArray(entries)) return 0;
    let count = 0;
    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        if (!e.dismissed && !e.read) {
            count++;
        }
    }
    return count;
}

function filterEntries(entries, options) {
    if (!Array.isArray(entries)) return [];
    const opts = options || {};
    const query = (opts.query || "").toLowerCase().trim();
    const appFilter = opts.appFilter || "All";
    const unreadOnly = !!opts.unreadOnly;

    return entries.filter(function(e) {
        if (!e || e.dismissed) return false;
        if (unreadOnly && e.read) return false;

        const appName = e.appName || e.app || "Other";
        if (appFilter !== "All" && appName !== appFilter) {
            return false;
        }

        if (query) {
            const summary = (e.summary || "").toLowerCase();
            const body = (e.body || "").toLowerCase();
            const app = appName.toLowerCase();
            if (!summary.includes(query) && !body.includes(query) && !app.includes(query)) {
                return false;
            }
        }

        return true;
    });
}

function groupEntriesByDay(entries, now) {
    const current = typeof now === "number" ? now : Date.now();
    const d = new Date(current);
    d.setHours(0, 0, 0, 0);
    const todayMs = d.getTime();
    const yesterdayMs = todayMs - 86400000;

    const groups = {
        today: [],
        yesterday: [],
        earlier: []
    };

    if (!Array.isArray(entries)) return groups;

    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        if (!e || e.dismissed) continue;
        const ts = e.ts || e.createdTs || 0;
        if (ts >= todayMs) {
            groups.today.push(e);
        } else if (ts >= yesterdayMs) {
            groups.yesterday.push(e);
        } else {
            groups.earlier.push(e);
        }
    }

    return groups;
}

function clearGroupFromEntries(entries, groupName, now) {
    const current = typeof now === "number" ? now : Date.now();
    const d = new Date(current);
    d.setHours(0, 0, 0, 0);
    const todayMs = d.getTime();
    const yesterdayMs = todayMs - 86400000;

    if (!Array.isArray(entries)) return [];

    return entries.filter(function(e) {
        const ts = e.ts || e.createdTs || 0;
        if (groupName === "today") {
            return ts < todayMs;
        } else if (groupName === "yesterday") {
            return ts >= todayMs || ts < yesterdayMs;
        } else if (groupName === "earlier") {
            return ts >= yesterdayMs;
        }
        return true;
    });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        timeAgo,
        getAppNames,
        getUnreadCount,
        filterEntries,
        groupEntriesByDay,
        clearGroupFromEntries
    };
}
