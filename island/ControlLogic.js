// ControlLogic.js — Pure logic helpers for GPS Island Control Center
// Works in both Node.js (unit tests) and QML / Quickshell environments.

(function (root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.ControlLogic = factory();
    }
}(typeof self !== "undefined" ? self : this, function () {
    "use strict";

    const DEFAULT_PROFILES = ["power-saver", "balanced", "performance"];

    const DEFAULT_TILES = [
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
        const trimmed = rawText.trim();
        if (trimmed === "") return DEFAULT_PROFILES.slice();

        // If space-separated string (e.g. /sys/firmware/acpi/platform_profile_choices)
        if (!trimmed.includes("\n") && !trimmed.includes(":")) {
            const parts = trimmed.split(/\s+/).filter(Boolean);
            return parts.length > 0 ? parts : DEFAULT_PROFILES.slice();
        }

        // powerprofilesctl list output format:
        //   performance:
        //     CpuDriver: ...
        // * balanced:
        //     ...
        const found = [];
        const lines = trimmed.split("\n");
        for (const line of lines) {
            const m = line.match(/^[\s\*]*([a-zA-Z0-9_\-]+):\s*$/);
            if (m && m[1]) {
                const name = m[1].trim().toLowerCase();
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
        const list = Array.isArray(availableProfiles) && availableProfiles.length > 0
            ? availableProfiles
            : DEFAULT_PROFILES;
        const cur = (currentProfile || "").trim().toLowerCase();
        const idx = list.indexOf(cur);
        if (idx < 0) return list[0];
        return list[(idx + 1) % list.length];
    }

    /**
     * Format battery time remaining.
     */
    function formatBatteryTime(seconds, charging) {
        if (typeof seconds !== "number" || !isFinite(seconds) || seconds <= 60) return "";
        const totalMinutes = Math.floor(seconds / 60);
        const h = Math.floor(totalMinutes / 60);
        const m = totalMinutes % 60;
        const timeStr = h > 0 ? (h + "h " + (m > 0 ? m + "m" : "")) : (m + "m");
        return charging ? (timeStr.trim() + " to full") : (timeStr.trim() + " left");
    }

    /**
     * Calculate minutes from now until the next occurrence of targetHour:targetMinute.
     */
    function calcMinutesUntilNext(targetHour, targetMinute, nowMs) {
        const now = new Date(typeof nowMs === "number" ? nowMs : Date.now());
        const target = new Date(now.getTime());
        target.setHours(targetHour, targetMinute || 0, 0, 0);
        if (target.getTime() <= now.getTime()) {
            target.setDate(target.getDate() + 1);
        }
        const diffMs = target.getTime() - now.getTime();
        return Math.max(1, Math.round(diffMs / 60000));
    }

    /**
     * Generate human-readable subtitle for Do Not Disturb tile.
     */
    function formatDndSubText(dndState, isDnd, nowMs) {
        if (!isDnd) return "Off";
        const now = typeof nowMs === "number" ? nowMs : Date.now();
        if (dndState && dndState.mode === "snooze" && dndState.snoozeUntil) {
            const diffMin = Math.ceil((dndState.snoozeUntil - now) / 60000);
            if (diffMin > 0) {
                if (diffMin >= 60) {
                    const h = Math.floor(diffMin / 60);
                    const m = diffMin % 60;
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
     * When disabling game mode, restores from snapshot.
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
        // Restore from snapshot or safe defaults
        const snap = snapshot || {};
        const anim = snap.animations_enabled !== undefined ? Boolean(snap.animations_enabled) : true;
        const blur = snap.blur_enabled !== undefined ? Boolean(snap.blur_enabled) : true;
        const shadow = snap.shadow_enabled !== undefined ? Boolean(snap.shadow_enabled) : true;
        const gapsIn = typeof snap.gaps_in === "number" ? Math.max(0, snap.gaps_in) : 5;
        const gapsOut = typeof snap.gaps_out === "number" ? Math.max(0, snap.gaps_out) : 20;

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
            const first = val.trim().split(/\s+/)[0];
            const n = parseInt(first, 10);
            if (!isNaN(n)) return n;
        }
        return fallback;
    }

    /**
     * Validate and merge customized controlTiles settings.
     */
    function validateControlTiles(configuredTiles) {
        const defaults = DEFAULT_TILES.map(t => Object.assign({}, t));
        if (!Array.isArray(configuredTiles) || configuredTiles.length === 0) {
            return defaults;
        }

        const validIds = new Set(defaults.map(t => t.id));
        const result = [];
        const seen = new Set();

        for (const item of configuredTiles) {
            if (!item || typeof item !== "object") continue;
            const id = typeof item.id === "string" ? item.id.trim().toLowerCase() : "";
            if (!validIds.has(id) || seen.has(id)) continue;
            seen.add(id);

            const def = defaults.find(t => t.id === id);
            result.push({
                id: id,
                title: typeof item.title === "string" && item.title.trim() !== "" ? item.title : def.title,
                enabled: typeof item.enabled === "boolean" ? item.enabled : true
            });
        }

        // Append any default tiles not present in configured list
        for (const def of defaults) {
            if (!seen.has(def.id)) {
                result.push(Object.assign({}, def));
                seen.add(def.id);
            }
        }

        return result;
    }

    return {
        DEFAULT_PROFILES: DEFAULT_PROFILES,
        DEFAULT_TILES: DEFAULT_TILES,
        parseProfiles: parseProfiles,
        cycleProfile: cycleProfile,
        formatBatteryTime: formatBatteryTime,
        calcMinutesUntilNext: calcMinutesUntilNext,
        formatDndSubText: formatDndSubText,
        buildGameModeLua: buildGameModeLua,
        parseGapsValue: parseGapsValue,
        validateControlTiles: validateControlTiles
    };
}));
