.pragma library

// Pure queue and persistence normalization for the Media Hub music page.
// Keeping this out of the QML component makes it testable with Node and avoids
// trusting previously written queue entries or API fields at face value.

var MAX_QUEUE = 200;
var MAX_TEXT = 240;
var MAX_URL = 2048;
var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/;
var HEX_RE = /^#[0-9a-fA-F]{6}$/;
var FALLBACK_GRAD = ["#0b1030", "#2a1b5e", "#0e4a6b"];
var SOURCES = ["jamendo", "radio", "local"];

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function isArrayLike(value) {
    return value !== null && typeof value === "object"
        && isNumber(value.length) && value.length >= 0;
}

function integer(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, Math.floor(value)));
}

function real(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, value));
}

function cleanText(value, limit) {
    if (typeof value !== "string") return "";
    var text = value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, limit || MAX_TEXT);
}

function safeUrl(value, allowHttp) {
    if (typeof value !== "string") return "";
    var raw = value.trim();
    if (raw.length < 8 || raw.length > MAX_URL) return "";
    if (/[\u0000-\u0020\u007f]/.test(raw)) return "";
    var match = /^(https?):\/\/(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?([\/?#][^\s]*)?$/i.exec(raw);
    if (!match) return "";
    var scheme = match[1].toLowerCase();
    if (scheme !== "https" && (scheme !== "http" || allowHttp !== true)) return "";
    if (match[3]) {
        var port = parseInt(match[3], 10);
        if (port < 1 || port > 65535) return "";
    }
    return raw;
}

function safeStreamUrl(value) {
    return safeUrl(value, true);
}

function safeWebUrl(value) {
    return safeUrl(value, false);
}

function stringList(value, limit, itemLimit) {
    if (!isArrayLike(value)) return [];
    var out = [];
    for (var i = 0; i < value.length && out.length < (limit || 8); i++) {
        var text = cleanText(value[i], itemLimit || 40);
        if (text && out.indexOf(text) < 0) out.push(text);
    }
    return out;
}

function gradient(value) {
    if (!isArrayLike(value) || value.length < 3) return FALLBACK_GRAD.slice();
    var out = [];
    for (var i = 0; i < 3; i++) {
        if (typeof value[i] !== "string" || !HEX_RE.test(value[i])) return FALLBACK_GRAD.slice();
        out.push(value[i]);
    }
    return out;
}

function sanitizeItem(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var kind = raw.kind === "track" ? "track" : (raw.kind === "station" ? "station" : "");
    if (!kind) return null;
    var id = typeof raw.id === "string" ? raw.id : "";
    if (!ID_RE.test(id)) return null;
    var title = cleanText(raw.title, 180);
    var streamUrl = safeStreamUrl(raw.streamUrl);
    if (!title || !streamUrl) return null;
    var item = {
        kind: kind,
        id: id,
        title: title,
        artist: cleanText(raw.artist, 120),
        album: cleanText(raw.album, 120),
        genre: cleanText(raw.genre, 80),
        license: cleanText(raw.license, 60) || (kind === "station" ? "Radio" : "Creative Commons"),
        moods: stringList(raw.moods, 4, 40),
        streamUrl: streamUrl,
        art: safeWebUrl(raw.art),
        sourceUrl: safeWebUrl(raw.sourceUrl),
        g: gradient(raw.g),
        dur: kind === "track" ? integer(raw.dur, 0, 0, 86400) : 0,
        plays: integer(raw.plays, 0, 0, 2000000000),
        added: integer(raw.added, 0, 0, 2000000000)
    };
    if (kind === "station") {
        item.votes = integer(raw.votes, 0, 0, 2000000000);
        item.clicks = integer(raw.clicks, 0, 0, 2000000000);
        item.listeners = integer(raw.listeners, item.votes, 0, 2000000000);
        item.bitrate = integer(raw.bitrate, 0, 0, 10000);
        item.codec = cleanText(raw.codec, 24);
        item.country = cleanText(raw.country, 80);
        item.tags = stringList(raw.tags, 8, 40);
        item.hls = raw.hls === true;
    }
    return item;
}

function sanitizeList(value, limit) {
    if (!isArrayLike(value)) return [];
    var max = integer(limit, MAX_QUEUE, 1, MAX_QUEUE);
    var out = [];
    var seen = {};
    for (var i = 0; i < value.length && out.length < max; i++) {
        var item = sanitizeItem(value[i]);
        if (!item || seen[item.id]) continue;
        seen[item.id] = true;
        out.push(item);
    }
    return out;
}

function normalizeIndex(value, length) {
    if (!isNumber(length) || length <= 0) return -1;
    if (!isNumber(value)) return -1;
    var index = Math.floor(value);
    if (index < 0 || index >= length) return -1;
    return index;
}

function isFavorite(list, id) {
    var items = isArrayLike(list) ? list : [];
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].id === id) return true;
    return false;
}

function toggleFavorite(list, item) {
    var items = sanitizeList(list, MAX_QUEUE);
    var clean = sanitizeItem(item);
    if (!clean) return items;
    var out = [];
    var removed = false;
    for (var i = 0; i < items.length; i++) {
        if (items[i].id === clean.id) removed = true;
        else out.push(items[i]);
    }
    if (!removed) out.unshift(clean);
    return out;
}

function queueAdd(queue, index, item, next) {
    var items = sanitizeList(queue, MAX_QUEUE);
    var clean = sanitizeItem(item);
    var current = normalizeIndex(index, items.length);
    if (!clean) return { queue: items, index: current };
    if (items.length === 0) return { queue: [clean], index: 0 };
    var at = next === true ? current + 1 : items.length;
    if (at < 0) at = 0;
    if (at > items.length) at = items.length;
    items.splice(at, 0, clean);
    return { queue: items, index: current };
}

function removeAt(queue, index, current) {
    var items = sanitizeList(queue, MAX_QUEUE);
    var removeIndex = normalizeIndex(index, items.length);
    if (removeIndex < 0) return { queue: items, index: normalizeIndex(current, items.length), removedCurrent: false };
    var oldCurrent = normalizeIndex(current, items.length);
    items.splice(removeIndex, 1);
    var newIndex = oldCurrent;
    if (oldCurrent >= 0) {
        if (removeIndex < oldCurrent) newIndex = oldCurrent - 1;
        else if (removeIndex === oldCurrent) newIndex = items.length === 0 ? -1 : Math.min(removeIndex, items.length - 1);
    }
    return {
        queue: items,
        index: normalizeIndex(newIndex, items.length),
        removedCurrent: removeIndex === oldCurrent
    };
}

function move(queue, index, delta) {
    var items = sanitizeList(queue, MAX_QUEUE);
    var from = normalizeIndex(index, items.length);
    if (from < 0) return items;
    var to = from + integer(delta, 0, -MAX_QUEUE, MAX_QUEUE);
    if (to < 0 || to >= items.length) return items;
    var item = items[from];
    items[from] = items[to];
    items[to] = item;
    return items;
}

function movedIndex(current, from, delta) {
    if (!isNumber(current) || !isNumber(from) || !isNumber(delta)) return current;
    var to = from + delta;
    if (current === from) return to;
    if (current === to) return from;
    return current;
}

function shuffle(list, rng) {
    var items = sanitizeList(list, MAX_QUEUE);
    var random = typeof rng === "function" ? rng : Math.random;
    for (var i = items.length - 1; i > 0; i--) {
        var j = Math.floor(Math.max(0, Math.min(0.999999999, random())) * (i + 1));
        var item = items[i];
        items[i] = items[j];
        items[j] = item;
    }
    return items;
}

function parseState(text, fallback) {
    if (typeof text !== "string" || text === "") return null;
    var raw;
    try {
        raw = JSON.parse(text);
    } catch (error) {
        return null;
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var base = fallback && typeof fallback === "object" ? fallback : {};
    var favorites = isArrayLike(raw.favorites)
        ? sanitizeList(raw.favorites, MAX_QUEUE)
        : sanitizeList(base.favorites, MAX_QUEUE);
    var queue = isArrayLike(raw.queue)
        ? sanitizeList(raw.queue, MAX_QUEUE)
        : sanitizeList(base.queue, MAX_QUEUE);
    var source = typeof raw.source === "string" && SOURCES.indexOf(raw.source) >= 0
        ? raw.source
        : (SOURCES.indexOf(base.source) >= 0 ? base.source : "jamendo");
    var queueIndex = isNumber(raw.queueIndex) ? raw.queueIndex : base.queueIndex;
    return {
        favorites: favorites,
        queue: queue,
        queueIndex: normalizeIndex(queueIndex, queue.length),
        source: source,
        mood: typeof raw.mood === "string" ? cleanText(raw.mood, 40) : cleanText(base.mood, 40),
        volume: real(raw.volume, real(base.volume, 0.7, 0, 1), 0, 1),
        muted: typeof raw.muted === "boolean" ? raw.muted : base.muted === true,
        shuffleOn: typeof raw.shuffleOn === "boolean" ? raw.shuffleOn : base.shuffleOn === true,
        repeatOn: typeof raw.repeatOn === "boolean" ? raw.repeatOn : base.repeatOn === true
    };
}
