const assert = require("assert");
const EventsLogic = require("../components/EventsLogic.js");

function runTests() {
    console.log("Running EventsLogic Power Tests...");

    // 1. Initial State creation
    const init = EventsLogic.createInitialPowerState();
    assert.strictEqual(init.initialized, false);
    assert.strictEqual(init.dischargingLevel, "normal");

    // 2. Normal initial run (startup at 80% on AC) produces no false alarms
    let res = EventsLogic.evaluatePower(
        { percentage: 80, onBattery: false, state: 1, isPresent: true },
        init,
        {},
        false
    );
    assert.strictEqual(res.state.initialized, true);
    assert.strictEqual(res.state.lastPercentage, 80);
    assert.strictEqual(res.actions.length, 0, "Initial run should not emit spurious crossings");

    // 3. Charger unplugged
    res = EventsLogic.evaluatePower(
        { percentage: 80, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.lastOnBattery, true);
    assert.strictEqual(res.actions.length, 2, "Unplug should emit notification and sound");
    assert.strictEqual(res.actions[0].type, "notification");
    assert.strictEqual(res.actions[0].summary, "Power Disconnected");
    assert.strictEqual(res.actions[1].type, "sound");
    assert.strictEqual(res.actions[1].event, "unplug");

    // 4. Battery drain to 50% (normal discharging, above low threshold)
    res = EventsLogic.evaluatePower(
        { percentage: 50, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0);

    // 5. Battery low threshold crossing (at 20%)
    res = EventsLogic.evaluatePower(
        { percentage: 20, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.dischargingLevel, "low");
    assert.strictEqual(res.actions.length, 2, "Low battery crossing must emit notification and sound");
    assert.strictEqual(res.actions[0].summary, "Battery Low");
    assert.strictEqual(res.actions[0].urgency, "normal");
    assert.strictEqual(res.actions[1].event, "battery-low");

    // 6. Flapping at low threshold (20% -> 21% -> 19% -> 20%) must NOT repeat spam
    res = EventsLogic.evaluatePower(
        { percentage: 21, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "Flapping +1% below hysteresis margin must not re-arm");
    assert.strictEqual(res.state.dischargingLevel, "low");

    res = EventsLogic.evaluatePower(
        { percentage: 19, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "Flapping back down must not trigger again");

    res = EventsLogic.evaluatePower(
        { percentage: 20, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "No repeat spam on flap");

    // 7. Battery critical threshold crossing (at 8%)
    res = EventsLogic.evaluatePower(
        { percentage: 8, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.dischargingLevel, "critical");
    assert.strictEqual(res.actions.length, 2, "Critical battery must emit notification and critical sound");
    assert.strictEqual(res.actions[0].summary, "Battery Critical");
    assert.strictEqual(res.actions[0].urgency, "critical");
    assert.strictEqual(res.actions[1].event, "critical");

    // 8. Flapping at critical threshold (8% -> 9% -> 7% -> 8%)
    res = EventsLogic.evaluatePower(
        { percentage: 9, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "Flapping at 9% (below 8 + 3 = 11%) must not re-arm");

    res = EventsLogic.evaluatePower(
        { percentage: 7, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "No duplicate critical alert");

    // 9. Critical Action: Suspend when configured
    const suspendRes = EventsLogic.evaluatePower(
        { percentage: 8, onBattery: true, state: 2, isPresent: true },
        { initialized: true, lastOnBattery: true, lastPercentage: 9, dischargingLevel: "low" },
        { criticalAction: "suspend" },
        false
    );
    const systemAction = suspendRes.actions.find(a => a.type === "system");
    assert.ok(systemAction, "Critical action suspend must be present when configured");
    assert.strictEqual(systemAction.action, "suspend");

    // 10. Hysteresis recovery above critical margin (pct >= 11) moves level back to low
    res = EventsLogic.evaluatePower(
        { percentage: 12, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.dischargingLevel, "low", "12% is >= 8+3, so dischargingLevel recovers to low");
    assert.strictEqual(res.actions.length, 0);

    // Dropping back to 8% triggers critical again because it recovered
    res = EventsLogic.evaluatePower(
        { percentage: 8, onBattery: true, state: 2, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 2, "Re-armed critical fires on next crossing");

    // 11. Charger Plugged in
    res = EventsLogic.evaluatePower(
        { percentage: 8, onBattery: false, state: 1, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.dischargingLevel, "normal", "Plugging in charger must reset discharging level to normal");
    assert.strictEqual(res.actions.length, 2);
    assert.strictEqual(res.actions[0].summary, "Power Connected");
    assert.strictEqual(res.actions[1].event, "plug");

    // 12. Fully charged transition (reaches 100%)
    res = EventsLogic.evaluatePower(
        { percentage: 100, onBattery: false, state: 4, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.state.fullyChargedFired, true);
    assert.strictEqual(res.actions.length, 1);
    assert.strictEqual(res.actions[0].summary, "Battery Fully Charged");

    // Repeated 100% on AC does not fire again
    res = EventsLogic.evaluatePower(
        { percentage: 100, onBattery: false, state: 4, isPresent: true },
        res.state,
        {},
        false
    );
    assert.strictEqual(res.actions.length, 0, "Fully charged must not repeat spam");

    // 13. DND Behavior: normal events silenced, critical bypasses DND
    const dndUnplugRes = EventsLogic.evaluatePower(
        { percentage: 50, onBattery: true, state: 2, isPresent: true },
        { initialized: true, lastOnBattery: false, lastPercentage: 50, dischargingLevel: "normal" },
        {},
        true // dndActive = true
    );
    // Sound unplug must NOT be present
    const dndUnplugSound = dndUnplugRes.actions.find(a => a.type === "sound");
    assert.strictEqual(dndUnplugSound, undefined, "Normal sound must be silenced during DND");

    const dndCritRes = EventsLogic.evaluatePower(
        { percentage: 7, onBattery: true, state: 2, isPresent: true },
        { initialized: true, lastOnBattery: true, lastPercentage: 15, dischargingLevel: "low" },
        {},
        true // dndActive = true
    );
    const dndCritSound = dndCritRes.actions.find(a => a.type === "sound");
    assert.ok(dndCritSound, "Critical sound must NOT be silenced by DND");
    assert.strictEqual(dndCritSound.event, "critical");
    assert.strictEqual(dndCritSound.bypassDnd, true);
    const dndCritNotif = dndCritRes.actions.find(a => a.type === "notification");
    assert.strictEqual(dndCritNotif.urgency, "critical");

    console.log("All EventsLogic Power Tests Passed Successfully!");
}

runTests();
