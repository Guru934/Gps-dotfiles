#!/usr/bin/env python3
"""Guard tests to verify test suite hermeticity and prevent spawning real desktop daemons."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tests.helpers import (
    HermeticTestCase,
    HermeticEnv,
    PROHIBITED_REAL_BINARIES,
)


class HermeticGuardTests(HermeticTestCase):
    """Guard tests ensuring tests cannot execute real system daemons."""

    def test_stubs_intercept_all_prohibited_binaries(self):
        """Verify that PATH resolution in HermeticEnv resolves each binary to our stub."""
        for binary in PROHIBITED_REAL_BINARIES:
            resolved = shutil.which(binary, path=self.env["PATH"])
            self.assertIsNotNone(
                resolved,
                f"Stub for prohibited binary '{binary}' was not found in PATH"
            )
            resolved_path = Path(resolved).resolve()
            stubs_dir = self.hermetic.stubs.resolve()
            self.assertTrue(
                str(resolved_path).startswith(str(stubs_dir)),
                f"'{binary}' resolved to real binary '{resolved_path}' instead of stub in '{stubs_dir}'!"
            )

    def test_prohibited_binaries_record_invocations_and_do_not_execute_real(self):
        """Calling each prohibited binary via hermetic environment logs to stub log."""
        test_calls = [
            ("hypridle", ["-v"]),
            ("quickshell", ["--version"]),
            ("pw-play", ["--latency", "50ms", "/dummy.wav"]),
            ("ydotool", ["type", "hello"]),
            ("awww", ["img", "wall.png"]),
            ("wl-paste", ["--list-types"]),
            ("wl-copy", []),
        ]

        for binary, args in test_calls:
            res = self.hermetic.run([binary] + args, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"Stub {binary} failed with {res.returncode}")

        logged_calls = self.hermetic.get_stub_calls()
        for binary, _ in test_calls:
            matching = [line for line in logged_calls if f"STUB_CALL:{binary}:" in line]
            self.assertTrue(
                len(matching) > 0,
                f"Stub execution for '{binary}' was not logged! Logged calls: {logged_calls}"
            )

    def test_no_test_hardcodes_prohibited_real_binaries(self):
        """Grep guard: verify no test file invokes /usr/bin/<prohibited_binary> in subprocesses."""
        test_dirs = [
            ROOT / "tests",
            ROOT / "island" / "tests",
            ROOT / "pet" / "tests",
        ]

        prohibited_exec_patterns = [
            re.compile(rf'["\']/usr/bin/{re.escape(b)}["\']')
            for b in PROHIBITED_REAL_BINARIES
        ] + [
            re.compile(rf'["\']/bin/{re.escape(b)}["\']')
            for b in PROHIBITED_REAL_BINARIES
        ]

        violations = []
        for d in test_dirs:
            if not d.is_dir():
                continue
            for f in d.glob("*"):
                if f.is_file() and f.suffix in (".py", ".js", ".sh"):
                    # Exclude the guard test itself
                    if f.name == "test_hermetic_guards.py" or f.name == "helpers.py":
                        continue
                    text = f.read_text(encoding="utf-8", errors="replace")
                    for pat in prohibited_exec_patterns:
                        match = pat.search(text)
                        if match:
                            # Allow matches if they are in comments or string assertions like assertIn('quickshell...')
                            lines = text.splitlines()
                            for line_no, line in enumerate(lines, 1):
                                if match.group(0) in line:
                                    stripped = line.strip()
                                    # If line is an assertion about script contents (e.g. assertIn('/usr/bin/quickshell...')), allow it
                                    if "assertIn" in stripped or "assertEqual" in stripped or stripped.startswith("#") or stripped.startswith("//"):
                                        continue
                                    violations.append(f"{f.name}:{line_no}: {stripped}")

        self.assertEqual(
            violations,
            [],
            f"Found test files hardcoding execution of prohibited real binaries:\n" + "\n".join(violations)
        )

    def test_wayland_display_is_empty_in_hermetic_env(self):
        """WAYLAND_DISPLAY and DISPLAY must be empty in HermeticEnv to prevent socket connections."""
        self.assertEqual(self.env.get("WAYLAND_DISPLAY"), "")
        self.assertEqual(self.env.get("DISPLAY"), "")
        self.assertEqual(self.env.get("HYPRLAND_INSTANCE_SIGNATURE"), "")


if __name__ == "__main__":
    unittest.main()
