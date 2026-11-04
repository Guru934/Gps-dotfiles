#!/usr/bin/env python3
"""Automated hermetic tests for GPS Howdy Face Authentication integration across

Hyprlock, SDDM, and Island.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HYPRLOCK_CONF = ROOT / "dots" / "hypr" / "hyprlock.conf"
LOCK_INFO = ROOT / "scripts" / "lock-info.sh"
SETUP_LOCKSCREEN = ROOT / "scripts" / "setup-lockscreen.sh"
FACELOCK_QML = ROOT / "island" / "states" / "FaceLock.qml"


class HowdyHyprlockConfigTests(unittest.TestCase):
    """Verifies that hyprlock.conf correctly references the PAM service and honest labeling."""

    def test_hyprlock_conf_specifies_pam_module(self):
        self.assertTrue(HYPRLOCK_CONF.is_file(), f"Missing {HYPRLOCK_CONF}")
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertRegex(
            content,
            r"general\s*\{[^}]*pam_module\s*=\s*hyprlock",
            "hyprlock.conf general block must explicitly specify pam_module = hyprlock",
        )

    def test_hyprlock_conf_honest_camera_labeling(self):
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertNotIn(
            "Howdy IR Face",
            content,
            "hyprlock.conf must not represent standard RGB webcam as an IR camera",
        )
        self.assertIn("Howdy Face Unlock", content)

    def test_hyprlock_conf_queries_howdy_status(self):
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertIn("$info howdy-status", content)


class HowdyLockInfoScriptTests(unittest.TestCase):
    """Verifies lock-info.sh howdy-status, auth, and sockets reporting."""

    def test_howdy_status_executes_safely(self):
        res = subprocess.run(
            [str(LOCK_INFO), "howdy-status"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        output = res.stdout.strip()
        self.assertTrue(len(output) > 0)
        self.assertIn(
            any(k in output for k in ["Armed", "Ready", "Enrolled", "Not configured"]),
            [True],
            f"Unexpected howdy-status output: {output}",
        )

    def test_sockets_executes_safely(self):
        res = subprocess.run(
            [str(LOCK_INFO), "sockets"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("SOCKET", res.stdout)


class HowdySetupLockscreenSelfTests(unittest.TestCase):
    """Verifies that setup-lockscreen.sh passes its hermetic self-test suite."""

    def test_setup_lockscreen_self_test(self):
        res = subprocess.run(
            [str(SETUP_LOCKSCREEN), "--self-test"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        self.assertEqual(res.returncode, 0, f"Self-test failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("0 failed", res.stdout)


class HowdyIslandFaceLockTests(unittest.TestCase):
    """Verifies that Island's FaceLock component is an honest status and control interface."""

    def setUp(self):
        self.assertTrue(FACELOCK_QML.is_file(), f"Missing {FACELOCK_QML}")
        self.content = FACELOCK_QML.read_text(encoding="utf-8")

    def test_facelock_registers_key(self):
        self.assertIn('readonly property string key: "facelock"', self.content)
        self.assertIn("core.register(key, st)", self.content)

    def test_no_mock_prototype_stubs(self):
        self.assertNotIn("Visual prototype · authentication backend not connected", self.content)
        self.assertNotIn("NO SYSTEM ACTION", self.content)
        self.assertNotIn("UI ONLY", self.content)

    def test_honest_security_notice(self):
        self.assertIn("RGB webcam", self.content)
        self.assertIn("PAM authoritative", self.content)
        self.assertIn("Password authentication is always preserved as primary fallback", self.content)

    def test_safe_test_action_provided(self):
        self.assertIn("TEST SCAN", self.content)
        self.assertIn("compare.py", self.content)
        self.assertIn("LOCK NOW", self.content)


if __name__ == "__main__":
    unittest.main()
