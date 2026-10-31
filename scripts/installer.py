#!/usr/bin/env python3
"""GPS Desktop — Safe, Idempotent User-Space Installer.

Manages installation, updates, verification, and uninstallation of GPS desktop
configurations, user binaries, and settings templates.

Core principles:
- Strictly user-space: Never uses sudo, never touches system directories (/etc, /usr, /boot, /var).
- Safe & Reversible: Full pre-apply backups with SHA256 integrity verification.
- Transactional: Interrupted apply rolls back cleanly to previous state.
- Idempotent: Repeated apply makes zero duplicate changes and no redundant backups.
- Conflict-Preserving: Never overwrites user customizations or user runtime state.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple


class SecurityError(Exception):
    """Raised when a path breaches security or sandbox constraints."""
    pass


class BackupVerificationError(Exception):
    """Raised when a pre-flight backup fails integrity verification."""
    pass


class TransactionError(Exception):
    """Raised when an installation transaction fails during execution."""
    pass


FORBIDDEN_SYSTEM_PREFIXES = (
    Path("/etc"),
    Path("/usr"),
    Path("/boot"),
    Path("/var"),
    Path("/opt"),
    Path("/bin"),
    Path("/sbin"),
    Path("/lib"),
    Path("/lib64"),
    Path("/sys"),
    Path("/proc"),
    Path("/dev"),
    Path("/root"),
)

USER_STATE_PATTERNS = {
    "rice-settings.json",
    "gps-theme.json",
    "gps-last-wall.txt",
    "pet.json",
    "dnd",
    "notifications.json",
    "clipboard_pinned.json",
    "clipboard_settings.json",
    "clipboard_paused",
    "planner.json",
    "gamemode_state.json",
    "startup.log",
    "island.log",
    "theme.log",
}


def compute_sha256(path: Path) -> str:
    """Compute SHA256 digest of a regular file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def validate_path_safety(
    target: Path,
    allowed_roots: List[Path],
    label: str = "path",
) -> Path:
    """Ensure path is within user space and not in forbidden system directories."""
    # Ensure neither target nor its parent resolves into a forbidden system directory
    resolved_parent = target.parent.resolve()
    for forbidden in FORBIDDEN_SYSTEM_PREFIXES:
        try:
            resolved_parent.relative_to(forbidden)
            raise SecurityError(
                f"Security violation: {label} '{target}' parent resolves to system directory '{resolved_parent}'"
            )
        except ValueError:
            pass

    if not os.path.islink(target) and target.exists():
        resolved_target = target.resolve()
        for forbidden in FORBIDDEN_SYSTEM_PREFIXES:
            try:
                resolved_target.relative_to(forbidden)
                raise SecurityError(
                    f"Security violation: {label} '{target}' resolves to system directory '{resolved_target}'"
                )
            except ValueError:
                pass

    # Ensure target parent directory is contained within at least one allowed user root
    in_allowed = False
    for root in allowed_roots:
        resolved_root = root.resolve()
        try:
            resolved_parent.relative_to(resolved_root)
            in_allowed = True
            break
        except ValueError:
            pass

    if not in_allowed:
        raise SecurityError(
            f"Security violation: {label} '{target}' is outside allowed user roots: {[str(r) for r in allowed_roots]}"
        )

    return target


class InstallerManifest:
    """Declarative specification of all files managed by the GPS installer."""

    def __init__(
        self,
        repo_root: Path,
        home_dir: Path,
        config_dir: Path,
        state_dir: Path,
        bin_dir: Path,
    ):
        self.repo_root = repo_root
        self.home_dir = home_dir
        self.config_dir = config_dir
        self.state_dir = state_dir
        self.bin_dir = bin_dir
        self.backup_root = state_dir / "gps" / "backups"

    def get_entries(self) -> List[Dict[str, Any]]:
        """Return list of declared installation items."""
        return [
            # Hyprland configurations
            {
                "id": "hyprland_lua",
                "category": "config",
                "src": self.repo_root / "dots" / "hypr" / "hyprland.lua",
                "dest": self.config_dir / "hypr" / "hyprland.lua",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "hypridle_conf",
                "category": "config",
                "src": self.repo_root / "dots" / "hypr" / "hypridle.conf",
                "dest": self.config_dir / "hypr" / "hypridle.conf",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "hyprlock_conf",
                "category": "config",
                "src": self.repo_root / "dots" / "hypr" / "hyprlock.conf",
                "dest": self.config_dir / "hypr" / "hyprlock.conf",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "lock_bg_conf",
                "category": "config",
                "src": self.repo_root / "dots" / "hypr" / "lock-bg.conf",
                "dest": self.config_dir / "hypr" / "lock-bg.conf",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "lock_colors_conf",
                "category": "config",
                "src": self.repo_root / "dots" / "hypr" / "lock-colors.conf",
                "dest": self.config_dir / "hypr" / "lock-colors.conf",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # Rofi configuration
            {
                "id": "rofi_config",
                "category": "config",
                "src": self.repo_root / "dots" / "rofi" / "config.rasi",
                "dest": self.config_dir / "rofi" / "config.rasi",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # AWatcher configuration
            {
                "id": "awatcher_config",
                "category": "config",
                "src": self.repo_root / "dots" / "awatcher" / "config.toml",
                "dest": self.config_dir / "awatcher" / "config.toml",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "awatcher_bundle_config",
                "category": "config",
                "src": self.repo_root / "dots" / "awatcher" / "bundle-config.toml",
                "dest": self.config_dir / "awatcher" / "bundle-config.toml",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # Fontconfig
            {
                "id": "fontconfig_fonts",
                "category": "config",
                "src": self.repo_root / "dots" / "fontconfig" / "fonts.conf",
                "dest": self.config_dir / "fontconfig" / "fonts.conf",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # GTK 3 & GTK 4 settings.ini (repository-managed; gtk.css is generated dynamically)
            {
                "id": "gtk3_settings",
                "category": "config",
                "src": self.repo_root / "dots" / "gtk-3.0" / "settings.ini",
                "dest": self.config_dir / "gtk-3.0" / "settings.ini",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "gtk4_settings",
                "category": "config",
                "src": self.repo_root / "dots" / "gtk-4.0" / "settings.ini",
                "dest": self.config_dir / "gtk-4.0" / "settings.ini",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # UWSM environment (Phase 2 & Phase 7 requirement 15: preserve conflicting UWSM config)
            {
                "id": "uwsm_env",
                "category": "config",
                "src": self.repo_root / "dots" / "uwsm" / "env",
                "dest": self.config_dir / "uwsm" / "env",
                "type": "symlink",
                "backup_on_conflict": False,
                "preserve_on_conflict": True,
                "reversible": True,
                "is_state": False,
            },
            # Production user binaries (~/.local/bin)
            {
                "id": "bin_gps_ipc",
                "category": "binary",
                "src": self.repo_root / "scripts" / "gps-ipc",
                "dest": self.bin_dir / "gps-ipc",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "bin_gps_lock",
                "category": "binary",
                "src": self.repo_root / "scripts" / "gps-lock",
                "dest": self.bin_dir / "gps-lock",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "bin_gps_idle",
                "category": "binary",
                "src": self.repo_root / "scripts" / "gps-idle",
                "dest": self.bin_dir / "gps-idle",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "bin_gps_sound",
                "category": "binary",
                "src": self.repo_root / "scripts" / "gps-sound",
                "dest": self.bin_dir / "gps-sound",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "bin_pet_alert",
                "category": "binary",
                "src": self.repo_root / "scripts" / "pet-alert",
                "dest": self.bin_dir / "pet-alert",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            {
                "id": "bin_gps_gamemode",
                "category": "binary",
                "src": self.repo_root / "scripts" / "gps-gamemode",
                "dest": self.bin_dir / "gps-gamemode",
                "type": "symlink",
                "backup_on_conflict": True,
                "preserve_on_conflict": False,
                "reversible": True,
                "is_state": False,
            },
            # Templates: created ONLY if absent; never symlinked, never overwritten, never deleted
            {
                "id": "template_rice_settings",
                "category": "template",
                "src": self.repo_root / "templates" / "rice-settings.json",
                "dest": self.config_dir / "quickshell" / "rice-settings.json",
                "type": "template",
                "backup_on_conflict": False,
                "preserve_on_conflict": True,
                "reversible": False,
                "is_state": True,
            },
        ]


class GpsInstaller:
    """Main orchestrator for dry-run, apply, check, and uninstall operations."""

    def __init__(
        self,
        repo_root: Path,
        home_dir: Optional[Path] = None,
        config_dir: Optional[Path] = None,
        state_dir: Optional[Path] = None,
        data_dir: Optional[Path] = None,
        bin_dir: Optional[Path] = None,
        no_color: bool = False,
        skip_deps: bool = False,
    ):
        self.repo_root = repo_root.resolve()
        self.skip_deps = skip_deps or (os.environ.get("GPS_SKIP_DEPS") == "1")

        # Derive user directories
        self.home_dir = (home_dir or Path.home()).resolve()

        if config_dir:
            self.config_dir = config_dir.resolve()
        elif not home_dir and "XDG_CONFIG_HOME" in os.environ:
            self.config_dir = Path(os.environ["XDG_CONFIG_HOME"]).resolve()
        else:
            self.config_dir = self.home_dir / ".config"

        if state_dir:
            self.state_dir = state_dir.resolve()
        elif not home_dir and "XDG_STATE_HOME" in os.environ:
            self.state_dir = Path(os.environ["XDG_STATE_HOME"]).resolve()
        else:
            self.state_dir = self.home_dir / ".local" / "state"

        if data_dir:
            self.data_dir = data_dir.resolve()
        elif not home_dir and "XDG_DATA_HOME" in os.environ:
            self.data_dir = Path(os.environ["XDG_DATA_HOME"]).resolve()
        else:
            self.data_dir = self.home_dir / ".local" / "share"

        self.bin_dir = (bin_dir or (self.home_dir / ".local" / "bin")).resolve()
        self.backup_root = self.state_dir / "gps" / "backups"
        self.active_manifest_path = self.state_dir / "gps" / "install_manifest.json"

        self.no_color = no_color or not sys.stdout.isatty() or ("NO_COLOR" in os.environ)
        self.setup_colors()

        self.manifest = InstallerManifest(
            repo_root=self.repo_root,
            home_dir=self.home_dir,
            config_dir=self.config_dir,
            state_dir=self.state_dir,
            bin_dir=self.bin_dir,
        )

    def setup_colors(self):
        if self.no_color:
            self.C_RESET = ""
            self.C_BOLD = ""
            self.C_GREEN = ""
            self.C_RED = ""
            self.C_YELLOW = ""
            self.C_CYAN = ""
            self.C_GRAY = ""
        else:
            self.C_RESET = "\033[0m"
            self.C_BOLD = "\033[1m"
            self.C_GREEN = "\033[32m"
            self.C_RED = "\033[31m"
            self.C_YELLOW = "\033[33m"
            self.C_CYAN = "\033[36m"
            self.C_GRAY = "\033[90m"

    @property
    def allowed_roots(self) -> List[Path]:
        return [self.home_dir, self.config_dir, self.state_dir, self.data_dir, self.bin_dir]

    def validate_dest(self, dest: Path) -> Path:
        return validate_path_safety(dest, self.allowed_roots, label="destination")

    def inspect_destination(self, entry: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze current state of destination without altering filesystem."""
        dest = entry["dest"]
        src = entry["src"]
        self.validate_dest(dest)

        info: Dict[str, Any] = {
            "entry": entry,
            "dest_exists": os.path.lexists(dest),
            "is_symlink": os.path.islink(dest),
            "is_dir": False,
            "is_file": False,
            "symlink_target": None,
            "canonical_target": None,
            "is_up_to_date": False,
            "is_conflict": False,
            "needs_backup": False,
            "preserve_existing": False,
            "action": "none",
            "reason": "",
        }

        if not info["dest_exists"]:
            info["action"] = "create_symlink" if entry["type"] == "symlink" else "create_template"
            info["reason"] = "Destination does not exist"
            return info

        if info["is_symlink"]:
            try:
                target_raw = os.readlink(dest)
                info["symlink_target"] = target_raw
                # Check if it points to GPS source
                canonical_dest_target = Path(dest).resolve()
                canonical_src = src.resolve()
                info["canonical_target"] = str(canonical_dest_target)
                if canonical_dest_target == canonical_src:
                    info["is_up_to_date"] = True
                    info["action"] = "up_to_date"
                    info["reason"] = f"Already correctly linked to {src}"
                    return info
            except OSError as e:
                info["reason"] = f"Broken symlink: {e}"

            # Symlink points to something else
            if entry.get("preserve_on_conflict", False):
                info["is_conflict"] = True
                info["preserve_existing"] = True
                info["action"] = "preserve"
                info["reason"] = f"Conflicting symlink pointing to {info.get('symlink_target')}; preserved without overwriting"
            else:
                info["is_conflict"] = True
                info["needs_backup"] = entry.get("backup_on_conflict", True)
                info["action"] = "backup_and_link"
                info["reason"] = f"Conflicting symlink pointing to {info.get('symlink_target')}; will be backed up"
            return info

        # Existing directory or file
        if dest.is_dir():
            info["is_dir"] = True
            info["is_conflict"] = True
            if entry.get("preserve_on_conflict", False):
                info["preserve_existing"] = True
                info["action"] = "preserve"
                info["reason"] = "Conflicting directory exists; preserved without overwriting"
            else:
                info["needs_backup"] = entry.get("backup_on_conflict", True)
                info["action"] = "backup_and_link"
                info["reason"] = "Conflicting directory exists; will be backed up"
            return info

        if dest.is_file():
            info["is_file"] = True
            if entry["type"] == "template":
                # Existing template/user state is preserved without change
                info["is_up_to_date"] = True
                info["action"] = "preserve"
                info["reason"] = "Existing configuration file preserved without modifying user state"
                return info

            if entry.get("preserve_on_conflict", False):
                info["is_conflict"] = True
                info["preserve_existing"] = True
                info["action"] = "preserve"
                info["reason"] = "Conflicting file exists; preserved without overwriting"
            else:
                info["is_conflict"] = True
                info["needs_backup"] = entry.get("backup_on_conflict", True)
                info["action"] = "backup_and_link"
                info["reason"] = "Conflicting file exists; will be backed up"
            return info

        return info

    def query_dependencies(self) -> Dict[str, Any]:
        """Call scripts/gps-deps --json to obtain authoritative dependency data."""
        if getattr(self, "skip_deps", False):
            return {"ok": False, "summary": {}, "dependencies": [], "suggested_commands": {}}

        deps_script = self.repo_root / "scripts" / "gps-deps"
        if not deps_script.is_file():
            return {"ok": False, "summary": {}, "dependencies": [], "suggested_commands": {}}

        try:
            res = subprocess.run(
                [sys.executable, str(deps_script), "--json"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if res.returncode == 0 and res.stdout.strip():
                return json.loads(res.stdout)
        except Exception:
            pass
        return {"ok": False, "summary": {}, "dependencies": [], "suggested_commands": {}}

    def print_plan(self, inspection_results: List[Dict[str, Any]], backup_dir: Path):
        """Format and print detailed dry-run installation plan."""
        print(f"\n{self.C_BOLD}{self.C_CYAN}=== GPS Desktop Installer — Installation Plan ==={self.C_RESET}")
        print(f"  {self.C_GRAY}Repository Root : {self.repo_root}{self.C_RESET}")
        print(f"  {self.C_GRAY}Target Home     : {self.home_dir}{self.C_RESET}")
        print(f"  {self.C_GRAY}Config Directory: {self.config_dir}{self.C_RESET}")
        print(f"  {self.C_GRAY}State Directory : {self.state_dir}{self.C_RESET}")
        print(f"  {self.C_GRAY}User Binaries   : {self.bin_dir}{self.C_RESET}")
        print(f"  {self.C_GRAY}Planned Backup  : {backup_dir}{self.C_RESET}\n")

        print(f"{self.C_BOLD}Planned Target Actions:{self.C_RESET}")
        to_link = 0
        to_backup = 0
        up_to_date = 0
        preserved = 0
        to_create_template = 0

        for r in inspection_results:
            entry = r["entry"]
            action = r["action"]
            dest_str = str(entry["dest"])
            src_str = str(entry["src"])

            if action == "up_to_date":
                up_to_date += 1
                status = f"{self.C_GREEN}[UP TO DATE]{self.C_RESET}"
            elif action == "create_symlink":
                to_link += 1
                status = f"{self.C_CYAN}[LINK]{self.C_RESET}"
            elif action == "create_template":
                to_create_template += 1
                status = f"{self.C_CYAN}[CREATE TEMPLATE]{self.C_RESET}"
            elif action == "backup_and_link":
                to_link += 1
                to_backup += 1
                status = f"{self.C_YELLOW}[BACKUP & LINK]{self.C_RESET}"
            elif action == "preserve":
                preserved += 1
                status = f"{self.C_GREEN}[PRESERVE]{self.C_RESET}"
            else:
                status = f"[{action}]"

            rel_src = entry["src"].relative_to(self.repo_root) if self.repo_root in entry["src"].parents else entry["src"]
            print(f"  {status:<24} {rel_src} -> {dest_str}")
            if r["reason"] and action != "up_to_date":
                print(f"     {self.C_GRAY}Notice: {r['reason']}{self.C_RESET}")

        print(f"\n{self.C_BOLD}Summary of Actions:{self.C_RESET}")
        print(f"  Symlinks to create / update : {to_link}")
        print(f"  Templates to create         : {to_create_template}")
        print(f"  Conflicting files to back up: {to_backup}")
        print(f"  Already up to date          : {up_to_date}")
        print(f"  Preserved existing configs  : {preserved}")

    def dry_run(self) -> int:
        """Execute read-only dry-run inspection without modifying any files."""
        # Validate that repo source files exist
        for entry in self.manifest.get_entries():
            if not entry["src"].is_file():
                print(
                    f"{self.C_RED}ERROR: Source file missing in repository: {entry['src']}{self.C_RESET}",
                    file=sys.stderr,
                )
                return 1

        simulated_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        simulated_backup_dir = self.backup_root / simulated_ts

        inspection = [self.inspect_destination(e) for e in self.manifest.get_entries()]
        self.print_plan(inspection, simulated_backup_dir)

        # Inspect dependencies
        dep_data = self.query_dependencies()
        self.report_dependencies(dep_data)

        print(f"\n{self.C_GREEN}{self.C_BOLD}[DRY-RUN] Completed inspection with ZERO changes made to the filesystem.{self.C_RESET}\n")
        return 0

    def report_dependencies(self, dep_data: Dict[str, Any]):
        """Analyze and display dependency guidance and prominent security warnings."""
        if not dep_data or not dep_data.get("ok"):
            print(f"\n{self.C_YELLOW}Note: Dependency inspector unavailable or returned incomplete data.{self.C_RESET}")
            return

        deps = dep_data.get("dependencies", [])
        missing_core = [d for d in deps if d.get("is_required") and not d.get("installed")]
        missing_optional = [d for d in deps if not d.get("is_required") and not d.get("installed")]

        # Prominent security check: hyprlock and hypridle
        lock_missing = any(d.get("name") == "hyprlock" and not d.get("installed") for d in deps)
        idle_missing = any(d.get("name") == "hypridle" and not d.get("installed") for d in deps)

        if lock_missing or idle_missing:
            print(f"\n{self.C_RED}{self.C_BOLD}========================================================================{self.C_RESET}")
            print(f"{self.C_RED}{self.C_BOLD} CRITICAL SECURITY WARNING: LOCK & IDLE FACILITIES INCOMPLETE{self.C_RESET}")
            print(f"{self.C_RED}{self.C_BOLD}========================================================================{self.C_RESET}")
            print(f"{self.C_YELLOW}Your system is missing core security screen locking or idle watchers:{self.C_RESET}")
            if lock_missing:
                print(f"  - {self.C_BOLD}hyprlock{self.C_RESET}: Desktop screen locking facility (GPS Lockscreen)")
            if idle_missing:
                print(f"  - {self.C_BOLD}hypridle{self.C_RESET}: Session activity watcher (GPS Idle Management)")
            print(f"{self.C_RED}WARNING: The desktop CANNOT be marked fully protected by GPS until installed!{self.C_RESET}")
            print(f"{self.C_BOLD}To install manually, execute:{self.C_RESET}")
            print(f"  sudo pacman -S --needed hyprlock hypridle\n")

        if missing_core:
            print(f"\n{self.C_RED}{self.C_BOLD}Missing Core-Required Dependencies ({len(missing_core)}):{self.C_RESET}")
            for d in missing_core:
                print(f"  - {self.C_BOLD}{d['name']}{self.C_RESET}: {d.get('description', '')}")

        if missing_optional:
            print(f"\n{self.C_YELLOW}{self.C_BOLD}Unavailable Optional Features ({len(missing_optional)} missing dependencies):{self.C_RESET}")
            for d in missing_optional:
                print(f"  - {self.C_BOLD}{d['name']}{self.C_RESET} ({d.get('manifest', 'optional')}): {d.get('description', '')}")

        suggested = dep_data.get("suggested_commands", {})
        if suggested.get("pacman") or suggested.get("paru"):
            print(f"\n{self.C_BOLD}Suggested Manual Installation Commands:{self.C_RESET}")
            if suggested.get("pacman"):
                print(f"  {self.C_CYAN}Official packages : {suggested['pacman']}{self.C_RESET}")
            if suggested.get("paru"):
                print(f"  {self.C_CYAN}AUR packages      : {suggested['paru']}{self.C_RESET}")

    def apply(self) -> int:
        """Execute safe, idempotent installation with pre-apply backup and rollback."""
        # 1. Pre-flight source verification
        for entry in self.manifest.get_entries():
            if not entry["src"].is_file():
                print(f"{self.C_RED}ERROR: Source file missing: {entry['src']}{self.C_RESET}", file=sys.stderr)
                return 1

        inspection = [self.inspect_destination(e) for e in self.manifest.get_entries()]
        items_to_backup = [r for r in inspection if r["needs_backup"]]

        # 2. Check if already completely up to date
        all_up_to_date = all(
            r["action"] in ("up_to_date", "preserve") for r in inspection
        )
        if all_up_to_date and not items_to_backup:
            print(f"\n{self.C_GREEN}{self.C_BOLD}GPS Desktop is already fully up to date.{self.C_RESET}")
            print("Zero files modified; 0 backups created (idempotent no-op).\n")
            return 0

        # 3. Create unique backup directory
        ts_base = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_dir = self.backup_root / ts_base
        counter = 1
        while backup_dir.exists():
            backup_dir = self.backup_root / f"{ts_base}_{counter}"
            counter += 1

        backup_files_dir = backup_dir / "files"

        # If items need backup, create backup directory with 0700 permissions
        if items_to_backup:
            backup_files_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            print(f"\n{self.C_BOLD}Backing up conflicting destinations to:{self.C_RESET} {backup_dir}")

        backup_records: List[Dict[str, Any]] = []

        # 4. Perform backups with attribute preservation
        for r in items_to_backup:
            dest = r["entry"]["dest"]
            rel_backup_path = Path(f"{r['entry']['category']}") / dest.name
            b_target = backup_files_dir / rel_backup_path
            b_target.parent.mkdir(parents=True, exist_ok=True)

            record: Dict[str, Any] = {
                "id": r["entry"]["id"],
                "dest": str(dest),
                "src": str(r["entry"]["src"]),
                "backup_rel": str(rel_backup_path),
                "original_type": "absent",
                "symlink_target": None,
                "sha256": None,
                "size": None,
                "mode": None,
            }

            if r["is_symlink"]:
                target_raw = os.readlink(dest)
                record["original_type"] = "symlink"
                record["symlink_target"] = target_raw
                # Store symlink in backup archive
                if b_target.is_symlink() or b_target.exists():
                    b_target.unlink()
                os.symlink(target_raw, b_target)
            elif r["is_dir"]:
                record["original_type"] = "directory"
                record["mode"] = oct(dest.stat().st_mode)
                shutil.copytree(dest, b_target, symlinks=True)
            elif r["is_file"]:
                record["original_type"] = "file"
                record["sha256"] = compute_sha256(dest)
                record["size"] = dest.stat().st_size
                record["mode"] = oct(dest.stat().st_mode)
                shutil.copy2(dest, b_target)

            backup_records.append(record)
            print(f"  Backed up: {dest} -> {rel_backup_path}")

        # 5. Verify backup integrity
        for rec in backup_records:
            b_path = backup_files_dir / rec["backup_rel"]
            if rec["original_type"] == "file":
                if not b_path.is_file() or compute_sha256(b_path) != rec["sha256"]:
                    raise BackupVerificationError(f"Backup verification failed for {rec['dest']}")
            elif rec["original_type"] == "symlink":
                if not b_path.is_symlink() or os.readlink(b_path) != rec["symlink_target"]:
                    raise BackupVerificationError(f"Backup symlink verification failed for {rec['dest']}")
            elif rec["original_type"] == "directory":
                if not b_path.is_dir():
                    raise BackupVerificationError(f"Backup directory verification failed for {rec['dest']}")

        # 6. Build transaction manifest
        manifest_data = {
            "version": "1.0",
            "timestamp": backup_dir.name,
            "created_at": datetime.now().isoformat(),
            "repo_root": str(self.repo_root),
            "home_dir": str(self.home_dir),
            "config_dir": str(self.config_dir),
            "state_dir": str(self.state_dir),
            "bin_dir": str(self.bin_dir),
            "backup_dir": str(backup_dir) if items_to_backup else None,
            "apply_completed": False,
            "entries": [],
        }

        # 7. Execute transaction with journal for atomic rollback
        journal: List[Dict[str, Any]] = []
        try:
            print(f"\n{self.C_BOLD}Applying GPS configuration and symlinks...{self.C_RESET}")
            for r in inspection:
                entry = r["entry"]
                dest = entry["dest"]
                src = entry["src"]
                action = r["action"]

                entry_manifest: Dict[str, Any] = {
                    "id": entry["id"],
                    "category": entry["category"],
                    "type": entry["type"],
                    "src": str(src),
                    "dest": str(dest),
                    "original_type": "absent",
                    "backup_rel": None,
                    "symlink_target": None,
                    "applied": False,
                }

                # Find corresponding backup record if exists
                matched_backup = next((b for b in backup_records if b["dest"] == str(dest)), None)
                if matched_backup:
                    entry_manifest["original_type"] = matched_backup["original_type"]
                    entry_manifest["backup_rel"] = matched_backup["backup_rel"]
                    entry_manifest["symlink_target"] = matched_backup["symlink_target"]
                elif r["dest_exists"]:
                    if r["is_symlink"]:
                        entry_manifest["original_type"] = "symlink"
                        entry_manifest["symlink_target"] = r.get("symlink_target")
                    elif r["is_file"]:
                        entry_manifest["original_type"] = "file"
                    elif r["is_dir"]:
                        entry_manifest["original_type"] = "directory"

                if action in ("up_to_date", "preserve"):
                    print(f"  {self.C_GREEN}Preserved / Up to date:{self.C_RESET} {dest}")
                    entry_manifest["applied"] = True
                    manifest_data["entries"].append(entry_manifest)
                    continue

                dest.parent.mkdir(parents=True, exist_ok=True)

                if entry["type"] == "symlink":
                    # Step recorded in journal before modification
                    j_step = {
                        "dest": dest,
                        "src": src,
                        "type": "symlink",
                        "backup_path": (backup_files_dir / matched_backup["backup_rel"]) if matched_backup else None,
                        "original_type": matched_backup["original_type"] if matched_backup else "absent",
                        "symlink_target": matched_backup["symlink_target"] if matched_backup else None,
                    }
                    journal.append(j_step)

                    # Atomic symlink replacement
                    tmp_link = dest.with_name(f".{dest.name}.tmp.{os.getpid()}")
                    if tmp_link.is_symlink() or tmp_link.exists():
                        tmp_link.unlink()
                    os.symlink(src, tmp_link)

                    # If dest is an existing directory, remove it (already backed up)
                    if dest.is_dir() and not os.path.islink(dest):
                        shutil.rmtree(dest)

                    os.replace(tmp_link, dest)
                    entry_manifest["applied"] = True
                    print(f"  {self.C_CYAN}Linked:{self.C_RESET} {dest} -> {src}")

                elif entry["type"] == "template":
                    # Only create template if absent
                    if not dest.exists() and not dest.is_symlink():
                        j_step = {
                            "dest": dest,
                            "src": src,
                            "type": "template",
                            "backup_path": None,
                            "original_type": "absent",
                            "symlink_target": None,
                        }
                        journal.append(j_step)

                        tmp_file = dest.with_name(f".{dest.name}.tmp.{os.getpid()}")
                        shutil.copy2(src, tmp_file)
                        os.replace(tmp_file, dest)
                        entry_manifest["applied"] = True
                        print(f"  {self.C_CYAN}Created template:{self.C_RESET} {dest}")
                    else:
                        print(f"  {self.C_GREEN}Preserved user settings:{self.C_RESET} {dest}")
                        entry_manifest["applied"] = True

                manifest_data["entries"].append(entry_manifest)

            # Mark completion
            manifest_data["apply_completed"] = True

            # Save manifest in backup_dir (if created) and in state_dir as active manifest
            if items_to_backup:
                with open(backup_dir / "manifest.json", "w", encoding="utf-8") as f:
                    json.dump(manifest_data, f, indent=2)

            self.active_manifest_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            with open(self.active_manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest_data, f, indent=2)

        except Exception as e:
            # ROLLBACK on failure
            print(f"\n{self.C_RED}ERROR encountered during installation: {e}{self.C_RESET}", file=sys.stderr)
            print(f"{self.C_YELLOW}Initiating automatic rollback of current transaction...{self.C_RESET}", file=sys.stderr)
            self.rollback_transaction(journal, backup_dir if items_to_backup else None)
            raise TransactionError(f"Apply transaction failed and was rolled back: {e}") from e

        print(f"\n{self.C_GREEN}{self.C_BOLD}GPS Desktop installation completed successfully!{self.C_RESET}")

        # Post-install dependency notice
        dep_data = self.query_dependencies()
        self.report_dependencies(dep_data)
        return 0

    def rollback_transaction(self, journal: List[Dict[str, Any]], backup_dir: Optional[Path] = None):
        """Roll back only changes executed in the current failed transaction."""
        for step in reversed(journal):
            dest = step["dest"]
            orig_type = step["original_type"]
            backup_path = step["backup_path"]

            try:
                # If destination currently points to our newly created link or template, remove it
                if os.path.islink(dest) or dest.is_file():
                    dest.unlink()

                # Restore previous state from backup if one existed
                if orig_type == "file" and backup_path and backup_path.is_file():
                    shutil.copy2(backup_path, dest)
                elif orig_type == "symlink" and step.get("symlink_target"):
                    os.symlink(step["symlink_target"], dest)
                elif orig_type == "directory" and backup_path and backup_path.is_dir():
                    shutil.copytree(backup_path, dest, symlinks=True)
            except Exception as e:
                print(f"Warning: Failed to rollback {dest}: {e}", file=sys.stderr)

        if backup_dir and backup_dir.is_dir():
            shutil.rmtree(backup_dir, ignore_errors=True)

    def uninstall(self) -> int:
        """Safely uninstall GPS desktop configurations, preserving user modifications and state."""
        print(f"\n{self.C_BOLD}{self.C_CYAN}=== GPS Desktop Uninstaller ==={self.C_RESET}")

        # Locate active manifest
        manifest_path = None
        if self.active_manifest_path.is_file():
            manifest_path = self.active_manifest_path
        elif self.backup_root.is_dir():
            # Search latest backup manifest
            backups = sorted(
                [d for d in self.backup_root.iterdir() if d.is_dir() and (d / "manifest.json").is_file()],
                key=lambda p: p.name,
                reverse=True,
            )
            if backups:
                manifest_path = backups[0] / "manifest.json"

        manifest_data = None
        if manifest_path:
            try:
                with open(manifest_path, "r", encoding="utf-8") as f:
                    manifest_data = json.load(f)
            except Exception as e:
                print(f"{self.C_RED}Warning: Failed to read installation manifest {manifest_path}: {e}{self.C_RESET}")

        entries_to_process = []
        backup_files_dir = None
        if manifest_data and "entries" in manifest_data:
            entries_to_process = manifest_data["entries"]
            if manifest_data.get("backup_dir"):
                backup_files_dir = Path(manifest_data["backup_dir"]) / "files"
        else:
            # Fallback to inspecting current manifest definitions
            print(f"{self.C_YELLOW}No saved manifest found; scanning declared GPS targets directly.{self.C_RESET}")
            for entry in self.manifest.get_entries():
                entries_to_process.append({
                    "id": entry["id"],
                    "type": entry["type"],
                    "src": str(entry["src"]),
                    "dest": str(entry["dest"]),
                    "original_type": "absent",
                    "backup_rel": None,
                })

        # Phase 7 test 21: Verify backup archive integrity before restoration
        if backup_files_dir and backup_files_dir.is_dir():
            for entry in entries_to_process:
                orig_type = entry.get("original_type")
                b_rel = entry.get("backup_rel")
                if orig_type in ("file", "symlink", "directory") and b_rel:
                    b_file = backup_files_dir / b_rel
                    if not b_file.exists() and not b_file.is_symlink():
                        print(
                            f"{self.C_RED}ERROR: Corrupt or incomplete backup archive: missing {b_file}. "
                            f"Refusing restoration to prevent inconsistent state.{self.C_RESET}",
                            file=sys.stderr,
                        )
                        return 1

        conflicts: List[str] = []
        restored: List[str] = []
        removed: List[str] = []
        preserved_state: List[str] = []

        for entry in entries_to_process:
            dest = Path(entry["dest"])
            src = Path(entry["src"])
            orig_type = entry.get("original_type", "absent")
            b_rel = entry.get("backup_rel")
            backup_source = (backup_files_dir / b_rel) if (backup_files_dir and b_rel) else None

            # 1. Never delete templates or user state files
            if entry["type"] == "template" or dest.name in USER_STATE_PATTERNS:
                preserved_state.append(str(dest))
                continue

            if not os.path.lexists(dest):
                # Destination already absent; if original was present, restore it
                if orig_type != "absent" and backup_source and (backup_source.exists() or backup_source.is_symlink()):
                    self.restore_original(dest, orig_type, backup_source, entry.get("symlink_target"))
                    restored.append(str(dest))
                continue

            # Check if destination is a symlink pointing to GPS source
            if os.path.islink(dest):
                try:
                    target_raw = os.readlink(dest)
                    canonical_dest_target = dest.resolve()
                    canonical_src = src.resolve()

                    if canonical_dest_target == canonical_src:
                        # Safe to remove GPS-managed symlink
                        dest.unlink()
                        removed.append(str(dest))

                        # Restore original if one existed
                        if orig_type != "absent" and backup_source and (backup_source.exists() or backup_source.is_symlink()):
                            self.restore_original(dest, orig_type, backup_source, entry.get("symlink_target"))
                            restored.append(str(dest))
                    else:
                        # User altered symlink target after installation -> Conflict!
                        conflict_msg = f"{dest} points to '{target_raw}', not GPS target '{src}'. Preserved user symlink."
                        conflicts.append(conflict_msg)
                except Exception as e:
                    conflicts.append(f"{dest}: Error evaluating symlink: {e}")
            else:
                # Destination is a regular file or directory (user replaced symlink) -> Conflict!
                conflict_msg = f"{dest} was replaced by the user with a regular {'directory' if dest.is_dir() else 'file'}. Preserved user file."
                conflicts.append(conflict_msg)

        # Print detailed report
        print(f"\n{self.C_BOLD}Uninstall Results:{self.C_RESET}")
        for p in removed:
            print(f"  {self.C_GREEN}Removed GPS symlink:{self.C_RESET} {p}")
        for p in restored:
            print(f"  {self.C_CYAN}Restored original file:{self.C_RESET} {p}")
        for p in preserved_state:
            print(f"  {self.C_GRAY}Preserved user state / template:{self.C_RESET} {p}")

        if conflicts:
            print(f"\n{self.C_YELLOW}{self.C_BOLD}Conflicts Detected ({len(conflicts)}):{self.C_RESET}")
            for c in conflicts:
                print(f"  - {self.C_YELLOW}{c}{self.C_RESET}")
            print(
                f"\n{self.C_RED}{self.C_BOLD}Uninstall finished with {len(conflicts)} conflict(s). "
                f"User files were preserved; uninstall is incomplete.{self.C_RESET}\n"
            )
            return 2

        # Clean up active manifest on clean uninstall
        if self.active_manifest_path.is_file():
            try:
                self.active_manifest_path.unlink()
            except OSError:
                pass

        print(f"\n{self.C_GREEN}{self.C_BOLD}GPS Desktop uninstalled cleanly. All original files restored.{self.C_RESET}\n")
        return 0

    def restore_original(
        self,
        dest: Path,
        orig_type: str,
        backup_source: Path,
        symlink_target: Optional[str],
    ):
        """Restore original item from backup preserving attributes."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        if orig_type == "file":
            shutil.copy2(backup_source, dest)
        elif orig_type == "symlink":
            target = symlink_target or os.readlink(backup_source)
            os.symlink(target, dest)
        elif orig_type == "directory":
            shutil.copytree(backup_source, dest, symlinks=True)

    def check(self) -> int:
        """Run system diagnostics and verify installation correctness."""
        print(f"\n{self.C_BOLD}{self.C_CYAN}=== GPS Desktop Installation & Health Check ==={self.C_RESET}\n")

        # 1. Check core installation status
        print(f"{self.C_BOLD}[1/3] Verifying GPS Managed Files:{self.C_RESET}")
        all_ok = True
        missing_count = 0
        conflicts_count = 0

        for entry in self.manifest.get_entries():
            dest = entry["dest"]
            src = entry["src"]
            if entry["type"] == "template":
                if dest.is_file():
                    print(f"  {self.C_GREEN}OK{self.C_RESET}     {dest} (Template installed)")
                else:
                    print(f"  {self.C_YELLOW}NOTICE{self.C_RESET} {dest} (Template absent; defaults will be used)")
            elif entry["type"] == "symlink":
                if os.path.islink(dest):
                    try:
                        if dest.resolve() == src.resolve():
                            print(f"  {self.C_GREEN}OK{self.C_RESET}     {dest} -> {src}")
                        else:
                            print(f"  {self.C_YELLOW}DIFF{self.C_RESET}   {dest} -> {os.readlink(dest)} (does not point to {src})")
                            conflicts_count += 1
                            all_ok = False
                    except OSError:
                        print(f"  {self.C_RED}BROKEN{self.C_RESET} {dest} (broken symlink)")
                        missing_count += 1
                        all_ok = False
                elif dest.exists():
                    print(f"  {self.C_YELLOW}FILE{self.C_RESET}   {dest} (existing regular file, not symlinked to repo)")
                    conflicts_count += 1
                else:
                    print(f"  {self.C_RED}MISSING{self.C_RESET} {dest} (not installed)")
                    missing_count += 1
                    all_ok = False

        # 2. Check dependencies
        print(f"\n{self.C_BOLD}[2/3] Inspecting System & Feature Dependencies:{self.C_RESET}")
        dep_data = self.query_dependencies()
        self.report_dependencies(dep_data)

        # 3. Run gps-doctor diagnostics
        print(f"\n{self.C_BOLD}[3/3] Running Session Health Doctor:{self.C_RESET}")
        doctor_script = self.repo_root / "scripts" / "gps-doctor"
        doctor_code = 0
        if doctor_script.is_file():
            res = subprocess.run([sys.executable, str(doctor_script)])
            doctor_code = res.returncode
        else:
            print(f"  {self.C_YELLOW}gps-doctor script not found at {doctor_script}{self.C_RESET}")

        if not all_ok:
            print(f"\n{self.C_RED}{self.C_BOLD}Installation check completed with issues ({missing_count} missing, {conflicts_count} altered).{self.C_RESET}")
            return 1

        print(f"\n{self.C_GREEN}{self.C_BOLD}Core installation files are properly installed.{self.C_RESET}")
        return doctor_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Safe, idempotent user-space installer for GPS Desktop"
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true", default=False, help="Inspect actions without making changes (default)")
    group.add_argument("--apply", action="store_true", default=False, help="Apply installation plan with backup and rollback")
    group.add_argument("--uninstall", action="store_true", default=False, help="Revert installation and restore backed-up configurations")
    group.add_argument("--check", action="store_true", default=False, help="Verify installation status and run session health diagnostics")

    parser.add_argument("--home", type=Path, default=None, help="Override HOME directory")
    parser.add_argument("--config-dir", type=Path, default=None, help="Override XDG_CONFIG_HOME")
    parser.add_argument("--state-dir", type=Path, default=None, help="Override XDG_STATE_HOME")
    parser.add_argument("--data-dir", type=Path, default=None, help="Override XDG_DATA_HOME")
    parser.add_argument("--bin-dir", type=Path, default=None, help="Override user bin directory (~/.local/bin)")
    parser.add_argument("--repo-root", type=Path, default=None, help="Override repository root directory")
    parser.add_argument("--no-color", action="store_true", default=False, help="Disable colored output")
    parser.add_argument("--skip-deps", action="store_true", default=False, help="Skip querying system dependencies")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    # Never allow running as root or via sudo
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        print("ERROR: The GPS installer must not be run as root or via sudo.", file=sys.stderr)
        print("It is strictly a user-space installer and modifies only user directories.", file=sys.stderr)
        return 1

    parser = build_parser()
    args = parser.parse_args(argv)

    # Resolve repository root
    if args.repo_root:
        repo_root = args.repo_root.resolve()
    elif "GPS_ROOT" in os.environ and os.path.isdir(os.environ["GPS_ROOT"]):
        repo_root = Path(os.environ["GPS_ROOT"]).resolve()
    else:
        repo_root = Path(__file__).resolve().parent.parent

    installer = GpsInstaller(
        repo_root=repo_root,
        home_dir=args.home,
        config_dir=args.config_dir,
        state_dir=args.state_dir,
        data_dir=args.data_dir,
        bin_dir=args.bin_dir,
        no_color=args.no_color,
        skip_deps=args.skip_deps,
    )

    if args.apply:
        return installer.apply()
    elif args.uninstall:
        return installer.uninstall()
    elif args.check:
        return installer.check()
    else:
        # Default is dry-run
        return installer.dry_run()


if __name__ == "__main__":
    sys.exit(main())
