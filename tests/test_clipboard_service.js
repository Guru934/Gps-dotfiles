const assert = require("assert");
const CS = require("../components/ClipboardService.js");

let testCount = 0;
function test(name, fn) {
    testCount++;
    try {
        fn();
        console.log(`ok - ${name}`);
    } catch (e) {
        console.error(`FAIL - ${name}:`, e);
        process.exit(1);
    }
}

console.log("=== Running ClipboardService.js tests ===");

test("validateId accepts valid positive integers and rejects bad input", () => {
    assert.strictEqual(CS.validateId(1), 1);
    assert.strictEqual(CS.validateId(2146), 2146);
    assert.strictEqual(CS.validateId("123"), 123);
    assert.strictEqual(CS.validateId("  456  "), 456);

    assert.strictEqual(CS.validateId(0), null);
    assert.strictEqual(CS.validateId(-5), null);
    assert.strictEqual(CS.validateId("0"), null);
    assert.strictEqual(CS.validateId("-1"), null);
    assert.strictEqual(CS.validateId("abc"), null);
    assert.strictEqual(CS.validateId("12a"), null);
    assert.strictEqual(CS.validateId(null), null);
    assert.strictEqual(CS.validateId(undefined), null);
    assert.strictEqual(CS.validateId(""), null);
});

test("classifyItem correctly detects entry types", () => {
    assert.strictEqual(CS.classifyItem("[[ binary data 2 MiB png 1089x1200 ]]"), "image");
    assert.strictEqual(CS.classifyItem("[[ binary data 184 KiB png 1752x1134 ]]"), "image");
    assert.strictEqual(CS.classifyItem("#ff0000"), "color");
    assert.strictEqual(CS.classifyItem("#FFF"), "color");
    assert.strictEqual(CS.classifyItem("#12345678"), "color");
    assert.strictEqual(CS.classifyItem("rgb(255, 0, 128)"), "color");
    assert.strictEqual(CS.classifyItem("https://google.com"), "url");
    assert.strictEqual(CS.classifyItem("http://localhost:8080/path"), "url");
    assert.strictEqual(CS.classifyItem("/home/rice/Projects/my-rice"), "path");
    assert.strictEqual(CS.classifyItem("~/Documents/notes.txt"), "path");
    assert.strictEqual(CS.classifyItem("Just some plain text"), "text");
    assert.strictEqual(CS.classifyItem("Line 1\nLine 2"), "text");
});

test("parseLine extracts fields and metadata cleanly", () => {
    const textLine = "101\tHello World";
    const item1 = CS.parseLine(textLine);
    assert.strictEqual(item1.id, 101);
    assert.strictEqual(item1.preview, "Hello World");
    assert.strictEqual(item1.kind, "text");
    assert.strictEqual(item1.isImage, false);

    const imgLine = "202\t[[ binary data 2 MiB png 1089x1200 ]]";
    const item2 = CS.parseLine(imgLine);
    assert.strictEqual(item2.id, 202);
    assert.strictEqual(item2.kind, "image");
    assert.strictEqual(item2.isImage, true);
    assert.deepStrictEqual(item2.imageInfo, {
        sizeStr: "2 MiB",
        format: "PNG",
        dims: "1089x1200"
    });

    const colorLine = "303\t#00ffcc";
    const item3 = CS.parseLine(colorLine);
    assert.strictEqual(item3.id, 303);
    assert.strictEqual(item3.kind, "color");
    assert.strictEqual(item3.colorHex, "#00ffcc");

    // Malformed lines
    assert.strictEqual(CS.parseLine("NoTabHere"), null);
    assert.strictEqual(CS.parseLine("abc\tBadId"), null);
    assert.strictEqual(CS.parseLine(""), null);
});

test("parseList bounds history to 200 items", () => {
    let output = "";
    for (let i = 1; i <= 300; i++) {
        output += `${i}\tEntry number ${i}\n`;
    }
    const list = CS.parseList(output, 200);
    assert.strictEqual(list.length, 200);
    assert.strictEqual(list[0].id, 1);
    assert.strictEqual(list[199].id, 200);
});

test("filterItems searches case-insensitively across preview and kind", () => {
    const items = [
        { id: 1, preview: "Google URL", kind: "url" },
        { id: 2, preview: "Cat Photo", kind: "image" },
        { id: 3, preview: "Important Password", kind: "text" },
        { id: 4, preview: "#ff00ff", kind: "color" }
    ];

    const res1 = CS.filterItems(items, "photo");
    assert.strictEqual(res1.length, 1);
    assert.strictEqual(res1[0].id, 2);

    const res2 = CS.filterItems(items, "color");
    assert.strictEqual(res2.length, 1);
    assert.strictEqual(res2[0].id, 4);

    const res3 = CS.filterItems(items, "");
    assert.strictEqual(res3.length, 4);
});

test("pinned items persist, toggle, and survive cliphist trimming", () => {
    const store = CS.createDefaultPinnedStore();
    assert.strictEqual(store.pinned.length, 0);

    const item1 = { id: 10, preview: "Keep this safe", kind: "text" };
    const r1 = CS.togglePin(store, item1, 1000);
    assert.strictEqual(r1.pinned, true);
    assert.strictEqual(store.pinned.length, 1);
    assert.strictEqual(CS.isPinned(store.pinned, 10, "Keep this safe"), true);

    // Toggle off
    const r2 = CS.togglePin(store, item1, 1001);
    assert.strictEqual(r2.pinned, false);
    assert.strictEqual(store.pinned.length, 0);

    // Add back 2 pinned items
    CS.togglePin(store, { id: 10, preview: "Keep this safe", kind: "text" }, 1000);
    CS.togglePin(store, { id: 20, preview: "Another secret", kind: "text" }, 1002);
    assert.strictEqual(store.pinned.length, 2);

    // Now simulate cliphist history that only contains item 10 and a new item 30
    // (item 20 was trimmed out of cliphist!)
    const history = [
        { id: 30, raw: "30\tNew item", preview: "New item", kind: "text" },
        { id: 10, raw: "10\tKeep this safe", preview: "Keep this safe", kind: "text" }
    ];

    const merged = CS.mergeHistoryAndPins(history, store);
    // Both pinned items (20 and 10) must be present at the top!
    assert.strictEqual(merged.length, 3);
    assert.strictEqual(merged[0].id, 20); // extra pin that survived trimming
    assert.strictEqual(merged[0].pinned, true);
    assert.strictEqual(merged[1].id, 10); // pin present in history
    assert.strictEqual(merged[1].pinned, true);
    assert.strictEqual(merged[2].id, 30); // regular unpinned history item
    assert.strictEqual(merged[2].pinned, false);
});

test("serialization handles JSON and safely recovers from corruption", () => {
    const valid = { paused: true, maxItems: 200 };
    const jsonStr = CS.serializeJson(valid);
    assert.deepStrictEqual(CS.deserializeJson(jsonStr, {}), valid);

    assert.deepStrictEqual(CS.deserializeJson("{corrupt json", { default: true }), { default: true });
    assert.deepStrictEqual(CS.deserializeJson("", { default: true }), { default: true });
    assert.deepStrictEqual(CS.deserializeJson(null, { default: true }), { default: true });
});

console.log(`ALL ${testCount} CLIPBOARD SERVICE CHECKS PASSED!`);
