.pragma library

// Pure download-job validation, formatting and persistence helpers for the
// Media Hub Downloads page. Network/process work lives in
// scripts/media-hub-downloads.py; this module only validates data crossing the
// QML boundary or restored from disk.

var MAX_JOBS = 200;
var MAX_TEXT = 300;
var MAX_URL = 4096;
var MAX_PATH = 4096;
var MAX_ERROR = 400;
var MAX_PLAYLIST_ITEMS = 100;
var MAX_ATTEMPTS = 5;
var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$/;
var FORMAT_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
var ERROR_CODE_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
var HOST_RE = /^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/;
var STATUSES = ["inspecting", "queued", "downloading", "postprocessing", "paused", "completed", "failed", "cancelled"];
var ACTIVE = ["inspecting", "downloading", "postprocessing"];
var TERMINAL = ["completed", "failed", "cancelled"];
var MODES = ["video", "audio"];
var SCOPES = ["single", "selected", "full"];
var CONTAINERS = ["Auto", "MP4", "MKV", "WebM"];
var AUDIO_FORMATS = ["original", "mp3", "m4a", "flac", "opus"];
var AUDIO_QUALITIES = ["best", "320k", "256k", "192k", "128k"];

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function isArrayLike(value) {
    return value !== null && typeof value === "object"
        && isNumber(value.length) && value.length >= 0;
}

function toArray(value) {
    if (!isArrayLike(value)) return [];
    var out = [];
    for (var i = 0; i < value.length; i++) out.push(value[i]);
    return out;
}

function cleanText(value, limit) {
    if (typeof value !== "string") return "";
    var text = value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, limit || MAX_TEXT);
}

function cleanUrl(value) {
    if (typeof value !== "string") return "";
    var raw = value.trim();
    if (raw.length < 8 || raw.length > MAX_URL) return "";
    if (/[\u0000-\u0020\u007f]/.test(raw)) return "";
    if (raw.indexOf("\\") >= 0) return "";
    var scheme = /^(https?):\/\//i.exec(raw);
    if (!scheme) return "";
    var rest = raw.slice(scheme[0].length);
    var authority = rest.split(/[/?#]/)[0];
    if (authority === "" || authority.indexOf("@") >= 0) return "";
    var host = "";
    if (authority.charAt(0) === "[") {
        var end = authority.indexOf("]");
        if (end < 1) return "";
        host = authority.slice(0, end + 1);
        var tail = authority.slice(end + 1);
        if (tail !== "" && !/^:[0-9]{1,5}$/.test(tail)) return "";
        if (tail !== "" && (Number(tail.slice(1)) < 1 || Number(tail.slice(1)) > 65535)) return "";
    } else {
        var colon = authority.lastIndexOf(":");
        var port = "";
        if (colon >= 0) {
            if (authority.indexOf(":") !== colon) return "";
            port = authority.slice(colon + 1);
            authority = authority.slice(0, colon);
            if (!/^[0-9]{1,5}$/.test(port)) return "";
            if (Number(port) < 1 || Number(port) > 65535) return "";
        }
        host = authority;
        if (!HOST_RE.test(host)) return "";
    }
    if (host === "" || host === "[]") return "";
    return raw;
}

function cleanPath(value) {
    if (typeof value !== "string") return "";
    var path = value.trim();
    if (path.length < 1 || path.length > MAX_PATH) return "";
    if (path.charAt(0) !== "/") return "";
    if (/[\u0000-\u001f\u007f]/.test(path)) return "";
    return path;
}

function cleanFormatId(value) {
    if (typeof value !== "string") return "";
    return FORMAT_ID_RE.test(value) ? value : "";
}

function integer(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, Math.floor(value)));
}

function real(value, fallback, min, max) {
    if (!isNumber(value)) return fallback;
    return Math.max(min, Math.min(max, value));
}

function boolean(value) {
    return value === true;
}

function normalizeAudioFormat(value) {
    var text = String(value || "").toLowerCase();
    return AUDIO_FORMATS.indexOf(text) >= 0 ? text : "original";
}

function normalizeAudioQuality(value) {
    var text = String(value || "").toLowerCase();
    return AUDIO_QUALITIES.indexOf(text) >= 0 ? text : "best";
}

function normalizeContainer(value) {
    var text = String(value || "").toLowerCase();
    for (var i = 0; i < CONTAINERS.length; i++)
        if (CONTAINERS[i].toLowerCase() === text) return CONTAINERS[i];
    return "Auto";
}

function validatePlaylistSpec(value) {
    if (typeof value !== "string") return { ok: false, count: 0, error: "Enter playlist item numbers." };
    var text = value.trim();
    if (text === "" || text.length > 200) return { ok: false, count: 0, error: "Enter playlist item numbers." };
    var parts = text.split(",");
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i].trim();
        var count = 0;
        var single = /^([0-9]{1,6})$/.exec(part);
        var range = /^([0-9]{1,6})-([0-9]{1,6})$/.exec(part);
        var slice = /^([0-9]{1,6}):([0-9]{1,6})(?::([0-9]{1,6}))?$/.exec(part);
        if (single) {
            if (Number(single[1]) < 1) return { ok: false, count: 0, error: "Item numbers start at 1." };
            count = 1;
        } else if (range) {
            var first = Number(range[1]);
            var last = Number(range[2]);
            if (first < 1 || last < first) return { ok: false, count: 0, error: "Check the playlist range." };
            count = last - first + 1;
        } else if (slice) {
            var start = Number(slice[1]);
            var stop = Number(slice[2]);
            var step = slice[3] ? Number(slice[3]) : 1;
            if (start < 1 || stop < start || step < 1) return { ok: false, count: 0, error: "Check the playlist range." };
            count = Math.floor((stop - start) / step) + 1;
        } else {
            return { ok: false, count: 0, error: "Use item numbers such as 1,3-5,7." };
        }
        total += count;
        if (total > MAX_PLAYLIST_ITEMS)
            return { ok: false, count: total, error: "Select at most " + MAX_PLAYLIST_ITEMS + " playlist items." };
    }
    if (total < 1) return { ok: false, count: 0, error: "Select at least one playlist item." };
    return { ok: true, count: total, error: "", spec: text };
}

function progressFraction(job) {
    if (!job) return 0;
    if (job.status === "completed") return 1;
    var downloaded = isNumber(job.downloadedBytes) ? job.downloadedBytes : 0;
    var total = isNumber(job.totalBytes) ? job.totalBytes : 0;
    if (downloaded > 0 && total > 0) return Math.max(0, Math.min(1, downloaded / total));
    if (isNumber(job.progress) && job.progress > 0) return Math.max(0, Math.min(1, job.progress));
    var index = isNumber(job.fragmentIndex) ? job.fragmentIndex : 0;
    var count = isNumber(job.fragmentCount) ? job.fragmentCount : 0;
    if (index > 0 && count > 0) return Math.max(0, Math.min(1, index / count));
    return 0;
}

function progressKnown(job) {
    if (!job) return false;
    if (job.status === "completed") return true;
    if (isNumber(job.totalBytes) && job.totalBytes > 0) return true;
    return isNumber(job.fragmentCount) && job.fragmentCount > 0;
}

function formatBytes(bytes) {
    if (!isNumber(bytes) || bytes <= 0) return "unknown size";
    var value = bytes;
    var units = ["B", "KB", "MB", "GB", "TB"];
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
        value /= 1024;
        index++;
    }
    return (index === 0 ? Math.round(value) : value.toFixed(value >= 100 ? 0 : 1)) + " " + units[index];
}

function formatSpeed(bytesPerSecond) {
    if (!isNumber(bytesPerSecond) || bytesPerSecond <= 0) return "";
    return formatBytes(bytesPerSecond) + "/s";
}

function formatEta(seconds) {
    if (!isNumber(seconds) || seconds < 0) return "";
    var value = Math.round(seconds);
    if (value < 60) return value + "s";
    var minutes = Math.floor(value / 60);
    var rest = value % 60;
    if (minutes < 60) return minutes + "m " + rest + "s";
    var hours = Math.floor(minutes / 60);
    minutes = minutes % 60;
    return hours + "h " + minutes + "m";
}

function formatDuration(seconds) {
    if (!isNumber(seconds) || seconds <= 0) return "";
    var value = Math.round(seconds);
    var hours = Math.floor(value / 3600);
    var minutes = Math.floor((value % 3600) / 60);
    var secs = value % 60;
    if (hours > 0) return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (secs < 10 ? "0" : "") + secs;
    return minutes + ":" + (secs < 10 ? "0" : "") + secs;
}

function statusLabel(job) {
    if (!job) return "";
    if (job.status === "failed" && job.interrupted === true) return "INTERRUPTED";
    if (job.status === "postprocessing") return "POST-PROCESSING";
    return String(job.status || "").toUpperCase();
}

function isActiveStatus(status) {
    return ACTIVE.indexOf(String(status || "")) >= 0;
}

function isTerminalStatus(status) {
    return TERMINAL.indexOf(String(status || "")) >= 0;
}

function canRetry(job) {
    if (!job) return false;
    if (job.status !== "failed" && job.status !== "cancelled") return false;
    return integer(job.attempts, 0, 0, 1000) < MAX_ATTEMPTS;
}

function nextQueuedIndex(jobs) {
    if (!isArrayLike(jobs)) return -1;
    for (var i = jobs.length - 1; i >= 0; i--)
        if (jobs[i] && jobs[i].status === "queued") return i;
    return -1;
}

function findJob(jobs, id) {
    if (!isArrayLike(jobs)) return null;
    for (var i = 0; i < jobs.length; i++)
        if (jobs[i] && jobs[i].id === id) return jobs[i];
    return null;
}

function sanitizeJob(raw) {
    if (!raw || typeof raw !== "object") return null;
    var id = typeof raw.id === "string" && ID_RE.test(raw.id) ? raw.id : "";
    if (id === "") return null;
    var url = cleanUrl(raw.url);
    if (url === "") return null;
    var status = STATUSES.indexOf(raw.status) >= 0 ? raw.status : "failed";
    var mode = MODES.indexOf(raw.mode) >= 0 ? raw.mode : "video";
    var dest = cleanPath(raw.dest);
    if (dest === "") return null;
    var scope = SCOPES.indexOf(raw.scope) >= 0 ? raw.scope : "single";
    var playlistItems = "";
    if (scope === "selected") {
        var checked = validatePlaylistSpec(raw.playlistItems);
        playlistItems = checked.ok ? checked.spec : "1";
    }
    var files = [];
    if (isArrayLike(raw.files)) {
        for (var i = 0; i < raw.files.length && i < MAX_PLAYLIST_ITEMS; i++) {
            var file = cleanPath(raw.files[i]);
            if (file !== "" && files.indexOf(file) < 0) files.push(file);
        }
    }
    var finalPath = cleanPath(raw.finalPath);
    if (finalPath === "" && files.length > 0) finalPath = files[0];
    return {
        id: id,
        url: url,
        title: cleanText(raw.title, MAX_TEXT) || "Untitled media",
        source: cleanText(raw.source, 120),
        uploader: cleanText(raw.uploader, 160),
        extractor: cleanText(raw.extractor, 120),
        thumbnail: cleanUrl(raw.thumbnail),
        duration: real(raw.duration, 0, 0, 864000),
        mode: mode,
        formatId: cleanFormatId(raw.formatId),
        formatHasAudio: boolean(raw.formatHasAudio),
        qualityCap: integer(raw.qualityCap, 0, 0, 10000),
        quality: cleanText(raw.quality, 60) || "Best",
        container: normalizeContainer(raw.container),
        audioFormat: normalizeAudioFormat(raw.audioFormat),
        audioQuality: normalizeAudioQuality(raw.audioQuality),
        scope: scope,
        playlistItems: playlistItems,
        playlistCount: integer(raw.playlistCount, 0, 0, 1000000),
        playlistTitle: cleanText(raw.playlistTitle, MAX_TEXT),
        dest: dest,
        status: status,
        statusDetail: cleanText(raw.statusDetail, 160),
        progress: real(raw.progress, 0, 0, 1),
        downloadedBytes: integer(raw.downloadedBytes, 0, 0, 9007199254740991),
        totalBytes: integer(raw.totalBytes, 0, 0, 9007199254740991),
        speed: real(raw.speed, 0, 0, 9007199254740991),
        eta: integer(raw.eta, 0, 0, 31536000),
        fragmentIndex: integer(raw.fragmentIndex, 0, 0, 100000000),
        fragmentCount: integer(raw.fragmentCount, 0, 0, 100000000),
        postprocessor: cleanText(raw.postprocessor, 120),
        finalPath: finalPath,
        files: files,
        error: cleanText(raw.error, MAX_ERROR),
        errorCode: typeof raw.errorCode === "string" && ERROR_CODE_RE.test(raw.errorCode) ? raw.errorCode : "",
        interrupted: raw.interrupted === true,
        attempts: integer(raw.attempts, 0, 0, MAX_ATTEMPTS),
        createdAt: integer(raw.createdAt, 0, 0, 9007199254740991),
        startedAt: integer(raw.startedAt, 0, 0, 9007199254740991),
        completedAt: integer(raw.completedAt, 0, 0, 9007199254740991),
        updatedAt: integer(raw.updatedAt, 0, 0, 9007199254740991)
    };
}

function createJob(request, now) {
    if (!request || typeof request !== "object") return null;
    var url = cleanUrl(request.url);
    if (url === "") return null;
    var dest = cleanPath(request.dest);
    if (dest === "") return null;
    var mode = MODES.indexOf(request.mode) >= 0 ? request.mode : "video";
    var scope = SCOPES.indexOf(request.scope) >= 0 ? request.scope : "single";
    var playlistItems = "";
    if (scope === "selected") {
        var checked = validatePlaylistSpec(request.playlistItems);
        if (!checked.ok) return null;
        playlistItems = checked.spec;
    }
    var stamp = isNumber(now) ? Math.floor(now) : Date.now();
    var id = typeof request.id === "string" && ID_RE.test(request.id)
        ? request.id
        : "dl-" + stamp.toString(36) + "-" + Math.floor(Math.random() * 0x1000000).toString(36);
    return sanitizeJob({
        id: id,
        url: url,
        title: request.title || "Untitled media",
        source: request.source || "",
        uploader: request.uploader || "",
        extractor: request.extractor || "",
        thumbnail: request.thumbnail || "",
        duration: request.duration || 0,
        mode: mode,
        formatId: request.formatId || "",
        formatHasAudio: request.formatHasAudio === true,
        qualityCap: request.qualityCap || 0,
        quality: request.quality || "Best",
        container: request.container || "Auto",
        audioFormat: request.audioFormat || "original",
        audioQuality: request.audioQuality || "best",
        scope: scope,
        playlistItems: playlistItems,
        playlistCount: request.playlistCount || 0,
        playlistTitle: request.playlistTitle || "",
        dest: dest,
        status: "queued",
        statusDetail: "Queued",
        progress: 0,
        downloadedBytes: 0,
        totalBytes: 0,
        speed: 0,
        eta: 0,
        fragmentIndex: 0,
        fragmentCount: 0,
        postprocessor: "",
        finalPath: "",
        files: [],
        error: "",
        errorCode: "",
        interrupted: false,
        attempts: 0,
        createdAt: stamp,
        startedAt: 0,
        completedAt: 0,
        updatedAt: stamp
    });
}

function parseState(text) {
    if (typeof text !== "string" || text.trim() === "") {
        return { jobs: [], skipped: 0, queuePaused: false };
    }
    var parsed = null;
    try {
        parsed = JSON.parse(text);
    } catch (error) {
        return null;
    }
    if (!parsed || typeof parsed !== "object" || !isArrayLike(parsed.jobs)) return null;
    var jobs = [];
    var skipped = 0;
    for (var i = 0; i < parsed.jobs.length && jobs.length < MAX_JOBS; i++) {
        var job = sanitizeJob(parsed.jobs[i]);
        if (job === null) {
            skipped++;
            continue;
        }
        var duplicate = false;
        for (var j = 0; j < jobs.length; j++) {
            if (jobs[j].id === job.id) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            skipped++;
            continue;
        }
        jobs.push(job);
    }
    return { jobs: jobs, skipped: skipped, queuePaused: parsed.queuePaused === true };
}

function serialize(jobs, queuePaused, now) {
    var clean = [];
    if (isArrayLike(jobs)) {
        for (var i = 0; i < jobs.length && clean.length < MAX_JOBS; i++) {
            var job = sanitizeJob(jobs[i]);
            if (job !== null) clean.push(job);
        }
    }
    return JSON.stringify({
        version: 1,
        savedAt: isNumber(now) ? Math.floor(now) : Date.now(),
        queuePaused: queuePaused === true,
        jobs: clean
    });
}

function formatLabel(format) {
    if (!format || typeof format !== "object") return "format";
    var parts = [];
    if (isNumber(format.height) && format.height > 0) {
        var quality = Math.round(format.height) + "p";
        if (isNumber(format.fps) && format.fps > 0) quality += Math.round(format.fps);
        parts.push(quality);
    }
    if (format.ext) parts.push(String(format.ext).toUpperCase());
    var codec = format.hasVideo ? String(format.vcodec || "") : String(format.acodec || "");
    if (codec !== "" && codec !== "none") parts.push(codec.split(".")[0]);
    if (isNumber(format.abr) && format.abr > 0) parts.push(Math.round(format.abr) + "k");
    if (isNumber(format.sizeBytes) && format.sizeBytes > 0) parts.push(formatBytes(format.sizeBytes));
    parts.push("#" + format.format_id);
    return cleanText(parts.join(" · "), 90);
}

function redact(text) {
    var value = String(text || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
    value = value.replace(/https?:\/\/[^\s"'<>]+/g, function (match) {
        var question = match.indexOf("?");
        if (question >= 0) return match.slice(0, question) + "?[redacted]";
        return match;
    });
    return cleanText(value, MAX_ERROR);
}
