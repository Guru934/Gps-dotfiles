// Pure logic for system event detection, thresholds, hysteresis, debounce and DND rules.
// No QML dependencies; fully testable under Node.js and in QML.

const DEFAULT_EVENTS_SETTINGS = {
    batteryLowThreshold: 20,
    batteryCriticalThreshold: 8,
    criticalAction: "none", // "none" | "suspend"
    hysteresisMargin: 3,    // 3% margin to re-arm thresholds
    notifyBatteryLow: true,
    notifyBatteryCritical: true,
    notifyPowerPlug: true,
    notifyPowerUnplug: true,
    notifyFullyCharged: true,
    soundBatteryLow: true,
    soundBatteryCritical: true,
    soundPowerPlug: true,
    soundPowerUnplug: true,
    soundFullyCharged: false,
    // Device settings
    notifyUsb: true,
    notifyBluetooth: true,
    notifyWifi: true,
    soundUsb: true,
    soundBluetooth: true,
    soundWifi: false
};

function normalizePercentage(raw) {
    if (typeof raw !== "number" || isNaN(raw)) return 0;
    const pct = raw <= 1.0 ? Math.round(raw * 100) : Math.round(raw);
    return Math.max(0, Math.min(100, pct));
}

function mergeSettings(userSettings) {
    const s = Object.assign({}, DEFAULT_EVENTS_SETTINGS);
    if (!userSettings || typeof userSettings !== "object") return s;
    for (const k of Object.keys(userSettings)) {
        if (userSettings[k] !== undefined) {
            s[k] = userSettings[k];
        }
    }
    return s;
}

function createInitialPowerState() {
    return {
        initialized: false,
        lastOnBattery: null,
        lastPercentage: null,
        lastState: null,
        dischargingLevel: "normal", // "normal" | "low" | "critical"
        fullyChargedFired: false
    };
}

/**
 * Evaluates power changes from UPower and returns actions to take.
 *
 * @param {Object} current - { percentage, onBattery, state, isPresent }
 * @param {Object} prevState - Current state tracker
 * @param {Object} userSettings - Configuration overrides
 * @param {boolean} dndActive - Whether Do Not Disturb is active
 * @returns {Object} { state: newState, actions: Array<{type, ...}> }
 */
function evaluatePower(current, prevState, userSettings, dndActive) {
    const settings = mergeSettings(userSettings);
    const state = Object.assign({}, prevState || createInitialPowerState());
    const actions = [];

    if (!current || current.isPresent === false) {
        return { state: state, actions: actions };
    }

    const pct = normalizePercentage(current.percentage);
    const onBattery = !!current.onBattery;
    const devState = current.state !== undefined ? current.state : 0;

    // First run initialization without false crossings
    if (!state.initialized) {
        state.initialized = true;
        state.lastOnBattery = onBattery;
        state.lastPercentage = pct;
        state.lastState = devState;
        if (onBattery) {
            if (pct <= settings.batteryCriticalThreshold) {
                state.dischargingLevel = "critical";
            } else if (pct <= settings.batteryLowThreshold) {
                state.dischargingLevel = "low";
            } else {
                state.dischargingLevel = "normal";
            }
        } else {
            state.dischargingLevel = "normal";
            state.fullyChargedFired = (pct >= 100 || devState === 4);
        }
        return { state: state, actions: actions };
    }

    const wasOnBattery = state.lastOnBattery;
    state.lastPercentage = pct;
    state.lastState = devState;
    state.lastOnBattery = onBattery;

    // 1. AC Plug / Unplug Transitions
    if (wasOnBattery !== null && wasOnBattery !== onBattery) {
        if (onBattery) {
            // Unplugged (switched to battery)
            state.fullyChargedFired = false;
            // Determine initial discharging level on unplug
            if (pct <= settings.batteryCriticalThreshold) {
                state.dischargingLevel = "critical";
            } else if (pct <= settings.batteryLowThreshold) {
                state.dischargingLevel = "low";
            } else {
                state.dischargingLevel = "normal";
            }

            if (settings.notifyPowerUnplug) {
                actions.push({
                    type: "notification",
                    app: "System",
                    summary: "Power Disconnected",
                    body: "Running on battery (" + pct + "%)",
                    urgency: "normal",
                    icon: "battery-alert"
                });
            }
            if (settings.soundPowerUnplug && !dndActive) {
                actions.push({
                    type: "sound",
                    event: "unplug"
                });
            }
        } else {
            // Plugged in (connected to AC)
            state.dischargingLevel = "normal"; // Re-arm low/critical for next discharge cycle

            if (settings.notifyPowerPlug) {
                actions.push({
                    type: "notification",
                    app: "System",
                    summary: "Power Connected",
                    body: "Charging (" + pct + "%)",
                    urgency: "normal",
                    icon: "battery-charging"
                });
            }
            if (settings.soundPowerPlug && !dndActive) {
                actions.push({
                    type: "sound",
                    event: "plug"
                });
            }
        }
    }

    // 2. Discharging alerts & hysteresis
    if (onBattery) {
        if (pct <= settings.batteryCriticalThreshold) {
            if (state.dischargingLevel !== "critical") {
                state.dischargingLevel = "critical";

                if (settings.notifyBatteryCritical) {
                    actions.push({
                        type: "notification",
                        app: "System",
                        summary: "Battery Critical",
                        body: pct + "% remaining. Connect charger immediately.",
                        urgency: "critical",
                        icon: "battery-caution"
                    });
                }
                // Sound for critical ALWAYS plays (even during DND)
                if (settings.soundBatteryCritical) {
                    actions.push({
                        type: "sound",
                        event: "critical",
                        bypassDnd: true
                    });
                }
                if (settings.criticalAction === "suspend") {
                    actions.push({
                        type: "system",
                        action: "suspend"
                    });
                }
            }
        } else if (pct <= settings.batteryLowThreshold) {
            if (state.dischargingLevel === "normal") {
                state.dischargingLevel = "low";

                if (settings.notifyBatteryLow) {
                    actions.push({
                        type: "notification",
                        app: "System",
                        summary: "Battery Low",
                        body: pct + "% remaining.",
                        urgency: "normal",
                        icon: "battery-low"
                    });
                }
                if (settings.soundBatteryLow && !dndActive) {
                    actions.push({
                        type: "sound",
                        event: "battery-low"
                    });
                }
            }
        } else {
            // Check hysteresis re-arming
            const lowReArm = settings.batteryLowThreshold + settings.hysteresisMargin;
            if (pct >= lowReArm && state.dischargingLevel !== "normal") {
                state.dischargingLevel = "normal";
            }
        }

        // Hysteresis between critical and low
        const critReArm = settings.batteryCriticalThreshold + settings.hysteresisMargin;
        if (state.dischargingLevel === "critical" && pct >= critReArm && pct <= settings.batteryLowThreshold) {
            state.dischargingLevel = "low";
        }
    } else {
        // 3. Fully charged alert while on AC
        const isFull = (pct >= 100 || devState === 4); // 4 = FullyCharged
        if (isFull && !state.fullyChargedFired) {
            state.fullyChargedFired = true;

            if (settings.notifyFullyCharged) {
                actions.push({
                    type: "notification",
                    app: "System",
                    summary: "Battery Fully Charged",
                    body: "100% charged.",
                    urgency: "low",
                    icon: "battery-full"
                });
            }
            if (settings.soundFullyCharged && !dndActive) {
                actions.push({
                    type: "sound",
                    event: "notification"
                });
            }
        } else if (pct < (100 - settings.hysteresisMargin)) {
            // Re-arm fully charged alert if percentage drops
            state.fullyChargedFired = false;
        }
    }

    return {
        state: state,
        actions: actions
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_EVENTS_SETTINGS,
        normalizePercentage,
        mergeSettings,
        createInitialPowerState,
        evaluatePower
    };
}
