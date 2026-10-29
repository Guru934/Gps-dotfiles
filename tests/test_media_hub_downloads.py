import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts" / "media-hub-downloads.py"
SPEC = importlib.util.spec_from_file_location("media_hub_downloads", HELPER)
downloads = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(downloads)


def valid_url(value="https://media.example/watch?v=abc123"):
    return downloads.validate_url(value)


def command_args(**overrides):
    values = {
        "url": "https://media.example/watch?v=abc123",
        "destination": Path("/tmp/gps-download-test"),
        "mode": "video",
        "format_id": "",
        "format_has_audio": True,
        "quality_cap": 1080,
        "container": "Auto",
        "audio_format": "original",
        "audio_quality": "best",
        "scope": "single",
        "playlist_items": "",
        "playlist_count": 0,
        "ffmpeg_available": True,
    }
    values.update(overrides)
    return values


def build(**overrides):
    values = command_args(**overrides)
    values["ytdlp"] = "/usr/bin/yt-dlp"
    return downloads.build_download_command(**values)


def video_payload(**overrides):
    payload = {
        "_type": "video",
        "id": "abc123",
        "title": "A public test video",
        "uploader": "Example Channel",
        "extractor_key": "Example",
        "duration": 93.5,
        "thumbnail": "https://media.example/thumb.jpg",
        "formats": [
            {
                "format_id": "137",
                "ext": "mp4",
                "vcodec": "avc1.640028",
                "acodec": "none",
                "height": 1080,
                "fps": 30,
                "filesize": 100000000,
                "tbr": 4500,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "abr": 128,
                "filesize": 1500000,
            },
            {
                "format_id": "22",
                "ext": "mp4",
                "vcodec": "avc1.64001F",
                "acodec": "mp4a.40.2",
                "height": 720,
                "fps": 30,
                "filesize_approx": 50000000,
            },
        ],
    }
    payload.update(overrides)
    return payload


def playlist_payload(**overrides):
    payload = {
        "_type": "playlist",
        "id": "playlist-1",
        "title": "A public playlist",
        "playlist_count": 3,
        "entries": [
            {"id": "one", "title": "First", "duration": 10, "playlist_index": 1},
            {"id": "two", "title": "Second", "duration": 20, "playlist_index": 2},
            {"id": "three", "title": "Third", "duration": 30, "playlist_index": 3},
        ],
    }
    payload.update(overrides)
    return payload


FAKE_TOOLS = {
    "yt-dlp": r'''#!@PYTHON@
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
if args == ["--version"]:
    print("9999.01.01")
    raise SystemExit(0)
url = args[-1]
if "--dump-single-json" in args:
    if "playlist" in url and "--flat-playlist" in args:
        payload = {
            "_type": "playlist",
            "id": "playlist-1",
            "title": "Fake playlist",
            "playlist_count": 2,
            "entries": [
                {"id": "one", "title": "First", "duration": 10, "playlist_index": 1},
                {"id": "two", "title": "Second", "duration": 20, "playlist_index": 2},
            ],
        }
    else:
        payload = {
            "_type": "video",
            "id": "fakeid",
            "title": "Fake video",
            "uploader": "Fake channel",
            "extractor_key": "Fake",
            "duration": 42,
            "thumbnail": "https://media.example/fake.jpg",
            "formats": [
                {"format_id": "137", "ext": "mp4", "vcodec": "avc1", "acodec": "none",
                 "height": 1080, "fps": 30, "filesize": 1000},
                {"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a",
                 "abr": 128, "filesize": 100},
            ],
        }
    print(json.dumps(payload))
    raise SystemExit(0)

if "fail" in url:
    print("ERROR: HTTP Error 403: Forbidden", file=sys.stderr)
    raise SystemExit(1)

out = args[args.index("--output") + 1]
directory = Path(out).parent
path = directory / "Fake video [fakeid].mp4"
print("GPS_PLAN|" + str(path), flush=True)
print("GPS_PROGRESS|downloading|50|100|100|10.5|5|0|0", flush=True)
path.write_bytes(b"fake media bytes")
print("GPS_PROGRESS|finished|100|100|100|NA|0|0|0", flush=True)
print("GPS_POSTPROCESS|started|Merger", flush=True)
print("GPS_POSTPROCESS|finished|Merger", flush=True)
print("GPS_FILE|" + str(path), flush=True)
raise SystemExit(0)
''',
    "ffmpeg": r'''#!@PYTHON@
import sys
print("ffmpeg version fake")
''',
    "ffprobe": r'''#!@PYTHON@
import sys
print("ffprobe version fake")
''',
}


class FakeToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        for name, source in FAKE_TOOLS.items():
            path = self.bin / name
            path.write_text(source.replace("@PYTHON@", sys.executable), encoding="utf-8")
            path.chmod(0o755)
        self.output = Path(self.temp.name) / "output"
        self.output.mkdir()
        self.env = patch.dict(os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", "")})
        self.env.start()
        self.addCleanup(self.env.stop)

    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = downloads.main(argv)
        lines = [line for line in output.getvalue().splitlines() if line.strip()]
        return code, [json.loads(line) for line in lines]

    def test_inspect_playlist_reports_entries_and_sample_formats(self):
        code, lines = self.run_main(["inspect", "--url", "https://media.example/playlist"])
        self.assertEqual(code, 0)
        payload = lines[-1]
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["playlist"]["isPlaylist"])
        self.assertEqual(payload["playlist"]["count"], 2)
        self.assertEqual([entry["title"] for entry in payload["playlist"]["entries"]], ["First", "Second"])
        self.assertEqual(payload["item"]["title"], "Fake video")
        self.assertEqual(payload["videoFormats"][0]["format_id"], "137")
        self.assertEqual(payload["qualityHeights"], [1080])

    def test_download_emits_progress_and_verifies_the_file(self):
        code, lines = self.run_main([
            "download",
            "--url", "https://media.example/watch?v=abc123",
            "--job-id", "dl-test-1",
            "--mode", "video",
            "--output-dir", str(self.output),
            "--scope", "single",
            "--quality-cap", "1080",
        ])
        self.assertEqual(code, 0)
        self.assertEqual(lines[0]["event"], "started")
        self.assertTrue(any(line.get("event") == "progress" for line in lines))
        self.assertTrue(any(line.get("event") == "postprocess" for line in lines))
        self.assertEqual(lines[-1]["event"], "finished")
        final_path = Path(lines[-1]["file"])
        self.assertTrue(final_path.is_file())
        self.assertEqual(final_path.parent, self.output)

    def test_download_failure_is_structured_and_does_not_claim_success(self):
        code, lines = self.run_main([
            "download",
            "--url", "https://media.example/fail",
            "--job-id", "dl-test-2",
            "--mode", "video",
            "--output-dir", str(self.output),
            "--scope", "single",
        ])
        self.assertEqual(code, 1)
        self.assertEqual(lines[-1]["event"], "failed")
        self.assertFalse(lines[-1]["ok"])
        self.assertEqual(lines[-1]["code"], "access_denied")

    def test_status_detects_fake_tools(self):
        code, lines = self.run_main(["status"])
        self.assertEqual(code, 0)
        payload = lines[0]
        self.assertTrue(payload["ready"])
        self.assertTrue(payload["ffmpegReady"])
        self.assertEqual(Path(payload["ytDlpPath"]), self.bin / "yt-dlp")


class ValidationTests(unittest.TestCase):
    def test_url_validation_rejects_shell_like_and_private_credentials(self):
        self.assertEqual(valid_url(), "https://media.example/watch?v=abc123")
        for value in (
            "",
            "file:///tmp/video.mp4",
            "javascript:alert(1)",
            "https://user:pass@media.example/video",
            "https://media.example/a b",
            "https://media.example/video\n--exec=sh",
            "https://media.example/" + ("x" * 5000),
        ):
            with self.subTest(value=value):
                with self.assertRaises(downloads.BridgeError):
                    downloads.validate_url(value)

    def test_playlist_specs_are_bounded_and_parse_ranges(self):
        self.assertEqual(downloads.validate_playlist_spec("1,3-5,10:20:2"), ("1,3-5,10:20:2", 10))
        for value in ("", "0", "5-3", "1,,2", "--playlist-items=1", "1:500", "1-" + "2" * 10):
            with self.subTest(value=value):
                with self.assertRaises(downloads.BridgeError):
                    downloads.validate_playlist_spec(value)
        with self.assertRaises(downloads.BridgeError) as caught:
            downloads.validate_playlist_spec("1-101")
        self.assertEqual(caught.exception.code, "playlist_too_large")

    def test_redaction_removes_query_values_and_control_characters(self):
        text = "failed https://media.example/video?token=secret&x=1\x1b[31m\nERROR"
        redacted = downloads.redact_text(text)
        self.assertNotIn("secret", redacted)
        self.assertNotIn("\x1b", redacted)
        self.assertIn("https://media.example/video?[redacted]", redacted)

    def test_failure_classification_does_not_include_credentials(self):
        error = downloads.classify_failure(
            "ERROR: unable to download https://media.example/a?token=secret\nHTTP Error 403: Forbidden",
            1,
        )
        self.assertEqual(error.code, "access_denied")
        self.assertNotIn("secret", error.message)


class CommandBuildTests(unittest.TestCase):
    def test_single_scope_is_explicit_and_url_is_the_final_argument(self):
        command = build(scope="single")
        self.assertIn("--no-playlist", command)
        self.assertEqual(command[command.index("--") + 1], "https://media.example/watch?v=abc123")
        self.assertEqual(command[-1], "https://media.example/watch?v=abc123")
        self.assertEqual(command[command.index("--format") + 1], "bv*[height<=1080]+ba/b[height<=1080]")

    def test_selected_and_full_playlists_are_bounded(self):
        selected = build(scope="selected", playlist_items="1,3-5")
        self.assertIn("--yes-playlist", selected)
        self.assertEqual(selected[selected.index("--playlist-items") + 1], "1,3-5")
        full = build(scope="full", playlist_count=100)
        self.assertEqual(full[full.index("--playlist-items") + 1], "1:100")
        with self.assertRaises(downloads.BridgeError):
            build(scope="full", playlist_count=101)
        with self.assertRaises(downloads.BridgeError):
            build(scope="selected", playlist_items="1-101")

    def test_format_container_audio_and_quality_inputs_are_strict(self):
        command = build(format_id="137", format_has_audio=False)
        self.assertEqual(command[command.index("--format") + 1], "137+ba/137")
        command = build(format_id="22", format_has_audio=True, container="MP4")
        self.assertEqual(command[command.index("--format") + 1], "22")
        self.assertEqual(command[command.index("--merge-output-format") + 1], "mp4")
        command = build(mode="audio", format_id="", audio_format="mp3", audio_quality="320K")
        self.assertIn("--extract-audio", command)
        self.assertEqual(command[command.index("--audio-format") + 1], "mp3")
        self.assertEqual(command[command.index("--audio-quality") + 1], "320K")
        for overrides in (
            {"format_id": "137 --exec=sh"},
            {"container": "avi"},
            {"audio_format": "wav"},
            {"audio_quality": "999K"},
            {"quality_cap": 0, "format_id": "137", "scope": "single", "container": "not-real"},
            {"quality_cap": -1},
        ):
            with self.subTest(overrides=overrides):
                with self.assertRaises(downloads.BridgeError):
                    build(**overrides)

    def test_audio_conversion_without_ffmpeg_fails_before_ytdlp(self):
        with self.assertRaises(downloads.BridgeError) as caught:
            build(mode="audio", audio_format="mp3", ffmpeg_available=False)
        self.assertEqual(caught.exception.code, "ffmpeg_missing")
        original = build(mode="audio", format_id="140", ffmpeg_available=False)
        self.assertEqual(original[original.index("--format") + 1], "140")

    def test_output_path_cannot_break_out_of_the_destination(self):
        command = build(destination=Path("/tmp/100%/downloads"))
        output = command[command.index("--output") + 1]
        self.assertTrue(output.startswith("/tmp/100%%/downloads/"))
        self.assertTrue(output.endswith(downloads.OUTPUT_TEMPLATE))
        self.assertIn("--ignore-config", command)
        self.assertNotIn("--exec", command)
        self.assertNotIn("--config-location", command)


class MetadataTests(unittest.TestCase):
    def test_single_video_metadata_is_normalized_and_bounded(self):
        result = downloads.normalize_metadata(video_payload(), "https://media.example/watch?v=abc123",
                                              is_playlist=False)
        self.assertEqual(result["title"], "A public test video")
        self.assertEqual(result["source"], "Example")
        self.assertEqual(result["item"]["thumbnail"], "https://media.example/thumb.jpg")
        self.assertEqual(result["videoFormats"][0]["format_id"], "137")
        self.assertEqual(result["videoFormats"][0]["sizeBytes"], 100000000)
        self.assertEqual(result["audioFormats"][0]["format_id"], "140")
        self.assertEqual(result["playlist"]["count"], 0)
        self.assertFalse(result["playlist"]["isPlaylist"])

    def test_playlist_metadata_lists_entries_without_untrusted_thumbnail(self):
        result = downloads.normalize_metadata(playlist_payload(), "https://media.example/playlist",
                                              is_playlist=True, sample=video_payload())
        self.assertEqual(result["playlist"]["count"], 3)
        self.assertEqual(len(result["playlist"]["entries"]), 3)
        self.assertEqual(result["playlist"]["entries"][2]["title"], "Third")
        self.assertFalse(result["playlist"]["truncated"])
        self.assertEqual(result["videoFormats"][0]["format_id"], "137")
        result = downloads.normalize_metadata(
            playlist_payload(thumbnail="javascript:alert(1)"),
            "https://media.example/playlist",
            is_playlist=True,
        )
        self.assertEqual(result["thumbnail"], "")

    def test_progress_and_postprocess_lines_are_parsed_safely(self):
        progress = downloads.parse_progress_line(
            "GPS_PROGRESS|downloading|500|1000|900|123.5|7|2|10"
        )
        self.assertEqual(progress["downloadedBytes"], 500)
        self.assertEqual(progress["totalBytes"], 1000)
        self.assertEqual(progress["speed"], 123.5)
        self.assertEqual(downloads.parse_progress_line("GPS_PROGRESS|downloading|None|None|None|NA|None|0|0")["downloadedBytes"], None)
        self.assertIsNone(downloads.parse_progress_line("not a progress line"))
        self.assertEqual(downloads.parse_postprocess_line("GPS_POSTPROCESS|started|Merger")["postprocessor"], "Merger")
        self.assertIsNone(downloads.parse_postprocess_line("GPS_POSTPROCESS|unknown|Merger"))


class DestinationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def test_missing_destination_is_reported_not_created_implicitly(self):
        target = self.base / "new" / "folder"
        result = downloads.check_destination(str(target))
        self.assertFalse(result["exists"])
        self.assertFalse(target.exists())
        with self.assertRaises(downloads.BridgeError) as caught:
            downloads.require_destination(str(target))
        self.assertEqual(caught.exception.code, "destination_missing")
        created = downloads.create_destination(str(target))
        self.assertTrue(created["created"])
        self.assertTrue(target.is_dir())

    def test_root_symlink_and_relative_destinations_are_rejected(self):
        for value, code in (
            ("/", "invalid_destination"),
            ("relative/folder", "invalid_destination"),
            ("", "invalid_destination"),
        ):
            with self.subTest(value=value):
                with self.assertRaises(downloads.BridgeError) as caught:
                    downloads.clean_destination(value)
                self.assertEqual(caught.exception.code, code)
        real = self.base / "real"
        real.mkdir()
        link = self.base / "link"
        link.symlink_to(real, target_is_directory=True)
        with self.assertRaises(downloads.BridgeError) as caught:
            downloads.check_destination(str(link))
        self.assertEqual(caught.exception.code, "destination_symlink")

    def test_verify_rejects_empty_symlinked_and_escaped_files(self):
        destination = self.base / "downloads"
        destination.mkdir()
        good = destination / "video.mp4"
        good.write_bytes(b"data")
        self.assertTrue(downloads.verify_file(str(good), destination)["ok"])
        empty = destination / "empty.mp4"
        empty.write_bytes(b"")
        self.assertEqual(downloads.verify_file(str(empty), destination)["code"], "empty")
        outside = self.base / "outside.mp4"
        outside.write_bytes(b"data")
        self.assertEqual(downloads.verify_file(str(outside), destination)["code"], "outside_destination")
        link = destination / "link.mp4"
        link.symlink_to(outside)
        self.assertEqual(downloads.verify_file(str(link), destination)["code"], "symlink")
        self.assertEqual(downloads.verify_file("relative.mp4", destination)["code"], "invalid_path")


class CliTests(unittest.TestCase):
    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = downloads.main(argv)
        return code, json.loads(output.getvalue())

    def test_failures_are_json_and_do_not_echo_the_url(self):
        code, payload = self.run_main(["inspect", "--url", "file:///tmp/private-video.mp4"])
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["code"], "invalid_url")
        self.assertNotIn("private-video", json.dumps(payload))

    def test_status_cli_is_json(self):
        code, payload = self.run_main(["status"])
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertIn("ytDlpReady", payload)
        self.assertEqual(payload["limits"]["maxConcurrentJobs"], 1)


if __name__ == "__main__":
    unittest.main()
