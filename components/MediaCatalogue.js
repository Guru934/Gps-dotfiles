.pragma library

// Pure AniList request configuration, media sanitization and local
// watchlist/reading-list persistence for the Media Hub catalogue pages.
// Networking and API normalization live in scripts/media-hub-anilist.py; this
// module only validates data crossing the QML boundary or coming from disk.

var MAX_ENTRIES = 500;
var MAX_TEXT = 240;
var MAX_DESCRIPTION = 5000;
var MAX_URL = 2048;
var MAX_PROGRESS = 100000;
var ID_RE = /^(anime|manga)-[0-9]{1,10}$/;
var HEX_RE = /^#[0-9a-fA-F]{6}$/;
var STATUS = {
    anime: ["Plan to Watch", "Watching", "Completed", "Dropped"],
    manga: ["Plan to Read", "Reading", "Completed", "Dropped"]
};
var VIEWS = {
    anime: ["Trending", "Popular", "Top Rated", "Seasonal", "Newest", "Watchlist"],
    manga: ["Trending", "Popular", "Top Rated", "Newest", "Reading List"]
};
var GENRES = [
    "Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror",
    "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological",
    "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"
];
var ORIGINS = ["All regions", "Manga · JP", "Manhwa · KR", "Manhua · CN", "Manhua · TW"];
var GRADIENTS = [
    ["#0b1030", "#2a1b5e", "#0e4a6b"],
    ["#2a1236", "#6b2c5f", "#f59e8b"],
    ["#071a1f", "#0e4a5b", "#a78bfa"],
    ["#1a1208", "#5a3a14", "#fbbf24"],
    ["#12060a", "#4a1218", "#f97316"],
    ["#06150f", "#0f4a3a", "#7bd0ff"]
];

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

function cleanText(value, limit) {
    if (typeof value !== "string") return "";
    var text = value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, limit || MAX_TEXT);
}

function cleanDescription(value) {
    if (typeof value !== "string") return "";
    var text = value.replace(/\r/g, "").replace(/[ \t]+/g, " ").trim();
    return text.slice(0, MAX_DESCRIPTION);
}

function safeUrl(value, allowHttp) {
    if (typeof value !== "string") return "";
    var raw = value.trim();
    if (raw.length < 8 || raw.length > MAX_URL) return "";
    if (/[\u0000-\u0020\u007f]/.test(raw)) return "";
    var match = /^(https?):\/\/([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?([\/?#][^\s]*)?$/i.exec(raw);
    if (!match) return "";
    var scheme = match[1].toLowerCase();
    if (scheme !== "https" && (scheme !== "http" || allowHttp !== true)) return "";
    if (match[3]) {
        var port = parseInt(match[3], 10);
        if (port < 1 || port > 65535) return "";
    }
    return raw;
}

function safeImage(value) {
    var raw = safeUrl(value, false);
    if (!raw) return "";
    var match = /^https:\/\/([^\/?#]+)/i.exec(raw);
    if (!match) return "";
    var host = match[1].toLowerCase();
    var trusted = host === "anilist.co" || host.slice(-11) === ".anilist.co"
               || host === "anili.st" || host.slice(-9) === ".anili.st";
    return trusted ? raw : "";
}

function stringList(value, limit, itemLimit) {
    if (!isArrayLike(value)) return [];
    var out = [];
    for (var i = 0; i < value.length && out.length < (limit || 8); i++) {
        var text = cleanText(value[i], itemLimit || 80);
        if (text && out.indexOf(text) < 0) out.push(text);
    }
    return out;
}

function staffList(value) {
    if (!isArrayLike(value)) return [];
    var out = [];
    for (var i = 0; i < value.length && out.length < 6; i++) {
        var raw = value[i];
        if (!raw || typeof raw !== "object") continue;
        var name = cleanText(raw.name, 100);
        if (!name) continue;
        out.push({ role: cleanText(raw.role, 80) || "Staff", name: name });
    }
    return out;
}

function officialLinks(value) {
    if (!isArrayLike(value)) return [];
    var out = [];
    var seen = {};
    for (var i = 0; i < value.length && out.length < 6; i++) {
        var raw = value[i];
        if (!raw || typeof raw !== "object") continue;
        var site = cleanText(raw.site, 80);
        var url = safeUrl(raw.url, false);
        if (!site || !url || seen[url]) continue;
        seen[url] = true;
        out.push({ site: site, url: url });
    }
    return out;
}

function gradientFor(kind, catalogueId) {
    var index = Math.abs(integer(catalogueId, 0, 0, 2000000000)) % GRADIENTS.length;
    if (kind === "manga") index = (index + 2) % GRADIENTS.length;
    return GRADIENTS[index].slice();
}

function kindFor(value) {
    return value === "anime" || value === "manga" ? value : "";
}

function statusOptions(kind) {
    return STATUS[kind] ? STATUS[kind].slice() : [];
}

function normalizeStatus(kind, value) {
    if (kind !== "anime" && kind !== "manga") return "";
    var text = cleanText(value, 40);
    if (kind === "manga" && text === "Currently Reading") text = "Reading";
    return STATUS[kind].indexOf(text) >= 0 ? text : "";
}

function defaultStatus(kind) {
    return kind === "anime" ? "Plan to Watch" : (kind === "manga" ? "Plan to Read" : "");
}

function statusEnum(kind, label) {
    if (label === "All" || label === "") return "";
    if (kind === "anime") {
        if (label === "Airing") return "RELEASING";
        if (label === "Finished") return "FINISHED";
        if (label === "Upcoming") return "NOT_YET_RELEASED";
        if (label === "Hiatus") return "HIATUS";
        if (label === "Cancelled") return "CANCELLED";
        return "";
    }
    if (kind === "manga") {
        if (label === "Ongoing") return "RELEASING";
        if (label === "Completed") return "FINISHED";
        if (label === "Upcoming") return "NOT_YET_RELEASED";
        if (label === "Hiatus") return "HIATUS";
        if (label === "Cancelled") return "CANCELLED";
    }
    return "";
}

function statusFilterOptions(kind) {
    return kind === "anime"
        ? ["All", "Airing", "Finished", "Upcoming", "Hiatus", "Cancelled"]
        : ["All", "Ongoing", "Completed", "Upcoming", "Hiatus", "Cancelled"];
}

function viewOptions(kind) {
    return VIEWS[kind] ? VIEWS[kind].slice() : [];
}

function listView(kind) {
    return kind === "anime" ? "Watchlist" : "Reading List";
}

function isLocalView(view) {
    return view === "Watchlist" || view === "Reading List";
}

function sortForView(view) {
    if (view === "Trending") return "TRENDING_DESC";
    if (view === "Top Rated") return "SCORE_DESC";
    if (view === "Newest") return "START_DATE_DESC";
    if (view === "Popular" || view === "Seasonal") return "POPULARITY_DESC";
    return "";
}

function seasonalView(view) {
    return view === "Seasonal";
}

function genreOptions(kind) {
    return ["All"].concat(GENRES);
}

function originOptions() {
    return ORIGINS.slice();
}

function originCountry(label) {
    if (label === "Manga · JP") return "JP";
    if (label === "Manhwa · KR") return "KR";
    if (label === "Manhua · CN") return "CN";
    if (label === "Manhua · TW") return "TW";
    return "";
}

function pageClamp(value) {
    return integer(value, 1, 1, 500);
}

function requestKey(request) {
    if (!request || typeof request !== "object") return "";
    return JSON.stringify([
        kindFor(request.kind), cleanText(request.query, 100),
        cleanText(request.genre, 40), cleanText(request.status, 32),
        cleanText(request.country, 2), cleanText(request.sort, 32),
        integer(request.page, 1, 1, 500), integer(request.perPage, 24, 1, 50),
        request.seasonal === true
    ]);
}

function makeRequest(kind, view, query, genre, statusLabel, originLabel, page, perPage) {
    var safeKind = kindFor(kind);
    if (!safeKind) return null;
    return {
        kind: safeKind,
        query: cleanText(query, 100),
        genre: genre && genre !== "All" ? cleanText(genre, 40) : "",
        status: statusEnum(safeKind, statusLabel || "All"),
        country: originCountry(originLabel || "All regions"),
        sort: sortForView(view) || "POPULARITY_DESC",
        page: pageClamp(page),
        perPage: integer(perPage, 24, 1, 50),
        seasonal: seasonalView(view),
        key: ""
    };
}

function isCurrent(sequence, currentSequence) {
    return isNumber(sequence) && isNumber(currentSequence)
        && Math.floor(sequence) === Math.floor(currentSequence);
}

function catalogueStatusMatches(item, statusLabel) {
    var expected = statusEnum(item && item.kind, statusLabel || "All");
    return expected === "" || (item && item.catalogueStatus === expected);
}

function originMatches(item, originLabel) {
    var country = originCountry(originLabel || "All regions");
    return country === "" || (item && item.country === country);
}

function sanitizeMedia(kind, raw) {
    var safeKind = kindFor(kind);
    if (!safeKind || !raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    if (raw.kind && raw.kind !== safeKind) return null;
    var id = typeof raw.id === "string" ? raw.id : "";
    if (!ID_RE.test(id)) return null;
    var prefix = safeKind + "-";
    if (id.slice(0, prefix.length) !== prefix) return null;
    var catalogueId = parseInt(id.slice(prefix.length), 10);
    if (!isNumber(catalogueId) || catalogueId < 1) return null;
    var title = cleanText(raw.title, 200);
    if (!title || raw.isAdult === true) return null;
    var genres = stringList(raw.genres, 20, 40).filter(function (genre) {
        return GENRES.indexOf(genre) >= 0;
    }).slice(0, 8);
    var score = integer(raw.score, 0, 0, 100);
    var total = integer(raw.total, 0, 0, MAX_PROGRESS);
    var staff = staffList(raw.staff);
    return {
        kind: safeKind,
        id: id,
        catalogueId: catalogueId,
        title: title,
        titleRomaji: cleanText(raw.titleRomaji, 200),
        titleEnglish: cleanText(raw.titleEnglish, 200),
        titleNative: cleanText(raw.titleNative, 200),
        altTitles: stringList(raw.altTitles, 8, 160),
        description: cleanDescription(raw.description),
        genres: genres,
        year: integer(raw.year, 0, 0, 3000),
        season: cleanText(raw.season, 8),
        seasonYear: integer(raw.seasonYear, 0, 0, 3000),
        seasonLabel: cleanText(raw.seasonLabel, 40),
        catalogueStatus: cleanText(raw.catalogueStatus, 24),
        statusLabel: cleanText(raw.statusLabel, 32) || "Unknown",
        format: cleanText(raw.format, 24),
        formatLabel: cleanText(raw.formatLabel, 32),
        type: cleanText(raw.type, 24) || (safeKind === "anime" ? "Anime" : "Manga"),
        country: cleanText(raw.country, 2),
        countryLabel: cleanText(raw.countryLabel, 40),
        episodes: integer(raw.episodes, 0, 0, MAX_PROGRESS),
        chapters: integer(raw.chapters, 0, 0, MAX_PROGRESS),
        volumes: integer(raw.volumes, 0, 0, MAX_PROGRESS),
        total: total,
        duration: integer(raw.duration, 0, 0, 10000),
        score: score,
        scoreLabel: cleanText(raw.scoreLabel, 8) || (score > 0 ? (score / 10).toFixed(1) : "—"),
        popularity: integer(raw.popularity, 0, 0, 2000000000),
        trending: integer(raw.trending, 0, 0, 2000000000),
        favourites: integer(raw.favourites, 0, 0, 2000000000),
        cover: safeImage(raw.cover),
        coverColor: HEX_RE.test(String(raw.coverColor || "")) ? raw.coverColor : "",
        banner: safeImage(raw.banner),
        siteUrl: "https://anilist.co/" + safeKind + "/" + catalogueId,
        officialLinks: officialLinks(raw.officialLinks),
        studios: stringList(raw.studios, 4, 100),
        staff: staff,
        author: cleanText(raw.author, 200),
        g: gradientFor(safeKind, catalogueId)
    };
}

function sanitizeMediaList(kind, value, limit) {
    if (!isArrayLike(value)) return [];
    var out = [];
    var seen = {};
    var max = integer(limit, 50, 1, MAX_ENTRIES);
    for (var i = 0; i < value.length && out.length < max; i++) {
        var item = sanitizeMedia(kind, value[i]);
        if (item && !seen[item.id]) {
            seen[item.id] = true;
            out.push(item);
        }
    }
    return out;
}

function trackingFrom(raw, kind, media) {
    var status = normalizeStatus(kind, raw.userStatus);
    var progress = integer(raw.progress, 0, 0, MAX_PROGRESS);
    if (media.total > 0) progress = Math.min(progress, media.total);
    return {
        userStatus: status,
        progress: progress,
        favorite: raw.favorite === true,
        openedAt: integer(raw.openedAt, 0, 0, 9000000000000),
        savedAt: integer(raw.savedAt, 0, 0, 9000000000000)
    };
}

function entryFromMedia(kind, media, tracking) {
    var clean = sanitizeMedia(kind, media);
    if (!clean) return null;
    var t = trackingFrom(tracking || {}, kind, clean);
    return Object.assign({}, clean, t);
}

function sanitizeEntry(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var kind = kindFor(raw.kind);
    if (!kind) return null;
    var media = sanitizeMedia(kind, raw);
    if (!media) return null;
    var entry = Object.assign({}, media, trackingFrom(raw, kind, media));
    if (!entry.userStatus && !entry.favorite && entry.progress <= 0) return null;
    return entry;
}

function normalizeState(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    var source = isArrayLike(raw.entries) ? raw.entries : null;
    if (!source) return null;
    var out = [];
    var seen = {};
    var dropped = 0;
    for (var i = 0; i < source.length && out.length < MAX_ENTRIES; i++) {
        var entry = sanitizeEntry(source[i]);
        if (entry && !seen[entry.id]) {
            seen[entry.id] = true;
            out.push(entry);
        } else {
            dropped += 1;
        }
    }
    return { version: 1, entries: out, dropped: dropped };
}

function parseState(text) {
    var raw;
    try { raw = JSON.parse(String(text || "")); } catch (error) { return null; }
    return normalizeState(raw);
}

function serialize(entries) {
    var clean = [];
    var seen = {};
    if (isArrayLike(entries)) {
        for (var i = 0; i < entries.length && clean.length < MAX_ENTRIES; i++) {
            var entry = sanitizeEntry(entries[i]);
            if (entry && !seen[entry.id]) {
                seen[entry.id] = true;
                clean.push(entry);
            }
        }
    }
    return JSON.stringify({ version: 1, entries: clean }, null, 2);
}

function findEntry(entries, id) {
    if (!isArrayLike(entries)) return null;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i] && entries[i].id === id) return entries[i];
    }
    return null;
}

function updateEntry(entries, media, patch) {
    var clean = sanitizeMedia(media && media.kind, media);
    if (!clean) return isArrayLike(entries) ? Array.from(entries) : [];
    var tracking = Object.assign({}, patch || {});
    var out = [];
    var found = false;
    if (isArrayLike(entries)) {
        for (var i = 0; i < entries.length && out.length < MAX_ENTRIES; i++) {
            var existing = sanitizeEntry(entries[i]);
            if (!existing) continue;
            if (existing.id === clean.id) {
                var merged = Object.assign({}, existing, clean, tracking);
                merged.userStatus = normalizeStatus(clean.kind, merged.userStatus);
                merged.progress = integer(merged.progress, existing.progress, 0, clean.total > 0 ? clean.total : MAX_PROGRESS);
                merged.favorite = merged.favorite === true;
                if (merged.userStatus || merged.favorite || merged.progress > 0)
                    out.push(merged);
                found = true;
            } else {
                out.push(existing);
            }
        }
    }
    if (!found) {
        var fresh = Object.assign({}, clean, {
            userStatus: normalizeStatus(clean.kind, tracking.userStatus || ""),
            progress: integer(tracking.progress, 0, 0, clean.total > 0 ? clean.total : MAX_PROGRESS),
            favorite: tracking.favorite === true,
            openedAt: integer(tracking.openedAt, 0, 0, 9000000000000),
            savedAt: integer(tracking.savedAt, Date.now(), 0, 9000000000000)
        });
        if (fresh.userStatus || fresh.favorite || fresh.progress > 0) out.unshift(fresh);
    }
    return out;
}

function removeEntry(entries, id) {
    var out = [];
    if (!isArrayLike(entries)) return out;
    for (var i = 0; i < entries.length && out.length < MAX_ENTRIES; i++) {
        var entry = sanitizeEntry(entries[i]);
        if (entry && entry.id !== id) out.push(entry);
    }
    return out;
}

function searchableText(item) {
    if (!item) return "";
    return (item.title + " " + (item.altTitles || []).join(" ") + " "
        + (item.genres || []).join(" ") + " " + (item.author || "") + " "
        + (item.studios || []).join(" ")).toLowerCase();
}
