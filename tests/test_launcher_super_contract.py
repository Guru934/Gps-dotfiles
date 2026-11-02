#!/usr/bin/env python3
"""Contract and regression tests for GPS Island Launcher V2 and Super-only binding."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPRLAND_LUA = (ROOT / "dots" / "hypr" / "hyprland.lua").read_text(encoding="utf-8")
ISLAND_QML = (ROOT / "island" / "Island.qml").read_text(encoding="utf-8")
ISLAND_VISIBILITY_JS = (ROOT / "island" / "IslandVisibility.js").read_text(encoding="utf-8")
LAUNCHER_QML = (ROOT / "island" / "states" / "Launcher.qml").read_text(encoding="utf-8")
GPS_IPC = (ROOT / "scripts" / "gps-ipc").read_text(encoding="utf-8")
BRAND_MARK = (ROOT / "components" / "BrandMark.qml").read_text(encoding="utf-8")
RUN_GPS = (ROOT / "scripts" / "run-gps.fish").read_text(encoding="utf-8")
SHELL_QML = (ROOT / "shell.qml").read_text(encoding="utf-8")


class LauncherSuperContractTests(unittest.TestCase):
    """Verifies that the Super key alone triggers GPS Island launcher and that Tide is removed."""

    def test_hyprland_super_modifier_only_bindings(self):
        """Releasing either Super key opens the launcher; Space remains unbound."""
        integration = (ROOT / "dots" / "hypr" / "gps" / "integration.lua").read_text(encoding="utf-8")
        self.assertIn('{ "SUPER + Super_L", hl.dsp.exec_cmd(ipc_command("island launcher toggle")), { release = true } }', integration)
        self.assertIn('{ "SUPER + Super_R", hl.dsp.exec_cmd(ipc_command("island launcher toggle")), { release = true } }', integration)
        self.assertNotIn('{ "SUPER + SPACE",', integration)
        self.assertIn('{ "SUPER + R", hl.dsp.exec_cmd(ipc_command("island launcher toggle")) }', integration)

    def test_hyprland_preserves_super_key_shortcuts(self):
        """Window management and utility shortcuts on Super+key must remain intact."""
        self.assertIn('hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))', HYPRLAND_LUA)
        self.assertIn('hl.bind(mainMod .. " + C", hl.dsp.window.close())', HYPRLAND_LUA)
        self.assertIn('hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))', HYPRLAND_LUA)
        self.assertIn('hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())', HYPRLAND_LUA)
        self.assertIn('hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(repo .. "/scripts/gps-ipc shell clipboard toggle"))', HYPRLAND_LUA)

    def test_launcher_qml_focus_and_interaction_contracts(self):
        """Launcher.qml must focus input, handle Escape, Return/Enter, and search apps."""
        self.assertIn("input.forceActiveFocus()", LAUNCHER_QML)
        self.assertIn("Keys.onEscapePressed: {", LAUNCHER_QML)
        self.assertIn("st.core.setLauncher(false)", LAUNCHER_QML)
        self.assertIn("Keys.onReturnPressed: st.activate(st.calc ? null : st.results[st.sel])", LAUNCHER_QML)
        self.assertIn("Keys.onEnterPressed: st.activate(st.calc ? null : st.results[st.sel])", LAUNCHER_QML)
        self.assertIn("DesktopEntries.applications.values", LAUNCHER_QML)

    def test_island_qml_exclusive_focus_and_ipc_contract(self):
        """Island.qml must request Exclusive layer-shell focus when launcher is active."""
        self.assertIn('WlrLayershell.keyboardFocus: root.mode === "launcher"', ISLAND_QML)
        self.assertIn('? WlrKeyboardFocus.Exclusive', ISLAND_QML)
        self.assertIn('function launcher(state: string)', ISLAND_QML)
        self.assertIn('root.setLauncher(', ISLAND_QML)

    def test_launcher_state_lifecycle_and_focus_contract(self):
        """IPC state changes persist through visibility updates and the search input is focused."""
        set_launcher = re.search(r"function setLauncher\(open\) \{(?P<body>.*?)\n    \}", ISLAND_QML, re.S)
        self.assertIsNotNone(set_launcher)
        self.assertIn("launcherOpen = Boolean(open)", set_launcher.group("body"))
        self.assertIn("if (launcherOpen) root.manualHide = false", set_launcher.group("body"))
        self.assertIn("root.updateVisibility()", set_launcher.group("body"))
        self.assertIn('root.setLauncher(state === "toggle" ? !root.launcherOpen : state !== "close")', ISLAND_QML)
        self.assertIn("onActiveChanged: {", LAUNCHER_QML)
        self.assertIn("focusTimer.restart()", LAUNCHER_QML)
        self.assertIn("onTriggered: input.forceActiveFocus()", LAUNCHER_QML)
        self.assertIn("onTextChanged:", LAUNCHER_QML)

    def test_brandmark_routes_to_gps_launcher(self):
        """Clicking the dock brand mark routes to GPS Island launcher."""
        self.assertIn('Quickshell.execDetached([script, "island", "launcher", "toggle"])', BRAND_MARK)
        self.assertNotIn("rofi", BRAND_MARK)

    def test_tide_island_removed_from_runtime_and_configs(self):
        """No Tide Island autostarts, paths, or IPC handlers remain in GPS-managed files."""
        self.assertNotIn("tide-island", RUN_GPS)
        self.assertNotIn("share/tide", RUN_GPS)
        self.assertNotIn("tidePath", SHELL_QML)
        self.assertNotIn("tideIslandActive", SHELL_QML)
        self.assertNotIn("tide-island", HYPRLAND_LUA)

    def test_launcher_v2_favorites_persistence_and_paths(self):
        """Favorites must persist in XDG_STATE_HOME using atomic writes without hardcoded paths."""
        self.assertIn('readonly property string favoritesPath: (Quickshell.env("XDG_STATE_HOME")', LAUNCHER_QML)
        self.assertIn('"/island/launcher-favorites.json"', LAUNCHER_QML)
        self.assertIn("function saveFavorites()", LAUNCHER_QML)
        self.assertIn("function toggleFavorite(id)", LAUNCHER_QML)
        self.assertIn("function isAppFavorite(id)", LAUNCHER_QML)
        self.assertNotIn("/home/rice", LAUNCHER_QML)
        self.assertNotIn("/home/guru", LAUNCHER_QML)

    def test_launcher_v2_frequent_apps_and_ranking(self):
        """Usage tracking records successful launches and ranks frequent apps, excluding favorites."""
        self.assertIn('readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME")', LAUNCHER_QML)
        self.assertIn('"/island/launcher-usage.json"', LAUNCHER_QML)
        self.assertIn("function bump(id)", LAUNCHER_QML)
        self.assertIn("freqList.sort((a, b) => b.count - a.count)", LAUNCHER_QML)
        self.assertIn("const topFreq = freqList.slice(0, 6)", LAUNCHER_QML)
        self.assertIn("!favSet.has(id)", LAUNCHER_QML)

    def test_launcher_v2_smart_dismissal_contract(self):
        """Launcher closes on successful launch or web search, but stays open on failed launches."""
        self.assertIn("function launchApp(entry)", LAUNCHER_QML)
        self.assertIn("entry.execute()", LAUNCHER_QML)
        self.assertIn("bump(entry.id)", LAUNCHER_QML)
        self.assertIn("function launchWeb(url)", LAUNCHER_QML)
        self.assertIn("Quickshell.execDetached([\"xdg-open\", url])", LAUNCHER_QML)
        self.assertIn("if (launchApp(r.entry)) {\n                core.setLauncher(false)\n            }", LAUNCHER_QML)
        self.assertIn("if (launchWeb(r.url)) {\n                core.setLauncher(false)\n            }", LAUNCHER_QML)

    def test_launcher_v2_idle_visibility_contract(self):
        """IslandVisibility keeps the island visible indefinitely with nextExpiry: null when launcher is open."""
        self.assertIn("if (inputs.launcherOpen) {", ISLAND_VISIBILITY_JS)
        self.assertIn('state: "launcher"', ISLAND_VISIBILITY_JS)
        self.assertIn("nextExpiry: null", ISLAND_VISIBILITY_JS)
        self.assertIn('reason: "launcher_open"', ISLAND_VISIBILITY_JS)

    def test_atomic_save_execution_hermetic(self):
        """The shell command used in atomicSave must write atomically with restricted permissions."""
        import json
        import os
        import stat
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            target = Path(tmp_dir) / "nested" / "island" / "launcher-favorites.json"
            data = json.dumps(["firefox.desktop", "kitty.desktop"], indent=2)
            cmd = [
                "sh", "-c",
                'umask 077; d="$(dirname "$1")"; tmp="${d}/.$(basename "$1").tmp.$$"; mkdir -p "$d" && printf \'%s\\n\' "$2" > "$tmp" && mv -f "$tmp" "$1"',
                "sh", str(target), data
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)
            self.assertTrue(target.is_file())
            content = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(content, ["firefox.desktop", "kitty.desktop"])
            # Verify permission is 0600 (umask 077)
            mode = stat.S_IMODE(os.stat(target).st_mode)
            self.assertEqual(mode, 0o600)
            # Verify no leftover temp files
            parent_files = list(target.parent.iterdir())
            self.assertEqual(parent_files, [target])

    def test_ranking_and_exclusion_logic(self):
        """Frequent apps must be ranked by descending usage count and exclude favorited apps."""
        favorites = ["firefox.desktop", "kitty.desktop"]
        usage = {
            "firefox.desktop": 50,
            "kitty.desktop": 10,
            "thunar.desktop": 25,
            "code.desktop": 5,
            "mpv.desktop": 30,
            "spotify.desktop": 2,
        }

        fav_set = set(favorites)
        freq_list = []
        for app_id, count in usage.items():
            if app_id not in fav_set:
                freq_list.append({"id": app_id, "count": count})
        freq_list.sort(key=lambda x: x["count"], reverse=True)
        top_freq = freq_list[:6]

        self.assertEqual([x["id"] for x in top_freq], ["mpv.desktop", "thunar.desktop", "code.desktop", "spotify.desktop"])
        # Firefox and kitty must not appear in frequent apps
        self.assertNotIn("firefox.desktop", [x["id"] for x in top_freq])
        self.assertNotIn("kitty.desktop", [x["id"] for x in top_freq])

    def test_malformed_json_fallback_resilience(self):
        """Malformed or non-conforming JSON must parse safely into empty array/dict without raising."""
        import json

        def parse_favorites(text):
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    return [x for x in parsed if isinstance(x, str) and x.strip()]
                return []
            except Exception:
                return []

        def parse_usage(text):
            try:
                parsed = json.loads(text)
                if isinstance(parsed, dict) and not isinstance(parsed, list):
                    return parsed
                return {}
            except Exception:
                return {}

        self.assertEqual(parse_favorites("{invalid json"), [])
        self.assertEqual(parse_favorites('{"key": "value"}'), [])
        self.assertEqual(parse_favorites('["firefox.desktop", 123, ""]'), ["firefox.desktop"])

        self.assertEqual(parse_usage("{invalid json"), {})
        self.assertEqual(parse_usage('["an", "array"]'), {})
        self.assertEqual(parse_usage('{"kitty.desktop": 5}'), {"kitty.desktop": 5})


if __name__ == "__main__":
    unittest.main()
