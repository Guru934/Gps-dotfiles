#!/usr/bin/env python3
"""Unit tests for GPS Sound Engine (rate limiter, mic suppression, DND rules, dedupe, capping)."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import sound_engine
from scripts.sound_engine import (
    DEFAULT_SETTINGS,
    SoundEngine,
    SoundStateStore,
    is_allowed_sound_file,
    is_dnd_active,
    resolve_sound_file,
)


class MockClock:
    def __init__(self, start: float = 1000.0):
        self.current = start

    def __call__(self) -> float:
        return self.current

    def advance(self, seconds: float):
        self.current += seconds


class SoundEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.state_file = self.temp_path / "sound_state.json"
        self.state_store = SoundStateStore(self.state_file)
        self.clock = MockClock(1000.0)

        # Create a mock theme and dummy sound file
        self.themes_root = self.temp_path / "themes"
        self.default_theme = self.themes_root / "default"
        self.default_theme.mkdir(parents=True, exist_ok=True)
        self.dummy_sound = self.default_theme / "chime.wav"
        self.dummy_sound.write_bytes(b"RIFFdummyWAVEfmt ")
        self.dummy_crit = self.default_theme / "crit.wav"
        self.dummy_crit.write_bytes(b"RIFFdummyWAVEfmt ")
        self.dummy_agent = self.default_theme / "agent.wav"
        self.dummy_agent.write_bytes(b"RIFFdummyWAVEfmt ")
        self.dummy_tick = self.default_theme / "tick.wav"
        self.dummy_tick.write_bytes(b"RIFFdummyWAVEfmt ")

        self.theme_manifest = self.default_theme / "theme.json"
        self.theme_manifest.write_text(
            json.dumps({
                "notification": "chime.wav",
                "critical": "crit.wav",
                "notification-critical": "crit.wav",
                "agent-permission": "agent.wav",
                "tick": "tick.wav",
            }),
            encoding="utf-8",
        )

        self.settings = dict(DEFAULT_SETTINGS)
        self.settings["volume"] = 0.8
        self.settings["volumeCap"] = 1.0
        self.settings["rateLimitSeconds"] = 1.5
        self.settings["dedupeWindowSeconds"] = 3.0
        self.settings["agentDedupeWindowSeconds"] = 5.0
        self.settings["soundsBypassDnd"] = True
        self.settings["quietWhileMicInUse"] = True

        self.dnd_active = False
        self.mic_in_use = False

    def tearDown(self):
        self.temp_dir.cleanup()

    def make_engine(self, **overrides) -> SoundEngine:
        cfg = dict(self.settings)
        cfg.update(overrides)
        return SoundEngine(
            settings=cfg,
            dnd_active_fn=lambda: self.dnd_active,
            mic_in_use_fn=lambda: self.mic_in_use,
            state_store=self.state_store,
            clock_fn=self.clock,
            themes_root=self.themes_root,
        )

    def test_basic_playback_evaluation(self):
        engine = self.make_engine()
        d = engine.evaluate("notification")
        self.assertTrue(d.allowed)
        self.assertEqual(d.volume, 0.8)
        self.assertEqual(d.reason, "ok")
        self.assertEqual(d.sound_file, self.dummy_sound)

    def test_rate_limiter_drops_normal_sounds(self):
        engine = self.make_engine()
        # First sound passes
        d1 = engine.evaluate("notification", custom_dedupe_key="notif1")
        self.assertTrue(d1.allowed)

        # 0.5s later, second different sound is dropped by rate limit
        self.clock.advance(0.5)
        d2 = engine.evaluate("notification", custom_dedupe_key="notif2")
        self.assertFalse(d2.allowed)
        self.assertEqual(d2.reason, "rate_limited")

        # 1.6s later (total 2.1s), next sound passes
        self.clock.advance(1.6)
        d3 = engine.evaluate("notification", custom_dedupe_key="notif3")
        self.assertTrue(d3.allowed)

    def test_critical_and_agent_permission_never_dropped_by_rate_limit(self):
        engine = self.make_engine()
        # Play standard sound
        d1 = engine.evaluate("notification", custom_dedupe_key="notif1")
        self.assertTrue(d1.allowed)

        # Immediately (0.01s later), critical alert arrives -> must NOT be dropped
        self.clock.advance(0.01)
        d_crit = engine.evaluate("critical", custom_dedupe_key="crit1")
        self.assertTrue(d_crit.allowed)

        # Immediately (0.01s later), agent permission arrives -> must NOT be dropped
        self.clock.advance(0.01)
        d_agent = engine.evaluate("agent-permission", custom_dedupe_key="agent1")
        self.assertTrue(d_agent.allowed)

    def test_volume_tick_throttled_to_120ms(self):
        engine = self.make_engine()
        # First tick passes
        d1 = engine.evaluate("tick", custom_dedupe_key="tick1")
        self.assertTrue(d1.allowed)

        # 50ms later, second tick dropped (50ms < 120ms)
        self.clock.advance(0.050)
        d2 = engine.evaluate("tick", custom_dedupe_key="tick2")
        self.assertFalse(d2.allowed)
        self.assertEqual(d2.reason, "rate_limited")

        # Another 80ms later (total 130ms > 120ms), tick passes
        self.clock.advance(0.080)
        d3 = engine.evaluate("tick", custom_dedupe_key="tick3")
        self.assertTrue(d3.allowed)

    def test_quiet_while_mic_in_use(self):
        self.mic_in_use = True
        engine = self.make_engine(quietWhileMicInUse=True)

        # Normal sound dropped
        d_norm = engine.evaluate("notification")
        self.assertFalse(d_norm.allowed)
        self.assertEqual(d_norm.reason, "mic_in_use")

        # Critical sound passes
        d_crit = engine.evaluate("critical")
        self.assertTrue(d_crit.allowed)

        # Agent permission passes
        d_agent = engine.evaluate("agent-permission")
        self.assertTrue(d_agent.allowed)

        # If quietWhileMicInUse is disabled, normal sound passes
        engine_no_quiet = self.make_engine(quietWhileMicInUse=False)
        self.clock.advance(2.0)
        d_norm2 = engine_no_quiet.evaluate("notification")
        self.assertTrue(d_norm2.allowed)

    def test_dnd_bypass_rules(self):
        self.dnd_active = True

        # Case 1: soundsBypassDnd is True (default)
        engine = self.make_engine(soundsBypassDnd=True)
        # Normal sound dropped
        d_norm = engine.evaluate("notification")
        self.assertFalse(d_norm.allowed)
        self.assertEqual(d_norm.reason, "dnd_active")

        # Critical bypasses
        d_crit = engine.evaluate("critical")
        self.assertTrue(d_crit.allowed)

        # Agent-permission bypasses
        d_agent = engine.evaluate("agent-permission")
        self.assertTrue(d_agent.allowed)

        # Case 2: soundsBypassDnd is False -> ALL muted
        engine_strict = self.make_engine(soundsBypassDnd=False)
        self.clock.advance(2.0)
        d_crit_strict = engine_strict.evaluate("critical")
        self.assertFalse(d_crit_strict.allowed)
        self.assertEqual(d_crit_strict.reason, "dnd_active")

    def test_deduplication_key(self):
        engine = self.make_engine()
        # Normal sound with default key (event name)
        d1 = engine.evaluate("notification")
        self.assertTrue(d1.allowed)

        # 2.0s later, rate limit (1.5s) has passed, but dedupe (3.0s) drops it
        self.clock.advance(2.0)
        d2 = engine.evaluate("notification")
        self.assertFalse(d2.allowed)
        self.assertEqual(d2.reason, "deduplicated")

        # 3.1s after first play, sound is allowed again
        self.clock.advance(1.2)
        d3 = engine.evaluate("notification")
        self.assertTrue(d3.allowed)

    def test_agent_deduplication_window(self):
        engine = self.make_engine()
        # Agent permission arrives via pet-alert
        d1 = engine.evaluate("agent-permission", custom_dedupe_key="agent:opencode:rm_cmd")
        self.assertTrue(d1.allowed)

        # Same request arrives via desktop notification 1s later -> dropped
        self.clock.advance(1.0)
        d2 = engine.evaluate("agent-permission", custom_dedupe_key="agent:opencode:rm_cmd")
        self.assertFalse(d2.allowed)
        self.assertEqual(d2.reason, "deduplicated")

        # After 5.1s, another permission request with same key is allowed
        self.clock.advance(4.2)
        d3 = engine.evaluate("agent-permission", custom_dedupe_key="agent:opencode:rm_cmd")
        self.assertTrue(d3.allowed)

    def test_master_mute_and_volume_capping(self):
        # Master mute
        engine_muted = self.make_engine(muted=True)
        d = engine_muted.evaluate("notification")
        self.assertFalse(d.allowed)
        self.assertEqual(d.reason, "master_muted")

        # Volume cap
        engine_capped = self.make_engine(
            volume=0.9,
            volumeCap=0.5,
            events={"notification": {"volume": 1.0, "enabled": True}},
        )
        d_cap = engine_capped.evaluate("notification")
        self.assertTrue(d_cap.allowed)
        self.assertEqual(d_cap.volume, 0.5)

        # Per-event disabled
        engine_ev_disabled = self.make_engine(
            events={"notification": {"enabled": False}},
        )
        d_dis = engine_ev_disabled.evaluate("notification")
        self.assertFalse(d_dis.allowed)
        self.assertEqual(d_dis.reason, "event_disabled")

    def test_missing_pw_play_fallback(self):
        engine = self.make_engine()
        with patch("shutil.which", return_value=None):
            played, reason = engine.play("notification")
            # Must degrade silently (return True or ok, no exception)
            self.assertTrue(played)
            self.assertEqual(reason, "pw_play_missing_silent")

    def test_sound_file_allowlist(self):
        # A file in repo assets/sounds is allowed
        repo_sound = Path(sound_engine.get_repo_root()) / "assets" / "sounds" / "test.wav"
        repo_sound.parent.mkdir(parents=True, exist_ok=True)
        repo_sound.write_bytes(b"dummy")
        self.assertTrue(is_allowed_sound_file(repo_sound))

        # A file in /tmp or random directory is NOT allowed
        random_file = self.temp_path / "secret.wav"
        random_file.write_bytes(b"secret")
        self.assertFalse(is_allowed_sound_file(random_file))


if __name__ == "__main__":
    unittest.main()
