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

    // --- Device Events Tests ---
    console.log("Running EventsLogic Device Tests...");

    const devState = EventsLogic.createInitialDeviceState();

    // 14. USB connect
    let devRes = EventsLogic.evaluateDeviceEvent(
        { type: "usb", action: "connected", name: "SanDisk Ultra" },
        devState,
        {},
        false,
        1000
    );
    assert.strictEqual(devRes.actions.length, 2);
    assert.strictEqual(devRes.actions[0].type, "notification");
    assert.strictEqual(devRes.actions[0].summary, "USB Storage Connected");
    assert.strictEqual(devRes.actions[0].body, "SanDisk Ultra");
    assert.strictEqual(devRes.actions[1].type, "sound");
    assert.strictEqual(devRes.actions[1].event, "device-connect");

    // 15. Debounce: immediate duplicate USB event within 2s is dropped
    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "usb", action: "connected", name: "SanDisk Ultra" },
        devRes.state,
        {},
        false,
        1500 // 500ms later (< 2000ms debounce)
    );
    assert.strictEqual(devRes.actions.length, 0, "Rapid duplicate device event must be debounced");

    // 16. USB disconnect after debounce window
    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "usb", action: "disconnected", name: "SanDisk Ultra" },
        devRes.state,
        {},
        false,
        3500 // > 2000ms later
    );
    assert.strictEqual(devRes.actions.length, 2);
    assert.strictEqual(devRes.actions[0].summary, "USB Storage Removed");
    assert.strictEqual(devRes.actions[1].event, "device-disconnect");

    // 17. Bluetooth connect & disconnect
    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "bluetooth", action: "connected", name: "Sony WH-1000XM4" },
        devRes.state,
        {},
        false,
        5000
    );
    assert.strictEqual(devRes.actions.length, 2);
    assert.strictEqual(devRes.actions[0].summary, "Bluetooth Connected");
    assert.strictEqual(devRes.actions[0].body, "Sony WH-1000XM4");
    assert.strictEqual(devRes.actions[1].event, "device-connect");

    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "bluetooth", action: "disconnected", name: "Sony WH-1000XM4" },
        devRes.state,
        {},
        false,
        7500
    );
    assert.strictEqual(devRes.actions.length, 2);
    assert.strictEqual(devRes.actions[0].summary, "Bluetooth Disconnected");
    assert.strictEqual(devRes.actions[1].event, "device-disconnect");

    // 18. Wi-Fi connect & disconnect (quiet by default, no sound)
    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "wifi", action: "connected", name: "GPS-Home-5G" },
        devRes.state,
        {},
        false,
        10000
    );
    assert.strictEqual(devRes.actions.length, 1, "Wi-Fi connect should have notification only by default");
    assert.strictEqual(devRes.actions[0].summary, "Wi-Fi Connected");
    assert.strictEqual(devRes.actions[0].body, "GPS-Home-5G");
    assert.strictEqual(devRes.actions[0].urgency, "low");

    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "wifi", action: "disconnected", name: "GPS-Home-5G" },
        devRes.state,
        {},
        false,
        12500
    );
    assert.strictEqual(devRes.actions.length, 1);
    assert.strictEqual(devRes.actions[0].summary, "Wi-Fi Disconnected");

    // 19. Device sound silencing under DND
    devRes = EventsLogic.evaluateDeviceEvent(
        { type: "usb", action: "connected", name: "USB Stick" },
        devRes.state,
        {},
        true, // dndActive = true
        15000
    );
    assert.strictEqual(devRes.actions.length, 1, "Device sound must be silenced during DND");
    assert.strictEqual(devRes.actions[0].type, "notification");

    console.log("All EventsLogic Device Tests Passed Successfully!");
}

runTests();
