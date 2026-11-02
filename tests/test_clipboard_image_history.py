#!/usr/bin/env python3
"""Hermetic regression test for clipboard image history and preview pipeline.

Verifies:
- Binary PNG clipboard capture is preserved without UTF-8 corruption.
- Thumbnail generation in clip-thumbs cache.
- Image previews in history model are correctly referenced.
- Stored image can be loaded as an image file.
- MIME type is preserved during copy.
- Text clipboard handling remains functional.
"""

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIP_STORE = ROOT / "scripts" / "gps-clip-store"
GPS_CLIPBOARD = ROOT / "scripts" / "gps-clipboard"

# Minimal valid 16x16 PNG fixture
PNG_FIXTURE = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10\x00\x00\x00\x10\x08\x02"
    b"\x00\x00\x00\x90\x91h6\x00\x00\x00\x1dIDATx\x9cc\xfc\xcf\x80\x01\x18\x18\x18"
    b"\x18\x98!\x80\r\x98!\x80\r\x98!\x80\r\x18\x00\x00\x08c\x01\x91\x92\xd4\xcd\xc2"
    b"\x00\x00\x00\x00IEND\xaeB`\x82"
)


class ClipboardImageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.td.name)
        self.bin_dir = self.temp_dir / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        self.state_dir = self.temp_dir / ".local" / "state" / "gps"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir = self.temp_dir / ".cache" / "gps"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir = self.temp_dir / "run" / "gps"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)

        self.env = os.environ.copy()
        self.env["CLIPBOARD_STATE"] = "data"
        self.env["HOME"] = str(self.temp_dir)
        self.env["XDG_STATE_HOME"] = str(self.temp_dir / ".local" / "state")
        self.env["XDG_CACHE_HOME"] = str(self.temp_dir / ".cache")
        self.env["XDG_RUNTIME_DIR"] = str(self.temp_dir / "run")
        self.env["GPS_ROOT"] = str(ROOT)
        self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"

        # Mock cliphist with realistic store/list/decode support
        self.db_file = self.temp_dir / "cliphist_db.json"
        self.db_file.write_text("[]", encoding="utf-8")
        self.mock_cliphist = self.bin_dir / "cliphist"
        self.mock_cliphist.write_text(
            f"""#!/usr/bin/env python3
import sys, json
from pathlib import Path

db_file = Path("{self.db_file}")
cmd = "list"
for a in sys.argv[1:]:
    if a in ("store", "list", "decode", "wipe", "delete"):
        cmd = a
        break

if cmd == "store":
    data = sys.stdin.buffer.read()
    records = json.loads(db_file.read_text(encoding="utf-8")) if db_file.exists() else []
    next_id = len(records) + 1
    is_png = data.startswith(b"\\x89PNG\\r\\n\\x1a\\n")
    if is_png:
        preview = f"[[ binary data {{len(data)}} B png 16x16 ]]"
    else:
        preview = data.decode("utf-8", errors="replace").strip()

    payload_file = Path("{self.temp_dir}") / f"clip_{{next_id}}.bin"
    payload_file.write_bytes(data)
    records.insert(0, {{"id": next_id, "preview": preview, "file": str(payload_file), "is_image": is_png}})
    db_file.write_text(json.dumps(records), encoding="utf-8")
    sys.exit(0)

elif cmd == "list":
    if not db_file.exists():
        sys.exit(0)
    records = json.loads(db_file.read_text(encoding="utf-8"))
    for r in records:
        print(f"{{r['id']}}\\t{{r['preview']}}")
    sys.exit(0)

elif cmd == "decode":
    target_id = int(sys.argv[-1])
    records = json.loads(db_file.read_text(encoding="utf-8")) if db_file.exists() else []
    for r in records:
        if r["id"] == target_id:
            payload = Path(r["file"]).read_bytes()
            sys.stdout.buffer.write(payload)
            sys.exit(0)
    sys.exit(1)

elif cmd == "wipe":
    db_file.write_text("[]", encoding="utf-8")
    sys.exit(0)

sys.exit(0)
""",
            encoding="utf-8",
        )
        self.mock_cliphist.chmod(0o755)

        # Mock wl-paste returning image/png
        self.mock_wl_paste = self.bin_dir / "wl-paste"
        self._set_mock_types(["image/png"])

    def tearDown(self):
        self.td.cleanup()

    def _set_mock_types(self, types):
        lines = "\n".join(f'    echo "{t}"' for t in types)
        self.mock_wl_paste.write_text(
            f"""#!/bin/sh
if [ "$1" = "--list-types" ]; then
{lines}
    exit 0
fi
exit 0
""",
            encoding="utf-8",
        )
        self.mock_wl_paste.chmod(0o755)

    def test_image_capture_and_history_preview(self):
        """Image is captured as binary, metadata is parsed, and thumbnail file is produced."""
        # 1. Feed PNG fixture into gps-clip-store
        proc = subprocess.run(
            [str(CLIP_STORE)],
            input=PNG_FIXTURE,
            env=self.env,
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0)

        # 2. Query gps-clipboard list
        list_proc = subprocess.run(
            ["node", str(GPS_CLIPBOARD), "list"],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(list_proc.returncode, 0)
        res = json.loads(list_proc.stdout)
        self.assertTrue(res.get("ok"))
        self.assertTrue(len(res.get("items", [])) >= 1)

        img_item = res["items"][0]
        self.assertEqual(img_item.get("kind"), "image")
        self.assertTrue(img_item.get("isImage"))
        self.assertIn("thumbPath", img_item)

        # 3. Verify thumbPath exists and is readable as a valid PNG
        thumb_file = Path(img_item["thumbPath"])
        self.assertTrue(thumb_file.exists())
        self.assertTrue(thumb_file.stat().st_size > 0)
        thumb_bytes = thumb_file.read_bytes()
        self.assertTrue(thumb_bytes.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(thumb_bytes, PNG_FIXTURE)

        # 4. Check permissions on thumbnail cache
        mode = oct(thumb_file.stat().st_mode & 0o777)
        self.assertEqual(mode, oct(0o600))

    def test_text_and_image_coexistence(self):
        """Text entries remain functional alongside image entries."""
        # Store text entry
        self._set_mock_types(["text/plain", "UTF8_STRING"])
        text_payload = b"Sample text entry for clipboard"
        proc = subprocess.run([str(CLIP_STORE)], input=text_payload, env=self.env)
        self.assertEqual(proc.returncode, 0)

        # Store image entry
        self._set_mock_types(["image/png"])
        proc = subprocess.run([str(CLIP_STORE)], input=PNG_FIXTURE, env=self.env)
        self.assertEqual(proc.returncode, 0)

        # List both
        list_proc = subprocess.run(
            ["node", str(GPS_CLIPBOARD), "list"],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(list_proc.returncode, 0)
        res = json.loads(list_proc.stdout)
        items = res["items"]
        self.assertEqual(len(items), 2)
        # Most recent is image
        self.assertEqual(items[0]["kind"], "image")
        self.assertTrue(items[0]["isImage"])
        self.assertTrue(Path(items[0]["thumbPath"]).is_file())

        # Second is text
        self.assertEqual(items[1]["kind"], "text")
        self.assertFalse(items[1]["isImage"])
        self.assertEqual(items[1]["preview"], "Sample text entry for clipboard")

    def test_copy_image_preserves_mime_type(self):
        """Copying an image item from history invokes wl-copy with --type image/png."""
        # Store image
        self._set_mock_types(["image/png"])
        subprocess.run([str(CLIP_STORE)], input=PNG_FIXTURE, env=self.env, check=True)

        # Mock wl-copy to record arguments and received stdin
        wl_copy_log = self.temp_dir / "wl_copy_record.bin"
        wl_copy_args = self.temp_dir / "wl_copy_args.txt"
        mock_wl_copy = self.bin_dir / "wl-copy"
        mock_wl_copy.write_text(
            f"""#!/bin/sh
echo "$@" > "{wl_copy_args}"
cat > "{wl_copy_log}"
exit 0
""",
            encoding="utf-8",
        )
        mock_wl_copy.chmod(0o755)

        # Fetch id
        list_proc = subprocess.run(["node", str(GPS_CLIPBOARD), "list"], env=self.env, capture_output=True, text=True)
        item_id = json.loads(list_proc.stdout)["items"][0]["id"]

        # Copy item
        copy_proc = subprocess.run(["node", str(GPS_CLIPBOARD), "copy", str(item_id)], env=self.env, capture_output=True)
        self.assertEqual(copy_proc.returncode, 0)

        # Verify wl-copy was invoked with --type image/png and received binary PNG
        self.assertTrue(wl_copy_args.exists())
        self.assertIn("image/png", wl_copy_args.read_text(encoding="utf-8"))
        self.assertTrue(wl_copy_log.exists())
        self.assertEqual(wl_copy_log.read_bytes(), PNG_FIXTURE)


if __name__ == "__main__":
    unittest.main()
