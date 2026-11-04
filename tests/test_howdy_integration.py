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
LOCK_EXTRA = ROOT / "scripts" / "lock-extra.sh"
SETUP_LOCKSCREEN = ROOT / "scripts" / "setup-lockscreen.sh"
FACELOCK_QML = ROOT / "island" / "states" / "FaceLock.qml"


class HowdyHyprlockConfigTests(unittest.TestCase):
    """Verifies that hyprlock.conf correctly references the PAM service and honest labeling."""

    def test_hyprlock_conf_specifies_auth_pam_module(self):
        self.assertTrue(HYPRLOCK_CONF.is_file(), f"Missing {HYPRLOCK_CONF}")
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        # Ensure supported auth block syntax
        self.assertRegex(
            content,
            r"auth\s*\{[^}]*pam:enabled\s*=\s*true",
            "hyprlock.conf must specify pam:enabled = true in auth block",
        )
        self.assertRegex(
            content,
            r"auth\s*\{[^}]*pam:module\s*=\s*hyprlock",
            "hyprlock.conf must specify pam:module = hyprlock in auth block",
        )
        # Ensure deprecated/unsupported general:pam_module is absent
        self.assertNotRegex(
            content,
            r"general\s*\{[^}]*pam_module",
            "hyprlock.conf must not use invalid general:pam_module in Hyprlock 0.9.7",
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

    def test_hyprlock_conf_lock_root_and_script_references(self):
        content = HYPRLOCK_CONF.read_text(encoding="utf-8")
        self.assertIn("source = ~/.config/hypr/lock-root.conf", content)
        self.assertIn("$info = $GPS_ROOT/scripts/lock-info.sh", content)
        self.assertIn("$extra = $GPS_ROOT/scripts/lock-extra.sh", content)


class HowdyLockScriptsTests(unittest.TestCase):
    """Verifies lock-info.sh and lock-extra.sh execution without relying on GPS_ROOT in environment."""

    def setUp(self):
        self.clean_env = os.environ.copy()
        self.clean_env.pop("GPS_ROOT", None)

    def test_lock_script_executables_exist_and_executable(self):
        self.assertTrue(LOCK_INFO.is_file(), f"Missing {LOCK_INFO}")
        self.assertTrue(os.access(LOCK_INFO, os.X_OK), f"{LOCK_INFO} is not executable")
        self.assertTrue(LOCK_EXTRA.is_file(), f"Missing {LOCK_EXTRA}")
        self.assertTrue(os.access(LOCK_EXTRA, os.X_OK), f"{LOCK_EXTRA} is not executable")

    def test_howdy_status_executes_safely_without_gps_root(self):
        res = subprocess.run(
            [str(LOCK_INFO), "howdy-status"],
            env=self.clean_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0, f"Stderr: {res.stderr}")
        output = res.stdout.strip()
        self.assertTrue(len(output) > 0)
        self.assertTrue(
            any(k in output for k in ["Armed", "Ready", "Enrolled", "Not configured"]),
            f"Unexpected howdy-status output: {output}",
        )

    def test_auth_and_sockets_execute_safely_without_gps_root(self):
        for subcmd in ["auth", "sockets", "user", "host", "bat"]:
            res = subprocess.run(
                [str(LOCK_INFO), subcmd],
                env=self.clean_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            self.assertEqual(res.returncode, 0, f"Command {subcmd} failed: {res.stderr}")

    def test_lock_extra_executes_safely_without_gps_root(self):
        for subcmd in ["greeting", "media-state", "volume", "profile"]:
            res = subprocess.run(
                [str(LOCK_EXTRA), subcmd],
                env=self.clean_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            self.assertEqual(res.returncode, 0, f"lock-extra.sh {subcmd} failed: {res.stderr}")


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
