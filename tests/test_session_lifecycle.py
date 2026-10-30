#!/usr/bin/env python3
"""Automated tests for GPS session and process lifecycle (P5.2).

Verifies:
- scripts/run-gps.fish implements graceful process termination with SIGKILL fallback.
- Both master shell and Island Quickshell instances use `--no-duplicate`.
- Startup script does not use hardcoded repository paths in pgrep queries.
- Startup logging captures diagnostics and error tails on launch failure.
- switch-island.fish gracefully stops exact target instances.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUN_GPS = (ROOT / "scripts" / "run-gps.fish").read_text()
SWITCH_ISLAND = (ROOT / "scripts" / "switch-island.fish").read_text()


class SessionLifecycleTests(unittest.TestCase):
    """Lifecycle safety and contract tests for GPS startup scripts."""

    def test_run_gps_creates_config_dir(self):
        """Ensures ~/.config/quickshell directory is created before logging."""
        self.assertIn('mkdir -p "$HOME/.config/quickshell"', RUN_GPS)

    def test_run_gps_graceful_stop_pattern(self):
        """Ensures graceful SIGTERM with timeout before SIGKILL fallback."""
        self.assertIn("function stop_pattern", RUN_GPS)
        self.assertIn("kill -TERM $pid", RUN_GPS)
        self.assertIn("kill -9 $pid", RUN_GPS)
        self.assertIn('stop_pattern "quickshell.*shell\\.qml" "GPS master shell"', RUN_GPS)

    def test_run_gps_no_duplicate_flag_on_both_instances(self):
        """Both Island and Master QuickShell instances must enforce --no-duplicate."""
        self.assertIn('set -l gps_path "$REPO_DIR/island/IslandProduction.qml"', RUN_GPS)
        self.assertIn('/usr/bin/quickshell --no-duplicate -d -p "$gps_path"', RUN_GPS)

        shell_launch = re.search(r"/usr/bin/quickshell[^\n]*shell\.qml", RUN_GPS)
        self.assertIsNotNone(shell_launch, "shell.qml launch command missing")
        self.assertIn("--no-duplicate", shell_launch.group(0))

    def test_run_gps_no_hardcoded_repo_dir_in_pgrep(self):
        """Process checks must use pattern matching rather than hardcoded 'my-rice/'."""
        self.assertNotIn("my-rice/she", RUN_GPS)
        self.assertNotIn("my-rice/island", RUN_GPS)
        self.assertIn("quickshell.*shell\\.qml", RUN_GPS)
        self.assertIn("quickshell.*IslandProduction\\.qml", RUN_GPS)

    def test_run_gps_diagnostic_logging_on_failure(self):
        """Ensures startup failure dumps recent log lines to startup.log."""
        self.assertIn("qs-gps.log", RUN_GPS)
        self.assertIn("tail -n 3", RUN_GPS)

    def test_switch_island_exact_stop_and_no_duplicate(self):
        """switch-island.fish must use exact stop pattern and --no-duplicate."""
        self.assertIn("function stop_exact", SWITCH_ISLAND)
        self.assertIn("kill -TERM $pid", SWITCH_ISLAND)
        self.assertIn("kill -9 $pid", SWITCH_ISLAND)
        self.assertIn("--no-duplicate", SWITCH_ISLAND)


if __name__ == "__main__":
    unittest.main()
