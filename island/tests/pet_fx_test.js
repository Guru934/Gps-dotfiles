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

const F = load(path.join(__dirname, "..", "states", "PetFx.js"));
const SOURCE_SPRITES = load(path.join(__dirname, "..", "..", "pet", "PetSprites.js"));
const ISLAND_SPRITES = load(path.join(__dirname, "..", "states", "PetSprites.js"));

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("inactive reactions have no frame", () => {
    assert.strictEqual(F.elapsed(-1, 100), -1);
    assert.strictEqual(F.waving(-1, 100), false);
    assert.strictEqual(F.jumping(-1, 100), false);
    assert.strictEqual(F.lift(-1, 100), 0);
    assert.strictEqual(F.elapsed(10, 9), -1);
});

check("wave lasts twelve frames and stops", () => {
    assert.strictEqual(F.waving(40, 40), true);
    assert.strictEqual(F.waving(40, 51), true);
    assert.strictEqual(F.waving(40, 52), false);
});

check("jump lift follows the short arc and settles", () => {
    assert.deepStrictEqual([0, 1, 2, 3, 4, 5].map(f => F.lift(70, 70 + f)), [0, -4, -8, -8, -5, -2]);
    assert.strictEqual(F.jumping(70, 75), true);
    assert.strictEqual(F.jumping(70, 76), false);
    assert.strictEqual(F.lift(70, 76), 0);
    assert.strictEqual(F.lift(70, 77), 0);
});

check("a new start frame restarts the same arc cleanly", () => {
    assert.strictEqual(F.lift(10, 13), -8);
    assert.strictEqual(F.lift(20, 21), -4);
    assert.strictEqual(F.waving(20, 21), true);
    assert.strictEqual(F.waving(20, 32), false);
});

check("island sprite mirror matches the desktop pet engine", () => {
    for (const skin of SOURCE_SPRITES.order) {
        for (const pose of SOURCE_SPRITES.poses) {
            for (let tick = 0; tick < 28; tick++) {
                const source = JSON.stringify(SOURCE_SPRITES.build(skin, pose, tick));
                const mirror = JSON.stringify(ISLAND_SPRITES.build(skin, pose, tick));
                assert.strictEqual(mirror, source, skin + "/" + pose + "/" + tick);
            }
        }
    }
});

console.log("ALL PASS (" + passed + " island pet fx checks)");
