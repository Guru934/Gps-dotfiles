import importlib.util
import io
import json
import os
import stat
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts" / "media-hub-manga.py"
SPEC = importlib.util.spec_from_file_location("media_hub_manga", HELPER)
manga = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manga)


class MangaTestBase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.cache = self.root / "cache"
        self.env = patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.cache)})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def image(self, path, data=b"image"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def zip(self, name, entries):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as bundle:
            for entry_name, data in entries:
                bundle.writestr(entry_name, data)
        return path

    def zip_info(self, name, data, mode=None):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as bundle:
            info = zipfile.ZipInfo("page.png")
            info.create_system = 3
            if mode is not None:
                info.external_attr = mode << 16
            bundle.writestr(info, data)
        return path


class FolderTests(MangaTestBase):
    def test_folder_pages_and_chapters_are_naturally_ordered(self):
        folder = self.root / "Series"
        for name in ("page10.png", "page2.png", "page1.jpg"):
            self.image(folder / name)
        self.image(folder / "chapter-10" / "002.png")
        self.image(folder / "chapter-2" / "001.png")
        collection = manga.collection_payload(str(folder))
        self.assertEqual(collection["format"], "Folder")
        self.assertEqual(collection["chapterCount"], 3)
        self.assertEqual([chapter["title"] for chapter in collection["chapters"]],
                         ["Series", "chapter-2", "chapter-10"])
        self.assertEqual([Path(page).name for page in collection["chapters"][0]["pages"]],
                         ["page1.jpg", "page2.png", "page10.png"])
        self.assertEqual(collection["pageCount"], 5)

    def test_folder_rejects_relative_empty_and_unsupported_paths(self):
        for value, code in (("relative", "invalid_path"),
                            (str(self.root / "missing"), "not_found"),
                            (str(self.root / "notes.txt"), "unsupported_file")):
            if value.endswith("notes.txt"):
                self.image(self.root / "notes.txt")
            with self.assertRaises(manga.MangaError) as caught:
                manga.collection_payload(value)
            self.assertEqual(caught.exception.code, code)

    def test_folder_skips_symlinked_images(self):
        folder = self.root / "linked"
        folder.mkdir()
        target = self.image(self.root / "outside.png")
        (folder / "page.png").symlink_to(target)
        with self.assertRaises(manga.MangaError) as caught:
            manga.collection_payload(str(folder))
        self.assertEqual(caught.exception.code, "no_pages")

    def test_corrupt_archive_in_folder_is_reported_without_hiding_valid_pages(self):
        folder = self.root / "mixed"
        self.image(folder / "page.png")
        (folder / "broken.cbz").write_bytes(b"not a zip")
        collection = manga.collection_payload(str(folder))
        self.assertEqual(collection["chapterCount"], 1)
        self.assertEqual(collection["warnings"], ["broken.cbz: That CBZ archive is damaged."])

    def test_file_url_is_accepted(self):
        folder = self.root / "Series"
        self.image(folder / "page.png")
        collection = manga.collection_payload(folder.as_uri())
        self.assertEqual(collection["title"], "Series")


class ArchiveSafetyTests(MangaTestBase):
    def test_unsafe_archive_names_are_rejected(self):
        for name in ("../evil.png", "/absolute.png", "a\\..\\evil.png"):
            with self.subTest(name=name):
                path = self.zip("unsafe.cbz", [(name, b"x")])
                with self.assertRaises(manga.MangaError) as caught:
                    manga.collection_payload(str(path))
                self.assertEqual(caught.exception.code, "unsafe_archive")

    def test_symlink_entries_are_rejected(self):
        path = self.zip_info("link.cbz", b"/etc/passwd", stat.S_IFLNK | 0o777)
        with self.assertRaises(manga.MangaError) as caught:
            manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "unsafe_archive")

    def test_duplicate_page_names_are_rejected(self):
        path = self.zip("duplicate.cbz", [("page.png", b"a"), ("page.png", b"b")])
        with self.assertRaises(manga.MangaError) as caught:
            manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "unsafe_archive")

    def test_corrupt_and_encrypted_archives_fail_cleanly(self):
        broken = self.root / "broken.cbz"
        broken.write_bytes(b"not a zip")
        with self.assertRaises(manga.MangaError) as caught:
            manga.collection_payload(str(broken))
        self.assertEqual(caught.exception.code, "corrupt_archive")

        encrypted = self.zip("encrypted.cbz", [("page.png", b"x")])
        with zipfile.ZipFile(encrypted) as bundle:
            infos = bundle.infolist()
        with patch.object(manga.zipfile, "ZipFile") as fake:
            fake.return_value.__enter__.return_value.infolist.return_value = [
                type("Info", (), {
                    "filename": infos[0].filename,
                    "flag_bits": 1,
                    "external_attr": 0,
                    "file_size": 1,
                    "is_dir": lambda self: False,
                })()
            ]
            with self.assertRaises(manga.MangaError) as caught:
                manga.collection_payload(str(encrypted))
        self.assertEqual(caught.exception.code, "encrypted_archive")

    def test_entry_and_total_limits_are_enforced(self):
        path = self.zip("many.cbz", [("1.png", b"x"), ("2.png", b"y")])
        with patch.object(manga, "MAX_ENTRIES", 1):
            with self.assertRaises(manga.MangaError) as caught:
                manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "too_many_entries")

        path = self.zip("large.cbz", [("page.png", b"12345")])
        with patch.object(manga, "MAX_ENTRY_BYTES", 2):
            with self.assertRaises(manga.MangaError) as caught:
                manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "archive_too_large")


class CbzTests(MangaTestBase):
    def test_cbz_pages_are_ordered_and_cached(self):
        path = self.zip("chapter.cbz", [("10.png", b"a"), ("2.jpg", b"b"), ("001.png", b"c")])
        first = manga.collection_payload(str(path))
        self.assertEqual(first["format"], "CBZ")
        self.assertEqual([Path(page).name for page in first["chapters"][0]["pages"]],
                         ["001.png", "2.jpg", "10.png"])
        cache_dirs = list((self.cache / "gps-media-hub" / "manga").iterdir())
        self.assertEqual(len(cache_dirs), 1)
        manifest = cache_dirs[0] / "manifest.json"
        self.assertTrue(manifest.is_file())

        with patch.object(manga, "extract_zip", side_effect=AssertionError("cache should be reused")):
            second = manga.collection_payload(str(path))
        self.assertEqual(first["chapters"][0]["pages"], second["chapters"][0]["pages"])

        cleanup = manga.cleanup_payload(str(path))
        self.assertTrue(cleanup["removed"])
        self.assertFalse(cache_dirs[0].exists())

    def test_non_image_entries_are_ignored_but_still_limited(self):
        path = self.zip("mixed.cbz", [("notes.txt", b"x"), ("page.png", b"y")])
        collection = manga.collection_payload(str(path))
        self.assertEqual(collection["pageCount"], 1)
        self.assertEqual(Path(collection["chapters"][0]["pages"][0]).name, "page.png")

    def test_archive_without_images_is_rejected(self):
        path = self.zip("empty.cbz", [("notes.txt", b"x")])
        with self.assertRaises(manga.MangaError) as caught:
            manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "no_pages")


class CbrTests(MangaTestBase):
    def test_cbr_uses_7z_when_available(self):
        if not manga.seven_zip():
            self.skipTest("7z is not installed")
        path = self.zip("chapter.cbr", [("10.png", b"a"), ("2.jpg", b"b")])
        collection = manga.collection_payload(str(path))
        self.assertEqual(collection["format"], "CBR")
        self.assertEqual([Path(page).name for page in collection["chapters"][0]["pages"]],
                         ["2.jpg", "10.png"])

    def test_missing_cbr_extractor_is_a_clear_failure(self):
        path = self.zip("chapter.cbr", [("page.png", b"a")])
        with patch.object(manga, "seven_zip", return_value=""):
            with self.assertRaises(manga.MangaError) as caught:
                manga.collection_payload(str(path))
        self.assertEqual(caught.exception.code, "cbr_unsupported")

    def test_cbr_listing_rejects_links_and_traversal(self):
        listing = "\n".join([
            "7-Zip",
            "----------",
            "Path = ../evil.png",
            "Folder = -",
            "Size = 1",
            "Attributes = A",
            "Encrypted = -",
            "",
        ])
        fake = type("Result", (), {"returncode": 0, "stdout": listing.encode(), "stderr": b""})()
        with patch.object(manga.subprocess, "run", return_value=fake):
            with self.assertRaises(manga.MangaError) as caught:
                manga.validate_cbr_entries(Path("/tmp/fake.cbr"), "/usr/bin/7z")
        self.assertEqual(caught.exception.code, "unsafe_archive")

        listing = listing.replace("Path = ../evil.png", "Path = page.png").replace(
            "Attributes = A", "Attributes =  lrwxrwxrwx")
        fake = type("Result", (), {"returncode": 0, "stdout": listing.encode(), "stderr": b""})()
        with patch.object(manga.subprocess, "run", return_value=fake):
            with self.assertRaises(manga.MangaError) as caught:
                manga.validate_cbr_entries(Path("/tmp/fake.cbr"), "/usr/bin/7z")
        self.assertEqual(caught.exception.code, "unsafe_archive")


class CliTests(MangaTestBase):
    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = manga.main(argv)
        return code, json.loads(output.getvalue())

    def test_status_is_json_and_reports_capabilities(self):
        code, payload = self.run_main(["status"])
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["cbzSupported"])
        self.assertTrue(payload["folderSupported"])
        self.assertIn("cbrSupported", payload)

    def test_errors_are_json_and_do_not_echo_absolute_paths(self):
        code, payload = self.run_main(["open", "--path", str(self.root / "missing")])
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "not_found")
        self.assertNotIn(str(self.root), json.dumps(payload))


if __name__ == "__main__":
    unittest.main()
