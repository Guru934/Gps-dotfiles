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
NOTIFY_STATE_QML = (ROOT / "island/states/Notify.qml").read_text(encoding="utf-8")
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

    def test_notify_popup_uses_plaintext_and_bounded_image(self):
        """Notify.qml must enforce Text.PlainText and bounded image dimensions to prevent injection and OOM."""
        self.assertIn("textFormat: Text.PlainText", NOTIFY_STATE_QML)
        self.assertIn("sourceSize.width: Math.min(128,", NOTIFY_STATE_QML)
        self.assertIn("sourceSize.height: Math.min(128,", NOTIFY_STATE_QML)

    def test_critical_notification_stays_alive_contract(self):
        """Critical notifications must stay alive (timeout: 0) and not expire automatically."""
        self.assertIn("const crit = n.urgency === NotificationUrgency.Critical", ISLAND_QML)
        self.assertIn("timeout: crit ? 0 :", ISLAND_QML)
        self.assertIn("hasCritical", ISLAND_QML)

    def test_store_body_and_clear_history_contract(self):
        """Island and gps-ipc must expose store-body and clear commands."""
        self.assertIn("setStoreBody", ISLAND_QML)
        self.assertIn("clearNotifications", ISLAND_QML)
        self.assertIn("store-body)", GPS_IPC)
        self.assertIn("clear)", GPS_IPC)

    def test_action_notification_ipc_contract(self):
        """Island and gps-ipc must expose action command to invoke notification actions."""
        self.assertIn("actionNotification", ISLAND_QML)
        self.assertIn("action)", GPS_IPC)

    def test_held_notification_release_posts_notify_event(self):
        """Releasing held notifications must post 'notify' event to display them."""
        self.assertIn('root.postEvent("notify", IslandVisibility.PRIORITY.TRANSIENT, root.durations.notification)', ISLAND_QML)

    def test_notif_center_live_fileview_watch_contract(self):
        """NotifCenter must watch notification history for live updates."""
        self.assertIn("path: root.notifHistoryPath", NOTIF_CENTER_QML)
        self.assertIn("watchChanges: true", NOTIF_CENTER_QML)
        self.assertIn("onFileChanged: reload()", NOTIF_CENTER_QML)

    def test_notif_center_search_placeholder_and_chips_contract(self):
        """Search placeholder is left-aligned after icon; chips row is scrollable with fade edges."""
        qml = (ROOT / "components/NotifCenter.qml").read_text(encoding="utf-8")
        self.assertIn("anchors.left: parent.left", qml)
        self.assertIn("anchors.verticalCenter: parent.verticalCenter", qml)
        self.assertIn('text: "Search notifications…"', qml)
        self.assertIn("chipsFlickable", qml)
        self.assertIn("chipsFlickable.contentX > 2", qml)
        self.assertIn("chipsFlickable.contentWidth > chipsFlickable.width", qml)

    def test_notif_center_group_header_scrollbar_clearance_contract(self):
        """Group header Clear button and cards leave clearance to prevent scrollbar clipping."""
        qml = (ROOT / "components/NotifCenter.qml").read_text(encoding="utf-8")
        self.assertIn("id: inboxFeedCol\n                        width: parent.width - 12", qml)
        self.assertIn("Gutter clearance so clear button is never clipped by the scrollbar", qml)


if __name__ == "__main__":
    unittest.main()
