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

const G = load(path.join(__dirname, "..", "PetGeometry.js"));
const MONITORS = JSON.stringify([{
    id: "eDP-1", name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200, scale: 1.5,
    reserved: [52, 0, 0, 0], focused: true, activeWorkspace: { id: 3 }
}]);
const CLIENTS = JSON.stringify([]);

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("floor inset leaves the bottom outline on screen", () => {
    const world = G.parse(MONITORS, CLIENTS, 60, 66, 3);
    assert.strictEqual(world.ok, true);
    assert.strictEqual(world.monitor.floorY, 797);
    assert.strictEqual(world.monitor.floorY + 3, world.monitor.h);
});

check("zero or missing inset preserves the old floor", () => {
    assert.strictEqual(G.parse(MONITORS, CLIENTS, 60, 66, 0).monitor.floorY, 800);
    assert.strictEqual(G.parse(MONITORS, CLIENTS, 60, 66).monitor.floorY, 800);
});

check("bottom reserved space is kept below the outline", () => {
    const monitors = JSON.stringify([{
        id: "eDP-1", name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200, scale: 1.5,
        reserved: [52, 0, 0, 30], focused: true, activeWorkspace: { id: 3 }
    }]);
    const world = G.parse(monitors, CLIENTS, 60, 66, 3);
    assert.strictEqual(world.monitor.floorY, 767);
    assert.strictEqual(world.monitor.floorY + 3, 770);
});

check("surface filtering still uses the screen floor", () => {
    const clients = JSON.stringify([{
        address: "0x1", mapped: true, hidden: false, monitor: "eDP-1",
        workspace: { id: 3 }, at: [100, 100], size: [500, 690], floating: false
    }]);
    const world = G.parse(MONITORS, clients, 60, 66, 3);
    const ids = world.surfaces.map(s => s.id);
    assert.strictEqual(ids.join(","), "0x1t");
});

console.log("ALL PASS (" + passed + " geometry checks)");
