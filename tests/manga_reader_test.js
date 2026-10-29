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

const M = load(path.join(__dirname, "..", "components", "MangaReader.js"));

function collection(overrides) {
    return Object.assign({
        id: "local-0123456789abcdef",
        title: "Frieren Volume 1",
        path: "/home/reader/Manga/Frieren v01.cbz",
        format: "CBZ",
        chapterCount: 3,
        pageCount: 60,
        lastChapter: 1,
        lastPage: 4,
        completed: false,
        addedAt: 100,
        openedAt: 200,
        savedAt: 300
    }, overrides || {});
}

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("valid collection state is normalized", () => {
    const item = M.sanitizeCollection(collection({ title: "  Frieren\n Volume 1  " }));
    assert.strictEqual(item.title, "Frieren Volume 1");
    assert.strictEqual(item.format, "CBZ");
    assert.strictEqual(item.chapterCount, 3);
    assert.strictEqual(item.pageCount, 60);
    assert.strictEqual(item.lastChapter, 1);
    assert.strictEqual(item.lastPage, 4);
});

check("invalid ids, relative paths and formats are rejected", () => {
    assert.strictEqual(M.sanitizeCollection(collection({ id: "local-123" })), null);
    assert.strictEqual(M.sanitizeCollection(collection({ path: "relative/file.cbz" })), null);
    assert.strictEqual(M.sanitizeCollection(collection({ path: "/bad\npath.cbz" })), null);
    assert.strictEqual(M.sanitizeCollection(collection({ format: "PDF" })), null);
    assert.strictEqual(M.sanitizeCollection(collection({ title: "" })), null);
});

check("upsert preserves existing progress and refreshes metadata", () => {
    const old = collection({ title: "Old title", openedAt: 900, addedAt: 100 });
    const fresh = collection({ title: "New title", lastChapter: 0, lastPage: 0, openedAt: 0, addedAt: 0 });
    const out = M.upsertCollection([old], fresh);
    assert.strictEqual(out.length, 1);
    assert.strictEqual(out[0].title, "New title");
    assert.strictEqual(out[0].lastChapter, 1);
    assert.strictEqual(out[0].lastPage, 4);
    assert.strictEqual(out[0].openedAt, 900);
    assert.strictEqual(out[0].addedAt, 100);
});

check("new collections are added and capped safely", () => {
    const out = M.upsertCollection([], collection({ id: "local-fedcba9876543210", addedAt: 0 }));
    assert.strictEqual(out.length, 1);
    assert.ok(out[0].addedAt > 0);
    const many = [];
    for (let i = 0; i < 250; i++) {
        const suffix = i.toString(16).padStart(16, "0");
        many.push(collection({ id: "local-" + suffix, path: "/manga/" + i + ".cbz" }));
    }
    assert.strictEqual(M.normalizeState({ collections: many }).collections.length, M.MAX_COLLECTIONS);
});

check("progress is clamped and completion is explicit", () => {
    const out = M.updateProgress([collection()], "local-0123456789abcdef", 99, 999, true);
    assert.strictEqual(out[0].lastChapter, 2);
    assert.strictEqual(out[0].lastPage, 59);
    assert.strictEqual(out[0].completed, true);
    assert.strictEqual(M.updateProgress(out, "missing", 0, 0, false).length, 1);
});

check("touching a collection updates recency without changing progress", () => {
    const out = M.touchCollection([collection({ openedAt: 1, savedAt: 1 })], "local-0123456789abcdef");
    assert.ok(out[0].openedAt > 1);
    assert.ok(out[0].savedAt > 1);
    assert.strictEqual(out[0].lastPage, 4);
});

check("removing a collection keeps the rest", () => {
    const other = collection({ id: "local-fedcba9876543210", path: "/manga/other.cbz" });
    const out = M.removeCollection([collection(), other], "local-0123456789abcdef");
    assert.strictEqual(out.length, 1);
    assert.strictEqual(out[0].id, "local-fedcba9876543210");
});

check("recent collections sort by open and add timestamps", () => {
    const a = collection({ id: "local-0000000000000001", openedAt: 100, addedAt: 500 });
    const b = collection({ id: "local-0000000000000002", openedAt: 900, addedAt: 100 });
    const c = collection({ id: "local-0000000000000003", openedAt: 0, addedAt: 700 });
    const out = M.recentCollections([a, b, c]);
    assert.deepStrictEqual(Array.from(out, item => item.id),
        ["local-0000000000000002", "local-0000000000000001", "local-0000000000000003"]);
});

check("progress labels cover single and multi-chapter collections", () => {
    assert.strictEqual(M.progressLabel(collection({ chapterCount: 1, lastPage: 9, pageCount: 20 })), "Page 10 / 20");
    assert.strictEqual(M.progressLabel(collection()), "Ch 2/3 \u00b7 Page 5/60");
    assert.strictEqual(M.progressLabel(collection({ completed: true })), "Completed");
});

check("state parsing drops malformed records and serializes cleanly", () => {
    const state = {
        version: 1,
        collections: [collection(), { id: "broken" }, collection({ id: "local-fedcba9876543210", path: "/manga/other.cbz" })]
    };
    const parsed = M.parseState(JSON.stringify(state));
    assert.strictEqual(parsed.collections.length, 2);
    assert.strictEqual(parsed.dropped, 1);
    const text = M.serialize(parsed.collections);
    const round = M.parseState(text);
    assert.strictEqual(round.collections.length, 2);
    assert.strictEqual(round.collections[0].title, "Frieren Volume 1");
});

check("malformed state is rejected", () => {
    assert.strictEqual(M.parseState("not json"), null);
    assert.strictEqual(M.parseState("{}"), null);
    assert.strictEqual(M.normalizeState({ collections: "nope" }), null);
});

console.log(passed + " Manga Reader tests passed");
