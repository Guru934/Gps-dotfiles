"""Unit tests for system tray logic: ordering, grouping by status, count badge.

These tests exercise pure Python reference implementations of the JavaScript
logic embedded in TrayPopup.qml:
  - visibleItems: Active + NeedsAttention, NeedsAttention first, then by id
  - passiveItems: Passive only, sorted by id
  - count badge: "" for 0–1 items, number string for 2–9, "9+" for 10+
  - tray button visibility: shown iff count > 0

All tests are hermetic (no subprocess, no Wayland session, no D-Bus).
"""

import unittest


# ---------------------------------------------------------------------------
# Reference implementations matching TrayPopup.qml / LeftRail.qml logic
# ---------------------------------------------------------------------------

class Status:
    Passive = 0
    Active = 1
    NeedsAttention = 2


def visible_items(items):
    """Items with Active or NeedsAttention status, NeedsAttention first then by id."""
    out = [it for it in items if it["status"] != Status.Passive]
    out.sort(key=lambda it: (
        0 if it["status"] == Status.NeedsAttention else 1,
        it["id"],
    ))
    return out


def passive_items(items):
    """Items with Passive status, sorted by id."""
    out = [it for it in items if it["status"] == Status.Passive]
    out.sort(key=lambda it: it["id"])
    return out


def count_badge(count):
    """Sublabel text on the tray rail button."""
    if count > 9:
        return "9+"
    if count > 1:
        return str(count)
    return ""


def tray_button_visible(count):
    """Rail button visibility condition."""
    return count > 0


def tooltip_text(item):
    """Tooltip: tooltipTitle if non-empty, else title."""
    tt = item.get("tooltipTitle", "")
    return tt if tt else item.get("title", "")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_item(id_, status=Status.Active, title="", tooltip_title=""):
    return {"id": id_, "status": status, "title": title, "tooltipTitle": tooltip_title}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestVisibleItems(unittest.TestCase):
    """visibleItems: Active + NeedsAttention, NeedsAttention first, stable by id."""

    def test_empty_list_returns_empty(self):
        self.assertEqual(visible_items([]), [])

    def test_passive_only_returns_empty(self):
        items = [make_item("a", Status.Passive), make_item("b", Status.Passive)]
        self.assertEqual(visible_items(items), [])

    def test_active_only_sorted_by_id(self):
        items = [make_item("zz", Status.Active), make_item("aa", Status.Active)]
        result = visible_items(items)
        self.assertEqual([it["id"] for it in result], ["aa", "zz"])

    def test_needs_attention_before_active(self):
        items = [
            make_item("a", Status.Active),
            make_item("b", Status.NeedsAttention),
        ]
        result = visible_items(items)
        self.assertEqual(result[0]["id"], "b")  # NeedsAttention first
        self.assertEqual(result[1]["id"], "a")

    def test_multiple_needs_attention_sorted_by_id(self):
        items = [
            make_item("c", Status.NeedsAttention),
            make_item("a", Status.NeedsAttention),
            make_item("b", Status.Active),
        ]
        result = visible_items(items)
        ids = [it["id"] for it in result]
        self.assertEqual(ids, ["a", "c", "b"])

    def test_mixed_status(self):
        items = [
            make_item("p", Status.Passive),
            make_item("n", Status.NeedsAttention),
            make_item("a", Status.Active),
        ]
        result = visible_items(items)
        ids = [it["id"] for it in result]
        self.assertEqual(ids, ["n", "a"])

    def test_passive_items_excluded(self):
        items = [make_item("x", Status.Passive), make_item("y", Status.Active)]
        result = visible_items(items)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["id"], "y")

    def test_stable_sort_with_equal_status(self):
        """Items with same status are sorted alphabetically by id."""
        items = [
            make_item("z", Status.Active),
            make_item("m", Status.Active),
            make_item("a", Status.Active),
        ]
        result = visible_items(items)
        self.assertEqual([it["id"] for it in result], ["a", "m", "z"])


class TestPassiveItems(unittest.TestCase):
    """passiveItems: Passive only, sorted by id."""

    def test_empty_returns_empty(self):
        self.assertEqual(passive_items([]), [])

    def test_active_only_returns_empty(self):
        items = [make_item("a", Status.Active), make_item("b", Status.NeedsAttention)]
        self.assertEqual(passive_items(items), [])

    def test_passive_items_sorted_by_id(self):
        items = [
            make_item("z", Status.Passive),
            make_item("a", Status.Passive),
            make_item("m", Status.Passive),
        ]
        result = passive_items(items)
        self.assertEqual([it["id"] for it in result], ["a", "m", "z"])

    def test_mixed_only_returns_passive(self):
        items = [
            make_item("p1", Status.Passive),
            make_item("a1", Status.Active),
            make_item("p2", Status.Passive),
            make_item("n1", Status.NeedsAttention),
        ]
        result = passive_items(items)
        ids = [it["id"] for it in result]
        self.assertEqual(sorted(ids), ["p1", "p2"])
        self.assertEqual(ids, ["p1", "p2"])  # already sorted


class TestCountBadge(unittest.TestCase):
    """count_badge: sublabel text on the rail button."""

    def test_zero_items_empty_string(self):
        self.assertEqual(count_badge(0), "")

    def test_one_item_empty_string(self):
        self.assertEqual(count_badge(1), "")

    def test_two_items_returns_2(self):
        self.assertEqual(count_badge(2), "2")

    def test_nine_items_returns_9(self):
        self.assertEqual(count_badge(9), "9")

    def test_ten_items_returns_9plus(self):
        self.assertEqual(count_badge(10), "9+")

    def test_large_count_returns_9plus(self):
        self.assertEqual(count_badge(99), "9+")
        self.assertEqual(count_badge(1000), "9+")

    def test_boundary_9(self):
        self.assertEqual(count_badge(9), "9")

    def test_boundary_10(self):
        self.assertEqual(count_badge(10), "9+")


class TestTrayButtonVisibility(unittest.TestCase):
    """Tray rail button visibility: shown iff count > 0."""

    def test_zero_items_hidden(self):
        self.assertFalse(tray_button_visible(0))

    def test_one_item_visible(self):
        self.assertTrue(tray_button_visible(1))

    def test_many_items_visible(self):
        self.assertTrue(tray_button_visible(10))


class TestTooltipText(unittest.TestCase):
    """tooltip_text: prefer tooltipTitle, fall back to title."""

    def test_tooltip_title_preferred(self):
        item = make_item("x", title="App", tooltip_title="App - Running")
        self.assertEqual(tooltip_text(item), "App - Running")

    def test_falls_back_to_title_when_tooltip_empty(self):
        item = make_item("x", title="NetworkManager Applet", tooltip_title="")
        self.assertEqual(tooltip_text(item), "NetworkManager Applet")

    def test_empty_both_returns_empty_string(self):
        item = make_item("x", title="", tooltip_title="")
        self.assertEqual(tooltip_text(item), "")

    def test_no_tooltip_title_key_falls_back(self):
        item = {"id": "x", "status": Status.Active, "title": "KDE Connect"}
        self.assertEqual(tooltip_text(item), "KDE Connect")


class TestGroupingIntegration(unittest.TestCase):
    """Integration: grouping + counting together, simulating a live tray."""

    def _make_tray(self, specs):
        """specs: list of (id, status) tuples"""
        return [make_item(id_, status) for id_, status in specs]

    def test_all_passive_no_visible_items(self):
        tray = self._make_tray([("a", Status.Passive), ("b", Status.Passive)])
        self.assertEqual(visible_items(tray), [])
        self.assertEqual(len(passive_items(tray)), 2)
        # Button should still be visible because total count > 0
        self.assertTrue(tray_button_visible(len(tray)))

    def test_item_disappears_gracefully(self):
        """Simulate item removal: filter by existence."""
        tray = self._make_tray([("nm-applet", Status.Active)])
        self.assertEqual(len(visible_items(tray)), 1)
        # Remove the item
        tray.clear()
        self.assertEqual(len(visible_items(tray)), 0)
        self.assertFalse(tray_button_visible(len(tray)))

    def test_needs_attention_ordering_with_passive(self):
        tray = self._make_tray([
            ("z-passive", Status.Passive),
            ("m-active", Status.Active),
            ("a-attention", Status.NeedsAttention),
        ])
        vi = visible_items(tray)
        pi = passive_items(tray)
        self.assertEqual(vi[0]["id"], "a-attention")
        self.assertEqual(vi[1]["id"], "m-active")
        self.assertEqual(pi[0]["id"], "z-passive")

    def test_count_badge_reflects_total(self):
        tray = self._make_tray([(str(i), Status.Active) for i in range(12)])
        self.assertEqual(count_badge(len(tray)), "9+")

    def test_single_item_no_badge(self):
        tray = self._make_tray([("only", Status.NeedsAttention)])
        self.assertEqual(count_badge(len(tray)), "")
        self.assertTrue(tray_button_visible(len(tray)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
