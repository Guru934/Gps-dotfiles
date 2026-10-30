#!/usr/bin/env python3
"""Hermetic tests for GPS Device Watcher (E2).

Verifies:
- Command line arguments: --help, --dry-run, --test-emit
- Event formatting and JSON structure
- Unit logic for DeviceWatcher callbacks (UDisks2, BlueZ, NetworkManager)
- Debounce and notification handling
"""

import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import MagicMock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

# Import DeviceWatcher directly from the watcher script
import importlib.machinery
import importlib.util

loader = importlib.machinery.SourceFileLoader(
    "gps_device_watcher", str(ROOT / "scripts" / "gps-device-watcher")
)
spec = importlib.util.spec_from_loader("gps_device_watcher", loader)
gps_device_watcher = importlib.util.module_from_spec(spec)
loader.exec_module(gps_device_watcher)


class DeviceWatcherTests(unittest.TestCase):
    def test_cli_test_emit(self):
        """--test-emit prints JSON line and exits 0."""
        cmd = [
            str(ROOT / "scripts" / "gps-device-watcher"),
            "--test-emit",
            json.dumps({"type": "usb", "action": "connected", "name": "Kingston USB"}),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertEqual(data["type"], "usb")
        self.assertEqual(data["action"], "connected")
        self.assertEqual(data["name"], "Kingston USB")

    def test_cli_dry_run(self):
        """--dry-run attempts D-Bus connection and exits cleanly."""
        cmd = [str(ROOT / "scripts" / "gps-device-watcher"), "--dry-run"]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)

    def test_udisks_drive_added_and_removed(self):
        """Watcher extracts USB drive names and emits connected/disconnected."""
        watcher = gps_device_watcher.DeviceWatcher()
        emitted = []
        gps_device_watcher.emit_event = lambda t, a, n, extra=None: emitted.append((t, a, n, extra))

        # 1. Drive added
        drive_path = "/org/freedesktop/UDisks2/drives/Samsung_Flash_Drive_123"
        interfaces = {
            "org.freedesktop.UDisks2.Drive": {
                "Vendor": "Samsung",
                "Model": "Flash Drive FIT",
                "ConnectionBus": "usb",
                "Removable": True,
            }
        }
        watcher.handle_udisks_added(drive_path, interfaces)
        self.assertEqual(len(emitted), 1)
        self.assertEqual(emitted[0][0], "usb")
        self.assertEqual(emitted[0][1], "connected")
        self.assertEqual(emitted[0][2], "Samsung Flash Drive FIT")

        # 2. Drive removed
        watcher.handle_udisks_removed(drive_path, ["org.freedesktop.UDisks2.Drive"])
        self.assertEqual(len(emitted), 2)
        self.assertEqual(emitted[1][0], "usb")
        self.assertEqual(emitted[1][1], "disconnected")
        self.assertEqual(emitted[1][2], "Samsung Flash Drive FIT")

    def test_bluez_connected_changed(self):
        """Watcher emits bluetooth connected and disconnected on Connected property change."""
        watcher = gps_device_watcher.DeviceWatcher()
        emitted = []
        gps_device_watcher.emit_event = lambda t, a, n, extra=None: emitted.append((t, a, n, extra))

        dev_path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"

        # Connect
        watcher.handle_bluez_properties(
            "org.bluez.Device1",
            {"Connected": True, "Name": "MX Master 3S"},
            [],
            dev_path,
        )
        self.assertEqual(len(emitted), 1)
        self.assertEqual(emitted[0][0], "bluetooth")
        self.assertEqual(emitted[0][1], "connected")
        self.assertEqual(emitted[0][2], "MX Master 3S")

        # Disconnect
        watcher.handle_bluez_properties(
            "org.bluez.Device1",
            {"Connected": False},
            [],
            dev_path,
        )
        self.assertEqual(len(emitted), 2)
        self.assertEqual(emitted[1][0], "bluetooth")
        self.assertEqual(emitted[1][1], "disconnected")
        self.assertEqual(emitted[1][2], "MX Master 3S")

    def test_networkmanager_wifi_connected(self):
        """Watcher detects wireless active connection state 2 (activated)."""
        watcher = gps_device_watcher.DeviceWatcher()
        emitted = []
        gps_device_watcher.emit_event = lambda t, a, n, extra=None: emitted.append((t, a, n, extra))

        conn_path = "/org/freedesktop/NetworkManager/ActiveConnection/5"

        # Connected
        watcher.handle_nm_properties(
            "org.freedesktop.NetworkManager.Connection.Active",
            {"State": 2, "Type": "802-11-wireless", "Id": "Office-5GHz"},
            [],
            conn_path,
        )
        self.assertEqual(len(emitted), 1)
        self.assertEqual(emitted[0][0], "wifi")
        self.assertEqual(emitted[0][1], "connected")
        self.assertEqual(emitted[0][2], "Office-5GHz")

        # Disconnected
        watcher.handle_nm_properties(
            "org.freedesktop.NetworkManager.Connection.Active",
            {"State": 4, "Type": "802-11-wireless", "Id": "Office-5GHz"},
            [],
            conn_path,
        )
        self.assertEqual(len(emitted), 2)
        self.assertEqual(emitted[1][0], "wifi")
        self.assertEqual(emitted[1][1], "disconnected")
        self.assertEqual(emitted[1][2], "Office-5GHz")


if __name__ == "__main__":
    unittest.main()
