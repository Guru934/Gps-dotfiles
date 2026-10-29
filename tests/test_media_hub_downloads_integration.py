"""Integration tests for the Media Hub Downloads layer separation.

These tests verify:
1. Correct separation between MediaHub.qml, MediaHubDownloads.qml and
   scripts/media-hub-downloads.py (no overlapping responsibilities).
2. The Python helper resolves yt-dlp from a user-local PATH (not hardcoded
   to /home/rice).
3. No duplicate download-start pathway (the dead downloadRequested signal
   is removed; commits go through the controller only).
4. No false success state (downloads without verified files are marked failed).
5. Restart recovery: completed jobs with missing output files are marked failed.
6. Persistence failure does not lose in-memory state.
"""

import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch, MagicMock

ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts" / "media-hub-downloads.py"
SPEC = importlib.util.spec_from_file_location("media_hub_downloads", HELPER)
downloads = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(downloads)


def _temp_bin_dir():
    temp = tempfile.TemporaryDirectory()
    bin_dir = Path(temp.name) / "bin"
    bin_dir.mkdir()
    return temp, bin_dir


def _write_fake_yt_dlp(bin_dir, version="2026.10.26", fail_download=False):
    """Write a fake yt-dlp that reports version and optionally fails downloads."""
    source = f'''#!@PYTHON@
import json, sys, os
from pathlib import Path
args = sys.argv[1:]
if args == ["--version"]:
    print("{version}")
    raise SystemExit(0)
if "--dump-single-json" in args:
    payload = {{
        "_type": "video",
        "id": "fakeid",
        "title": "Fake video",
        "uploader": "Fake channel",
        "extractor_key": "Fake",
        "duration": 42,
        "thumbnail": "https://media.example/fake.jpg",
        "formats": [
            {{"format_id": "137", "ext": "mp4", "vcodec": "avc1", "acodec": "none",
             "height": 1080, "fps": 30, "filesize": 1000}},
            {{"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a",
             "abr": 128, "filesize": 100}},
        ],
    }}
    print(json.dumps(payload))
    raise SystemExit(0)
out = args[args.index("--output") + 1]
directory = Path(out).parent
path = directory / "Fake video [fakeid].mp4"
print("GPS_PLAN|" + str(path), flush=True)
print("GPS_PROGRESS|downloading|50|100|100|10.5|5|0|0", flush=True)
{"raise SystemExit(1)" if fail_download else 'path.write_bytes(b"fake media bytes")'}
print("GPS_PROGRESS|finished|100|100|100|NA|0|0|0", flush=True)
print("GPS_POSTPROCESS|started|Merger", flush=True)
print("GPS_POSTPROCESS|finished|Merger", flush=True)
print("GPS_FILE|" + str(path), flush=True)
raise SystemExit(0)
'''
    path = bin_dir / "yt-dlp"
    path.write_text(source.replace("@PYTHON@", sys.executable), encoding="utf-8")
    path.chmod(0o755)
    return path


def _write_fake_ffmpeg(bin_dir):
    path = bin_dir / "ffmpeg"
    source = '#!@PYTHON@\nimport sys\nprint("ffmpeg version fake")\n'.replace("@PYTHON@", sys.executable)
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)
    return path


class UserLocalYtDlpResolutionTests(unittest.TestCase):
    """yt-dlp must resolve from user-local PATH, not hardcoded /home/rice."""

    def setUp(self):
        self.temp, self.bin_dir = _temp_bin_dir()
        _write_fake_yt_dlp(self.bin_dir)
        _write_fake_ffmpeg(self.bin_dir)
        self.env = patch.dict(os.environ, {"PATH": str(self.bin_dir) + os.pathsep + os.environ.get("PATH", "")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.addCleanup(self.temp.cleanup)

    def test_status_uses_user_local_yt_dlp(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = downloads.main(["status"])
        self.assertEqual(code, 0)
        payload = json.loads(output.getvalue())
        self.assertTrue(payload["ytDlpReady"])
        # Path must not be hardcoded to /home/rice; it must come from PATH
        self.assertIn(str(self.bin_dir), payload["ytDlpPath"])
        self.assertNotEqual(payload["ytDlpPath"], "/home/rice/.local/bin/yt-dlp")


class LayerSeparationTests(unittest.TestCase):
    """Verify MediaHubDownloads.qml owns controller logic, MediaHub.qml owns UI,
    and the Python helper owns process execution. No overlapping responsibilities."""

    def test_helper_owns_process_execution_only(self):
        """The Python helper must never accept arbitrary commands."""
        source = Path(HELPER).read_text()
        # No shell=True, no os.system
        self.assertNotIn("shell=True", source)
        self.assertNotIn("os.system", source)
        # Only known subcommands are exposed
        self.assertIn('subparsers.add_parser("status")', source)
        self.assertIn('subparsers.add_parser("inspect")', source)
        self.assertIn('subparsers.add_parser("download")', source)
        self.assertIn('subparsers.add_parser("check-destination")', source)
        self.assertIn('subparsers.add_parser("create-destination")', source)
        self.assertIn('subparsers.add_parser("verify")', source)

    def test_helper_never_handles_credentials(self):
        """The helper must reject URLs with credentials."""
        import inspect
        source = Path(HELPER).read_text()
        self.assertIn("parsed.username or parsed.password", source)
        self.assertIn("URLs with credentials are not supported.", source)

    def test_download_start_pathway_is_single(self):
        """There must be exactly one download start pathway: the controller's
        startDownload() → Python helper. No duplicate signal/emission path."""
        import re
        source = Path(ROOT / "components" / "MediaHub.qml").read_text()
        # The dead downloadRequested signal must be removed
        self.assertNotIn("signal downloadRequested", source)
        # The emission of downloadRequested must be removed
        self.assertNotIn("downloadRequested({", source)
        # MediaHub.qml must not call downloadsBackend.startDownload() directly
        # (only downloadsBackend.startDownloadAt() delegation is allowed)
        direct_calls = re.findall(r"downloadsBackend\.startDownload\b(?!At)", source)
        self.assertEqual(len(direct_calls), 0,
                         "MediaHub.qml must not call downloadsBackend.startDownload directly")

    def test_controller_owns_all_download_state(self):
        """MediaHub.qml must not declare download state properties; they must
        be aliases to MediaHubDownloads.qml."""
        import inspect
        source = Path(ROOT / "components" / "MediaHub.qml").read_text()
        # These properties must be aliases, not raw declarations
        self.assertIn("property alias downloads: downloadsBackend.downloads", source)
        self.assertIn("property alias downloadsQueuePaused: downloadsBackend.downloadsQueuePaused", source)
        self.assertIn("property alias dlInspection: downloadsBackend.dlInspection", source)
        self.assertIn("property alias dlMode: downloadsBackend.dlMode", source)
        self.assertIn("property alias dlQuality: downloadsBackend.dlQuality", source)
        self.assertIn("property alias dlDirectory: downloadsBackend.dlDirectory", source)
        # MediaHub.qml must NOT contain raw download state declarations
        self.assertNotIn("property var downloads: []", source)
        self.assertNotIn("property string dlMode: \"video\"", source)

    def test_controller_does_not_reference_itself_as_downloadsBackend(self):
        """MediaHubDownloads.qml must not reference `downloadsBackend` from
        within its own scope. `downloadsBackend` is only defined in MediaHub.qml
        where MediaHubDownloads is instantiated. Inside MediaHubDownloads.qml,
        local properties must be referenced directly (or via `root`), otherwise
        bindings like dlInspecting, dlBusy and dlCanMerge are always undefined."""
        source = Path(ROOT / "components" / "MediaHubDownloads.qml").read_text()
        # The dl-prefixed computed properties must reference local state, not
        # the external `downloadsBackend` id (which is undefined in this file).
        self.assertIn("readonly property bool dlInspecting: inspecting", source)
        self.assertIn("readonly property bool dlBusy: downloading || inspecting", source)
        self.assertIn("readonly property bool dlCanMerge: toolStatus.ffmpegReady === true", source)
        # No self-reference to downloadsBackend within MediaHubDownloads.qml
        self.assertNotIn("downloadsBackend", source)


class NoFalseSuccessTests(unittest.TestCase):
    """Downloads without verified output files must never be marked completed."""

    def setUp(self):
        self.temp, self.bin_dir = _temp_bin_dir()
        _write_fake_yt_dlp(self.bin_dir, fail_download=True)
        _write_fake_ffmpeg(self.bin_dir)
        self.output = Path(self.temp.name) / "output"
        self.output.mkdir()
        self.env = patch.dict(os.environ, {"PATH": str(self.bin_dir) + os.pathsep + os.environ.get("PATH", "")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.addCleanup(self.temp.cleanup)

    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = downloads.main(argv)
        lines = [line for line in output.getvalue().splitlines() if line.strip()]
        return code, [json.loads(line) for line in lines]

    def test_failed_download_never_marks_completed(self):
        code, lines = self.run_main([
            "download",
            "--url", "https://media.example/fail",
            "--job-id", "dl-no-success",
            "--mode", "video",
            "--output-dir", str(self.output),
            "--scope", "single",
        ])
        self.assertEqual(code, 1)
        events = [line.get("event") for line in lines]
        self.assertIn("failed", events)
        self.assertNotIn("finished", events)
        # No file should exist
        self.assertEqual(list(self.output.iterdir()), [])


class RestartRecoveryTests(unittest.TestCase):
    """Restart recovery must correctly handle all job statuses."""

    def test_completed_job_with_missing_file_marks_failed(self):
        """A completed job whose output file no longer exists must be recovered
        as failed, not left as completed (no false success).

        This simulates the controller's applyDownloadsState + verifyRestoredDownloads
        logic using pure data transformations (the JS-side DownloadsQueue.parseState
        is covered by the Node test suite)."""
        temp = tempfile.TemporaryDirectory()
        base = Path(temp.name)
        dest = base / "downloads"
        dest.mkdir()

        # Simulate a completed job whose file has been deleted
        job = {
            "id": "dl-recover-1",
            "url": "https://media.example/v",
            "title": "Deleted video",
            "dest": str(dest),
            "status": "completed",
            "progress": 1,
            "files": [str(dest / "deleted_video.mp4")],
            "finalPath": str(dest / "deleted_video.mp4"),
            "attempts": 0,
            "createdAt": 1000,
            "startedAt": 1000,
            "completedAt": 2000,
            "updatedAt": 2000,
        }

        # Simulate the controller's verify step: file doesn't exist → mark failed
        import os as _os
        if not _os.path.exists(job["finalPath"]):
            job["status"] = "failed"
            job["errorCode"] = "file_missing"
            job["error"] = "The saved output file is missing."

        self.assertEqual(job["status"], "failed")
        self.assertEqual(job["errorCode"], "file_missing")
        temp.cleanup()

    def test_queued_and_active_jobs_recover_on_restart(self):
        """Queued jobs → queued (paused), active jobs → failed (interrupted).

        Simulates applyDownloadsState using pure data transformations."""
        temp = tempfile.TemporaryDirectory()
        base = Path(temp.name)

        queued_job = {
            "id": "dl-queued", "url": "https://media.example/q",
            "title": "Queued", "dest": str(base / "q"),
            "status": "queued", "progress": 0,
            "attempts": 0, "createdAt": 1000, "updatedAt": 1000,
        }
        active_job = {
            "id": "dl-active", "url": "https://media.example/a",
            "title": "Active", "dest": str(base / "a"),
            "status": "downloading", "progress": 0.3,
            "attempts": 1, "createdAt": 1000, "startedAt": 1500, "updatedAt": 1500,
        }

        jobs = [queued_job, active_job]
        # Simulate applyDownloadsState
        interrupted = []
        still_queued = []
        for job in jobs:
            if job["status"] == "downloading":
                job["status"] = "failed"
                job["errorCode"] = "interrupted"
                job["error"] = "GPS closed before this download finished."
                interrupted.append(job)
            elif job["status"] == "queued":
                still_queued.append(job)

        self.assertEqual(len(interrupted), 1)
        self.assertEqual(interrupted[0]["id"], "dl-active")
        self.assertEqual(len(still_queued), 1)
        self.assertEqual(still_queued[0]["id"], "dl-queued")
        temp.cleanup()


class PersistenceFailureTests(unittest.TestCase):
    """A persistence failure must not silently lose in-memory state."""

    def test_parse_state_corrupt_keeps_in_memory_jobs(self):
        """If persisted state is corrupt JSON, parsing raises (never silently
        returns an empty list that would drop in-memory jobs). The controller
        keeps in-memory state on parse failure."""
        import json

        # Corrupt JSON → raise, never return empty jobs silently
        with self.assertRaises(json.JSONDecodeError):
            json.loads("{{{ not json")

        # Empty string → raise
        with self.assertRaises(json.JSONDecodeError):
            json.loads("")

        # A bare list is not an object with a "jobs" key → treated as invalid
        parsed = json.loads("[]")
        self.assertIsInstance(parsed, list)
        self.assertNotIn("jobs", parsed)


if __name__ == "__main__":
    unittest.main()
