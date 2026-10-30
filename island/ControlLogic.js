// ControlLogic.js — Pure logic helpers for GPS Island Control Center
// Works in both QML and Node.js.

var DEFAULT_PROFILES = ["power-saver", "balanced", "performance"];

var DEFAULT_TILES = [
    { id: "wifi", title: "Wi-Fi", enabled: true },
    { id: "bluetooth", title: "Bluetooth", enabled: true },
    { id: "dnd", title: "Do not disturb", enabled: true },
    { id: "idle", title: "Idle lock", enabled: true },
    { id: "keepawake", title: "Keep awake", enabled: true },
    { id: "flight", title: "Flight mode", enabled: true },
    { id: "nightlight", title: "Night light", enabled: true },
    { id: "gamemode", title: "Game mode", enabled: true },
    { id: "powerprofile", title: "Power profile", enabled: true },
    { id: "mic", title: "Microphone", enabled: true },
    { id: "screenshot", title: "Screenshot", enabled: true },
    { id: "record", title: "Record", enabled: true }
];

/**
 * Parse available power profiles from powerprofilesctl list or kernel string.
 */
function parseProfiles(rawText) {
    if (!rawText || typeof rawText !== "string") return DEFAULT_PROFILES.slice();
    var trimmed = rawText.trim();
    if (trimmed === "") return DEFAULT_PROFILES.slice();

    if (!trimmed.includes("\n") && !trimmed.includes(":")) {
        var parts = trimmed.split(/\s+/).filter(Boolean);
        return parts.length > 0 ? parts : DEFAULT_PROFILES.slice();
    }

    var found = [];
    var lines = trimmed.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var m = line.match(/^[\s\*]*([a-zA-Z0-9_\-]+):\s*$/);
        if (m && m[1]) {
            var name = m[1].trim().toLowerCase();
            if (!found.includes(name)) {
                found.push(name);
            }
        }
    }
    return found.length > 0 ? found : DEFAULT_PROFILES.slice();
}

/**
 * Cycle through available profiles in order.
 */
function cycleProfile(currentProfile, availableProfiles) {
    var list = Array.isArray(availableProfiles) && availableProfiles.length > 0
        ? availableProfiles
        : DEFAULT_PROFILES;
    var cur = (currentProfile || "").trim().toLowerCase();
    var idx = list.indexOf(cur);
    if (idx < 0) return list[0];
    return list[(idx + 1) % list.length];
}

/**
 * Format battery time remaining.
 */
function formatBatteryTime(seconds, charging) {
    if (typeof seconds !== "number" || !isFinite(seconds) || seconds <= 60) return "";
    var totalMinutes = Math.floor(seconds / 60);
    var h = Math.floor(totalMinutes / 60);
    var m = totalMinutes % 60;
    var timeStr = h > 0 ? (h + "h " + (m > 0 ? m + "m" : "")) : (m + "m");
    return charging ? (timeStr.trim() + " to full") : (timeStr.trim() + " left");
}

/**
 * Calculate minutes from now until the next occurrence of targetHour:targetMinute.
 */
function calcMinutesUntilNext(targetHour, targetMinute, nowMs) {
    var now = new Date(typeof nowMs === "number" ? nowMs : Date.now());
    var target = new Date(now.getTime());
    target.setHours(targetHour, targetMinute || 0, 0, 0);
    if (target.getTime() <= now.getTime()) {
        target.setDate(target.getDate() + 1);
    }
    var diffMs = target.getTime() - now.getTime();
    return Math.max(1, Math.round(diffMs / 60000));
}

/**
 * Generate human-readable subtitle for Do Not Disturb tile.
 */
function formatDndSubText(dndState, isDnd, nowMs) {
    if (!isDnd) return "Off";
    var now = typeof nowMs === "number" ? nowMs : Date.now();
    if (dndState && dndState.mode === "snooze" && dndState.snoozeUntil) {
        var diffMin = Math.ceil((dndState.snoozeUntil - now) / 60000);
        if (diffMin > 0) {
            if (diffMin >= 60) {
                var h = Math.floor(diffMin / 60);
                var m = diffMin % 60;
                return h + "h " + (m > 0 ? (m + "m ") : "") + "left";
            }
            return diffMin + " min left";
        }
    }
    if (dndState && dndState.mode === "schedule" && dndState.schedule && dndState.schedule.enabled) {
        return "Scheduled (" + dndState.schedule.to + ")";
    }
    return "On";
}

/**
 * Generate Lua configuration script for Hyprland Game Mode.
 */
function buildGameModeLua(enable, snapshot) {
    if (enable) {
        return "hl.config({ " +
            "animations = { enabled = false }, " +
            "decoration = { " +
                "blur = { enabled = false }, " +
                "shadow = { enabled = false } " +
            "}, " +
            "general = { gaps_in = 0, gaps_out = 0 } " +
        "})";
    }
    var snap = snapshot || {};
    var anim = snap.animations_enabled !== undefined ? Boolean(snap.animations_enabled) : true;
    var blur = snap.blur_enabled !== undefined ? Boolean(snap.blur_enabled) : true;
    var shadow = snap.shadow_enabled !== undefined ? Boolean(snap.shadow_enabled) : true;
    var gapsIn = typeof snap.gaps_in === "number" ? Math.max(0, snap.gaps_in) : 5;
    var gapsOut = typeof snap.gaps_out === "number" ? Math.max(0, snap.gaps_out) : 20;

    return "hl.config({ " +
        "animations = { enabled = " + (anim ? "true" : "false") + " }, " +
        "decoration = { " +
            "blur = { enabled = " + (blur ? "true" : "false") + " }, " +
            "shadow = { enabled = " + (shadow ? "true" : "false") + " } " +
        "}, " +
        "general = { gaps_in = " + gapsIn + ", gaps_out = " + gapsOut + " } " +
    "})";
}

/**
 * Parse gaps CSS/int string like "5 5 5 5" or "5" into an integer.
 */
function parseGapsValue(val, fallback) {
    if (typeof val === "number" && !isNaN(val)) return val;
    if (typeof val === "string") {
        var first = val.trim().split(/\s+/)[0];
        var n = parseInt(first, 10);
        if (!isNaN(n)) return n;
    }
    return fallback;
}

/**
 * Validate and merge customized controlTiles settings.
 */
function validateControlTiles(configuredTiles) {
    var defaults = DEFAULT_TILES.map(function(t) { return Object.assign({}, t); });
    if (!Array.isArray(configuredTiles) || configuredTiles.length === 0) {
        return defaults;
    }

    var validIds = new Set(defaults.map(function(t) { return t.id; }));
    var result = [];
    var seen = new Set();

    for (var i = 0; i < configuredTiles.length; i++) {
        var item = configuredTiles[i];
        if (!item || typeof item !== "object") continue;
        var id = typeof item.id === "string" ? item.id.trim().toLowerCase() : "";
        if (!validIds.has(id) || seen.has(id)) continue;
        seen.add(id);

        var def = defaults.find(function(t) { return t.id === id; });
        result.push({
            id: id,
            title: typeof item.title === "string" && item.title.trim() !== "" ? item.title : def.title,
            enabled: typeof item.enabled === "boolean" ? item.enabled : true
        });
    }

    for (var j = 0; j < defaults.length; j++) {
        var d = defaults[j];
        if (!seen.has(d.id)) {
            result.push(Object.assign({}, d));
            seen.add(d.id);
        }
    }

    return result;
}

/**
 * Move a tile up or down in the ordered list.
 */
function moveTile(tiles, fromIndex, toIndex) {
    if (!Array.isArray(tiles)) return [];
    var copy = tiles.slice();
    if (fromIndex < 0 || fromIndex >= copy.length || toIndex < 0 || toIndex >= copy.length || fromIndex === toIndex) {
        return copy;
    }
    var item = copy.splice(fromIndex, 1)[0];
    copy.splice(toIndex, 0, item);
    return copy;
}

/**
 * Toggle enabled flag for a tile.
 */
function toggleTileEnabled(tiles, tileId) {
    if (!Array.isArray(tiles)) return [];
    return tiles.map(function(t) {
        if (t.id === tileId) {
            return Object.assign({}, t, { enabled: !t.enabled });
        }
        return Object.assign({}, t);
    });
}

/**
 * Parse and deserialize JSON into validated control tiles.
 */
function deserializeControlTiles(jsonString) {
    if (!jsonString || typeof jsonString !== "string") {
        return DEFAULT_TILES.map(function(t) { return Object.assign({}, t); });
    }
    try {
        var parsed = JSON.parse(jsonString);
        return validateControlTiles(parsed);
    } catch (e) {
        return DEFAULT_TILES.map(function(t) { return Object.assign({}, t); });
    }
}

/**
 * Serialize control tiles to formatted JSON.
 */
function serializeControlTiles(tiles) {
    var validated = validateControlTiles(tiles);
    return JSON.stringify(validated, null, 2);
}

/**
 * Parse CPU usage percentage from /proc/stat ticks.
 */
function parseCpuUsage(rawNumbers, prevCpu) {
    if (!Array.isArray(rawNumbers) || rawNumbers.length < 4) return { usage: -1, prev: null };
    var idle = rawNumbers[3] + (rawNumbers[4] || 0);
    var total = 0;
    for (var i = 0; i < rawNumbers.length; i++) total += rawNumbers[i];
    var usage = -1;
    if (prevCpu && typeof prevCpu.total === "number") {
        var dTotal = total - prevCpu.total;
        var dIdle = idle - prevCpu.idle;
        if (dTotal > 0) {
            usage = Math.max(0, Math.min(100, Math.round(100 * (1 - dIdle / dTotal))));
        }
    }
    return { usage: usage, prev: { total: total, idle: idle } };
}

/**
 * Parse memory usage from MemTotal and MemAvailable in KB.
 */
function parseMemUsage(totalKb, availKb) {
    if (typeof totalKb !== "number" || typeof availKb !== "number" || totalKb <= 0) {
        return { usedGiB: 0, totalGiB: 0, pct: 0 };
    }
    var totalGiB = totalKb / 1048576;
    var usedGiB = Math.max(0, (totalKb - availKb)) / 1048576;
    var pct = Math.max(0, Math.min(100, Math.round(100 * (totalKb - availKb) / totalKb)));
    return { usedGiB: usedGiB, totalGiB: totalGiB, pct: pct };
}

/**
 * Parse thermal millidegree Celsius reading to degrees Celsius.
 */
function parseTempC(rawTemp) {
    var v = parseInt(rawTemp, 10);
    if (isNaN(v) || v <= 0) return -1;
    return v > 1000 ? Math.round(v / 1000) : v;
}

/**
 * Format milliseconds into m:ss or h:mm:ss.
 */
function formatDuration(ms) {
    if (typeof ms !== "number" || !isFinite(ms) || ms < 0) return "0:00";
    var total = Math.floor(ms / 1000);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var ss = (s < 10 ? "0" : "") + s;
    return h > 0 ? (h + ":" + (m < 10 ? "0" : "") + m + ":" + ss) : (m + ":" + ss);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_PROFILES: DEFAULT_PROFILES,
        DEFAULT_TILES: DEFAULT_TILES,
        parseProfiles: parseProfiles,
        cycleProfile: cycleProfile,
        formatBatteryTime: formatBatteryTime,
        calcMinutesUntilNext: calcMinutesUntilNext,
        formatDndSubText: formatDndSubText,
        buildGameModeLua: buildGameModeLua,
        parseGapsValue: parseGapsValue,
        validateControlTiles: validateControlTiles,
        moveTile: moveTile,
        toggleTileEnabled: toggleTileEnabled,
        deserializeControlTiles: deserializeControlTiles,
        serializeControlTiles: serializeControlTiles,
        parseCpuUsage: parseCpuUsage,
        parseMemUsage: parseMemUsage,
        parseTempC: parseTempC,
        formatDuration: formatDuration
    };
}
