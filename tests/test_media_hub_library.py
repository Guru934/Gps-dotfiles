import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("media_hub_library", SCRIPTS / "media-hub-library.py")
library = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(library)


class MediaHubLibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name) / "Music"
        self.root.mkdir()
        self.audio_path = self.root / "Song With Spaces.mp3"
        self.audio_path.write_bytes(b"test media placeholder")
        self.cache_dir = Path(self.temp_dir.name) / "cache"
        self.cache = library.hub_common.DiskCache(
            self.cache_dir,
            ttl_seconds=3600,
            max_bytes=1024 * 1024,
        )
        self.probe_payload = json.dumps({
            "format": {
                "duration": "214.25",
                "tags": {
                    "TITLE": "Tagged title",
                    "ARTIST": "Test artist",
                    "ALBUM": "Test album",
                    "GENRE": "Ambient",
                },
            },
        })

    def tearDown(self):
        self.temp_dir.cleanup()

    def scan_with_probe(self, probe):
        with patch.object(library.shutil, "which", return_value="/usr/bin/ffprobe"), \
             patch.object(library.subprocess, "run", return_value=probe) as run:
            result = library.scan(self.root, cache=self.cache)
        return result, run

    def test_scans_and_normalizes_local_tags_to_a_file_track(self):
        result, run = self.scan_with_probe(SimpleNamespace(returncode=0, stdout=self.probe_payload))
        track = result["results"][0]
        self.assertEqual(result["count"], 1)
        self.assertEqual(track["title"], "Tagged title")
        self.assertEqual(track["artist"], "Test artist")
        self.assertEqual(track["album"], "Test album")
        self.assertEqual(track["genre"], "Ambient")
        self.assertEqual(track["dur"], 214)
        self.assertEqual(track["id"][:6], "local:")
        self.assertEqual(track["streamUrl"], self.audio_path.as_uri())
        self.assertEqual(run.call_args.args[0][0], "ffprobe")
        self.assertEqual(run.call_args.kwargs["timeout"], library.FFPROBE_TIMEOUT)

    def test_unchanged_files_reuse_the_cached_probe_index(self):
        probe = SimpleNamespace(returncode=0, stdout=self.probe_payload)
        with patch.object(library.shutil, "which", return_value="/usr/bin/ffprobe"), \
             patch.object(library.subprocess, "run", return_value=probe) as run:
            first = library.scan(self.root, cache=self.cache)
            second = library.scan(self.root, cache=self.cache)
        self.assertEqual(first["results"], second["results"])
        self.assertEqual(run.call_count, 1)

    def test_changed_files_are_reprobed_and_removed_files_disappear(self):
        probe = SimpleNamespace(returncode=0, stdout=self.probe_payload)
        self.scan_with_probe(probe)
        self.audio_path.write_bytes(b"changed media placeholder")
        with patch.object(library.shutil, "which", return_value="/usr/bin/ffprobe"), \
             patch.object(library.subprocess, "run", return_value=probe) as run:
            changed = library.scan(self.root, cache=self.cache)
            self.assertEqual(run.call_count, 1)
            self.audio_path.unlink()
            removed = library.scan(self.root, cache=self.cache)
        self.assertEqual(changed["count"], 1)
        self.assertEqual(removed["count"], 0)

    def test_unsupported_files_are_not_probed(self):
        self.audio_path.unlink()
        (self.root / "notes.txt").write_text("not audio")
        with patch.object(library.shutil, "which", return_value="/usr/bin/ffprobe"), \
             patch.object(library.subprocess, "run") as run:
            result = library.scan(self.root, cache=self.cache)
        self.assertEqual(result["count"], 0)
        run.assert_not_called()

    def test_missing_folder_and_ffprobe_are_explicit_errors(self):
        with self.assertRaises(library.hub_common.HubError) as missing:
            library.scan(self.root / "missing", cache=self.cache)
        self.assertEqual(missing.exception.kind, "invalid")
        with patch.object(library.shutil, "which", return_value=None):
            with self.assertRaises(library.hub_common.HubError) as no_ffprobe:
                library.scan(self.root, cache=self.cache)
        self.assertEqual(no_ffprobe.exception.kind, "unavailable")


if __name__ == "__main__":
    unittest.main()
