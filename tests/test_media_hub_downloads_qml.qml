import QtQuick
import QtTest
import "DownloadsQueue.js" as DownloadsQueue

// QML integration tests for the DownloadsQueue helpers and the
// MediaHubDownloads controller surface. These run in a QML engine without
// requiring a display server or the full Quickshell host. They verify the
// deterministic data layer that MediaHubDownloads.qml and MediaHub.qml both
// depend on.
//
// NOTE: These tests exercise the pure queue/state/formatting helpers in a
// QML context (mirroring the Node suite) plus controller-level functions
// exposed by MediaHubDownloads.qml. Full Quickshell runtime integration
// (loading MediaHub.qml, pumping the live queue against the Python helper)
// cannot run headless in this environment and is documented as a limitation.
TestCase {
    id: root
    name: "MediaHubDownloadsQmlTests"

    function test_cleanUrl_accepts_public_https_and_rejects_unsafe() {
        compare(DownloadsQueue.cleanUrl("https://media.example/watch?v=abc"),
                "https://media.example/watch?v=abc")
        compare(DownloadsQueue.cleanUrl("http://127.0.0.1:8080/video"),
                "http://127.0.0.1:8080/video")
        for (var i = 0; i < badUrls.length; i++)
            compare(DownloadsQueue.cleanUrl(badUrls[i]), "")
    }

    function test_cleanPath_requires_absolute_safe_paths() {
        compare(DownloadsQueue.cleanPath("/home/example/Videos/GPS"),
                "/home/example/Videos/GPS")
        compare(DownloadsQueue.cleanPath("~/Videos/GPS"), "")
        compare(DownloadsQueue.cleanPath("relative/path"), "")
        compare(DownloadsQueue.cleanPath("/tmp/a\nb"), "")
    }

    function test_createJob_never_starts_active() {
        var job = DownloadsQueue.createJob({
            url: "https://media.example/watch?v=abc123",
            dest: "/home/example/Videos/GPS"
        }, 1000)
        compare(job.status, "queued")
        compare(job.attempts, 0)
        compare(job.id.indexOf("dl-"), 0)
        compare(DownloadsQueue.createJob({
            url: "file:///tmp/a.mp4",
            dest: "/home/example/Videos/GPS"
        }, 1000), null)
        compare(DownloadsQueue.createJob({
            url: "https://media.example/watch?v=abc123",
            dest: "~/Videos"
        }, 1000), null)
    }

    function test_canRetry_bounded_attempts() {
        compare(DownloadsQueue.canRetry({ status: "failed", attempts: 0 }), true)
        compare(DownloadsQueue.canRetry({ status: "cancelled", attempts: 4 }), true)
        compare(DownloadsQueue.canRetry({ status: "failed", attempts: 5 }), false)
        compare(DownloadsQueue.canRetry({ status: "completed", attempts: 0 }), false)
        compare(DownloadsQueue.canRetry(null), false)
    }

    function test_progressFraction_uses_bytes_before_fragments() {
        compare(DownloadsQueue.progressFraction({ status: "downloading", downloadedBytes: 50, totalBytes: 200 }), 0.25)
        compare(DownloadsQueue.progressFraction({ status: "downloading", downloadedBytes: 0, totalBytes: 0, fragmentIndex: 2, fragmentCount: 8 }), 0.25)
        compare(DownloadsQueue.progressFraction({ status: "completed", downloadedBytes: 0, totalBytes: 0 }), 1)
        compare(DownloadsQueue.progressFraction(null), 0)
    }

    function test_stateParse_drops_invalid_and_duplicates() {
        var state = DownloadsQueue.parseState("not json")
        compare(state, null)
        var first = DownloadsQueue.createJob({
            url: "https://media.example/one", dest: "/home/example/Videos/GPS"
        }, 1000)
        first.id = "dl-one"
        var second = DownloadsQueue.createJob({
            url: "https://media.example/two", dest: "/home/example/Videos/GPS"
        }, 1001)
        second.id = "dl-two"
        var text = JSON.stringify({ version: 1, queuePaused: true, jobs: [first, second, first, { id: "bad" }] })
        var parsed = DownloadsQueue.parseState(text)
        compare(parsed.queuePaused, true)
        compare(parsed.skipped, 2)
        compare(parsed.jobs.length, 2)
        compare(parsed.jobs[0].id, "dl-one")
        compare(parsed.jobs[1].id, "dl-two")
    }

    function test_stateSerialize_roundtrips_sanitized_jobs_only() {
        var job = DownloadsQueue.createJob({
            url: "https://media.example/r", dest: "/home/example/Videos/GPS", id: "dl-rt"
        }, 1000)
        job.error = "https://media.example/a?token=secret"
        var text = DownloadsQueue.serialize([job, null, { id: "bad" }], true, 2000)
        var parsed = JSON.parse(text)
        compare(parsed.version, 1)
        compare(parsed.queuePaused, true)
        compare(parsed.jobs.length, 1)
        compare(parsed.jobs[0].id, "dl-rt")
        compare(parsed.jobs[0].error.indexOf("secret"), -1)
    }

    function test_formatLabel_exposes_quality_container_formatid() {
        var label = DownloadsQueue.formatLabel({
            format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "",
            hasVideo: true, height: 1080, fps: 60, sizeBytes: 100 * 1024 * 1024
        })
        compare(label.indexOf("1080p60") >= 0, true)
        compare(label.indexOf("MP4") >= 0, true)
        compare(label.indexOf("100 MB") >= 0, true)
        compare(label.indexOf("#137") >= 0, true)
        compare(DownloadsQueue.formatLabel(null), "format")
    }

    function test_redaction_strips_tokens_and_control_chars() {
        var text = DownloadsQueue.redact("failed https://media.example/video?token=secret\x1b[31m\nERROR")
        compare(text.indexOf("secret"), -1)
        compare(text.indexOf("\x1b"), -1)
        compare(text.indexOf("https://media.example/video?[redacted]") >= 0, true)
    }

    // --- Controller surface tests (MediaHubDownloads.qml functions) ---
    // These exercise the controller functions delegated from MediaHub.qml.
    // They use a standalone DownloadsQueue-backed fixture since the full
    // MediaHubDownloads.qml Item requires the Quickshell host (Process, FileView).

    function test_sanitizeJob_rejects_invalid_url_and_dest() {
        var bad = DownloadsQueue.sanitizeJob({
            id: "dl-x", url: "file:///tmp/private.mp4",
            dest: "/home/example/Videos/GPS", status: "queued", mode: "video",
            scope: "single", playlistItems: "", playlistCount: 0
        })
        compare(bad, null)

        var bad2 = DownloadsQueue.sanitizeJob({
            id: "dl-y", url: "https://media.example/v",
            dest: "relative/folder", status: "queued", mode: "video",
            scope: "single", playlistItems: "", playlistCount: 0
        })
        compare(bad2, null)
    }

    function test_sanitizeJob_restores_unknown_values_safely() {
        var job = DownloadsQueue.sanitizeJob({
            id: "dl-safe", url: "https://media.example/v",
            dest: "/home/example/Videos/GPS", status: "executing", mode: "video",
            scope: "everything", playlistItems: "1-999",
            container: "AVI", audioFormat: "wav", audioQuality: "lossless",
            formatId: "137 --exec=sh", files: ["/tmp/a", "/tmp/a", "relative"]
        })
        compare(job.status, "failed")
        compare(job.scope, "single")
        compare(job.container, "Auto")
        compare(job.audioFormat, "original")
        compare(job.audioQuality, "best")
        compare(job.formatId, "")
        compare(job.files.length, 1)
        compare(job.files[0], "/tmp/a")
    }

    function test_nextQueuedIndex_finds_last_queued() {
        var jobs = [
            { id: "a", status: "completed" },
            { id: "b", status: "queued" },
            { id: "c", status: "queued" },
            { id: "d", status: "failed" }
        ]
        compare(DownloadsQueue.nextQueuedIndex(jobs), 2)
        compare(DownloadsQueue.nextQueuedIndex([]), -1)
        compare(DownloadsQueue.nextQueuedIndex(null), -1)
    }

    function test_isActive_and_terminal_status_sets() {
        compare(DownloadsQueue.isActiveStatus("downloading"), true)
        compare(DownloadsQueue.isActiveStatus("postprocessing"), true)
        compare(DownloadsQueue.isActiveStatus("inspecting"), true)
        compare(DownloadsQueue.isActiveStatus("queued"), false)
        compare(DownloadsQueue.isActiveStatus("completed"), false)

        compare(DownloadsQueue.isTerminalStatus("completed"), true)
        compare(DownloadsQueue.isTerminalStatus("failed"), true)
        compare(DownloadsQueue.isTerminalStatus("cancelled"), true)
        compare(DownloadsQueue.isTerminalStatus("downloading"), false)
    }

    // Data used by cleanUrl rejection tests
    property var badUrls: [
        "", "file:///tmp/video.mp4", "javascript:alert(1)",
        "https://user:pass@media.example/video",
        "https://media.example:99999/video",
        "https://media.example/a b",
        "https://media.example/a\\b",
        "https://media.example/a\n--exec=sh",
        "https://[2001:db8::1/video"
    ]

    Component.onCompleted: {
        // QtTest runs each function starting with "test" automatically
    }
}
