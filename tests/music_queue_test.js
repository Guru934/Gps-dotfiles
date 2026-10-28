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

const M = load(path.join(__dirname, "..", "components", "MusicQueue.js"));

function track(overrides) {
    return Object.assign({
        kind: "track",
        id: "jamendo-987654",
        title: "Rain on Neon Glass",
        artist: "Velvet Circuit",
        album: "Midnight Transit",
        genre: "Synthwave",
        license: "CC BY-SA",
        moods: ["Night Drive"],
        dur: 214,
        streamUrl: "https://prod-1.storage.jamendo.com/?trackid=987654",
        art: "https://usercontent.jamendo.com/cover.jpg",
        sourceUrl: "https://www.jamendo.com/track/987654",
        g: ["#0b1030", "#2a1b5e", "#0e4a6b"]
    }, overrides || {});
}

function station(overrides) {
    return Object.assign({
        kind: "station",
        id: "radio-3d5a6c9e-12b4-4f51-9a8c-7e2f0d1b6c33",
        title: "Neon Static FM",
        artist: "Live radio",
        genre: "Synthwave",
        streamUrl: "https://stream.example.net/neon.mp3",
        sourceUrl: "https://neon.example.net/",
        votes: 140,
        clicks: 912,
        bitrate: 128,
        codec: "MP3",
        country: "Germany",
        moods: ["Night Drive"],
        g: ["#2a1236", "#6b2c5f", "#f59e8b"]
    }, overrides || {});
}

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("track fields are normalized and station-only fields omitted", () => {
    const item = M.sanitizeItem(track({ title: "  Rain\n on Neon  " }));
    assert.strictEqual(item.title, "Rain on Neon");
    assert.strictEqual(item.dur, 214);
    assert.strictEqual(item.votes, undefined);
    assert.strictEqual(item.streamUrl, "https://prod-1.storage.jamendo.com/?trackid=987654");
    assert.deepStrictEqual(Array.from(item.g), ["#0b1030", "#2a1b5e", "#0e4a6b"]);
});

check("station metadata and HTTPS links are retained", () => {
    const item = M.sanitizeItem(station());
    assert.strictEqual(item.kind, "station");
    assert.strictEqual(item.dur, 0);
    assert.strictEqual(item.votes, 140);
    assert.strictEqual(item.bitrate, 128);
    assert.strictEqual(item.codec, "MP3");
    assert.strictEqual(item.country, "Germany");
    assert.strictEqual(item.sourceUrl, "https://neon.example.net/");
    assert.deepStrictEqual(Array.from(item.moods), ["Night Drive"]);
});

check("unsafe or incomplete queue items are rejected", () => {
    assert.strictEqual(M.sanitizeItem(null), null);
    assert.strictEqual(M.sanitizeItem([]), null);
    assert.strictEqual(M.sanitizeItem(track({ id: "../bad" })), null);
    assert.strictEqual(M.sanitizeItem(track({ title: "" })), null);
    assert.strictEqual(M.sanitizeItem(track({ streamUrl: "javascript:alert(1)" })), null);
    assert.strictEqual(M.sanitizeItem(track({ streamUrl: "file:///tmp/a.mp3" })), null);
    assert.strictEqual(M.sanitizeItem(track({ streamUrl: "https://user:pass@example.com/live" })), null);
    assert.strictEqual(M.sanitizeItem(track({ streamUrl: "https://example.com:99999/live" })), null);
    assert.strictEqual(M.sanitizeItem(track({ streamUrl: "https://example.com/a b" })), null);
});

check("HTTP radio streams remain valid while non-http artwork is dropped", () => {
    const item = M.sanitizeItem(station({
        streamUrl: "http://stream.example.net/live",
        art: "http://stream.example.net/icon.png"
    }));
    assert.strictEqual(item.streamUrl, "http://stream.example.net/live");
    assert.strictEqual(item.art, "");
});

check("invalid gradients fall back instead of entering the UI", () => {
    const item = M.sanitizeItem(track({ g: ["#fff", "red", null] }));
    assert.deepStrictEqual(Array.from(item.g), Array.from(M.FALLBACK_GRAD));
});

check("lists are deduplicated and bounded", () => {
    const list = M.sanitizeList([track(), track(), station(), null], 2);
    assert.strictEqual(list.length, 2);
    assert.strictEqual(list[0].id, "jamendo-987654");
    assert.strictEqual(list[1].id, "radio-3d5a6c9e-12b4-4f51-9a8c-7e2f0d1b6c33");
    assert.deepStrictEqual(Array.from(M.sanitizeList("nope")), []);
});

check("QVariantList-style array-like payloads are accepted", () => {
    const payload = {
        0: station({
            moods: { 0: "Dreamy", 1: "Cosmic", length: 2 },
            tags: { 0: "ambient", 1: "chillout", length: 2 },
            g: { 0: "#2a1236", 1: "#6b2c5f", 2: "#f59e8b", length: 3 }
        }),
        1: track(),
        length: 2
    };
    const clean = M.sanitizeList(payload, 60);
    assert.strictEqual(clean.length, 2);
    assert.deepStrictEqual(Array.from(clean[0].moods), ["Dreamy", "Cosmic"]);
    assert.deepStrictEqual(Array.from(clean[0].tags), ["ambient", "chillout"]);
    assert.deepStrictEqual(Array.from(clean[0].g), ["#2a1236", "#6b2c5f", "#f59e8b"]);
});

check("favorites toggle add and remove by id", () => {
    const first = M.toggleFavorite([], track());
    assert.strictEqual(first.length, 1);
    assert.strictEqual(M.isFavorite(first, "jamendo-987654"), true);
    const second = M.toggleFavorite(first, track());
    assert.strictEqual(second.length, 0);
    assert.strictEqual(M.isFavorite(second, "jamendo-987654"), false);
});

check("queue insertion appends or inserts after the current item", () => {
    const a = M.sanitizeItem(track());
    const b = M.sanitizeItem(station());
    let result = M.queueAdd([], -1, a, false);
    assert.strictEqual(result.queue.length, 1);
    assert.strictEqual(result.index, 0);
    result = M.queueAdd(result.queue, result.index, b, true);
    assert.strictEqual(result.queue.length, 2);
    assert.strictEqual(result.queue[1].id, b.id);
    result = M.queueAdd(result.queue, 1, a, false);
    assert.strictEqual(result.queue.length, 3);
    assert.strictEqual(result.queue[2].id, a.id);
});

check("removing queue items keeps the playing index consistent", () => {
    const a = M.sanitizeItem(track());
    const b = M.sanitizeItem(station());
    const c = M.sanitizeItem(track({ id: "jamendo-2", title: "Second track" }));
    let result = M.removeAt([a, b, c], 0, 1);
    assert.strictEqual(result.index, 0);
    assert.strictEqual(result.removedCurrent, false);
    result = M.removeAt([a, b, c], 1, 1);
    assert.strictEqual(result.index, 1);
    assert.strictEqual(result.removedCurrent, true);
    assert.strictEqual(result.queue[1].id, c.id);
    result = M.removeAt([a], 0, 0);
    assert.strictEqual(result.index, -1);
    assert.strictEqual(result.queue.length, 0);
});

check("moving queue entries swaps them and tracks the current index", () => {
    const a = M.sanitizeItem(track());
    const b = M.sanitizeItem(station());
    const moved = M.move([a, b], 0, 1);
    assert.strictEqual(moved[0].id, b.id);
    assert.strictEqual(moved[1].id, a.id);
    assert.strictEqual(M.movedIndex(0, 0, 1), 1);
    assert.strictEqual(M.movedIndex(1, 0, 1), 0);
    assert.strictEqual(M.movedIndex(2, 0, 1), 2);
    assert.strictEqual(M.move([a, b], 1, 1)[1].id, b.id);
});

check("shuffle is deterministic with an injected RNG", () => {
    const a = M.sanitizeItem(track());
    const b = M.sanitizeItem(station());
    const c = M.sanitizeItem(track({ id: "jamendo-3", title: "Third" }));
    const values = [0, 0];
    const shuffled = M.shuffle([a, b, c], () => values.shift());
    assert.strictEqual(shuffled.length, 3);
    assert.strictEqual(shuffled[0].id, b.id);
    assert.strictEqual(shuffled[2].id, a.id);
});

check("saved state rejects malformed data and clamps values", () => {
    assert.strictEqual(M.parseState("{", {}), null);
    assert.strictEqual(M.parseState("null", {}), null);
    assert.strictEqual(M.parseState("[]", {}), null);
    const state = M.parseState(JSON.stringify({
        favorites: [track(), track()],
        queue: [station(), track({ streamUrl: "javascript:bad" })],
        queueIndex: 99,
        source: "radio",
        mood: "  Night\nDrive ",
        volume: 4,
        muted: "yes",
        shuffleOn: true,
        repeatOn: false
    }), {});
    assert.strictEqual(state.favorites.length, 1);
    assert.strictEqual(state.queue.length, 1);
    assert.strictEqual(state.queueIndex, -1);
    assert.strictEqual(state.source, "radio");
    assert.strictEqual(state.mood, "Night Drive");
    assert.strictEqual(state.volume, 1);
    assert.strictEqual(state.muted, false);
    assert.strictEqual(state.shuffleOn, true);
    assert.strictEqual(state.repeatOn, false);
});

check("missing saved fields use fallback values", () => {
    const state = M.parseState("{}", {
        favorites: [track()],
        queue: [station()],
        queueIndex: 0,
        source: "radio",
        mood: "Focus",
        volume: 0.4,
        muted: true,
        shuffleOn: true,
        repeatOn: true
    });
    assert.strictEqual(state.favorites.length, 1);
    assert.strictEqual(state.queue.length, 1);
    assert.strictEqual(state.queueIndex, 0);
    assert.strictEqual(state.source, "radio");
    assert.strictEqual(state.mood, "Focus");
    assert.strictEqual(state.volume, 0.4);
    assert.strictEqual(state.muted, true);
    assert.strictEqual(state.shuffleOn, true);
    assert.strictEqual(state.repeatOn, true);
});

console.log("ALL PASS (" + passed + " music queue checks)");
