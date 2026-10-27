.pragma library

// Loaded numeric settings are clamped to the ranges the UI and brain support:
// scale 2..6 (integer), activity 0.4..2, sleepAfter 20..600 (integer),
// energy/mood 0..100, steps/sleepSeconds 0..MAX_SAFE_INTEGER, pets 0..INT_MAX.
// Non-finite, missing or wrongly typed values use the existing/default value.

var MAX_SAFE_INTEGER = 9007199254740991;
var MAX_INT = 2147483647;
var BOOL_KEYS = ["enabled", "roam", "windowEdges", "followCursor", "reactMusic", "sleepWhenIdle",
    "hideFullscreen", "respawnOnWorkspace", "reactAlerts"];

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function real(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, value));
}

function integer(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, Math.round(value)));
}

function normalize(o, fallback) {
    var out = {};
    out.character = typeof o.character === "string" ? o.character : fallback.character;
    out.petName = typeof o.petName === "string" ? o.petName : fallback.petName;
    out.scale = integer(o.scale, fallback.scale, 2, 6);
    out.activity = real(o.activity, fallback.activity, 0.4, 2);
    for (var i = 0; i < BOOL_KEYS.length; i++) {
        var k = BOOL_KEYS[i];
        out[k] = typeof o[k] === "boolean" ? o[k] : fallback[k];
    }
    out.sleepAfter = integer(o.sleepAfter, fallback.sleepAfter, 20, 600);
    out.energy = real(o.energy, fallback.energy, 0, 100);
    out.mood = real(o.mood, fallback.mood, 0, 100);
    out.steps = real(o.steps, fallback.steps, 0, MAX_SAFE_INTEGER);
    out.pets = integer(o.pets, fallback.pets, 0, MAX_INT);
    out.sleepSeconds = real(o.sleepSeconds, fallback.sleepSeconds, 0, MAX_SAFE_INTEGER);
    return out;
}

function parse(text, fallback) {
    var o;
    try { o = JSON.parse(text); } catch (e) { return null; }
    if (!o || typeof o !== "object" || Array.isArray(o)) return null;
    return normalize(o, fallback);
}
