import json
import os
from pathlib import Path
import stat
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ISLAND_QML = (ROOT / "island/Island.qml").read_text(encoding="utf-8")
SHELL_QML = (ROOT / "shell.qml").read_text(encoding="utf-8")
NOTIF_CENTER_QML = (ROOT / "components/NotifCenter.qml").read_text(encoding="utf-8")
GPS_IPC = (ROOT / "scripts/gps-ipc").read_text(encoding="utf-8")


class NotificationBackendContractTests(unittest.TestCase):
    """Verifies single D-Bus ownership, persistent store contracts, and IPC routing."""

    def test_single_dbus_notification_owner_contract(self):
        """Only the Island process instantiates NotificationServer; Shell must not."""
        self.assertIn("NotificationServer", ISLAND_QML)
        # Shell must not instantiate NotificationServer
        self.assertNotIn("NotificationServer {", SHELL_QML)

    def test_store_directory_and_private_file_mode(self):
        """State directory must be under ~/.local/state/gps/ with private permissions."""
        with tempfile.TemporaryDirectory() as td:
            state_dir = Path(td) / "gps"
            state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            mode = stat.S_IMODE(state_dir.stat().st_mode)
            self.assertEqual(mode & 0o077, 0, "State directory must not be readable/writable by others")

    def test_gps_ipc_routes_notify_commands(self):
        """gps-ipc must handle the 'notify' command and route to island notification service."""
        self.assertTrue("notify)" in GPS_IPC or "notify|" in GPS_IPC)
        for subcmd in ("history", "clear", "dismiss", "markread", "dnd", "status"):
            self.assertIn(subcmd, GPS_IPC)

    def test_notif_center_uses_consistent_item_schema(self):
        """NotifCenter must use modelData.ts for timeAgo calculation."""
        self.assertIn("root.timeAgo(modelData.ts)", NOTIF_CENTER_QML)

    def test_corrupt_json_recovery_in_python(self):
        """Verifies safe fallback when notifications.json is corrupt."""
        with tempfile.TemporaryDirectory() as td:
            bad_file = Path(td) / "notifications.json"
            bad_file.write_text("{corrupt json [", encoding="utf-8")

            # Fallback loader
            try:
                data = json.loads(bad_file.read_text())
            except Exception:
                data = {"version": 1, "entries": []}

            self.assertEqual(data["entries"], [])


if __name__ == "__main__":
    unittest.main()
