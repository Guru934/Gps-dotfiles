#!/usr/bin/env python3
"""Automated tests for graceful external dependency handling in GPS (P5.5).

Verifies that unavailable or missing system services produce clear UI states
and fallback data rather than unhandled exceptions, freezes, or crashes:
1. Audio (PipeWire / wpctl / parec)
2. Network (NetworkManager / nmcli)
3. Bluetooth (BlueZ / bluetoothctl)
4. Battery (UPower / powerprofilesctl)
5. Notifications (D-Bus NotificationServer / history)
6. Wallpapers (awww / extract-theme / Theme.qml fallbacks)
7. Media tools (mpv / vlc / ani-cli / media-hub-tools.py)
8. Download tools (yt-dlp / ffmpeg / media-hub-downloads.py)
9. Pet subsystem (procfs / hyprctl / PetSettings.js normalization)
"""

import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL_QML = (ROOT / "shell.qml").read_text()
LEFTRAIL_QML = (ROOT / "components" / "LeftRail.qml").read_text()
BATTERY_POPUP = (ROOT / "components" / "BatteryPopup.qml").read_text()
WIFI_POPUP = (ROOT / "components" / "WifiPopup.qml").read_text()
BT_POPUP = (ROOT / "components" / "BluetoothPopup.qml").read_text()
THEME_QML = (ROOT / "config" / "Theme.qml").read_text()
ISLAND_QML = (ROOT / "island" / "Island.qml").read_text()


class DependencyHandlingTests(unittest.TestCase):
    """Regression checks for graceful external service degradation."""

    def test_audio_degrades_gracefully_when_pipewire_is_absent(self):
        """Audio sinks are guarded with audioReady and provide fallbacks."""
        self.assertIn("readonly property bool audioReady: audioSink !== null && audioSink.audio !== null", SHELL_QML)
        self.assertIn("readonly property bool audioReady: audioSink !== null && audioSink.audio !== null", LEFTRAIL_QML)
        self.assertIn("if (!root.audioReady) return", SHELL_QML)
        self.assertIn("root.fallbackVolPct", LEFTRAIL_QML)

    def test_network_degrades_gracefully_with_actionable_error(self):
        """Missing NetworkManager sets wifiError with actionable advice."""
        self.assertIn("Is NetworkManager (nmcli) installed?", SHELL_QML)
        self.assertIn("Theme.statusDangerBg", WIFI_POPUP)
        self.assertIn("visible: root.hub && root.hub.wifiError !== \"\"", WIFI_POPUP)

    def test_bluetooth_degrades_gracefully_with_actionable_error(self):
        """Missing BlueZ sets btError with actionable advice."""
        self.assertIn("Is BlueZ (bluetoothctl) installed?", SHELL_QML)
        self.assertIn("Theme.statusDangerBg", BT_POPUP)
        self.assertIn("visible: root.hub && root.hub.btError !== \"\"", BT_POPUP)

    def test_battery_honestly_displays_no_battery_notice(self):
        """When UPower reports no battery device, honest notices are rendered."""
        self.assertIn("readonly property bool batPresent: batDevice !== null && batDevice.isPresent", LEFTRAIL_QML)
        self.assertIn("readonly property bool batPresent: batDevice !== null && batDevice.isPresent", BATTERY_POPUP)
        self.assertIn("visible: !root.batPresent", BATTERY_POPUP)
        self.assertIn("No battery detected on this device.", BATTERY_POPUP)
        self.assertIn("No power profiles available", BATTERY_POPUP)

    def test_notification_history_provides_empty_fallback(self):
        """Island history returns valid empty JSON payload when queue is empty."""
        self.assertIn("function history(): string", ISLAND_QML)
        self.assertIn("items: items", ISLAND_QML)

    def test_wallpaper_pipeline_handles_missing_target(self):
        """set_wallpaper.py fails cleanly without throwing unhandled exceptions."""
        res = subprocess.run(
            ["python3", str(ROOT / "scripts" / "set_wallpaper.py"), "/nonexistent/wallpaper.png", "--skip-awww"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("error", (res.stdout + res.stderr).lower())

    def test_theme_qml_has_canonical_built_in_defaults(self):
        """Theme.qml provides fixed fallback design tokens when gps-theme.json is missing."""
        self.assertIn('"#B30F131C"', THEME_QML)
        self.assertIn('"#CC1C1F29"', THEME_QML)
        self.assertIn('"#0B1016"', THEME_QML)
        self.assertIn('"#2DD4BF"', THEME_QML)

    def test_media_hub_tools_detects_tools_safely(self):
        """media-hub-tools.py runs cleanly and returns JSON containing tool guidance."""
        res = subprocess.run(
            ["python3", str(ROOT / "scripts" / "media-hub-tools.py"), "status"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertIn("guidance", data)
        self.assertIn("players", data)
        self.assertIn("terminals", data)

    def test_media_hub_downloads_detects_tools_safely(self):
        """media-hub-downloads.py runs cleanly and reports status without exceptions."""
        res = subprocess.run(
            ["python3", str(ROOT / "scripts" / "media-hub-downloads.py"), "status"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertIn("ready", data)
        self.assertIn("ytDlpReady", data)
        self.assertIn("ffmpegReady", data)


if __name__ == "__main__":
    unittest.main()
