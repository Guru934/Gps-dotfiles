const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

function load(file) {
    const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
    const context = {};
    vm.createContext(context);
    vm.runInContext(source, context, { filename: file });
    return context;
}

const Q = load(path.join(__dirname, "..", "components", "DownloadsQueue.js"));

function request(overrides) {
    return Object.assign({
        url: "https://media.example/watch?v=abc123",
        title: "A public test video",
        source: "Example",
        uploader: "Example Channel",
        duration: 93,
        mode: "video",
        formatId: "137",
        formatHasAudio: false,
        qualityCap: 1080,
        quality: "1080p",
        container: "MP4",
        audioFormat: "original",
        audioQuality: "best",
        scope: "single",
        playlistItems: "",
        playlistCount: 0,
        dest: "/home/example/Videos/GPS"
    }, overrides || {});
}

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok - " + name);
}

check("public HTTP(S) URLs are accepted while credentials and control characters are rejected", () => {
    assert.strictEqual(Q.cleanUrl("https://media.example/watch?v=abc"), "https://media.example/watch?v=abc");
    assert.strictEqual(Q.cleanUrl("http://127.0.0.1:8080/video"), "http://127.0.0.1:8080/video");
    assert.strictEqual(Q.cleanUrl("https://[2001:db8::1]/video"), "https://[2001:db8::1]/video");
    for (const value of [
        "", "file:///tmp/video.mp4", "javascript:alert(1)", "https://user:pass@media.example/video",
        "https://media.example:99999/video", "https://media.example/a b", "https://media.example/a\\b",
        "https://media.example/a\n--exec=sh", "https://[2001:db8::1/video"
    ]) {
        assert.strictEqual(Q.cleanUrl(value), "", value);
    }
});

check("paths must be absolute and free of control characters", () => {
    assert.strictEqual(Q.cleanPath("/home/example/Videos/GPS"), "/home/example/Videos/GPS");
    assert.strictEqual(Q.cleanPath("~/Videos/GPS"), "");
    assert.strictEqual(Q.cleanPath("relative/path"), "");
    assert.strictEqual(Q.cleanPath("/tmp/a\nb"), "");
});

check("array-like bridge payloads are copied into plain arrays", () => {
    assert.deepStrictEqual(Array.from(Q.toArray(["a", "b"])), ["a", "b"]);
    assert.deepStrictEqual(Array.from(Q.toArray({ 0: "a", 1: "b", length: 2 })), ["a", "b"]);
    assert.deepStrictEqual(Array.from(Q.toArray(null)), []);
    assert.deepStrictEqual(Array.from(Q.toArray({ length: "2" })), []);
});

check("playlist item specs are parsed and capped", () => {
    let result = Q.validatePlaylistSpec("1,3-5,10:20:2");
    assert.strictEqual(result.ok, true);
    assert.strictEqual(result.count, 10);
    assert.strictEqual(result.spec, "1,3-5,10:20:2");
    for (const value of ["", "0", "5-3", "1,,2", "--playlist-items=1", "1:500", "1-101"]) {
        assert.strictEqual(Q.validatePlaylistSpec(value).ok, false, value);
    }
});

check("new jobs are sanitized and can never start active", () => {
    const job = Q.createJob(request(), 1000);
    assert.strictEqual(job.status, "queued");
    assert.strictEqual(job.mode, "video");
    assert.strictEqual(job.dest, "/home/example/Videos/GPS");
    assert.strictEqual(job.formatId, "137");
    assert.strictEqual(job.attempts, 0);
    assert.match(job.id, /^dl-/);
    assert.strictEqual(Q.createJob(request({ url: "file:///tmp/a.mp4" }), 1000), null);
    assert.strictEqual(Q.createJob(request({ dest: "~/Videos" }), 1000), null);
    assert.strictEqual(Q.createJob(request({ scope: "selected", playlistItems: "1-101" }), 1000), null);
});

check("unknown status and scope values restore safely", () => {
    const job = Q.sanitizeJob(Object.assign(request(), {
        id: "dl-safe-1", status: "executing", scope: "everything", playlistItems: "1-999",
        container: "AVI", audioFormat: "wav", audioQuality: "lossless",
        formatId: "137 --exec=sh", files: ["/tmp/a", "/tmp/a", "relative"]
    }));
    assert.strictEqual(job.status, "failed");
    assert.strictEqual(job.scope, "single");
    assert.strictEqual(job.container, "Auto");
    assert.strictEqual(job.audioFormat, "original");
    assert.strictEqual(job.audioQuality, "best");
    assert.strictEqual(job.formatId, "");
    assert.deepStrictEqual(Array.from(job.files), ["/tmp/a"]);
});

check("progress uses byte totals before fragment estimates", () => {
    assert.strictEqual(Q.progressFraction({ status: "downloading", downloadedBytes: 50, totalBytes: 200 }), 0.25);
    assert.strictEqual(Q.progressFraction({ status: "downloading", downloadedBytes: 0, totalBytes: 0, fragmentIndex: 2, fragmentCount: 8 }), 0.25);
    assert.strictEqual(Q.progressFraction({ status: "completed", downloadedBytes: 0, totalBytes: 0 }), 1);
    assert.strictEqual(Q.progressKnown({ status: "downloading", totalBytes: 200 }), true);
    assert.strictEqual(Q.progressKnown({ status: "downloading", fragmentCount: 8 }), true);
    assert.strictEqual(Q.progressKnown({ status: "downloading" }), false);
});

check("byte, speed, ETA and duration formatting are stable", () => {
    assert.strictEqual(Q.formatBytes(0), "unknown size");
    assert.strictEqual(Q.formatBytes(512), "512 B");
    assert.strictEqual(Q.formatBytes(1536), "1.5 KB");
    assert.strictEqual(Q.formatBytes(20 * 1024 * 1024), "20.0 MB");
    assert.strictEqual(Q.formatSpeed(0), "");
    assert.strictEqual(Q.formatSpeed(1536), "1.5 KB/s");
    assert.strictEqual(Q.formatEta(5), "5s");
    assert.strictEqual(Q.formatEta(65), "1m 5s");
    assert.strictEqual(Q.formatEta(3660), "1h 1m");
    assert.strictEqual(Q.formatDuration(0), "");
    assert.strictEqual(Q.formatDuration(65), "1:05");
    assert.strictEqual(Q.formatDuration(3661), "1:01:01");
});

check("retry policy allows only failed or cancelled jobs below the limit", () => {
    assert.strictEqual(Q.canRetry({ status: "failed", attempts: 0 }), true);
    assert.strictEqual(Q.canRetry({ status: "cancelled", attempts: 4 }), true);
    assert.strictEqual(Q.canRetry({ status: "failed", attempts: 5 }), false);
    assert.strictEqual(Q.canRetry({ status: "completed", attempts: 0 }), false);
    assert.strictEqual(Q.canRetry(null), false);
});

check("state parse rejects malformed data, drops duplicates and restores queue pause", () => {
    assert.strictEqual(Q.parseState("not json"), null);
    assert.strictEqual(Q.parseState("[]"), null);
    const first = Q.createJob(request({ id: "dl-one" }), 1000);
    const second = Q.createJob(request({ id: "dl-two", url: "https://media.example/two" }), 1001);
    const text = JSON.stringify({ version: 1, queuePaused: true, jobs: [first, second, first, { id: "bad" }] });
    const state = Q.parseState(text);
    assert.strictEqual(state.queuePaused, true);
    assert.strictEqual(state.skipped, 2);
    assert.deepStrictEqual(Array.from(state.jobs, job => job.id), ["dl-one", "dl-two"]);
    const empty = Q.parseState("");
    assert.deepStrictEqual(Array.from(empty.jobs), []);
    assert.strictEqual(empty.queuePaused, false);
});

check("serialized state round-trips only sanitized jobs", () => {
    const job = Q.createJob(request({ id: "dl-roundtrip" }), 1000);
    job.error = "https://media.example/a?token=secret";
    const text = Q.serialize([job, null, { id: "bad" }], true, 2000);
    const parsed = JSON.parse(text);
    assert.strictEqual(parsed.version, 1);
    assert.strictEqual(parsed.savedAt, 2000);
    assert.strictEqual(parsed.queuePaused, true);
    assert.strictEqual(parsed.jobs.length, 1);
    assert.strictEqual(parsed.jobs[0].id, "dl-roundtrip");
    assert.strictEqual(parsed.jobs[0].status, "queued");
});

check("format labels expose quality, container and format id", () => {
    const label = Q.formatLabel({ format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "",
        hasVideo: true, height: 1080, fps: 60, sizeBytes: 100 * 1024 * 1024 });
    assert.match(label, /1080p60/);
    assert.match(label, /MP4/);
    assert.match(label, /100 MB/);
    assert.match(label, /#137/);
    assert.strictEqual(Q.formatLabel(null), "format");
});

check("error redaction strips terminal escapes, query values and control characters", () => {
    const text = Q.redact("failed https://media.example/video?token=secret\x1b[31m\nERROR");
    assert.ok(!text.includes("secret"));
    assert.ok(!text.includes("\x1b"));
    assert.ok(text.includes("https://media.example/video?[redacted]"));
});

check("status labels distinguish interrupted jobs", () => {
    assert.strictEqual(Q.statusLabel({ status: "failed", interrupted: true }), "INTERRUPTED");
    assert.strictEqual(Q.statusLabel({ status: "postprocessing" }), "POST-PROCESSING");
    assert.strictEqual(Q.statusLabel({ status: "queued" }), "QUEUED");
});

console.log(passed + " downloads queue tests passed");
