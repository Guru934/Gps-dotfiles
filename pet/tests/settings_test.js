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

const N = load(path.join(__dirname, "..", "PetSettings.js"));
const DEFAULTS = {
    character: "cat", petName: "", scale: 3, activity: 1.0, enabled: true, roam: true,
    windowEdges: true, followCursor: true, reactMusic: true, sleepWhenIdle: true,
    sleepAfter: 90, hideFullscreen: true, respawnOnWorkspace: true, reactAlerts: true,
    energy: 100, mood: 70, steps: 0, pets: 0, sleepSeconds: 0
};
const VALID = {
    character: "ghost", petName: "Houdini", scale: 4, activity: 1.7, enabled: false, roam: false,
    windowEdges: true, followCursor: false, reactMusic: true, sleepWhenIdle: false,
    sleepAfter: 120, hideFullscreen: false, respawnOnWorkspace: true, reactAlerts: false,
    energy: 42.5, mood: 63.2, steps: 1234, pets: 12, sleepSeconds: 4567
};

function plain(value) { return JSON.parse(JSON.stringify(value)); }

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("missing settings use defaults", () => {
    assert.deepStrictEqual(plain(N.normalize({}, DEFAULTS)), DEFAULTS);
});

check("valid settings are unchanged", () => {
    assert.deepStrictEqual(plain(N.normalize(JSON.parse(JSON.stringify(VALID)), DEFAULTS)), VALID);
});

check("activity cannot become zero", () => {
    assert.strictEqual(N.normalize({ activity: 0 }, DEFAULTS).activity, 0.4);
    assert.strictEqual(N.normalize({ activity: -2 }, DEFAULTS).activity, 0.4);
    assert.strictEqual(N.normalize({ activity: 10 }, DEFAULTS).activity, 2);
    assert.strictEqual(N.normalize({ activity: Infinity }, DEFAULTS).activity, 1);
});

check("scale stays positive and within the UI range", () => {
    assert.strictEqual(N.normalize({ scale: 0 }, DEFAULTS).scale, 2);
    assert.strictEqual(N.normalize({ scale: 2 }, DEFAULTS).scale, 2);
    assert.strictEqual(N.normalize({ scale: 100 }, DEFAULTS).scale, 6);
    assert.strictEqual(N.normalize({ scale: NaN }, DEFAULTS).scale, 3);
});

check("sleep timing is clamped to the UI range", () => {
    assert.strictEqual(N.normalize({ sleepAfter: 0 }, DEFAULTS).sleepAfter, 20);
    assert.strictEqual(N.normalize({ sleepAfter: 20 }, DEFAULTS).sleepAfter, 20);
    assert.strictEqual(N.normalize({ sleepAfter: 9999 }, DEFAULTS).sleepAfter, 600);
    assert.strictEqual(N.normalize({ sleepAfter: Infinity }, DEFAULTS).sleepAfter, 90);
});

check("vitals and counters reject negatives and huge values", () => {
    const low = N.normalize({ energy: -5, mood: -1, steps: -3, pets: -2, sleepSeconds: -8 }, DEFAULTS);
    assert.deepStrictEqual(plain(low), Object.assign({}, DEFAULTS, {
        energy: 0, mood: 0, steps: 0, pets: 0, sleepSeconds: 0
    }));
    const high = N.normalize({ energy: 101, mood: 150, steps: 1e300, pets: 1e300, sleepSeconds: 1e300 }, DEFAULTS);
    assert.strictEqual(high.energy, 100);
    assert.strictEqual(high.mood, 100);
    assert.strictEqual(high.steps, 9007199254740991);
    assert.strictEqual(high.pets, 2147483647);
    assert.strictEqual(high.sleepSeconds, 9007199254740991);
});

check("wrong types use defaults, while zero-valued counters remain valid", () => {
    const mixed = N.normalize({
        character: 42, petName: false, scale: "3", activity: "fast", enabled: "yes",
        energy: 0, mood: 0, steps: 0, pets: 0, sleepSeconds: 0
    }, DEFAULTS);
    assert.strictEqual(mixed.character, "cat");
    assert.strictEqual(mixed.petName, "");
    assert.strictEqual(mixed.scale, 3);
    assert.strictEqual(mixed.activity, 1);
    assert.strictEqual(mixed.enabled, true);
    assert.strictEqual(mixed.energy, 0);
    assert.strictEqual(mixed.mood, 0);
    assert.strictEqual(mixed.steps, 0);
    assert.strictEqual(mixed.pets, 0);
    assert.strictEqual(mixed.sleepSeconds, 0);
});

check("malformed or non-object JSON is ignored", () => {
    assert.strictEqual(N.parse("{", DEFAULTS), null);
    assert.strictEqual(N.parse("null", DEFAULTS), null);
    assert.strictEqual(N.parse("[]", DEFAULTS), null);
});

check("partial JSON is normalized against defaults", () => {
    const parsed = N.parse(JSON.stringify({ scale: 0, activity: 0, energy: 0 }), DEFAULTS);
    assert.strictEqual(parsed.scale, 2);
    assert.strictEqual(parsed.activity, 0.4);
    assert.strictEqual(parsed.energy, 0);
    assert.strictEqual(parsed.mood, DEFAULTS.mood);
});

console.log("ALL PASS (" + passed + " settings checks)");
