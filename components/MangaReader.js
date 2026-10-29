.pragma library

var MAX_COLLECTIONS = 200;
var MAX_TEXT = 200;
var MAX_PATH = 4096;
var MAX_PROGRESS = 100000;
var ID_RE = /^local-[0-9a-f]{16}$/;
var FORMATS = ["CBZ", "CBR", "Folder"];

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function integer(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, Math.floor(value)));
}

function cleanText(value, limit) {
    if (typeof value !== "string") return "";
    var text = value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, limit || MAX_TEXT);
}

function safePath(value) {
    if (typeof value !== "string") return "";
    var path = value.trim();
    if (path.length < 2 || path.length > MAX_PATH) return "";
    if (/[\u0000-\u001f\u007f]/.test(path)) return "";
    if (path.charAt(0) !== "/") return "";
    return path;
}

function sanitizeCollection(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var id = typeof raw.id === "string" ? raw.id : "";
    if (!ID_RE.test(id)) return null;
    var path = safePath(raw.path);
    if (!path) return null;
    var title = cleanText(raw.title, MAX_TEXT);
    if (!title) return null;
    var format = FORMATS.indexOf(raw.format) >= 0 ? raw.format : "";
    if (!format) return null;
    var chapterCount = integer(raw.chapterCount, 1, 1, MAX_PROGRESS);
    var pageCount = integer(raw.pageCount, 1, 1, MAX_PROGRESS);
    var lastChapter = integer(raw.lastChapter, 0, 0, chapterCount - 1);
    var lastPage = integer(raw.lastPage, 0, 0, pageCount - 1);
    return {
        id: id,
        title: title,
        path: path,
        format: format,
        chapterCount: chapterCount,
        pageCount: pageCount,
        lastChapter: lastChapter,
        lastPage: lastPage,
        completed: raw.completed === true,
        addedAt: integer(raw.addedAt, 0, 0, 9000000000000),
        openedAt: integer(raw.openedAt, 0, 0, 9000000000000),
        savedAt: integer(raw.savedAt, 0, 0, 9000000000000)
    };
}

function collectionFromPayload(payload) {
    if (!payload || typeof payload !== "object" || !payload.collection) return null;
    return sanitizeCollection(payload.collection);
}

function findCollection(entries, id) {
    if (!entries || typeof entries.length !== "number") return null;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i] && entries[i].id === id) return entries[i];
    }
    return null;
}

function upsertCollection(entries, raw) {
    var fresh = sanitizeCollection(raw);
    if (!fresh) return entries || [];
    if (!fresh.addedAt) fresh.addedAt = Date.now();
    var out = [];
    var found = false;
    var existing = findCollection(entries, fresh.id);
    if (existing) {
        fresh.lastChapter = integer(existing.lastChapter, 0, 0, fresh.chapterCount - 1);
        fresh.lastPage = integer(existing.lastPage, 0, 0, fresh.pageCount - 1);
        fresh.completed = existing.completed === true;
        fresh.addedAt = integer(existing.addedAt, fresh.addedAt, 0, 9000000000000);
        fresh.openedAt = integer(existing.openedAt, 0, 0, 9000000000000);
        fresh.savedAt = integer(existing.savedAt, 0, 0, 9000000000000);
    }
    if (entries && typeof entries.length === "number") {
        for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
            var item = sanitizeCollection(entries[i]);
            if (!item) continue;
            if (item.id === fresh.id) {
                out.push(fresh);
                found = true;
            } else {
                out.push(item);
            }
        }
    }
    if (!found && out.length < MAX_COLLECTIONS) out.unshift(fresh);
    return out;
}

function updateProgress(entries, id, chapter, page, completed) {
    var out = [];
    if (!entries || typeof entries.length !== "number") return out;
    var now = Date.now();
    for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
        var item = sanitizeCollection(entries[i]);
        if (!item) continue;
        if (item.id === id) {
            item.lastChapter = integer(chapter, item.lastChapter, 0, item.chapterCount - 1);
            item.lastPage = integer(page, item.lastPage, 0, item.pageCount - 1);
            item.completed = completed === true;
            item.savedAt = now;
            if (item.openedAt === 0) item.openedAt = now;
        }
        out.push(item);
    }
    return out;
}

function touchCollection(entries, id) {
    var out = [];
    if (!entries || typeof entries.length !== "number") return out;
    var now = Date.now();
    for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
        var item = sanitizeCollection(entries[i]);
        if (!item) continue;
        if (item.id === id) {
            item.openedAt = now;
            item.savedAt = now;
        }
        out.push(item);
    }
    return out;
}

function removeCollection(entries, id) {
    var out = [];
    if (!entries || typeof entries.length !== "number") return out;
    for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
        var item = sanitizeCollection(entries[i]);
        if (item && item.id !== id) out.push(item);
    }
    return out;
}

function recentCollections(entries) {
    var out = [];
    if (!entries || typeof entries.length !== "number") return out;
    for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
        var item = sanitizeCollection(entries[i]);
        if (item) out.push(item);
    }
    out.sort(function (a, b) {
        return (b.openedAt || 0) - (a.openedAt || 0)
            || (b.addedAt || 0) - (a.addedAt || 0)
            || a.title.localeCompare(b.title);
    });
    return out;
}

function progressLabel(collection) {
    var item = sanitizeCollection(collection);
    if (!item) return "";
    if (item.completed) return "Completed";
    if (item.chapterCount <= 1) return "Page " + (item.lastPage + 1) + " / " + item.pageCount;
    return "Ch " + (item.lastChapter + 1) + "/" + item.chapterCount
        + " \u00b7 Page " + (item.lastPage + 1) + "/" + item.pageCount;
}

function normalizeState(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var source = raw.collections;
    if (!source || typeof source !== "object" || typeof source.length !== "number") return null;
    var out = [];
    var seen = {};
    var dropped = 0;
    for (var i = 0; i < source.length && out.length < MAX_COLLECTIONS; i++) {
        var item = sanitizeCollection(source[i]);
        if (item && !seen[item.id]) {
            seen[item.id] = true;
            out.push(item);
        } else {
            dropped += 1;
        }
    }
    return { version: 1, collections: out, dropped: dropped };
}

function parseState(text) {
    var raw;
    try { raw = JSON.parse(String(text || "")); } catch (error) { return null; }
    return normalizeState(raw);
}

function serialize(entries) {
    var out = [];
    if (entries && typeof entries.length === "number") {
        for (var i = 0; i < entries.length && out.length < MAX_COLLECTIONS; i++) {
            var item = sanitizeCollection(entries[i]);
            if (item) out.push(item);
        }
    }
    return JSON.stringify({ version: 1, collections: out }, null, 2);
}
