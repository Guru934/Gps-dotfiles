#!/usr/bin/env python3
"""Unit tests for the GPS theme hook framework."""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
import sys
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import set_wallpaper
import theme_common


class ThemeHookFrameworkTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.home_dir = self.tmp_path / "home"
        self.home_dir.mkdir(parents=True, exist_ok=True)
        self.config_dir = self.home_dir / ".config"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.state_dir = self.home_dir / ".local" / "state" / "gps"
        self.state_dir.mkdir(parents=True, exist_ok=True)

        self.hooks_dir = self.tmp_path / "theme-hooks"
        self.hooks_dir.mkdir(parents=True, exist_ok=True)

        self.log_file = self.state_dir / "theme-hooks.log"

        # Valid sample palette
        self.valid_palette = dict(theme_common.DEFAULT_FALLBACK_THEME)
        self.valid_palette["wallpaper"] = str(self.tmp_path / "wall.jpg")
        self.palette_file = self.tmp_path / "gps-theme.json"
        self.palette_file.write_text(json.dumps(self.valid_palette, indent=2), encoding="utf-8")

        self.env_patcher = patch.dict(os.environ, {
            "HOME": str(self.home_dir),
            "XDG_CONFIG_HOME": str(self.config_dir),
            "XDG_STATE_HOME": str(self.home_dir / ".local" / "state"),
        })
        self.env_patcher.start()

    def tearDown(self):
        self.env_patcher.stop()
        self.tmp_dir.cleanup()

    def _create_hook(self, name: str, script_body: str, executable: bool = True) -> Path:
        hook_path = self.hooks_dir / name
        hook_path.write_text(script_body, encoding="utf-8")
        if executable:
            current = hook_path.stat().st_mode
            hook_path.chmod(current | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        return hook_path

    def test_successful_hook_execution(self):
        """Test that a well-behaved executable hook runs and receives the palette JSON path."""
        out_file = self.tmp_path / "hook_out.txt"
        script = f"""#!/bin/sh
echo "HOOK_ARG=$1" > {out_file}
exit 0
"""
        self._create_hook("01-success.sh", script)

        results = set_wallpaper.run_theme_hooks(
            palette_path=self.palette_file,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )

        self.assertEqual(len(results), 1)
        self.assertTrue(results[0]["ok"])
        self.assertEqual(results[0]["hook"], "01-success.sh")
        self.assertTrue(out_file.exists())
        self.assertIn(f"HOOK_ARG={self.palette_file.resolve()}", out_file.read_text())

    def test_invalid_palette_json(self):
        """Test that invalid palette JSON prevents hook execution and logs error."""
        bad_json = self.tmp_path / "bad.json"
        bad_json.write_text("NOT_VALID_JSON{", encoding="utf-8")

        self._create_hook("01-should-not-run.sh", "#!/bin/sh\nexit 0\n")

        results = set_wallpaper.run_theme_hooks(
            palette_path=bad_json,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )

        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["ok"])
        self.assertIn("validation error", results[0]["error"].lower())
        self.assertTrue(self.log_file.exists())
        self.assertIn("validation error", self.log_file.read_text().lower())

    def test_palette_missing_essential_keys(self):
        """Test that incomplete palette JSON is rejected before running hooks."""
        incomplete = self.tmp_path / "incomplete.json"
        incomplete.write_text(json.dumps({"some_key": "some_value"}), encoding="utf-8")

        self._create_hook("01-should-not-run.sh", "#!/bin/sh\nexit 0\n")

        results = set_wallpaper.run_theme_hooks(
            palette_path=incomplete,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )

        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["ok"])
        self.assertIn("missing essential keys", results[0]["error"].lower())

    def test_hook_timeout(self):
        """Test that a long-running hook is aborted after the configurable timeout without blocking."""
        script = """#!/bin/sh
sleep 5
exit 0
"""
        self._create_hook("01-slow.sh", script)

        start = time.time()
        results = set_wallpaper.run_theme_hooks(
            palette_path=self.palette_file,
            hooks_dir=self.hooks_dir,
            timeout=0.6,
            log_file=self.log_file,
        )
        elapsed = time.time() - start

        self.assertLess(elapsed, 3.0)
        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["ok"])
        self.assertTrue(results[0].get("timed_out"))
        self.assertTrue(self.log_file.exists())
        self.assertIn("timed out", self.log_file.read_text().lower())

    def test_one_failing_hook_while_another_succeeds(self):
        """Test isolation: failing hook does not stop subsequent hooks or abort pipeline."""
        fail_script = """#!/bin/sh
echo "intentional crash" >&2
exit 42
"""
        succ_out = self.tmp_path / "succ.txt"
        succ_script = f"""#!/bin/sh
echo "all good" > {succ_out}
exit 0
"""
        self._create_hook("01-fail.sh", fail_script)
        self._create_hook("02-success.sh", succ_script)

        results = set_wallpaper.run_theme_hooks(
            palette_path=self.palette_file,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )

        self.assertEqual(len(results), 2)
        # Hook 1 failed
        self.assertFalse(results[0]["ok"])
        self.assertEqual(results[0]["hook"], "01-fail.sh")
        self.assertEqual(results[0]["code"], 42)
        # Hook 2 succeeded
        self.assertTrue(results[1]["ok"])
        self.assertEqual(results[1]["hook"], "02-success.sh")
        self.assertTrue(succ_out.exists())
        # Logged failure
        self.assertTrue(self.log_file.exists())
        log_content = self.log_file.read_text()
        self.assertIn("01-fail.sh", log_content)
        self.assertIn("code 42", log_content)

    def test_non_executable_files_skipped(self):
        """Test that files without executable bit are skipped gracefully."""
        self._create_hook("notes.txt", "just a note", executable=False)
        succ_script = """#!/bin/sh
exit 0
"""
        self._create_hook("01-run.sh", succ_script, executable=True)

        results = set_wallpaper.run_theme_hooks(
            palette_path=self.palette_file,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["hook"], "01-run.sh")

    def test_missing_hooks_directory(self):
        """Test that non-existent hooks directory returns empty list without error."""
        non_existent = self.tmp_path / "does-not-exist"
        results = set_wallpaper.run_theme_hooks(
            palette_path=self.palette_file,
            hooks_dir=non_existent,
            log_file=self.log_file,
        )
        self.assertEqual(results, [])

    def test_missing_palette_file(self):
        """Test that non-existent palette file returns error and logs cleanly."""
        missing = self.tmp_path / "missing.json"
        results = set_wallpaper.run_theme_hooks(
            palette_path=missing,
            hooks_dir=self.hooks_dir,
            log_file=self.log_file,
        )
        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["ok"])
        self.assertIn("does not exist", results[0]["error"])

    def test_atomic_write_safety(self):
        """Test that atomic_write safely overwrites without leaving partial writes on failure."""
        target = self.tmp_path / "atomic_target.txt"
        target.write_text("original content", encoding="utf-8")

        theme_common.atomic_write(target, "new content")
        self.assertEqual(target.read_text(encoding="utf-8"), "new content")

        # Verify no temp files left behind
        temp_files = list(self.tmp_path.glob(".*tmp-*"))
        self.assertEqual(len(temp_files), 0)


if __name__ == "__main__":
    unittest.main()
