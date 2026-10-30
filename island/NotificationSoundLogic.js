// Pure logic for notification sound hints, freedesktop name mappings, and sound-file path allowlisting.
// No QML dependencies; fully testable in node.js and python.

const FREEDESKTOP_SOUND_MAP = {
    "message-new-instant": "notification",
    "message-new-email": "notification",
    "message": "notification",
    "dialog-information": "notification",
    "window-attention": "notification",
    "dialog-warning": "notification",
    "dialog-error": "error",
    "suspend-error": "error",
    "bell": "reminder",
    "alarm-clock-elapsed": "reminder",
    "complete": "download-done",
    "battery-low": "battery-low",
    "battery-caution": "battery-low",
    "power-plug": "plug",
    "power-unplug": "unplug",
    "device-added": "device-connect",
    "device-removed": "device-disconnect"
};

const ALLOWED_SOUND_DIRS = [
    "/usr/share/sounds",
    "/usr/local/share/sounds"
];

function isSuppressSound(hints) {
    if (!hints || typeof hints !== "object") return false;
    const val = hints["suppress-sound"] !== undefined ? hints["suppress-sound"] : hints["suppress_sound"];
    return val === true || val === 1 || val === "1" || val === "true";
}

function mapSoundName(name, defaultEvent) {
    if (typeof name !== "string") return defaultEvent;
    const clean = name.trim().toLowerCase();
    if (FREEDESKTOP_SOUND_MAP[clean]) {
        return FREEDESKTOP_SOUND_MAP[clean];
    }
    return defaultEvent;
}

function validateSoundFile(filePath, extraAllowedDirs) {
    if (typeof filePath !== "string" || !filePath) return null;
    let clean = filePath.trim();
    if (clean.startsWith("file://")) clean = clean.slice(7);
    if (clean.includes("..") || clean.includes("\0")) return null;
    if (!clean.startsWith("/")) return null;

    const allowed = ALLOWED_SOUND_DIRS.slice();
    if (Array.isArray(extraAllowedDirs)) {
        for (let i = 0; i < extraAllowedDirs.length; i++) {
            const dir = extraAllowedDirs[i];
            if (typeof dir === "string" && dir.startsWith("/")) allowed.push(dir);
        }
    }

    for (let i = 0; i < allowed.length; i++) {
        const dir = allowed[i];
        const prefix = dir.endsWith("/") ? dir : dir + "/";
        if (clean.startsWith(prefix) || clean === dir) {
            return clean;
        }
    }
    return null;
}

function resolveNotificationSound(n, options) {
    if (!n) return null;
    const hints = n.hints || {};

    if (isSuppressSound(hints)) {
        return null;
    }

    const isCrit = (n.urgency === 2 || n.urgency === "critical");
    let defaultEvent = isCrit ? "notification-critical" : "notification";

    const appName = (n.appName || "").trim().toLowerCase();
    const summary = (n.summary || "").trim().toLowerCase();
    if (appName === "planner" || summary === "task reminder") {
        defaultEvent = "reminder";
    }

    // 1. sound-file hint
    let soundFile = null;
    const rawFile = hints["sound-file"] !== undefined ? hints["sound-file"] : hints["sound_file"];
    if (rawFile) {
        const extraDirs = [];
        if (options && options.homeDir) {
            extraDirs.push(options.homeDir + "/.local/share/sounds");
            extraDirs.push(options.homeDir + "/.config/quickshell/sounds");
        }
        if (options && options.repoRoot) {
            extraDirs.push(options.repoRoot + "/assets/sounds");
        }
        soundFile = validateSoundFile(rawFile, extraDirs);
    }

    // 2. sound-name hint
    const rawName = hints["sound-name"] !== undefined ? hints["sound-name"] : hints["sound_name"];
    const event = mapSoundName(rawName, defaultEvent);

    return {
        event: event,
        soundFile: soundFile,
        isCritical: isCrit,
        dedupeKey: "notif:" + (n.id || "") + ":" + event
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FREEDESKTOP_SOUND_MAP,
        ALLOWED_SOUND_DIRS,
        isSuppressSound,
        mapSoundName,
        validateSoundFile,
        resolveNotificationSound
    };
}
