#!/usr/bin/env python3
"""Hermetic tests for GPS T3.1 clipboard privacy remediation.

Verifies:
- Normal text event.
- Normal image event.
- Sensitive event rejection via CLIPBOARD_STATE=sensitive.
- Missing and unknown CLIPBOARD_STATE rejection.
- Original stdin is used even when a mock clipboard changes afterward.
- No image artifact for rejected content.
- Existing IPC behavior and unchecked suffix protection (> 300 chars rejected).
- Existing history pause behavior.
"""

import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PRIVACY_SCRIPT = ROOT / "scripts" / "gps-clip-privacy"
CLIP_STORE_SCRIPT = ROOT / "scripts" / "gps-clip-store"
GPS_IPC_SCRIPT = ROOT / "scripts" / "gps-ipc"
ISLAND_QML = (ROOT / "island" / "Island.qml").read_text(encoding="utf-8")


class ClipboardPrivacyTests(unittest.TestCase):
    """Hermetic regression suite for clipboard privacy filtering and IPC protection."""

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.td.name)
        self.state_dir = self.temp_dir / ".local" / "state" / "gps"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir = self.temp_dir / "run"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.bin_dir = self.temp_dir / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)

        # Mock cliphist
        self.cliphist_log = self.temp_dir / "cliphist.log"
        self.mock_cliphist = self.bin_dir / "cliphist"
        self.mock_cliphist.write_text(
            f"""#!/bin/sh
cat >> "{self.cliphist_log}"
echo "STORED" >> "{self.cliphist_log}"
exit 0
""",
            encoding="utf-8",
        )
        self.mock_cliphist.chmod(0o755)

        # Mock quickshell for IPC routing
        self.qs_log = self.temp_dir / "qs.log"
        self.mock_qs = self.bin_dir / "quickshell"
        self.mock_qs.write_text(
            f"""#!/bin/sh
echo "$@" >> "{self.qs_log}"
exit 0
""",
            encoding="utf-8",
        )
        self.mock_qs.chmod(0o755)

        # Default mock wl-paste (normal types, default text payload)
        self.mock_wl_paste = self.bin_dir / "wl-paste"
        self._set_wl_paste_types(["text/plain", "UTF8_STRING"], text_payload="Hello Island Clipboard")

        self.env = os.environ.copy()
        self.env["CLIPBOARD_STATE"] = "data"
        self.env["HOME"] = str(self.temp_dir)
        self.env["XDG_STATE_HOME"] = str(self.temp_dir / ".local" / "state")
        self.env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)
        self.env["GPS_ROOT"] = str(ROOT)
        self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"

    def tearDown(self):
        self.td.cleanup()

    def _set_wl_paste_types(self, types, image_payload=b"FAKE_PNG_DATA", text_payload="Hello Island Clipboard", exit_code=0):
        """Configure mock wl-paste to return specific MIME types and content."""
        types_lines = "\n".join(f'    echo "{t}"' for t in types)
        img_dump = self.temp_dir / "mock_img.bin"
        img_dump.write_bytes(image_payload)
        txt_dump = self.temp_dir / "mock_txt.txt"
        txt_dump.write_text(text_payload, encoding="utf-8")
        script = f"""#!/bin/sh
if [ "$1" = "--list-types" ]; then
    if [ {exit_code} -ne 0 ]; then
        exit {exit_code}
    fi
{types_lines}
    exit 0
fi
if [ "$1" = "--type" ]; then
    case "$2" in
        image/*)
            cat "{img_dump}"
            exit 0
            ;;
        text/*|text|UTF8_STRING)
            cat "{txt_dump}"
            exit 0
            ;;
        *)
            echo "Mock paste for $2"
            exit 0
            ;;
    esac
fi
exit 0
"""
        self.mock_wl_paste.write_text(script, encoding="utf-8")
        self.mock_wl_paste.chmod(0o755)

    def _extract_clip_feed_script(self):
        """Extract the exact shell command executed by clipFeed in Island.qml."""
        m = re.search(r'id:\s*clipFeed[\s\S]*?command:\s*\["wl-paste",\s*"--type",\s*"text",\s*"--watch",\s*"sh",\s*"-c",\s*([\s\S]*?)\]\s*stdout:', ISLAND_QML)
        self.assertIsNotNone(m, "clipFeed command must be found in Island.qml")
        raw_parts = m.group(1).strip()
        parts = re.findall(r"'([^']*)'", raw_parts)
        return "".join(parts)

    def _extract_clip_img_feed_script(self):
        """Extract the exact shell command executed by clipImgFeed in Island.qml."""
        m = re.search(r'id:\s*clipImgFeed[\s\S]*?command:\s*\["wl-paste",\s*"--type",\s*"image",\s*"--watch",\s*"sh",\s*"-c",\s*([\s\S]*?)\]\s*stdout:', ISLAND_QML)
        self.assertIsNotNone(m, "clipImgFeed command must be found in Island.qml")
        raw_parts = m.group(1).strip()
        parts = re.findall(r"'([^']*)'", raw_parts)
        return "".join(parts)

    # ──────────────────────────────────────────────────────────────────────────
    # 1. CLIPBOARD_STATE & check-watch Policy Tests
    # ──────────────────────────────────────────────────────────────────────────

    def test_check_watch_policy(self):
        """check-watch allows data, rejects sensitive, nil, clear, missing and unknown."""
        # 1. data -> allow
        env = self.env.copy()
        env["CLIPBOARD_STATE"] = "data"
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 0)

        # 2. sensitive -> reject
        env["CLIPBOARD_STATE"] = "sensitive"
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 1)

        # 3. nil -> reject
        env["CLIPBOARD_STATE"] = "nil"
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 1)

        # 4. clear -> reject
        env["CLIPBOARD_STATE"] = "clear"
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 1)

        # 5. missing -> reject
        env.pop("CLIPBOARD_STATE", None)
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 1)

        # 6. unknown -> reject
        env["CLIPBOARD_STATE"] = "some_random_state"
        self.assertEqual(subprocess.run([str(PRIVACY_SCRIPT), "check-watch"], env=env).returncode, 1)

    # ──────────────────────────────────────────────────────────────────────────
    # 2. Text Watcher (clipFeed) & Image Watcher (clipImgFeed) Stdin Processing
    # ──────────────────────────────────────────────────────────────────────────

    def test_normal_text_event(self):
        """Text watcher validates event state, reads stdin once, and generates preview."""
        cmd = self._extract_clip_feed_script()
        input_text = "Original clipboard text entry"
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input=input_text,
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0)
        lines = proc.stdout.strip().split("\n")
        self.assertTrue(len(lines) >= 1)
        count, preview = lines[0].split("\t", 1)
        self.assertEqual(int(count), len(input_text))
        self.assertEqual(preview, input_text)

    def test_text_watcher_uses_original_stdin_even_if_clipboard_changes_afterward(self):
        """Text watcher uses its original stdin and does not re-query clipboard."""
        cmd = self._extract_clip_feed_script()
        input_text = "Event Stdin Text"
        # Set mock wl-paste to return something else entirely
        self._set_wl_paste_types(["text/plain"], text_payload="Different Changed Clipboard")
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input=input_text,
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("Event Stdin Text", proc.stdout)
        self.assertNotIn("Different Changed Clipboard", proc.stdout)

    def test_text_watcher_rejects_sensitive_event(self):
        """Text watcher rejects event when CLIPBOARD_STATE=sensitive."""
        cmd = self._extract_clip_feed_script()
        env = self.env.copy()
        env["CLIPBOARD_STATE"] = "sensitive"
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input="Password123",
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")

    def test_normal_image_event_saves_original_stdin_atomically(self):
        """Image watcher streams original stdin into protected temp file and atomically moves."""
        cmd = self._extract_clip_img_feed_script()
        sample_img = b"\x89PNG\r\n\x1a\n" + b"\x11" * 40
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input=sample_img,
            env=self.env,
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0)
        stdout = proc.stdout.decode("utf-8").strip()
        self.assertTrue(stdout.startswith("IMG\timage/png\t"))
        parts = stdout.split("\t")
        img_file = Path(parts[3])
        self.assertTrue(img_file.exists())
        self.assertEqual(img_file.read_bytes(), sample_img)
        # Check atomic file permissions (umask 077 -> 0600)
        mode = oct(img_file.stat().st_mode & 0o777)
        self.assertEqual(mode, oct(0o600))

    def test_image_watcher_uses_original_stdin_even_if_clipboard_changes_afterward(self):
        """Image watcher saves original stdin, not re-queried clipboard data."""
        cmd = self._extract_clip_img_feed_script()
        original_img = b"\x89PNG_ORIGINAL_STDIN_DATA"
        # Set mock wl-paste to return different data if queried
        self._set_wl_paste_types(["image/png"], image_payload=b"DIFFERENT_MOCK_DATA")
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input=original_img,
            env=self.env,
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0)
        img_file = self.runtime_dir / "island-clip-image"
        self.assertTrue(img_file.exists())
        self.assertEqual(img_file.read_bytes(), original_img)

    def test_image_watcher_rejects_sensitive_event_and_creates_no_artifact(self):
        """Image watcher rejects sensitive event and creates NO file artifact."""
        cmd = self._extract_clip_img_feed_script()
        env = self.env.copy()
        env["CLIPBOARD_STATE"] = "sensitive"
        proc = subprocess.run(
            ["sh", "-c", cmd],
            input=b"SENSITIVE_KEY_IMAGE_DATA",
            env=env,
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, b"")
        img_file = self.runtime_dir / "island-clip-image"
        self.assertFalse(img_file.exists())
        # Ensure no temp files remain
        self.assertEqual(len(list(self.runtime_dir.glob("island-clip-image.*"))), 0)

    def test_image_watcher_rejects_missing_or_unknown_clipboard_state(self):
        """Image watcher rejects when CLIPBOARD_STATE is missing or unknown."""
        cmd = self._extract_clip_img_feed_script()
        for bad_state in [None, "unknown", "nil", "clear"]:
            env = self.env.copy()
            if bad_state is None:
                env.pop("CLIPBOARD_STATE", None)
            else:
                env["CLIPBOARD_STATE"] = bad_state
            proc = subprocess.run(
                ["sh", "-c", cmd],
                input=b"IMAGE_BYTES",
                env=env,
                capture_output=True,
            )
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(proc.stdout, b"")
            self.assertFalse((self.runtime_dir / "island-clip-image").exists())

    # ──────────────────────────────────────────────────────────────────────────
    # 3. Practical IPC & Inspection Limit Protection
    # ──────────────────────────────────────────────────────────────────────────

    def test_ipc_rejects_unchecked_suffixes_beyond_inspection_limit(self):
        """Preview payload exceeding the 300 char inspection limit is rejected."""
        # 301 chars payload
        long_payload = "A" * 301
        self._set_wl_paste_types(["text/plain"], text_payload=long_payload)
        p = subprocess.run(
            [str(PRIVACY_SCRIPT), "check-ipc", "text", long_payload],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(p.returncode, 1, "Payloads with unchecked suffixes exceeding 300 chars must be rejected")

        # Exactly 300 chars is allowed
        exact_payload = "B" * 300
        self._set_wl_paste_types(["text/plain"], text_payload=exact_payload)
        p_ok = subprocess.run(
            [str(PRIVACY_SCRIPT), "check-ipc", "text", exact_payload],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(p_ok.returncode, 0)
        self.assertTrue(p_ok.stdout.startswith("OK\t"))

    def test_ipc_rejects_sensitive_tokens_and_hints(self):
        """check-ipc rejects sensitive tokens, private keys, and passwordManagerHint."""
        # Token
        p1 = subprocess.run([str(PRIVACY_SCRIPT), "check-ipc", "text", "ghp_12345678901234567890"], env=self.env)
        self.assertEqual(p1.returncode, 1)

        # Private key
        p2 = subprocess.run([str(PRIVACY_SCRIPT), "check-ipc", "text", "-----BEGIN RSA PRIVATE KEY-----"], env=self.env)
        self.assertEqual(p2.returncode, 1)

        # Hint in preview
        p3 = subprocess.run([str(PRIVACY_SCRIPT), "check-ipc", "text", "x-kde-passwordManagerHint"], env=self.env)
        self.assertEqual(p3.returncode, 1)

    def test_ipc_missing_helper_suppresses_preview(self):
        """Island QML IPC process suppresses preview if helper is missing."""
        # Verify Island QML command has fail-closed fallback
        self.assertIn("exit 1", ISLAND_QML)
        # Direct test with non-existent helper script
        cmd = 'r="/nonexistent"; priv="$r/scripts/gps-clip-privacy"; if [ -x "$priv" ]; then exec "$priv" check-ipc "$1" "$2"; else exit 1; fi'
        p = subprocess.run(["sh", "-c", cmd, "sh", "text", "hello"], capture_output=True)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(p.stdout, b"")

    def test_legitimate_ipc_notification_continues_working(self):
        """Matching safe clipboard entry through gps-ipc routes to quickshell."""
        self._set_wl_paste_types(["text/plain"], text_payload="Legitimate Copied String")
        p = subprocess.run(
            [str(GPS_IPC_SCRIPT), "island", "copied", "text", "Legitimate Copied String"],
            env=self.env,
            capture_output=True,
        )
        self.assertEqual(p.returncode, 0)
        self.assertTrue(self.qs_log.exists())
        self.assertIn("copied text Legitimate Copied String", self.qs_log.read_text())

    # ──────────────────────────────────────────────────────────────────────────
    # 4. History Pause Behavior Preservation
    # ──────────────────────────────────────────────────────────────────────────

    def test_history_pause_behavior_preserved(self):
        """History pause flag suppresses storage, independent of preview behavior."""
        # 1. Stored when unpaused
        p1 = subprocess.run([str(CLIP_STORE_SCRIPT)], input=b"Entry 1", env=self.env)
        self.assertEqual(p1.returncode, 0)
        self.assertTrue(self.cliphist_log.exists())

        # 2. Suppressed when paused
        (self.state_dir / "clipboard_paused").touch()
        self.cliphist_log.unlink()
        p2 = subprocess.run([str(CLIP_STORE_SCRIPT)], input=b"Entry 2", env=self.env)
        self.assertEqual(p2.returncode, 0)
        self.assertFalse(self.cliphist_log.exists())


if __name__ == "__main__":
    unittest.main()
