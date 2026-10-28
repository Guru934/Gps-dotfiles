const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

function load(file) {
    const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
    const context = {};
    vm.createContext(context);
    vm.runInContext(source, context, { filename: file });
    return context;
}

const M = load(path.join(__dirname, "..", "components", "MediaCatalogue.js"));

function media(overrides) {
    return Object.assign({
        kind: "anime",
        id: "anime-16498",
        catalogueId: 16498,
        title: "Attack on Titan",
        titleRomaji: "Shingeki no Kyojin",
        titleEnglish: "Attack on Titan",
        titleNative: "進撃の巨人",
        altTitles: ["AoT"],
        description: "A grim tale of survival.",
        genres: ["Action", "Drama"],
        year: 2026,
        season: "FALL",
        seasonYear: 2026,
        seasonLabel: "Fall 2026",
        catalogueStatus: "RELEASING",
        statusLabel: "Airing",
        format: "TV",
        formatLabel: "TV",
        type: "Anime",
        country: "JP",
        countryLabel: "Japan",
        episodes: 12,
        chapters: 0,
        volumes: 0,
        total: 12,
        duration: 24,
        score: 85,
        scoreLabel: "8.5",
        popularity: 500000,
        trending: 1200,
        favourites: 90000,
        cover: "https://s4.anilist.co/file/cover.jpg",
        coverColor: "#e4a15d",
        banner: "https://s4.anilist.co/file/banner.jpg",
        siteUrl: "https://anilist.co/anime/16498",
        studios: ["MAPPA"],
        staff: [{ role: "Director", name: "Tetsuro Araki" }],
        author: "Tetsuro Araki",
        officialLinks: [
            { site: "Crunchyroll", url: "https://www.crunchyroll.com/series/GR751KNZY" },
            { site: "Unsafe", url: "http://example.com/watch" },
            { site: "Crunchyroll duplicate", url: "https://www.crunchyroll.com/series/GR751KNZY" }
        ],
        isAdult: false,
        g: ["#0b1030", "#2a1b5e", "#0e4a6b"]
    }, overrides || {});
}

function entry(overrides) {
    return media(Object.assign({
        userStatus: "Watching",
        progress: 3,
        favorite: false,
        openedAt: 100,
        savedAt: 200
    }, overrides || {}));
}

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("view, sort and filter mappings match the planned pages", () => {
    assert.deepStrictEqual(Array.from(M.viewOptions("anime")),
        ["Trending", "Popular", "Top Rated", "Seasonal", "Newest", "Watchlist"]);
    assert.deepStrictEqual(Array.from(M.viewOptions("manga")),
        ["Trending", "Popular", "Top Rated", "Newest", "Reading List"]);
    assert.strictEqual(M.sortForView("Trending"), "TRENDING_DESC");
    assert.strictEqual(M.sortForView("Top Rated"), "SCORE_DESC");
    assert.strictEqual(M.sortForView("Newest"), "START_DATE_DESC");
    assert.strictEqual(M.sortForView("Seasonal"), "POPULARITY_DESC");
    assert.strictEqual(M.sortForView("Watchlist"), "");
    assert.strictEqual(M.isLocalView("Watchlist"), true);
    assert.strictEqual(M.isLocalView("Reading List"), true);
    assert.strictEqual(M.isLocalView("Trending"), false);
    assert.strictEqual(M.seasonalView("Seasonal"), true);
    assert.strictEqual(M.listView("manga"), "Reading List");
});

check("status and origin labels map to AniList values", () => {
    assert.strictEqual(M.statusEnum("anime", "Airing"), "RELEASING");
    assert.strictEqual(M.statusEnum("manga", "Ongoing"), "RELEASING");
    assert.strictEqual(M.statusEnum("manga", "Completed"), "FINISHED");
    assert.strictEqual(M.statusEnum("anime", "All"), "");
    assert.strictEqual(M.originCountry("Manga · JP"), "JP");
    assert.strictEqual(M.originCountry("Manhwa · KR"), "KR");
    assert.strictEqual(M.originCountry("Manhua · CN"), "CN");
    assert.strictEqual(M.originCountry("Manhua · TW"), "TW");
    assert.strictEqual(M.originCountry("All regions"), "");
    assert.strictEqual(M.normalizeStatus("manga", "Currently Reading"), "Reading");
    assert.strictEqual(M.normalizeStatus("anime", "Watching"), "Watching");
    assert.strictEqual(M.normalizeStatus("anime", "Reading"), "");
    assert.strictEqual(M.defaultStatus("manga"), "Plan to Read");
    assert.strictEqual(M.genreOptions("anime")[0], "All");
    assert.strictEqual(M.genreOptions("anime").includes("Ecchi"), false);
    assert.strictEqual(M.genreOptions("anime").includes("Hentai"), false);
});

check("requests are bounded, canonical and keyed without sequence data", () => {
    const request = M.makeRequest(
        "anime", "Seasonal", "  attack  ", "Action", "Airing", "Manga · JP", 999, 200
    );
    assert.strictEqual(request.kind, "anime");
    assert.strictEqual(request.query, "attack");
    assert.strictEqual(request.genre, "Action");
    assert.strictEqual(request.status, "RELEASING");
    assert.strictEqual(request.country, "JP");
    assert.strictEqual(request.sort, "POPULARITY_DESC");
    assert.strictEqual(request.page, 500);
    assert.strictEqual(request.perPage, 50);
    assert.strictEqual(request.seasonal, true);
    const key = M.requestKey(request);
    const withSequence = Object.assign({}, request, { seq: 99 });
    assert.strictEqual(M.requestKey(withSequence), key);
    assert.strictEqual(M.makeRequest("bad", "Trending"), null);
    assert.strictEqual(M.isCurrent(3, 3), true);
    assert.strictEqual(M.isCurrent(3, 4), false);
    assert.strictEqual(M.isCurrent("3", 3), false);
});

check("media is sanitized for cards and detail pages", () => {
    const item = M.sanitizeMedia("anime", media({
        title: "  Attack\n on Titan  ",
        description: "<p>Raw</p>",
        scoreLabel: ""
    }));
    assert.strictEqual(item.title, "Attack on Titan");
    assert.strictEqual(item.id, "anime-16498");
    assert.strictEqual(item.siteUrl, "https://anilist.co/anime/16498");
    assert.strictEqual(item.cover, "https://s4.anilist.co/file/cover.jpg");
    assert.strictEqual(item.scoreLabel, "8.5");
    assert.deepStrictEqual(Array.from(item.g), Array.from(M.gradientFor("anime", 16498)));
    assert.strictEqual(item.description, "<p>Raw</p>");
    assert.strictEqual(item.officialLinks.length, 1);
    assert.strictEqual(item.officialLinks[0].site, "Crunchyroll");
    assert.strictEqual(item.officialLinks[0].url, "https://www.crunchyroll.com/series/GR751KNZY");
    const filtered = M.sanitizeMedia("anime", media({ genres: ["Action", "Ecchi", "Not A Genre"] }));
    assert.deepStrictEqual(Array.from(filtered.genres), ["Action"]);
});

check("invalid media and unsafe links never enter the UI", () => {
    assert.strictEqual(M.sanitizeMedia("anime", null), null);
    assert.strictEqual(M.sanitizeMedia("anime", []), null);
    assert.strictEqual(M.sanitizeMedia("anime", media({ kind: "manga" })), null);
    assert.strictEqual(M.sanitizeMedia("anime", media({ id: "../anime-1" })), null);
    assert.strictEqual(M.sanitizeMedia("anime", media({ id: "manga-1" })), null);
    assert.strictEqual(M.sanitizeMedia("anime", media({ title: "" })), null);
    assert.strictEqual(M.sanitizeMedia("anime", media({ isAdult: true })), null);
    const unsafe = M.sanitizeMedia("anime", media({
        cover: "https://example.com/cover.jpg",
        banner: "https://anilist.co.evil.com/banner.jpg",
        siteUrl: "javascript:alert(1)",
        g: ["red"]
    }));
    assert.strictEqual(unsafe.cover, "");
    assert.strictEqual(unsafe.banner, "");
    assert.strictEqual(unsafe.siteUrl, "https://anilist.co/anime/16498");
    assert.strictEqual(unsafe.g.length, 3);
});

check("AniList image hosts are limited to HTTPS AniList domains", () => {
    assert.strictEqual(M.safeImage("https://s4.anilist.co/a.jpg"), "https://s4.anilist.co/a.jpg");
    assert.strictEqual(M.safeImage("https://anili.st/a.jpg"), "https://anili.st/a.jpg");
    assert.strictEqual(M.safeImage("http://s4.anilist.co/a.jpg"), "");
    assert.strictEqual(M.safeImage("https://notanilist.co/a.jpg"), "");
    assert.strictEqual(M.safeImage("https://anili.st.evil.com/a.jpg"), "");
    assert.strictEqual(M.safeImage("https://s4.anilist.co:444/a.jpg"), "");
    assert.strictEqual(M.safeImage("https://s4.anilist.co/a b.jpg"), "");
});

check("media lists are deduplicated, bounded and accept QVariantList shapes", () => {
    const list = M.sanitizeMediaList("anime", [media(), media(), null], 2);
    assert.strictEqual(list.length, 1);
    const payload = {
        0: media({ altTitles: { 0: "AoT", 1: "SnK", length: 2 } }),
        1: media({ id: "anime-2", catalogueId: 2, title: "Second" }),
        length: 2
    };
    const clean = M.sanitizeMediaList("anime", payload, 2);
    assert.strictEqual(clean.length, 2);
    assert.deepStrictEqual(Array.from(clean[0].altTitles), ["AoT", "SnK"]);
    assert.strictEqual(M.sanitizeMediaList("anime", "nope").length, 0);
});

check("state parsing migrates statuses, clamps progress and rejects bad entries", () => {
    const state = M.parseState(JSON.stringify({
        version: 1,
        entries: [
            entry({ userStatus: "Currently Reading", kind: "manga", id: "manga-30002",
                    catalogueId: 30002, total: 179, progress: 999 }),
            entry(),
            entry({ id: "anime-999", userStatus: "Dropped" }),
            entry({ id: "anime-999" }),
            { kind: "anime", id: "bad" },
            null
        ]
    }));
    assert.strictEqual(state.version, 1);
    assert.strictEqual(state.entries.length, 3);
    assert.strictEqual(state.entries[0].userStatus, "Reading");
    assert.strictEqual(state.entries[0].progress, 179);
    assert.strictEqual(state.dropped, 3);
    assert.strictEqual(M.parseState("{"), null);
    assert.strictEqual(M.parseState("[]"), null);
    assert.strictEqual(M.parseState(JSON.stringify({ entries: "nope" })), null);
});

check("favorite-only entries survive while untracked entries do not", () => {
    const favorite = M.sanitizeEntry(media({ favorite: true, userStatus: "" }));
    assert.strictEqual(favorite.favorite, true);
    assert.strictEqual(M.sanitizeEntry(media({ userStatus: "", progress: 0 })), null);
    const progressOnly = M.sanitizeEntry(media({ userStatus: "", progress: 2 }));
    assert.strictEqual(progressOnly.progress, 2);
});

check("serialize round-trips valid entries and bounds them", () => {
    const serialized = M.serialize([entry(), entry({ id: "anime-2", catalogueId: 2, title: "Second" })]);
    const parsed = M.parseState(serialized);
    assert.strictEqual(parsed.entries.length, 2);
    assert.strictEqual(parsed.entries[0].userStatus, "Watching");
    assert.strictEqual(parsed.entries[0].id, "anime-16498");
    assert.deepStrictEqual(Array.from(parsed.entries[0].g), Array.from(M.gradientFor("anime", 16498)));
});

check("updateEntry adds, merges tracking and preserves existing values", () => {
    let entries = M.updateEntry([], media(), {
        userStatus: "Watching", progress: 2, favorite: true, openedAt: 10
    });
    assert.strictEqual(entries.length, 1);
    assert.strictEqual(entries[0].userStatus, "Watching");
    assert.strictEqual(entries[0].favorite, true);
    assert.ok(entries[0].savedAt > 3000000000);

    entries = M.updateEntry(entries, media({ title: "Updated title" }), { progress: 5 });
    assert.strictEqual(entries.length, 1);
    assert.strictEqual(entries[0].title, "Updated title");
    assert.strictEqual(entries[0].userStatus, "Watching");
    assert.strictEqual(entries[0].favorite, true);
    assert.strictEqual(entries[0].progress, 5);

    entries = M.updateEntry(entries, media(), { userStatus: "Completed" });
    assert.strictEqual(entries[0].userStatus, "Completed");
    assert.strictEqual(entries[0].favorite, true);

    entries = M.updateEntry(entries, media(), { favorite: false, userStatus: "Completed" });
    assert.strictEqual(entries[0].favorite, false);
    assert.strictEqual(M.findEntry(entries, "anime-16498").id, "anime-16498");

    entries = M.updateEntry(entries, media(), { userStatus: "", progress: 0 });
    assert.strictEqual(entries.length, 0);
    assert.strictEqual(M.removeEntry(entries, "anime-16498").length, 0);
});

check("progress is clamped to the media total and invalid patches are ignored", () => {
    const entries = M.updateEntry([], media({ total: 12 }), {
        userStatus: "Watching", progress: 99
    });
    assert.strictEqual(entries[0].progress, 12);
    assert.strictEqual(M.updateEntry(entries, media({ id: "bad" }), { progress: 1 }).length, 1);
});

check("local filters use catalogue status and country", () => {
    const item = M.sanitizeMedia("anime", media());
    assert.strictEqual(M.catalogueStatusMatches(item, "Airing"), true);
    assert.strictEqual(M.catalogueStatusMatches(item, "Finished"), false);
    assert.strictEqual(M.catalogueStatusMatches(item, "All"), true);
    assert.strictEqual(M.originMatches(item, "Manga · JP"), true);
    assert.strictEqual(M.originMatches(item, "Manhwa · KR"), false);
    assert.strictEqual(M.originMatches(item, "All regions"), true);
    assert.ok(M.searchableText(item).includes("mappa"));
    assert.ok(M.searchableText(item).includes("attack on titan"));
});

console.log("\n" + passed + " Media Catalogue tests passed");
