#!/usr/bin/env python3
"""End-to-end integration tests for GPS sound system:

- Deduplication of simultaneous pet-alert and desktop notification (plays once within 5s)
- DND rules: normal notification muted, agent-permission and critical bypass DND
- Mic-in-use simulation: normal muted, agent-permission and critical bypass
- Burst of 50 rapid notifications handled gracefully under rate limiter
"""

import json
import os
import subprocess
import tempfile
import time
import unittest
import sys
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts import sound_engine
from scripts.sound_engine import (
    DEFAULT_SETTINGS,
    SoundEngine,
    SoundStateStore,
    is_dnd_active,
)


class GpsSoundIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.state_file = self.temp_path / "sound_state.json"
        self.state_store = SoundStateStore(self.state_file)
        self.dnd_file = self.temp_path / "dnd.json"

        # Setup mock themes
        self.themes_root = self.temp_path / "themes"
        self.default_theme = self.themes_root / "default"
        self.default_theme.mkdir(parents=True)
        (self.default_theme / "chime.ogg").write_bytes(b"dummy")
        (self.default_theme / "crit.ogg").write_bytes(b"dummy")
        (self.default_theme / "agent.ogg").write_bytes(b"dummy")
        (self.default_theme / "theme.json").write_text(
            json.dumps({
                "notification": "chime.ogg",
                "critical": "crit.ogg",
                "notification-critical": "crit.ogg",
                "agent-permission": "agent.ogg",
            }),
            encoding="utf-8",
        )

        self.current_time = 1700000000.0
        self.mic_active = False

    def tearDown(self):
        self.temp_dir.cleanup()

    def clock(self) -> float:
        return self.current_time

    def get_engine(self, settings=None) -> SoundEngine:
        cfg = dict(DEFAULT_SETTINGS)
        if settings:
            cfg.update(settings)
        return SoundEngine(
            settings=cfg,
            dnd_active_fn=lambda: is_dnd_active(self.dnd_file, self.current_time * 1000.0),
            mic_in_use_fn=lambda: self.mic_active,
            state_store=self.state_store,
            clock_fn=self.clock,
            themes_root=self.themes_root,
        )

    def test_simultaneous_pet_alert_and_desktop_notification_dedupes(self):
        """Simultaneous agent permission request via pet-alert and desktop notification plays exactly once."""
        engine = self.get_engine()

        # Channel 1: pet-alert fires with agent:codex:echo
        dedupe_key = "agent:codex:echopetalerttest"
        dec1 = engine.evaluate("agent-permission", custom_dedupe_key=dedupe_key)
        self.assertTrue(dec1.allowed, "First agent permission alert must play")

        # Channel 2: desktop notification arrives 0.2s later with same key
        self.current_time += 0.2
        dec2 = engine.evaluate("agent-permission", custom_dedupe_key=dedupe_key)
        self.assertFalse(dec2.allowed, "Duplicate agent alert arriving within 5s must be suppressed")
        self.assertEqual(dec2.reason, "deduplicated")

        # Channel 3: another simultaneous notification 1s later
        self.current_time += 1.0
        dec3 = engine.evaluate("agent-permission", custom_dedupe_key=dedupe_key)
        self.assertFalse(dec3.allowed)
        self.assertEqual(dec3.reason, "deduplicated")

        # After 5.1s, next request with same key is allowed
        self.current_time += 4.0  # total 5.2s
        dec4 = engine.evaluate("agent-permission", custom_dedupe_key=dedupe_key)
        self.assertTrue(dec4.allowed)

    def test_dnd_on_normal_and_agent_permission(self):
        """When DND is active, normal notifications are muted, but agent-permission and critical play."""
        self.dnd_file.write_text(json.dumps({"mode": "dnd", "allowCritical": True}), encoding="utf-8")
        engine = self.get_engine({"soundsBypassDnd": True})

        # Normal notification
        dec_normal = engine.evaluate("notification", custom_dedupe_key="n1")
        self.assertFalse(dec_normal.allowed)
        self.assertEqual(dec_normal.reason, "dnd_active")

        # Critical notification
        dec_crit = engine.evaluate("critical", custom_dedupe_key="c1")
        self.assertTrue(dec_crit.allowed, "Critical alert must bypass DND when soundsBypassDnd is True")

        # Agent permission
        dec_agent = engine.evaluate("agent-permission", custom_dedupe_key="agent:1")
        self.assertTrue(dec_agent.allowed, "Agent permission must bypass DND when soundsBypassDnd is True")

        # With soundsBypassDnd = False
        engine_no_bypass = self.get_engine({"soundsBypassDnd": False})
        self.current_time += 2.0
        dec_agent_blocked = engine_no_bypass.evaluate("agent-permission", custom_dedupe_key="agent:2")
        self.assertFalse(dec_agent_blocked.allowed)
        self.assertEqual(dec_agent_blocked.reason, "dnd_active")

    def test_mic_in_use_simulation(self):
        """When microphone is in use, standard sounds are quieted, but critical and agent permission play."""
        self.mic_active = True
        engine = self.get_engine({"quietWhileMicInUse": True})

        dec_norm = engine.evaluate("notification", custom_dedupe_key="n1")
        self.assertFalse(dec_norm.allowed)
        self.assertEqual(dec_norm.reason, "mic_in_use")

        dec_crit = engine.evaluate("critical", custom_dedupe_key="c1")
        self.assertTrue(dec_crit.allowed, "Critical sounds must play during mic in use")

        dec_agent = engine.evaluate("agent-permission", custom_dedupe_key="agent:1")
        self.assertTrue(dec_agent.allowed, "Agent permission sounds must play during mic in use")

    def test_burst_of_50_notifications(self):
        """A burst of 50 rapid notifications is cleanly handled by the rate limiter without errors."""
        engine = self.get_engine({"rateLimitSeconds": 1.5})
        played = 0
        dropped = 0

        # Send 50 notifications 10ms apart (total 0.5s)
        for i in range(50):
            dec = engine.evaluate("notification", custom_dedupe_key=f"burst_{i}")
            if dec.allowed:
                played += 1
            else:
                self.assertEqual(dec.reason, "rate_limited")
                dropped += 1
            self.current_time += 0.010

        self.assertEqual(played, 1, "In a 0.5s burst, exactly one normal notification must play")
        self.assertEqual(dropped, 49, "The remaining 49 notifications must be rate limited")

        # Advance 1.6s
        self.current_time += 1.6
        dec_after = engine.evaluate("notification", custom_dedupe_key="after_burst")
        self.assertTrue(dec_after.allowed, "After 1.5s cooldown, notifications resume playback")


if __name__ == "__main__":
    unittest.main()
