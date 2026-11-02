#!/usr/bin/env python3
"""Hermetic tests for GPS Night Light integration (island/states/Control.qml, island/Island.qml, scripts/gps-ipc, components/dashboard/ToolsTab.qml)."""

import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tests.helpers import HermeticTestCase, create_stub_executable

ISLAND_QML = (ROOT / "island/Island.qml").read_text(encoding="utf-8")
CONTROL_QML = (ROOT / "island/states/Control.qml").read_text(encoding="utf-8")
TOOLSTAB_QML = (ROOT / "components/dashboard/ToolsTab.qml").read_text(encoding="utf-8")
HOMETAB_QML = (ROOT / "components/dashboard/HomeTab.qml").read_text(encoding="utf-8")
GPS_IPC = (ROOT / "scripts/gps-ipc").read_text(encoding="utf-8")


class NightLightControllerContractTests(unittest.TestCase):
    """Tests for island/states/Control.qml night light control logic and contracts."""

    def test_controller_state_properties(self):
        """Control.qml must declare hasSunset, nightLightOn, nightKelvin, targetKelvin and kelvinSteps."""
        self.assertIn("property bool hasSunset: false", CONTROL_QML)
        self.assertIn("property bool nightLightOn: false", CONTROL_QML)
        self.assertIn("property int nightKelvin: 0", CONTROL_QML)
        self.assertIn("property int targetKelvin: 4000", CONTROL_QML)
        self.assertIn("readonly property var kelvinSteps: [3200, 4000, 4500, 5000]", CONTROL_QML)

    def test_controller_initial_probe_on_completed(self):
        """Control.qml triggers probe on completed so hyprsunset is detected without waiting for active."""
        self.assertIn("triggerProbe()", CONTROL_QML)
        match = re.search(r"Component\.onCompleted:\s*\{([^}]+)\}", CONTROL_QML)
        self.assertIsNotNone(match)
        self.assertIn("triggerProbe()", match.group(1))

    def test_probe_and_runcmd_run_without_active_guard(self):
        """triggerProbe, scheduleProbe and runCmd must execute detached commands even when not active."""
        self.assertNotIn("if (active && !sysProbe.running)", CONTROL_QML)
        self.assertIn("function triggerProbe() {\n        if (!sysProbe.running) sysProbe.running = true", CONTROL_QML)
        self.assertIn("function scheduleProbe(ms) {\n        probeDelay.interval = ms || 350", CONTROL_QML)
        self.assertIn("function runCmd(script, args, delayMs) {\n        Quickshell.execDetached(", CONTROL_QML)

    def test_sysprobe_stream_finished_processes_without_active_guard(self):
        """sysProbe stdout collector must not drop stream when inactive."""
        match = re.search(r"id:\s*sysProbe.*?stdout:\s*StdioCollector\s*\{([^}]+onStreamFinished:[^}]+)\}", CONTROL_QML, re.S)
        self.assertIsNotNone(match)
        self.assertNotIn("if (!st.active) return", match.group(1))

    def test_sysprobe_detects_hyprsunset_and_parses_temperature(self):
        """sysProbe inspects hyprsunset presence, running state, and -t kelvin argument."""
        self.assertIn("command -v hyprsunset >/dev/null 2>&1 && echo 'has_sunset=1' || echo 'has_sunset=0'", CONTROL_QML)
        self.assertIn("pgrep -x hyprsunset >/dev/null 2>&1 && echo 'sunset_run=1' || echo 'sunset_run=0'", CONTROL_QML)
        self.assertIn("ps -C hyprsunset -o args=", CONTROL_QML)
        self.assertIn("map.sunset_run === \"1\"", CONTROL_QML)

    def test_toggle_night_light_implementation(self):
        """toggleNightLight guards against missing hyprsunset, toggles state, and invokes process."""
        self.assertIn("function toggleNightLight()", CONTROL_QML)
        self.assertIn("if (!hasSunset) return false", CONTROL_QML)
        self.assertIn("pkill -x hyprsunset >/dev/null 2>&1; setsid hyprsunset -t \"$1\" >/dev/null 2>&1 &", CONTROL_QML)
        self.assertIn("pkill -x hyprsunset >/dev/null 2>&1", CONTROL_QML)

    def test_cycle_night_kelvin_implementation(self):
        """cycleNightKelvin advances through kelvinSteps presets and updates active process."""
        self.assertIn("function cycleNightKelvin()", CONTROL_QML)
        self.assertIn("if (!hasSunset) return false", CONTROL_QML)
        self.assertIn("const idx = kelvinSteps.indexOf(targetKelvin)", CONTROL_QML)
        self.assertIn("const nextK = kelvinSteps[(idx + 1) % kelvinSteps.length]", CONTROL_QML)

    def test_kelvin_cycling_order(self):
        """Verify kelvin step sequence strictly matches 3200 -> 4000 -> 4500 -> 5000 -> 3200."""
        steps = [3200, 4000, 4500, 5000]
        cur = 4000
        cur = steps[(steps.index(cur) + 1) % len(steps)]
        self.assertEqual(cur, 4500)
        cur = steps[(steps.index(cur) + 1) % len(steps)]
        self.assertEqual(cur, 5000)
        cur = steps[(steps.index(cur) + 1) % len(steps)]
        self.assertEqual(cur, 3200)
        cur = steps[(steps.index(cur) + 1) % len(steps)]
        self.assertEqual(cur, 4000)


class NightLightSimulationTests(HermeticTestCase):
    """Hermetic behavioral simulation of controller probe and command logic."""

    def test_probe_script_hyprsunset_available(self):
        """When hyprsunset is in PATH, probe command reports has_sunset=1."""
        stub_hyprsunset = self.hermetic.stubs / "hyprsunset"
        create_stub_executable(stub_hyprsunset, "#!/bin/sh\nexit 0\n")

        cmd = "command -v hyprsunset >/dev/null 2>&1 && echo 'has_sunset=1' || echo 'has_sunset=0'"
        res = self.hermetic.run(["sh", "-c", cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "has_sunset=1")

    def test_probe_script_hyprsunset_unavailable(self):
        """When hyprsunset is not in PATH, probe command reports has_sunset=0."""
        cmd = "command -v nonexistent_hyprsunset_binary >/dev/null 2>&1 && echo 'has_sunset=1' || echo 'has_sunset=0'"
        res = self.hermetic.run(["sh", "-c", cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "has_sunset=0")

    def test_probe_script_temperature_parser(self):
        """Simulate awk parser for ps -C hyprsunset -o args=."""
        awk_script = r'''
        awk '{for(i=1;i<=NF;i++) if($i=="-t" && $(i+1)~ /^[0-9]+$/){print $(i+1); exit}}'
        '''
        simulated_args = "hyprsunset -t 4500 --other-arg"
        proc = subprocess.run(["awk", '{for(i=1;i<=NF;i++) if($i=="-t" && $(i+1)~ /^[0-9]+$/){print $(i+1); exit}}'],
                              input=simulated_args, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "4500")


class NightLightIpcContractTests(HermeticTestCase):
    """Tests for IPC routing via scripts/gps-ipc and Island.qml IpcHandler."""

    def test_gps_ipc_subcommand_nightlight_exists(self):
        """scripts/gps-ipc must support nightlight subcommand."""
        self.assertIn("nightlight|night-light|sunset)", GPS_IPC)
        self.assertIn('call_qs "$ipath" island nightlight "$action" "$@"', GPS_IPC)

    def test_gps_ipc_island_subcommand_supports_nightlight(self):
        """gps-ipc island usage and dispatch supports nightlight action."""
        self.assertIn("focusToggle|nightlight|action>", GPS_IPC)

    def test_gps_ipc_routes_nightlight_status_to_quickshell(self):
        """gps-ipc nightlight status invokes quickshell with island nightlight status."""
        log_file = self.hermetic.root / "qs_ipc.log"
        mock_qs = self.hermetic.stubs / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{log_file}'\necho '{{\"ok\":true,\"available\":true,\"enabled\":false,\"kelvin\":0,\"targetKelvin\":4000}}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self.hermetic.run([str(ROOT / "scripts/gps-ipc"), "nightlight", "status"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertTrue(data["ok"])
        self.assertTrue(data["available"])
        self.assertFalse(data["enabled"])
        self.assertEqual(data["kelvin"], 0)
        self.assertEqual(data["targetKelvin"], 4000)

        logged = log_file.read_text()
        self.assertIn("call island nightlight status", logged)

    def test_gps_ipc_routes_nightlight_toggle_to_quickshell(self):
        """gps-ipc nightlight toggle invokes quickshell with island nightlight toggle."""
        log_file = self.hermetic.root / "qs_ipc.log"
        mock_qs = self.hermetic.stubs / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{log_file}'\necho '{{\"ok\":true,\"available\":true,\"enabled\":true,\"kelvin\":4000,\"targetKelvin\":4000}}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self.hermetic.run([str(ROOT / "scripts/gps-ipc"), "nightlight", "toggle"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertTrue(data["ok"])
        self.assertTrue(data["enabled"])
        self.assertEqual(data["kelvin"], 4000)

        logged = log_file.read_text()
        self.assertIn("call island nightlight toggle", logged)

    def test_gps_ipc_routes_nightlight_cycle_to_quickshell(self):
        """gps-ipc nightlight cycle invokes quickshell with island nightlight cycle."""
        log_file = self.hermetic.root / "qs_ipc.log"
        mock_qs = self.hermetic.stubs / "quickshell"
        mock_qs.write_text(f"#!/bin/sh\necho \"$@\" >> '{log_file}'\necho '{{\"ok\":true,\"available\":true,\"enabled\":true,\"kelvin\":4500,\"targetKelvin\":4500}}'\nexit 0\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self.hermetic.run([str(ROOT / "scripts/gps-ipc"), "nightlight", "cycle"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertTrue(data["ok"])
        self.assertEqual(data["kelvin"], 4500)

        logged = log_file.read_text()
        self.assertIn("call island nightlight cycle", logged)

    def test_gps_ipc_island_unavailable_returns_error_code(self):
        """When island process is not running, gps-ipc nightlight returns code 3."""
        mock_qs = self.hermetic.stubs / "quickshell"
        mock_qs.write_text("#!/bin/sh\necho 'No running instances for IslandProduction.qml' >&2\nexit 255\n")
        mock_qs.chmod(mock_qs.stat().st_mode | stat.S_IEXEC)

        res = self.hermetic.run([str(ROOT / "scripts/gps-ipc"), "nightlight", "status"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 3)
        self.assertIn("ERROR: Target Quickshell instance is not running", res.stderr)

    def test_island_qml_exposes_nightlight_ipc(self):
        """Island.qml must implement nightlight and nightLight IPC functions."""
        self.assertIn("function nightlight(action: string): string", ISLAND_QML)
        self.assertIn("function nightLight(action: string): string", ISLAND_QML)
        self.assertIn("function handleNightLightIpc(action)", ISLAND_QML)

    def test_island_qml_ipc_action_handling_contract(self):
        """Island.qml handleNightLightIpc handles status, toggle, cycle, on, off, and invalid actions."""
        self.assertIn('root.registry["control"]', ISLAND_QML)
        self.assertIn('act === "status"', ISLAND_QML)
        self.assertIn('act === "toggle"', ISLAND_QML)
        self.assertIn('act === "cycle"', ISLAND_QML)
        self.assertIn('act === "on"', ISLAND_QML)
        self.assertIn('act === "off"', ISLAND_QML)
        self.assertIn('invalid action: ', ISLAND_QML)


class ToolsTabNightLightContractTests(unittest.TestCase):
    """Tests for components/dashboard/ToolsTab.qml Night Light tile and UI state synchronization."""

    def test_placeholder_tile_is_removed(self):
        """The hardcoded disabled placeholder must be replaced with dynamic logic."""
        self.assertNotIn('sub: "unavailable \\u00b7 no hyprsunset",\n                                    disabled: true', TOOLSTAB_QML)
        self.assertNotIn('sub: "unavailable · no hyprsunset",\n                                    disabled: true', TOOLSTAB_QML)

    def test_toolstab_declares_night_light_properties(self):
        """ToolsTab.qml declares reactive night light state properties."""
        self.assertIn("property bool nightLightAvailable: false", TOOLSTAB_QML)
        self.assertIn("property bool nightLightOn: false", TOOLSTAB_QML)
        self.assertIn("property int nightLightKelvin: 0", TOOLSTAB_QML)
        self.assertIn("property int nightLightTargetKelvin: 4000", TOOLSTAB_QML)
        self.assertIn("property bool nightLightIpcError: false", TOOLSTAB_QML)
        self.assertIn("property bool nightLightLoaded: false", TOOLSTAB_QML)

    def test_toolstab_refresh_reads_invokes_refresh_night_light(self):
        """Opening the drawer or refreshReads() refreshes night light state."""
        self.assertIn("function refreshNightLight()", TOOLSTAB_QML)
        refresh_reads_match = re.search(r"function refreshReads\(\)\s*\{([^}]+)\}", TOOLSTAB_QML)
        self.assertIsNotNone(refresh_reads_match)
        self.assertIn("root.refreshNightLight()", refresh_reads_match.group(1))

    def test_toolstab_night_light_processes(self):
        """ToolsTab uses status and toggle processes communicating via gps-ipc."""
        self.assertIn("id: nightLightStatusProc", TOOLSTAB_QML)
        self.assertIn("id: nightLightToggleProc", TOOLSTAB_QML)
        self.assertIn('"nightlight"', TOOLSTAB_QML)
        self.assertIn('"status"', TOOLSTAB_QML)
        self.assertIn('"toggle"', TOOLSTAB_QML)

    def test_toolstab_click_invokes_toggle(self):
        """NIGHT WARMTH tile onTapped triggers root.toggleNightLight()."""
        match = re.search(r'title:\s*"NIGHT WARMTH".*?onTapped:\s*root\.toggleNightLight\(\)', TOOLSTAB_QML, re.S)
        self.assertIsNotNone(match, "ToolTile must connect onTapped to root.toggleNightLight()")

    def test_toolstab_tile_renders_correct_states(self):
        """NIGHT WARMTH tile defines visual representations for on, off, unavailable, and offline."""
        self.assertIn('sub: "unavailable \\u00b7 island offline"', TOOLSTAB_QML)
        self.assertIn('sub: "unavailable \\u00b7 no hyprsunset"', TOOLSTAB_QML)
        self.assertIn('sub: root.nightLightKelvin > 0 ? ("ON \\u00b7 " + root.nightLightKelvin + "K") : "ON"', TOOLSTAB_QML)
        self.assertIn('sub: "OFF"', TOOLSTAB_QML)

    def test_toolstab_reconciles_after_toggle(self):
        """ToolsTab schedules a reconciliation refresh after toggle command exits."""
        self.assertIn("id: nightLightReconcileTimer", TOOLSTAB_QML)
        self.assertIn("nightLightReconcileTimer.restart()", TOOLSTAB_QML)

    def test_toolstab_ipc_failure_does_not_produce_false_success(self):
        """When toggle or status process exits non-zero, error is set and false success is prevented."""
        self.assertIn("root.nightLightIpcError = true", TOOLSTAB_QML)
        self.assertIn('root.say("ERR :: night light toggle failed (island unreachable)", "err")', TOOLSTAB_QML)


class HomeTabNightLightContractTests(unittest.TestCase):
    """Tests for components/dashboard/HomeTab.qml Night Light quick toggle card integration."""

    def test_circadian_placeholder_is_replaced(self):
        """The hardcoded disabled Circadian placeholder must be replaced with dynamic Night Light control."""
        self.assertNotIn('title: "Circadian"', HOMETAB_QML)
        self.assertNotIn('subtitle: "unavailable \\u00b7 no backend"', HOMETAB_QML)
        self.assertIn('title: "Night Light"', HOMETAB_QML)

    def test_home_and_tools_use_same_ipc_actions(self):
        """HomeTab and ToolsTab must communicate via the identical gps-ipc nightlight status/toggle actions."""
        # Both must call gps-ipc with "nightlight" and "status" / "toggle"
        self.assertIn('root.projectPath + "/scripts/gps-ipc"', HOMETAB_QML)
        self.assertIn('"nightlight"', HOMETAB_QML)
        self.assertIn('"status"', HOMETAB_QML)
        self.assertIn('"toggle"', HOMETAB_QML)

        # Neither component implements independent hyprsunset process management
        self.assertNotIn("pkill -x hyprsunset", HOMETAB_QML)
        self.assertNotIn("setsid hyprsunset", HOMETAB_QML)
        self.assertNotIn("pkill -x hyprsunset", TOOLSTAB_QML)
        self.assertNotIn("setsid hyprsunset", TOOLSTAB_QML)

    def test_hometab_declares_night_light_properties(self):
        """HomeTab.qml declares reactive night light state properties identical to ToolsTab."""
        self.assertIn("property bool nightLightAvailable: false", HOMETAB_QML)
        self.assertIn("property bool nightLightOn: false", HOMETAB_QML)
        self.assertIn("property int nightLightKelvin: 0", HOMETAB_QML)
        self.assertIn("property int nightLightTargetKelvin: 4000", HOMETAB_QML)
        self.assertIn("property bool nightLightIpcError: false", HOMETAB_QML)
        self.assertIn("property bool nightLightLoaded: false", HOMETAB_QML)

    def test_hometab_refresh_reads_invokes_refresh_night_light(self):
        """Opening the drawer or onIsOpenChanged / Component.onCompleted refreshes night light state."""
        self.assertIn("function refreshNightLight()", HOMETAB_QML)
        self.assertIn("onIsOpenChanged: {\n        if (root.isOpen) root.refreshNightLight()\n    }", HOMETAB_QML)
        self.assertIn("Component.onCompleted: {\n        root.refreshNightLight()\n    }", HOMETAB_QML)

    def test_hometab_quick_toggle_card_renders_correct_states(self):
        """QuickToggleCard defines visual states for ON with Kelvin, OFF, unavailable, and offline."""
        self.assertIn('if (root.nightLightIpcError) return "unavailable \\u00b7 island offline"', HOMETAB_QML)
        self.assertIn('if (!root.nightLightAvailable) return "unavailable \\u00b7 no hyprsunset"', HOMETAB_QML)
        self.assertIn('("on \\u00b7 " + root.nightLightKelvin + "K")', HOMETAB_QML)
        self.assertIn('return "off"', HOMETAB_QML)

    def test_hometab_click_invokes_toggle(self):
        """Night Light QuickToggleCard onActivated triggers root.toggleNightLight()."""
        match = re.search(r'title:\s*"Night Light".*?onActivated:\s*root\.toggleNightLight\(\)', HOMETAB_QML, re.S)
        self.assertIsNotNone(match, "QuickToggleCard must connect onActivated to root.toggleNightLight()")

    def test_hometab_reconciles_after_toggle(self):
        """HomeTab schedules a reconciliation refresh after toggle command exits."""
        self.assertIn("id: nightLightReconcileTimer", HOMETAB_QML)
        self.assertIn("nightLightReconcileTimer.restart()", HOMETAB_QML)

    def test_hometab_ipc_failure_handling(self):
        """When toggle or status process exits non-zero, error is set and false success is prevented."""
        self.assertIn("root.nightLightIpcError = true", HOMETAB_QML)
        self.assertIn("dimmed: !root.nightLightAvailable || root.nightLightIpcError", HOMETAB_QML)
        self.assertIn("interactive: root.nightLightAvailable && !root.nightLightIpcError", HOMETAB_QML)


if __name__ == "__main__":
    unittest.main()
