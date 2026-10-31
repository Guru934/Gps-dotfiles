#!/usr/bin/env python3
"""Hermetic test suite for gps-deps and dependency manifests (Phase 5).

Verifies:
1. Correct parsing of manifests.
2. Blank lines and comments.
3. Malformed entry detection.
4. Duplicate package detection.
5. Installed package detection.
6. Missing package detection.
7. Official repository availability.
8. AUR availability.
9. Missing paru handling.
10. Required-only mode.
11. All-dependencies mode.
12. JSON output.
13. Exact grouped installation commands.
14. Missing metadata reported as unverified.
15. No installation commands executed.
16. No sudo invocation.
17. No package database synchronization.
18. No system files modified.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock

# Import the gps_deps module directly
REPO_ROOT = Path(__file__).resolve().parent.parent
sys_path_added = False
if str(REPO_ROOT / "scripts") not in os.sys.path:
    os.sys.path.insert(0, str(REPO_ROOT / "scripts"))
    sys_path_added = True

from importlib.machinery import SourceFileLoader

gps_deps_path = REPO_ROOT / "scripts" / "gps-deps"
gps_deps = SourceFileLoader("gps_deps", str(gps_deps_path)).load_module()


class MockCommandRunner:
    """Mock runner that simulates pacman and paru outputs and records all invocations."""

    def __init__(
        self,
        installed_packages: dict[str, str] | None = None,
        official_available: dict[str, dict[str, str]] | None = None,
        aur_available: dict[str, dict[str, str]] | None = None,
    ):
        self.installed = installed_packages or {}
        self.official = official_available or {}
        self.aur = aur_available or {}
        self.invocations: list[list[str]] = []

    def __call__(self, cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.invocations.append(cmd)
        cmd_str = " ".join(cmd)

        # Prohibit dangerous commands in tests
        for banned in ["sudo", "-Sy", "-Syu", "pacman -S ", "paru -S "]:
            if banned in cmd_str:
                raise RuntimeError(f"Prohibited command executed in dependency checker: {cmd_str}")

        # 1. pacman -Q (bulk query)
        if cmd == ["pacman", "-Q"]:
            lines = [f"{pkg} {ver}" for pkg, ver in self.installed.items()]
            return subprocess.CompletedProcess(cmd, 0, stdout="\n".join(lines), stderr="")

        # 2. pacman -Q <pkg>
        if len(cmd) == 3 and cmd[0] == "pacman" and cmd[1] == "-Q":
            target = cmd[2]
            if target in self.installed:
                return subprocess.CompletedProcess(cmd, 0, stdout=f"{target} {self.installed[target]}", stderr="")
            return subprocess.CompletedProcess(cmd, 1, stdout="", stderr=f"error: package '{target}' was not found")

        # 3. pacman -Si <pkg>
        if len(cmd) == 3 and cmd[0] == "pacman" and cmd[1] == "-Si":
            target = cmd[2]
            if target in self.official:
                info = self.official[target]
                repo = info.get("repo", "extra")
                ver = info.get("version", "1.0.0-1")
                out = f"Repository      : {repo}\nName            : {target}\nVersion         : {ver}\n"
                return subprocess.CompletedProcess(cmd, 0, stdout=out, stderr="")
            return subprocess.CompletedProcess(cmd, 1, stdout="", stderr=f"error: package '{target}' was not found")

        # 4. paru -Si <pkg>
        if len(cmd) == 3 and cmd[0].endswith("paru") and cmd[1] == "-Si":
            target = cmd[2]
            if target in self.aur:
                info = self.aur[target]
                ver = info.get("version", "1.0.0-1")
                out = f"Repository      : aur\nName            : {target}\nVersion         : {ver}\n"
                return subprocess.CompletedProcess(cmd, 0, stdout=out, stderr="")
            return subprocess.CompletedProcess(cmd, 1, stdout="", stderr=f"error: package '{target}' was not found")

        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="command not mocked")


class GpsDepsTests(unittest.TestCase):
    """Hermetic unit tests for dependency checker logic and manifests."""

    def setUp(self):
        self.test_dir = tempfile.TemporaryDirectory(prefix="gps_deps_test_")
        self.dir_path = Path(self.test_dir.name)

    def tearDown(self):
        self.test_dir.cleanup()

    def create_manifests(
        self,
        required_content: str = "",
        optional_content: str = "",
        aur_content: str = "",
    ) -> Path:
        (self.dir_path / "required.txt").write_text(required_content, encoding="utf-8")
        (self.dir_path / "optional.txt").write_text(optional_content, encoding="utf-8")
        (self.dir_path / "aur.txt").write_text(aur_content, encoding="utf-8")
        return self.dir_path

    def test_01_correct_parsing_of_manifests(self):
        """1. Correct parsing of manifests with standard tags and descriptions."""
        self.create_manifests(
            required_content="quickshell # Core shell\npython # Scripting\n",
            optional_content="kitty [optional] # Terminal\ngrim [feature] # Screenshot\n",
            aur_content="awatcher-bundle [optional] # ActivityWatch daemon\n",
        )
        entries, errors = gps_deps.load_all_manifests(self.dir_path)
        self.assertEqual(len(errors), 0, f"Unexpected errors: {errors}")
        self.assertEqual(len(entries), 5)

        names = [e.name for e in entries]
        self.assertEqual(names, ["quickshell", "python", "kitty", "grim", "awatcher-bundle"])
        self.assertTrue(entries[0].is_required)
        self.assertEqual(entries[0].category, "core-required")
        self.assertFalse(entries[2].is_required)
        self.assertEqual(entries[2].category, "optional")
        self.assertEqual(entries[3].category, "feature")
        self.assertEqual(entries[4].source, "aur")

    def test_02_blank_lines_and_comments_ignored(self):
        """2. Blank lines, whitespace, and full-line comments are ignored."""
        content = (
            "# Header comment\n"
            "\n"
            "   # Indented comment\n"
            "quickshell # Valid entry\n"
            "   \n"
            "python    \n"
            "# Trailing comment\n"
        )
        self.create_manifests(required_content=content)
        entries, errors = gps_deps.load_all_manifests(self.dir_path)
        self.assertEqual(len(errors), 0)
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0].name, "quickshell")
        self.assertEqual(entries[1].name, "python")

    def test_03_malformed_entry_detection(self):
        """3. Detect malformed package names, invalid tags, and excessive tokens."""
        bad_required = (
            "InvalidPackageNameUpperCase # bad\n"
            "package_two with extra tokens before comment # bad\n"
            "package_three [bad-tag-format # bad\n"
        )
        self.create_manifests(required_content=bad_required)
        entries, errors = gps_deps.load_all_manifests(self.dir_path)
        self.assertEqual(len(entries), 0)
        self.assertEqual(len(errors), 3)
        self.assertTrue(any("must match lowercase" in e for e in errors))
        self.assertTrue(any("Malformed entry" in e for e in errors))
        self.assertTrue(any("Malformed category tag" in e for e in errors))

    def test_04_duplicate_package_detection(self):
        """4. Detect duplicate package entries within and across manifests."""
        self.create_manifests(
            required_content="quickshell # first\nquickshell # duplicate in same file\n",
            optional_content="quickshell # duplicate across files\n",
        )
        entries, errors = gps_deps.load_all_manifests(self.dir_path)
        self.assertEqual(len(errors), 2)
        self.assertTrue(all("Duplicate package 'quickshell'" in e for e in errors))

    def test_05_installed_package_detection(self):
        """5. Installed packages are detected and marked OK."""
        self.create_manifests(required_content="quickshell # core\npython # core\n")
        runner = MockCommandRunner(installed_packages={"quickshell": "0.3.2-1", "python": "3.13.0-1"})
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
            which=lambda x: "/usr/bin/paru",
        )
        self.assertEqual(len(errors), 0)
        self.assertTrue(all(e.status == "OK" for e in entries))
        self.assertTrue(all(e.installed for e in entries))
        self.assertEqual(entries[0].installed_version, "0.3.2-1")

    def test_06_missing_package_detection(self):
        """6. Missing packages are detected when not installed."""
        self.create_manifests(required_content="quickshell # core\nhyprlock # missing\n")
        runner = MockCommandRunner(
            installed_packages={"quickshell": "0.3.2-1"},
            official_available={"hyprlock": {"repo": "cachyos-extra-v3", "version": "0.4.1-1"}},
        )
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
            which=lambda x: "/usr/bin/paru",
        )
        self.assertEqual(len(errors), 0)
        self.assertEqual(entries[0].status, "OK")
        self.assertEqual(entries[1].status, "MISSING")
        self.assertFalse(entries[1].installed)
        self.assertTrue(entries[1].available)

    def test_07_official_repository_availability(self):
        """7. Official repository metadata is correctly parsed via pacman -Si."""
        self.create_manifests(required_content="hyprlock # core\n")
        runner = MockCommandRunner(
            installed_packages={},
            official_available={"hyprlock": {"repo": "cachyos-extra-v3", "version": "0.4.1-1"}},
        )
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
        )
        self.assertEqual(entries[0].status, "MISSING")
        self.assertEqual(entries[0].repo, "cachyos-extra-v3")
        self.assertEqual(entries[0].available_version, "0.4.1-1")

    def test_08_aur_availability(self):
        """8. AUR metadata is queried using paru -Si when package is missing."""
        self.create_manifests(aur_content="awatcher-bundle [optional] # screen time\n")
        runner = MockCommandRunner(
            installed_packages={},
            aur_available={"awatcher-bundle": {"version": "0.4.0-1"}},
        )
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
            which=lambda x: "/usr/bin/paru" if x == "paru" else None,
        )
        self.assertEqual(entries[0].status, "MISSING")
        self.assertEqual(entries[0].source, "aur")
        self.assertEqual(entries[0].available_version, "0.4.0-1")

    def test_09_missing_paru_handling(self):
        """9. Missing paru is reported and uninstalled AUR dependencies become UNVERIFIED."""
        self.create_manifests(aur_content="awatcher-bundle [optional] # screen time\n")
        runner = MockCommandRunner(installed_packages={})
        entries, errors, paru_avail = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
            which=lambda x: None,  # paru not found
        )
        self.assertFalse(paru_avail)
        self.assertEqual(entries[0].status, "UNVERIFIED")
        self.assertIn("paru not found", entries[0].details)

        report = gps_deps.format_text_report(entries, errors, paru_available=paru_avail)
        self.assertIn("Notice: 'paru' is not installed", report)

    def test_10_required_only_mode(self):
        """10. Required-only mode filters out optional dependencies and only suggests required."""
        self.create_manifests(
            required_content="quickshell # core\nhyprlock # core missing\n",
            optional_content="kitty [optional] # optional missing\n",
        )
        runner = MockCommandRunner(
            installed_packages={"quickshell": "0.3.2-1"},
            official_available={
                "hyprlock": {"repo": "extra", "version": "0.4.0"},
                "kitty": {"repo": "extra", "version": "0.38.0"},
            },
        )
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            required_only=True,
            runner=runner,
        )
        self.assertEqual(len(entries), 2)
        self.assertTrue(all(e.is_required for e in entries))
        report = gps_deps.format_text_report(entries, errors, required_only=True)
        self.assertNotIn("Optional:", report)
        self.assertIn("sudo pacman -S --needed hyprlock", report)
        self.assertNotIn("kitty", report)

    def test_11_all_dependencies_mode(self):
        """11. All-dependencies mode includes required, optional, and AUR dependencies."""
        self.create_manifests(
            required_content="hyprlock # req missing\n",
            optional_content="mpv [optional] # opt missing\n",
            aur_content="ani-cli [optional] # aur missing\n",
        )
        runner = MockCommandRunner(
            installed_packages={},
            official_available={
                "hyprlock": {"repo": "extra", "version": "1.0"},
                "mpv": {"repo": "extra", "version": "1.0"},
            },
            aur_available={"ani-cli": {"version": "1.0"}},
        )
        entries, errors, paru_avail = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            include_all=True,
            runner=runner,
            which=lambda x: "/usr/bin/paru",
        )
        report = gps_deps.format_text_report(entries, errors, include_all=True, paru_available=paru_avail)
        self.assertIn("Core required:", report)
        self.assertIn("Optional:", report)
        self.assertIn("AUR:", report)
        self.assertIn("sudo pacman -S --needed hyprlock mpv", report)
        self.assertIn("paru -S --needed ani-cli", report)

    def test_12_json_output(self):
        """12. JSON report is valid, complete, and contains expected keys."""
        self.create_manifests(
            required_content="quickshell # core\nhyprlock # missing\n",
        )
        runner = MockCommandRunner(
            installed_packages={"quickshell": "0.3.2"},
            official_available={"hyprlock": {"repo": "extra", "version": "1.0"}},
        )
        entries, errors, paru_avail = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
        )
        raw_json = gps_deps.format_json_report(entries, errors, paru_available=paru_avail)
        data = json.loads(raw_json)

        self.assertIn("ok", data)
        self.assertFalse(data["ok"])  # has required missing
        self.assertIn("summary", data)
        self.assertEqual(data["summary"]["total"], 2)
        self.assertEqual(data["summary"]["installed"], 1)
        self.assertEqual(data["summary"]["missing"], 1)
        self.assertIn("suggested_commands", data)
        self.assertEqual(data["suggested_commands"]["pacman"], "sudo pacman -S --needed hyprlock")
        self.assertEqual(len(data["dependencies"]), 2)

    def test_13_exact_grouped_installation_commands(self):
        """13. Exact pacman and paru installation commands are generated."""
        self.create_manifests(
            required_content="pkg1 # core\npkg2 # core\n",
            aur_content="aur1 [optional] # aur\n",
        )
        runner = MockCommandRunner(
            installed_packages={},
            official_available={"pkg1": {"repo": "extra"}, "pkg2": {"repo": "extra"}},
            aur_available={"aur1": {"version": "1.0"}},
        )
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
            which=lambda x: "/usr/bin/paru",
        )
        cmds = gps_deps.build_suggested_commands(entries, include_all=True)
        self.assertEqual(cmds["pacman"], "sudo pacman -S --needed pkg1 pkg2")
        self.assertEqual(cmds["paru"], "paru -S --needed aur1")

    def test_14_missing_metadata_reported_as_unverified(self):
        """14. Packages not found in repositories are marked UNVERIFIED."""
        self.create_manifests(
            required_content="nonexistent-official-package # bad\n",
        )
        runner = MockCommandRunner(installed_packages={}, official_available={})
        entries, errors, _ = gps_deps.run_dependency_audit(
            manifest_dir=self.dir_path,
            runner=runner,
        )
        self.assertEqual(entries[0].status, "UNVERIFIED")
        self.assertIn("not found in official repository", entries[0].details)

    def test_15_no_installation_commands_executed(self):
        """15. Dependency checker never executes pacman -S, paru -S or install operations."""
        self.create_manifests(required_content="quickshell # core\nhyprlock # missing\n")
        runner = MockCommandRunner(
            installed_packages={},
            official_available={"hyprlock": {"repo": "extra"}},
        )
        gps_deps.run_dependency_audit(manifest_dir=self.dir_path, runner=runner)

        for inv in runner.invocations:
            self.assertNotIn("-S", inv)
            self.assertNotIn("-Sy", inv)
            self.assertNotIn("install", inv)

    def test_16_no_sudo_invocation(self):
        """16. Dependency checker never invokes sudo."""
        self.create_manifests(required_content="quickshell # core\n")
        runner = MockCommandRunner(installed_packages={"quickshell": "0.3.2"})
        gps_deps.run_dependency_audit(manifest_dir=self.dir_path, runner=runner)

        for inv in runner.invocations:
            self.assertNotIn("sudo", inv)

    def test_17_no_package_database_synchronization(self):
        """17. Dependency checker never runs pacman -Sy or pacman -Syy."""
        self.create_manifests(required_content="quickshell # core\n")
        runner = MockCommandRunner(installed_packages={"quickshell": "0.3.2"})
        gps_deps.run_dependency_audit(manifest_dir=self.dir_path, runner=runner)

        for inv in runner.invocations:
            self.assertNotIn("-Sy", inv)
            self.assertNotIn("-Syy", inv)
            self.assertNotIn("-Syu", inv)

    def test_18_no_system_files_modified(self):
        """18. Manifest files and temporary directory files remain unaltered."""
        self.create_manifests(
            required_content="quickshell # core\n",
            optional_content="kitty [optional] # terminal\n",
            aur_content="ani-cli [optional] # anime\n",
        )
        before_state = {f: f.read_bytes() for f in self.dir_path.glob("*.txt")}
        runner = MockCommandRunner(installed_packages={"quickshell": "1.0"})
        gps_deps.run_dependency_audit(manifest_dir=self.dir_path, runner=runner)
        after_state = {f: f.read_bytes() for f in self.dir_path.glob("*.txt")}

        self.assertEqual(before_state, after_state)

    def test_19_production_manifests_validity(self):
        """Verify the actual production manifests in packages/ directory."""
        prod_dir = REPO_ROOT / "packages"
        self.assertTrue((prod_dir / "required.txt").is_file())
        self.assertTrue((prod_dir / "optional.txt").is_file())
        self.assertTrue((prod_dir / "aur.txt").is_file())

        entries, errors = gps_deps.load_all_manifests(prod_dir)
        self.assertEqual(len(errors), 0, f"Production manifests have errors: {errors}")
        self.assertGreater(len(entries), 20)

        # Check disjoint sets across manifests
        req_names = {e.name for e in entries if e.manifest == "required"}
        opt_names = {e.name for e in entries if e.manifest == "optional"}
        aur_names = {e.name for e in entries if e.manifest == "aur"}

        self.assertEqual(len(req_names & opt_names), 0, "Duplicate package between required and optional")
        self.assertEqual(len(req_names & aur_names), 0, "Duplicate package between required and aur")
        self.assertEqual(len(opt_names & aur_names), 0, "Duplicate package between optional and aur")


if __name__ == "__main__":
    unittest.main()
