#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repo = path.resolve(__dirname, "..");
const read = relativePath => fs.readFileSync(path.join(repo, relativePath), "utf8");
const helperSource = read("components/WifiStatus.js").replace(/^\.pragma library\s*/, "");
const wifiStatus = {};
vm.runInNewContext(helperSource, wifiStatus);

function assertState(state, expected) {
    for (const [key, value] of Object.entries(expected)) {
        assert.equal(state[key], value, `${key} should reflect the native network state`);
    }
}

// 1. Backend unavailable
const unavailable = wifiStatus.resolve(false, [], true, 1);
assertState(unavailable, {
    available: false,
    enabled: false,
    connected: false,
    ssid: "Unavailable",
    device: ""
});

// 2. No wifi device present
const noWifiDevice = wifiStatus.resolve(true, [{ type: 2, name: "eth0" }], true, 1);
assertState(noWifiDevice, { available: false, ssid: "Unavailable" });

// 3. Connected state
const wifiDevice = {
    type: 1,
    name: "wlan0",
    networks: {
        values: [
            { connected: false, name: "Cafe", signalStrength: 0.6 },
            { connected: true, name: "Home:5G", signalStrength: 0.83 }
        ]
    }
};
const connected = wifiStatus.resolve(true, [wifiDevice], true, 1);
assertState(connected, {
    available: true,
    enabled: true,
    connected: true,
    ssid: "Home:5G",
    device: "wlan0",
    signalStrength: 0.83
});

// 4. Disconnected state (radio enabled, no connection -> "Not Connected")
wifiDevice.networks.values[1].connected = false;
const disconnected = wifiStatus.resolve(true, [wifiDevice], true, 1);
assertState(disconnected, {
    available: true,
    enabled: true,
    connected: false,
    ssid: "Not Connected"
});
assert.notEqual(disconnected.ssid, "Wi-Fi Off");

// 5. Radio off (only when actually disabled -> "Wi-Fi Off")
const radioOff = wifiStatus.resolve(true, [wifiDevice], false, 1);
assertState(radioOff, {
    available: true,
    enabled: false,
    connected: false,
    ssid: "Wi-Fi Off"
});

// 6. Toggling state simulation
let simWifiEnabled = false;
let simStatus = wifiStatus.resolve(true, [wifiDevice], simWifiEnabled, 1);
assert.equal(simStatus.enabled, false);
assert.equal(simStatus.ssid, "Wi-Fi Off");

// Toggle on
simWifiEnabled = true;
simStatus = wifiStatus.resolve(true, [wifiDevice], simWifiEnabled, 1);
assert.equal(simStatus.enabled, true);
assert.equal(simStatus.ssid, "Not Connected");

// Connect to SSID
wifiDevice.networks.values[0].connected = true;
simStatus = wifiStatus.resolve(true, [wifiDevice], simWifiEnabled, 1);
assert.equal(simStatus.connected, true);
assert.equal(simStatus.ssid, "Cafe");

const shell = read("shell.qml");
const rail = read("components/LeftRail.qml");
const popup = read("components/WifiPopup.qml");
const home = read("components/dashboard/HomeTab.qml");
const settings = read("settings.qml");

// Shell Wi-Fi contract
assert.match(shell, /Networking\.backend !== NetworkBackendType\.None/);
assert.match(shell, /onWifiStatusChanged:\s*root\.checkWifiPending\(\)/);
assert.doesNotMatch(shell, /id:\s*nmcliProc\b|id:\s*wifiRadioProc\b|function parseNmcli\b/);
assert.doesNotMatch(shell, /nmcli",\s*"-t",\s*"-f",\s*"DEVICE,TYPE,STATE,CONNECTION"/);
assert.doesNotMatch(shell, /nmcli",\s*"radio",\s*"wifi"\s*\]/);
assert.doesNotMatch(shell, /refreshWifiReads|wifiVerifyTries/);
assert.match(shell, /"-f",\s*"SSID,SIGNAL,SECURITY"/);
assert.doesNotMatch(shell, /IN-USE|active:\s*inUse/);
assert.match(shell, /wifiCmdProc\.command = \["nmcli", "radio", "wifi", target\]/);
assert.match(shell, /wifiCmdProc\.command = \["nmcli", "device", "wifi", "connect", ssid\]/);
assert.match(shell, /wifiCmdProc\.command = \["nmcli", "device", "disconnect", root\.netDevice\]/);
assert.match(shell, /root\.wifiStatusAvailable\)\s*return false/);

// LeftRail Wi-Fi contract
assert.match(rail, /root\.hub\.wifiConnected/);
assert.doesNotMatch(rail, /wifi_line|wifi_radio|nmcli/);

// WifiPopup contract
assert.match(popup, /root\.hub\.netName === modelData\.ssid/);
assert.match(popup, /root\.hub\.disconnectWifi\(\)/);
assert.match(popup, /root\.hub\.connectWifi\(modelData\.ssid, modelData\.secured\)/);
assert.doesNotMatch(popup, /modelData\.active/);

// HomeTab Wi-Fi contract (interactive guarded)
assert.match(home, /WifiStatus\.resolve\(/);
assert.match(home, /Networking\.wifiEnabled/);
assert.match(home, /interactive:\s*root\.wifiStatus\.available/);
assert.match(home, /dimmed:\s*!root\.wifiStatus\.available/);
assert.match(home, /if\s*\(root\.wifiStatus\.available\)\s*\{\s*Networking\.wifiEnabled = !Networking\.wifiEnabled/);

// Settings Hub Wi-Fi contract
assert.match(settings, /import Quickshell\.Networking/);
assert.match(settings, /WifiStatus\.resolve\(/);
assert.match(settings, /readonly property bool wifiAvailable:\s*root\.wifiStatus\.available/);
assert.match(settings, /readonly property bool wifiEnabled:\s*root\.wifiStatus\.available && root\.wifiStatus\.enabled/);
assert.match(settings, /readonly property bool wifiConnected:\s*root\.wifiStatus\.connected/);
assert.match(settings, /readonly property string wifiSsid:\s*root\.wifiStatus\.ssid/);
assert.doesNotMatch(settings, /property string wifiRadio: ""/);
assert.match(settings, /badge:\s*!root\.wifiAvailable/);
assert.match(settings, /Networking\.wifiEnabled = v/);
assert.match(settings, /nmcli -w 20 dev wifi connect/);
assert.match(settings, /nmcli dev disconnect/);

console.log("Wi-Fi native status bindings, Settings Hub reactive state, and action routing passed.");
