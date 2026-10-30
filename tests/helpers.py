"""Shared test helpers for hermetic test execution.

Provides isolated environment directories (HOME, XDG_*), sets WAYLAND_DISPLAY to empty,
prepends safe stubs for desktop daemons (hypridle, ydotool, pw-play, quickshell, etc.),
and tracks/cleans up spawned child processes.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent

PROHIBITED_REAL_BINARIES = [
    "hypridle",
    "ydotool",
    "ydotoold",
    "pw-play",
    "quickshell",
    "awww",
    "awww-daemon",
    "wl-paste",
    "wl-copy",
]


def create_stub_executable(path: Path, script_content: str) -> None:
    path.write_text(script_content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IRWXU)


HYPRIDLE_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys, os, re, time

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:hypridle:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

args = sys.argv[1:]
if "-v" in args:
    config_path = None
    if "-c" in args:
        idx = args.index("-c")
        if idx + 1 < len(args):
            config_path = args[idx + 1]
    elif "--config" in args:
        idx = args.index("--config")
        if idx + 1 < len(args):
            config_path = args[idx + 1]

    if config_path and os.path.isfile(config_path):
        with open(config_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        print(f"[LOG] Using config file: {config_path}")
        # Parse listener blocks with brace-depth tracking
        blocks = []
        in_listener = False
        current = []
        depth = 0
        for line in content.splitlines():
            stripped = line.strip()
            if "listener" in stripped and "{" in stripped and not in_listener:
                in_listener = True
                current = []
                depth = line.count("{") - line.count("}")
                continue
            if in_listener:
                depth += line.count("{") - line.count("}")
                if depth <= 0:
                    in_listener = False
                    blocks.append("\n".join(current))
                    current = []
                else:
                    current.append(line)

        for block in blocks:
            t_m = re.search(r'timeout\s*=\s*([0-9]+)', block)
            ot_m = re.search(r'on-timeout\s*=\s*([^\r\n]+)', block)
            ores_m = re.search(r'on-resume\s*=\s*([^\r\n]+)', block)
            if t_m:
                t_val = t_m.group(1)
                print(f"[LOG] Registered timeout rule for {t_val}s:")
                if ot_m:
                    print(f"      on-timeout: {ot_m.group(1).strip()}")
                if ores_m:
                    print(f"      on-resume: {ores_m.group(1).strip()}")
                print("      ignore_inhibit: false")
                print("      condition_cmd: ")
                print("      condition_retry: 0")
    else:
        print("[LOG] Registered timeout rule for 150s")
        print("[LOG] Registered timeout rule for 300s")
        print("[LOG] Registered timeout rule for 330s")
        print("[LOG] Registered timeout rule for 1200s")
    sys.exit(0)

while True:
    time.sleep(1)
'''

QUICKSHELL_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:quickshell:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

args = sys.argv[1:]
if "--version" in args:
    print("Quickshell 0.3.2 (revision 4f508be500dea6e5732cc3d50382a0048b17e7b1)")
    sys.exit(0)

if len(args) > 0 and args[0] == "ipc":
    sys.exit(0)

sys.exit(0)
'''

PW_PLAY_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:pw-play:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

sys.exit(0)
'''

YDOTOOL_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

name = sys.argv[0].split("/")[-1]
log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:{name}:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

sys.exit(0)
'''

AWWW_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys, time

name = sys.argv[0].split("/")[-1]
log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:{name}:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

if name == "awww-daemon":
    while True:
        time.sleep(1)

sys.exit(0)
'''

WL_PASTE_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys, time

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:wl-paste:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

args = sys.argv[1:]
if "--list-types" in args:
    print("text/plain")
    print("UTF8_STRING")
    sys.exit(0)

if "--watch" in args:
    while True:
        time.sleep(1)

sys.exit(0)
'''

WL_COPY_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:wl-copy:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

if not sys.stdin.isatty():
    try:
        sys.stdin.read()
    except Exception:
        pass

sys.exit(0)
'''

CLIPHIST_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:cliphist:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

args = sys.argv[1:]
if len(args) > 0 and args[0] == "list":
    print("1\tGPS Hermetic Test Clipboard Entry")
    sys.exit(0)

if len(args) > 0 and args[0] == "decode":
    print("GPS Hermetic Test Clipboard Entry")
    sys.exit(0)

sys.exit(0)
'''

HYPRCTL_STUB_TEMPLATE = r'''#!/usr/bin/env python3
import sys

log_file = LOG_FILE_PLACEHOLDER
try:
    with open(log_file, "a") as f:
        f.write(f"STUB_CALL:hyprctl:{' '.join(sys.argv[1:])}\n")
except Exception:
    pass

args = sys.argv[1:]
if "version" in args:
    print("Hyprland 0.57.0 built from hermetic test stubs clean.")
    sys.exit(0)

if "clients" in args or "-j" in args:
    print("[]")
    sys.exit(0)

sys.exit(0)
'''


def populate_stubs_dir(stubs_dir: Path, log_file: Path | None = None) -> None:
    """Populate stubs_dir with lightweight stub executables for hermetic testing."""
    stubs_dir.mkdir(parents=True, exist_ok=True)
    quoted_log = repr(str(log_file)) if log_file else repr("/dev/null")

    create_stub_executable(
        stubs_dir / "hypridle",
        HYPRIDLE_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "quickshell",
        QUICKSHELL_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "pw-play",
        PW_PLAY_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "ydotool",
        YDOTOOL_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "ydotoold",
        YDOTOOL_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "awww",
        AWWW_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "awww-daemon",
        AWWW_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "wl-paste",
        WL_PASTE_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "wl-copy",
        WL_COPY_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "cliphist",
        CLIPHIST_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )
    create_stub_executable(
        stubs_dir / "hyprctl",
        HYPRCTL_STUB_TEMPLATE.replace("LOG_FILE_PLACEHOLDER", quoted_log),
    )


class HermeticEnv:
    """Creates isolated test directories, environment variables, stubs and process tracking."""

    def __init__(self, prefix: str = "gps_test_"):
        self.tmp_dir = tempfile.TemporaryDirectory(prefix=prefix)
        self.root = Path(self.tmp_dir.name).resolve()
        self.home = self.root / "home"
        self.runtime = self.root / "run"
        self.config = self.home / ".config"
        self.state = self.home / ".local" / "state"
        self.share = self.home / ".local" / "share"
        self.cache = self.home / ".cache"
        self.stubs = self.root / "stubs"
        self.log_file = self.root / "stub_invocations.log"

        for d in [self.home, self.runtime, self.config, self.state, self.share, self.cache, self.stubs]:
            d.mkdir(parents=True, exist_ok=True)

        # Provide repo fontconfig in isolated XDG_CONFIG_HOME for hermetic font tests
        fontconfig_dir = self.config / "fontconfig"
        fontconfig_dir.mkdir(parents=True, exist_ok=True)
        repo_fonts_conf = REPO_ROOT / "dots" / "fontconfig" / "fonts.conf"
        if repo_fonts_conf.is_file():
            (fontconfig_dir / "fonts.conf").symlink_to(repo_fonts_conf)

        populate_stubs_dir(self.stubs, self.log_file)

        # Build clean environment dictionary
        self.env: dict[str, str] = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.state),
            "XDG_DATA_HOME": str(self.share),
            "XDG_CACHE_HOME": str(self.cache),
            "WAYLAND_DISPLAY": "",
            "DISPLAY": "",
            "HYPRLAND_INSTANCE_SIGNATURE": "",
            "PATH": f"{self.stubs}:{os.environ.get('PATH', '')}",
            "PYTHONPATH": str(REPO_ROOT),
            "GPS_STUB_LOG": str(self.log_file),
        }

        # Track only processes started by this instance
        self.started_pids: set[int] = set()

    def spawn(self, cmd: list[str], **kwargs) -> subprocess.Popen:
        """Spawn a child process using hermetic environment and track its PID."""
        env = {**self.env, **kwargs.pop("env", {})}
        proc = subprocess.Popen(cmd, env=env, **kwargs)
        self.started_pids.add(proc.pid)
        return proc

    def run(self, cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
        """Run a process synchronously using hermetic environment."""
        env = {**self.env, **kwargs.pop("env", {})}
        return subprocess.run(cmd, env=env, **kwargs)

    def get_stub_calls(self) -> list[str]:
        """Return lines logged by any stub executables."""
        if self.log_file.is_file():
            return [line.strip() for line in self.log_file.read_text(encoding="utf-8").splitlines() if line.strip()]
        return []

    def cleanup_child_processes(self) -> None:
        """Terminate and reap ONLY child processes started by this helper."""
        for pid in list(self.started_pids):
            try:
                os.kill(pid, 0)
            except OSError:
                continue

            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass

        time.sleep(0.05)

        for pid in list(self.started_pids):
            try:
                os.kill(pid, 0)
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass

        self.started_pids.clear()

    def cleanup(self) -> None:
        """Cleanup child processes and delete temporary directory."""
        self.cleanup_child_processes()
        try:
            self.tmp_dir.cleanup()
        except Exception:
            pass

    def __enter__(self) -> HermeticEnv:
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.cleanup()


class HermeticTestCase(unittest.TestCase):
    """Base test case providing hermetic environment and safe teardown."""

    def setUp(self) -> None:
        super().setUp()
        self.hermetic = HermeticEnv()
        self.env = self.hermetic.env
        self.tmp_path = self.hermetic.root

    def tearDown(self) -> None:
        self.hermetic.cleanup()
        super().tearDown()
