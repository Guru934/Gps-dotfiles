import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GPS_TOOLBOX = ROOT / "scripts/gps-toolbox"
TOOLBOX_BACKEND = (ROOT / "components/ToolboxBackend.qml").read_text(encoding="utf-8")
TOOLBOX_WIN = (ROOT / "components/ToolboxWindow.qml").read_text(encoding="utf-8")


class ToolboxSavedSpaceTests(unittest.TestCase):
    """Verifies GPS Toolbox Saved Space persistence, validation, and recovery."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.env = os.environ.copy()
        self.env["XDG_STATE_HOME"] = self.temp_dir.name
        self.state_dir = Path(self.temp_dir.name) / "gps/toolbox"
        self.state_file = self.state_dir / "saved_space.json"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_cli(self, *args):
        cmd = [str(GPS_TOOLBOX)] + list(args)
        proc = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        return proc

    def test_default_initialization(self):
        """Verifies missing state initializes with version 1, default collections, and empty items."""
        self.assertFalse(self.state_file.exists())
        res = self.run_cli("saved-space", "list")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertEqual(data.get("version"), 1)
        self.assertEqual(data.get("items"), [])
        self.assertIn("Development", data.get("collections", []))
        self.assertTrue(self.state_file.exists())

    def test_item_crud_and_atomic_persistence(self):
        """Verifies creating, patching, and deleting items persists atomically."""
        # 1. Create a bookmark
        item = {
            "id": "b1",
            "type": "bookmark",
            "title": "Hyprland Docs",
            "url": "https://wiki.hyprland.org",
            "collection": "Linux",
            "tags": ["wayland", "compositor"],
        }
        res = self.run_cli("saved-space", "save-item", json.dumps(item))
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertEqual(data["item"]["id"], "b1")
        self.assertEqual(data["item"]["title"], "Hyprland Docs")
        self.assertEqual(data["item"]["url"], "https://wiki.hyprland.org")
        self.assertFalse(data["item"]["sample"])

        # Verify on-disk file
        disk_data = json.loads(self.state_file.read_text(encoding="utf-8"))
        self.assertEqual(len(disk_data["items"]), 1)
        self.assertEqual(disk_data["items"][0]["title"], "Hyprland Docs")

        # 2. Patch item (favorite and pinned)
        res_patch = self.run_cli("saved-space", "patch-item", "b1", json.dumps({"favorite": True, "pinned": True}))
        self.assertEqual(res_patch.returncode, 0, res_patch.stderr)
        patch_data = json.loads(res_patch.stdout)
        self.assertTrue(patch_data["item"]["favorite"])
        self.assertTrue(patch_data["item"]["pinned"])

        disk_data = json.loads(self.state_file.read_text(encoding="utf-8"))
        self.assertTrue(disk_data["items"][0]["favorite"])
        self.assertTrue(disk_data["items"][0]["pinned"])

        # 3. Delete item
        res_del = self.run_cli("saved-space", "delete-item", "b1")
        self.assertEqual(res_del.returncode, 0, res_del.stderr)
        del_data = json.loads(res_del.stdout)
        self.assertEqual(del_data["deleted"], "b1")
        self.assertEqual(len(del_data["items"]), 0)

        disk_data = json.loads(self.state_file.read_text(encoding="utf-8"))
        self.assertEqual(len(disk_data["items"]), 0)

    def test_validation_rejects_unsafe_inputs(self):
        """Verifies input validation rejects bad schemes, empty titles, and missing note content."""
        # Unsafe scheme for bookmark
        bad_bookmark = {
            "type": "bookmark",
            "title": "Malicious",
            "url": "javascript:alert(document.cookie)",
        }
        res = self.run_cli("saved-space", "save-item", json.dumps(bad_bookmark))
        self.assertNotEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertFalse(data.get("ok"))

        # Empty title
        bad_title = {
            "type": "note",
            "title": "   ",
            "content": "Note content",
        }
        res = self.run_cli("saved-space", "save-item", json.dumps(bad_title))
        self.assertNotEqual(res.returncode, 0)

        # Empty content for note
        empty_note = {
            "type": "note",
            "title": "Empty Note",
            "content": "  ",
        }
        res = self.run_cli("saved-space", "save-item", json.dumps(empty_note))
        self.assertNotEqual(res.returncode, 0)

        # File scheme url open
        res_open = self.run_cli("saved-space", "open-url", "file:///etc/passwd")
        self.assertNotEqual(res_open.returncode, 0)
        data_open = json.loads(res_open.stdout)
        self.assertFalse(data_open.get("ok"))

    def test_corrupt_file_recovery(self):
        """Verifies corrupt JSON is backed up with timestamp and a fresh state is created."""
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text("{ corrupt json: [not valid", encoding="utf-8")

        res = self.run_cli("saved-space", "list")
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertEqual(data.get("items"), [])

        # Check backup file exists
        backups = list(self.state_dir.glob("saved_space.corrupt-*.json"))
        self.assertEqual(len(backups), 1)
        self.assertIn("corrupt json", backups[0].read_text(encoding="utf-8"))

    def test_collections_persistence(self):
        """Verifies collections array updates and deduplicates."""
        colls = ["Work", "Arch Linux", "Projects", "Work"]
        res = self.run_cli("saved-space", "save-collections", json.dumps(colls))
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertEqual(data["collections"], ["Work", "Arch Linux", "Projects"])

        disk_data = json.loads(self.state_file.read_text(encoding="utf-8"))
        self.assertEqual(disk_data["collections"], ["Work", "Arch Linux", "Projects"])

    def test_qml_wiring_contract(self):
        """Verifies ToolboxBackend and ToolboxWindow have Saved Space properties and processes."""
        self.assertIn("property var savedItems: []", TOOLBOX_BACKEND)
        self.assertIn("property var collections:", TOOLBOX_BACKEND)
        self.assertIn("property bool showSampleData: false", TOOLBOX_BACKEND)
        self.assertIn("listSavedSpaceProc", TOOLBOX_BACKEND)
        self.assertIn("saveItemProc", TOOLBOX_BACKEND)
        self.assertIn("deleteItemProc", TOOLBOX_BACKEND)
        self.assertIn("savedItems: backend.savedItems", TOOLBOX_WIN)
        self.assertIn("collections: backend.collections", TOOLBOX_WIN)


if __name__ == "__main__":
    unittest.main()

