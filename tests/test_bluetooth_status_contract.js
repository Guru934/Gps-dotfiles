#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repo = path.resolve(__dirname, "..");
const read = relativePath => fs.readFileSync(path.join(repo, relativePath), "utf8");
const helperSource = read("components/BluetoothStatus.js").replace(/^\.pragma library\s*/, "");
const btStatus = {};
vm.runInNewContext(helperSource, btStatus);

function assertState(state, expected) {
    for (const [key, value] of Object.entries(expected)) {
        assert.equal(state[key], value, `${key} should match expected state`);
    }
}

// 1. Adapter/service unavailable
const unavailable = btStatus.resolve(null);
assertState(unavailable, {
    available: false,
    enabled: false,
    connected: false,
    state: "unavailable",
    statusText: "Unavailable",
    connectedName: "",
    connectedCount: 0,
    connecting: false,
    disconnecting: false
});

// 2. Radio powered off
const radioOff = btStatus.resolve({
    name: "hci0",
    enabled: false,
    devices: { values: [] }
});
assertState(radioOff, {
    available: true,
    enabled: false,
    connected: false,
    state: "off",
    statusText: "Bluetooth Off",
    connectedName: "",
    connectedCount: 0
});

// 3. Radio powered on with no connected devices (NEVER "Bluetooth Off")
const poweredNoDev = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [] }
});
assertState(poweredNoDev, {
    available: true,
    enabled: true,
    connected: false,
    state: "on",
    statusText: "Not Connected",
    connectedName: "",
    connectedCount: 0
});
assert.notEqual(poweredNoDev.statusText, "Bluetooth Off");

// 4. Radio powered on with connected device
const singleDevice = {
    address: "AA:BB:CC:DD:EE:01",
    name: "Sony WH-1000XM4",
    connected: true,
    paired: true,
    state: 1,
    batteryAvailable: true,
    battery: 0.85
};
const connected = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [singleDevice] }
});
assertState(connected, {
    available: true,
    enabled: true,
    connected: true,
    state: "connected",
    statusText: "Connected: Sony WH-1000XM4",
    connectedName: "Sony WH-1000XM4",
    connectedCount: 1
});

// 5. Multiple connected devices
const secondDevice = {
    address: "AA:BB:CC:DD:EE:02",
    name: "Logitech MX Master",
    connected: true,
    paired: true,
    state: 1,
    batteryAvailable: false,
    battery: 0
};
const multiConnected = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [singleDevice, secondDevice] }
});
assertState(multiConnected, {
    available: true,
    enabled: true,
    connected: true,
    connectedName: "Sony WH-1000XM4",
    connectedCount: 2
});

// 6. Device disconnection
singleDevice.connected = false;
singleDevice.state = 0;
const disconnected = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [singleDevice] }
});
assertState(disconnected, {
    available: true,
    enabled: true,
    connected: false,
    state: "on",
    statusText: "Not Connected",
    connectedCount: 0
});

// 7. Device connecting state
const connectingDevice = {
    address: "AA:BB:CC:DD:EE:03",
    name: "AirPods",
    connected: false,
    paired: true,
    state: 3 // Connecting
};
const connectingState = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [connectingDevice] }
});
assertState(connectingState, {
    available: true,
    enabled: true,
    connected: false,
    connecting: true,
    state: "connecting",
    statusText: "Connecting…"
});

// 8. Device disconnecting state
const disconnectingDevice = {
    address: "AA:BB:CC:DD:EE:04",
    name: "Keyboard",
    connected: false,
    paired: true,
    state: 2 // Disconnecting
};
const disconnectingState = btStatus.resolve({
    name: "hci0",
    enabled: true,
    devices: { values: [disconnectingDevice] }
});
assertState(disconnectingState, {
    available: true,
    enabled: true,
    connected: false,
    disconnecting: true,
    state: "disconnecting",
    statusText: "Disconnecting…"
});

// 9. Inspect QML contract patterns across components
const shell = read("shell.qml");
const rail = read("components/LeftRail.qml");
const popup = read("components/BluetoothPopup.qml");
const home = read("components/dashboard/HomeTab.qml");
const control = read("island/states/Control.qml");
const settings = read("settings.qml");

// Shell contract
assert.match(shell, /import Quickshell\.Bluetooth/);
assert.match(shell, /BluetoothStatus\.resolve\(root\.btAdapter\)/);
assert.match(shell, /onBtStatusChanged:\s*root\.checkBtPending\(\)/);
assert.doesNotMatch(shell, /id:\s*btStatusProc\b|function parseBtStatus\b|function parseBtOutput\b/);
assert.doesNotMatch(shell, /refreshBtReads|btVerifyTries/);
assert.doesNotMatch(shell, /bluetoothctl",\s*"show"/);
assert.match(shell, /btCmdProc\.command = \["bluetoothctl", "power", target\]/);
assert.match(shell, /btCmdProc\.command = \["bluetoothctl", action, mac\]/);
assert.match(shell, /btCmdProc\.command = \["bluetoothctl", "pair", mac\]/);
assert.match(shell, /btCmdProc\.command = \["bluetoothctl", "remove", mac\]/);
assert.match(shell, /Is BlueZ \(bluetoothctl\) installed\?/);

// LeftRail contract: no bluetoothctl polling in sysPollProc
assert.match(rail, /root\.hub\.btAvailable/);
assert.match(rail, /root\.hub\.btConnected/);
assert.doesNotMatch(rail, /bt_power|bt_conn|bluetoothctl/);

// BluetoothPopup contract
assert.match(popup, /root\.hub\.btAvailable/);
assert.match(popup, /root\.hub\.toggleBtPower\(\)/);
assert.match(popup, /root\.hub\.scanBluetooth\(\)/);
assert.match(popup, /root\.hub\.pairBtDevice\(modelData\.mac\)/);
assert.match(popup, /root\.hub\.toggleBtDevice\(modelData\.mac,\s*modelData\.connected\)/);

// HomeTab contract
assert.match(home, /BluetoothStatus\.resolve\(/);
assert.match(home, /interactive:\s*root\.btStatus\.available/);
assert.match(home, /dimmed:\s*!root\.btStatus\.available/);
assert.doesNotMatch(home, /title:\s*"Bluetooth Off"/);

// Island Control contract: no redundant bluetoothctl loop in sysProbe
assert.match(control, /import Quickshell\.Bluetooth/);
assert.match(control, /BluetoothStatus\.resolve\(st\.btAdapter\)/);
assert.doesNotMatch(control, /bluetoothctl info/);
assert.doesNotMatch(control, /bluetoothctl show.*Powered/);

// Settings Hub contract
assert.match(settings, /import Quickshell\.Bluetooth/);
assert.match(settings, /BluetoothStatus\.resolve\(root\.adapter\)/);
assert.match(settings, /badge:\s*!root\.btAvailable/);

console.log("Bluetooth native status bindings and action routing passed.");

