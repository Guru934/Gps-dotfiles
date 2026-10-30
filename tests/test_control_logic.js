// tests/test_control_logic.js — Unit tests for ControlLogic.js
const assert = require("assert");
const ControlLogic = require("../island/ControlLogic.js");

console.log("=== Running ControlLogic.js tests ===");
let testCount = 0;
function test(name, fn) {
    fn();
    testCount++;
    console.log(`ok - ${name}`);
}

test("parseProfiles extracts profile names correctly from various formats", () => {
    const ppdOutput = `
  performance:
    CpuDriver: intel_pstate
    PlatformDriver: platform_profile
    Degraded: no

* balanced:
    CpuDriver: intel_pstate
    PlatformDriver: platform_profile

  power-saver:
    CpuDriver: intel_pstate
    PlatformDriver: platform_profile
`;
    const parsed = ControlLogic.parseProfiles(ppdOutput);
    assert.deepStrictEqual(parsed, ["performance", "balanced", "power-saver"]);

    const kernelOutput = "balanced performance power-saver";
    assert.deepStrictEqual(ControlLogic.parseProfiles(kernelOutput), ["balanced", "performance", "power-saver"]);

    assert.deepStrictEqual(ControlLogic.parseProfiles(""), ["power-saver", "balanced", "performance"]);
    assert.deepStrictEqual(ControlLogic.parseProfiles(null), ["power-saver", "balanced", "performance"]);
});

test("cycleProfile cycles only through offered profiles", () => {
    const machineProfiles = ["power-saver", "balanced", "performance"];
    assert.strictEqual(ControlLogic.cycleProfile("power-saver", machineProfiles), "balanced");
    assert.strictEqual(ControlLogic.cycleProfile("balanced", machineProfiles), "performance");
    assert.strictEqual(ControlLogic.cycleProfile("performance", machineProfiles), "power-saver");

    // Machine with only 2 profiles
    const twoProfiles = ["balanced", "power-saver"];
    assert.strictEqual(ControlLogic.cycleProfile("balanced", twoProfiles), "power-saver");
    assert.strictEqual(ControlLogic.cycleProfile("power-saver", twoProfiles), "balanced");

    // Unknown profile defaults to first available
    assert.strictEqual(ControlLogic.cycleProfile("turbo", twoProfiles), "balanced");
});

test("formatBatteryTime formats charging and discharging times accurately", () => {
    assert.strictEqual(ControlLogic.formatBatteryTime(5400, true), "1h 30m to full");
    assert.strictEqual(ControlLogic.formatBatteryTime(3600, false), "1h left");
    assert.strictEqual(ControlLogic.formatBatteryTime(1500, false), "25m left");
    assert.strictEqual(ControlLogic.formatBatteryTime(30, true), "");
    assert.strictEqual(ControlLogic.formatBatteryTime(0, false), "");
    assert.strictEqual(ControlLogic.formatBatteryTime(null, false), "");
});

test("calcMinutesUntilNext correctly calculates minutes until morning", () => {
    // 23:00 to 08:00 is 9 hours = 540 minutes
    const baseDate = new Date("2026-10-30T23:00:00Z").getTime();
    const mins = ControlLogic.calcMinutesUntilNext(8, 0, baseDate);
    // Depending on timezone of machine, ensure result is > 0 and <= 1440
    assert.ok(mins > 0 && mins <= 1440);
});

test("formatDndSubText reflects snooze, schedule, and manual states", () => {
    assert.strictEqual(ControlLogic.formatDndSubText(null, false), "Off");
    assert.strictEqual(ControlLogic.formatDndSubText({ mode: "dnd" }, true), "On");

    const now = 1000000;
    const snoozeState = { mode: "snooze", snoozeUntil: now + 45 * 60 * 1000 };
    assert.strictEqual(ControlLogic.formatDndSubText(snoozeState, true, now), "45 min left");

    const snoozeHours = { mode: "snooze", snoozeUntil: now + 90 * 60 * 1000 };
    assert.strictEqual(ControlLogic.formatDndSubText(snoozeHours, true, now), "1h 30m left");

    const schedState = { mode: "schedule", schedule: { enabled: true, to: "08:00" } };
    assert.strictEqual(ControlLogic.formatDndSubText(schedState, true, now), "Scheduled (08:00)");
});

test("buildGameModeLua creates correct Lua calls for enabling and restoring", () => {
    const enableLua = ControlLogic.buildGameModeLua(true);
    assert.ok(enableLua.includes("animations = { enabled = false }"));
    assert.ok(enableLua.includes("decoration = { blur = { enabled = false }, shadow = { enabled = false } }"));
    assert.ok(enableLua.includes("general = { gaps_in = 0, gaps_out = 0 }"));

    const snapshot = {
        animations_enabled: true,
        blur_enabled: true,
        shadow_enabled: true,
        gaps_in: 5,
        gaps_out: 20
    };
    const restoreLua = ControlLogic.buildGameModeLua(false, snapshot);
    assert.ok(restoreLua.includes("animations = { enabled = true }"));
    assert.ok(restoreLua.includes("blur = { enabled = true }"));
    assert.ok(restoreLua.includes("shadow = { enabled = true }"));
    assert.ok(restoreLua.includes("gaps_in = 5, gaps_out = 20"));
});

test("parseGapsValue parses integer and css gap strings", () => {
    assert.strictEqual(ControlLogic.parseGapsValue(10, 5), 10);
    assert.strictEqual(ControlLogic.parseGapsValue("20 20 20 20", 5), 20);
    assert.strictEqual(ControlLogic.parseGapsValue("invalid", 5), 5);
});

test("validateControlTiles validates order, merges defaults, and safely handles unknowns", () => {
    const userConfig = [
        { id: "gamemode", enabled: false },
        { id: "wifi", enabled: true },
        { id: "unknown_hack", enabled: true }
    ];
    const validated = ControlLogic.validateControlTiles(userConfig);
    assert.strictEqual(validated[0].id, "gamemode");
    assert.strictEqual(validated[0].enabled, false);
    assert.strictEqual(validated[1].id, "wifi");
    assert.strictEqual(validated[1].enabled, true);
    // unknown_hack should be filtered out
    assert.strictEqual(validated.find(t => t.id === "unknown_hack"), undefined);
    // All other defaults should be appended in default order
    assert.strictEqual(validated.length, ControlLogic.DEFAULT_TILES.length);
});

test("parseCpuUsage calculates diff delta correctly between ticks", () => {
    const tick1 = [100, 0, 50, 850]; // idle = 850, total = 1000
    const res1 = ControlLogic.parseCpuUsage(tick1, null);
    assert.strictEqual(res1.usage, -1);
    assert.deepStrictEqual(res1.prev, { total: 1000, idle: 850 });

    const tick2 = [150, 0, 70, 880]; // idle = 880, total = 1100 -> dTotal = 100, dIdle = 30 -> 70%
    const res2 = ControlLogic.parseCpuUsage(tick2, res1.prev);
    assert.strictEqual(res2.usage, 70);
    assert.deepStrictEqual(res2.prev, { total: 1100, idle: 880 });
});

test("parseMemUsage calculates GiB and percentage cleanly", () => {
    const totalKb = 16 * 1048576; // 16 GiB
    const availKb = 4 * 1048576;  // 4 GiB avail -> 12 GiB used = 75%
    const res = ControlLogic.parseMemUsage(totalKb, availKb);
    assert.strictEqual(res.totalGiB, 16);
    assert.strictEqual(res.usedGiB, 12);
    assert.strictEqual(res.pct, 75);
});

test("parseTempC converts millidegrees to degrees Celsius", () => {
    assert.strictEqual(ControlLogic.parseTempC("49000"), 49);
    assert.strictEqual(ControlLogic.parseTempC("52"), 52);
    assert.strictEqual(ControlLogic.parseTempC("-1"), -1);
    assert.strictEqual(ControlLogic.parseTempC(""), -1);
});

test("formatDuration formats playback position and total length accurately", () => {
    assert.strictEqual(ControlLogic.formatDuration(0), "0:00");
    assert.strictEqual(ControlLogic.formatDuration(65000), "1:05");
    assert.strictEqual(ControlLogic.formatDuration(3665000), "1:01:05");
});

console.log(`ALL ${testCount} CONTROL LOGIC CHECKS PASSED!`);
