#!/usr/bin/env python3
"""Hermetic tests for GPS capture toolkit:

- scripts/gps-shot (modes: region, window, monitor)
- scripts/gps-record (start, stop, toggle, status)
- scripts/gps-picker (hex color selection and notification)
- scripts/privacy_detector screen recorder detection
"""

import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"


def create_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class HermeticCaptureTestCase(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="gps_capture_test_")
        self.bin_dir = Path(self.test_dir) / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        self.home_dir = Path(self.test_dir) / "home"
        self.home_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir = Path(self.test_dir) / "runtime"
        self.runtime_dir.mkdir(parents=True, exist_ok=True)

        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"
        self.env["HOME"] = str(self.home_dir)
        self.env["XDG_RUNTIME_DIR"] = str(self.runtime_dir)
        self.env["XDG_PICTURES_DIR"] = str(self.home_dir / "Pictures")
        self.env["XDG_VIDEOS_DIR"] = str(self.home_dir / "Videos")
        self.env["GPS_ROOT"] = str(REPO_ROOT)

        # Default log files for stub invocations
        self.notify_log = Path(self.test_dir) / "notify.log"
        self.wl_copy_log = Path(self.test_dir) / "wl_copy.log"
        self.grim_log = Path(self.test_dir) / "grim.log"
        self.slurp_log = Path(self.test_dir) / "slurp.log"

        # Install standard stubs
        self.setup_standard_stubs()

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def setup_standard_stubs(self):
        # Stub notify-send
        create_executable(self.bin_dir / "notify-send", f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> "{self.notify_log}"
exit 0
""")

        # Stub wl-copy
        create_executable(self.bin_dir / "wl-copy", f"""#!/usr/bin/env bash
printf 'ARGS:%s\\n' "$*" >> "{self.wl_copy_log}"
cat >> "{self.wl_copy_log}"
exit 0
""")

        # Stub grim
        create_executable(self.bin_dir / "grim", f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> "{self.grim_log}"
# Last argument is output file
for arg in "$@"; do
    out="$arg"
done
printf 'fake-png-data-bytes' > "$out"
exit 0
""")

        # Stub slurp
        create_executable(self.bin_dir / "slurp", f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> "{self.slurp_log}"
echo "10,20 100x200"
exit 0
""")

    def run_cmd(self, cmd, check=True):
        return subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.env,
            check=check,
        )


class TestGpsShot(HermeticCaptureTestCase):
    def test_screenshot_region_success(self):
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "region"])
        self.assertEqual(res.returncode, 0)
        out_path = Path(res.stdout.strip())
        self.assertTrue(out_path.is_file())
        self.assertGreater(out_path.stat().st_size, 0)
        self.assertIn("Screenshots", str(out_path))

        # Check grim was called with -g
        grim_content = self.grim_log.read_text(encoding="utf-8")
        self.assertIn("-g 10,20 100x200", grim_content)

        # Check wl-copy was invoked with -t image/png
        wl_content = self.wl_copy_log.read_text(encoding="utf-8")
        self.assertIn("image/png", wl_content)

        # Check notify-send was called
        for _ in range(20):
            if self.notify_log.exists():
                break
            time.sleep(0.05)
        self.assertTrue(self.notify_log.exists())
        notify_content = self.notify_log.read_text(encoding="utf-8")
        self.assertIn("GPS Shot", notify_content)
        self.assertIn("open=Open", notify_content)
        self.assertIn("swappy=Edit in Swappy", notify_content)

    def test_screenshot_region_cancellation(self):
        # Stub slurp to exit with 1 (cancel)
        create_executable(self.bin_dir / "slurp", """#!/usr/bin/env bash
exit 1
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "region"])
        self.assertEqual(res.returncode, 0)
        # No screenshot created
        shots_dir = self.home_dir / "Pictures" / "Screenshots"
        if shots_dir.is_dir():
            self.assertEqual(list(shots_dir.glob("*.png")), [])
        # No notify
        self.assertFalse(self.notify_log.exists())
        # No clipboard
        self.assertFalse(self.wl_copy_log.exists())

    def test_screenshot_window_success(self):
        # Stub hyprctl activewindow
        create_executable(self.bin_dir / "hyprctl", """#!/usr/bin/env bash
if [[ "$*" == *"activewindow"* ]]; then
    echo '{"at": [40, 50], "size": [800, 600]}'
    exit 0
fi
exit 0
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "window"])
        self.assertEqual(res.returncode, 0)
        grim_content = self.grim_log.read_text(encoding="utf-8")
        self.assertIn("-g 40,50 800x600", grim_content)

    def test_screenshot_monitor_success(self):
        # Stub hyprctl monitors
        create_executable(self.bin_dir / "hyprctl", """#!/usr/bin/env bash
if [[ "$*" == *"monitors"* ]]; then
    echo '[{"name": "DP-2", "focused": true}]'
    exit 0
fi
exit 0
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "monitor"])
        self.assertEqual(res.returncode, 0)
        grim_content = self.grim_log.read_text(encoding="utf-8")
        self.assertIn("-o DP-2", grim_content)

    def test_screenshot_missing_grim(self):
        env_no_grim = self.env.copy()
        env_no_grim["GPS_GRIM_BIN"] = "/nonexistent/grim"
        res = subprocess.run(
            [str(SCRIPTS_DIR / "gps-shot"), "region"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env_no_grim,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("grim is required", res.stderr)

    def test_screenshot_zero_byte_rejection(self):
        # Stub grim creates 0-byte file
        create_executable(self.bin_dir / "grim", """#!/usr/bin/env bash
for arg in "$@"; do out="$arg"; done
touch "$out"
exit 0
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "region"], check=False)
        self.assertEqual(res.returncode, 1)
        self.assertIn("empty", res.stderr)
        shots_dir = self.home_dir / "Pictures" / "Screenshots"
        if shots_dir.is_dir():
            self.assertEqual(list(shots_dir.glob("*.png")), [])

    def test_screenshot_filename_collision(self):
        shots_dir = self.home_dir / "Pictures" / "Screenshots"
        shots_dir.mkdir(parents=True, exist_ok=True)
        # Pre-seed a file with current timestamp
        t_str = time.strftime("%Y-%m-%d_%H-%M-%S")
        pre_file = shots_dir / f"screenshot_{t_str}.png"
        pre_file.write_text("existing", encoding="utf-8")

        res = self.run_cmd([str(SCRIPTS_DIR / "gps-shot"), "region"])
        self.assertEqual(res.returncode, 0)
        out_path = Path(res.stdout.strip())
        self.assertTrue(out_path.is_file())
        self.assertNotEqual(out_path, pre_file)
        self.assertTrue(str(out_path).endswith("_1.png") or str(out_path) != str(pre_file))
        # Existing file preserved
        self.assertEqual(pre_file.read_text(encoding="utf-8"), "existing")


class TestGpsRecord(HermeticCaptureTestCase):
    def setUp(self):
        super().setUp()
        # Create a stub gpu-screen-recorder daemon that respects SIGINT instantly
        self.gsr_log = Path(self.test_dir) / "gsr.log"
        create_executable(self.bin_dir / "gpu-screen-recorder", f"""#!/usr/bin/env python3
import sys, signal, time
with open("{self.gsr_log}", "a") as log:
    log.write("ARGS:" + " ".join(sys.argv[1:]) + "\\n")

out = None
for i, arg in enumerate(sys.argv):
    if arg == "-o" and i + 1 < len(sys.argv):
        out = sys.argv[i + 1]

if out:
    with open(out, "w") as f:
        f.write("initial-video-header")

def on_signal(signum, frame):
    if out:
        with open(out, "a") as f:
            f.write("finalized-moov-atom")
    sys.exit(0)

signal.signal(signal.SIGINT, on_signal)
signal.signal(signal.SIGTERM, on_signal)

while True:
    time.sleep(0.05)
""")

    def test_record_start_status_and_clean_stop(self):
        # 1. Start recording
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "start", "--monitor", "--no-audio"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Recording started", res.stdout)

        # 2. Check status
        res_stat = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "status"])
        self.assertEqual(res_stat.returncode, 0)
        status = json.loads(res_stat.stdout.strip())
        self.assertTrue(status.get("recording"))
        self.assertIn("pid", status)
        out_file = Path(status["file"])
        self.assertTrue(out_file.exists())

        # 3. Stop recording
        res_stop = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "stop"])
        self.assertEqual(res_stop.returncode, 0)
        self.assertIn("Recording saved", res_stop.stdout)

        # Output file must contain finalization bytes from SIGINT handler
        final_content = out_file.read_text(encoding="utf-8")
        self.assertIn("finalized-moov-atom", final_content)

        # Status must now report not recording
        res_after = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "status"])
        status_after = json.loads(res_after.stdout.strip())
        self.assertFalse(status_after.get("recording"))

        # Notification dispatched
        notify_content = self.notify_log.read_text(encoding="utf-8")
        self.assertIn("Recording Saved", notify_content)

    def test_record_double_start_prevention(self):
        res1 = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "start"])
        self.assertEqual(res1.returncode, 0)

        # Double start must fail
        res2 = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "start"], check=False)
        self.assertEqual(res2.returncode, 1)
        self.assertIn("already active", res2.stderr)

        # Cleanup
        self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "stop"])

    def test_record_stale_pid_handling(self):
        state_dir = self.runtime_dir / "gps"
        state_dir.mkdir(parents=True, exist_ok=True)
        state_file = state_dir / "record-state.json"
        # Write state with a non-existent PID
        state_file.write_text(json.dumps({
            "recording": True,
            "pid": 99999999,
            "recorder": "gpu-screen-recorder",
            "file": str(self.home_dir / "Videos" / "dummy.mp4")
        }), encoding="utf-8")

        res = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "status"])
        self.assertEqual(res.returncode, 0)
        status = json.loads(res_stat := res.stdout.strip())
        self.assertFalse(status.get("recording"))

        # State file cleaned up
        updated_state = json.loads(state_file.read_text(encoding="utf-8"))
        self.assertFalse(updated_state.get("recording"))

    def test_record_pid_identity_verification(self):
        # Spawn a background sleep process (not a screen recorder)
        proc = subprocess.Popen(["sleep", "60"])
        try:
            state_dir = self.runtime_dir / "gps"
            state_dir.mkdir(parents=True, exist_ok=True)
            state_file = state_dir / "record-state.json"
            state_file.write_text(json.dumps({
                "recording": True,
                "pid": proc.pid,
                "recorder": "gpu-screen-recorder",
                "file": str(self.home_dir / "Videos" / "dummy.mp4")
            }), encoding="utf-8")

            # Try to stop — it must refuse to signal the sleep process!
            res = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "stop"])
            self.assertEqual(res.returncode, 0)
            self.assertTrue(
                "No recording active" in res.stdout or "already terminated" in res.stdout,
                f"Unexpected output: {res.stdout}"
            )

            # Verify the sleep process was NOT killed!
            self.assertIsNone(proc.poll())
        finally:
            proc.terminate()
            proc.wait()

    def test_record_region_cancellation(self):
        # Stub slurp to exit with 1 (cancel)
        create_executable(self.bin_dir / "slurp", """#!/usr/bin/env bash
exit 1
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "start", "--region"])
        self.assertEqual(res.returncode, 0)
        res_stat = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "status"])
        status = json.loads(res_stat.stdout.strip())
        self.assertFalse(status.get("recording"))

    def test_record_audio_flag(self):
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "start", "--audio"])
        self.assertEqual(res.returncode, 0)
        gsr_log_content = self.gsr_log.read_text(encoding="utf-8")
        self.assertIn("-a default_output", gsr_log_content)
        self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "stop"])

    def test_record_toggle(self):
        # Toggle 1 -> starts
        res1 = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "toggle"])
        self.assertEqual(res1.returncode, 0)
        self.assertIn("Recording started", res1.stdout)

        # Toggle 2 -> stops
        res2 = self.run_cmd([str(SCRIPTS_DIR / "gps-record"), "toggle"])
        self.assertEqual(res2.returncode, 0)
        self.assertIn("Recording saved", res2.stdout)


class TestGpsPicker(HermeticCaptureTestCase):
    def test_picker_success(self):
        create_executable(self.bin_dir / "hyprpicker", """#!/usr/bin/env bash
echo "#38BDF8"
exit 0
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-picker")])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "#38BDF8")

        # Clipboard copy
        wl_content = self.wl_copy_log.read_text(encoding="utf-8")
        self.assertIn("#38BDF8", wl_content)

        # Swatch generated
        swatch_file = self.runtime_dir / "gps" / "swatch_38BDF8.svg"
        self.assertTrue(swatch_file.is_file())
        self.assertIn("#38BDF8", swatch_file.read_text(encoding="utf-8"))

        # Notification
        notify_content = self.notify_log.read_text(encoding="utf-8")
        self.assertIn("Color Picked", notify_content)
        self.assertIn("#38BDF8", notify_content)

    def test_picker_cancellation(self):
        create_executable(self.bin_dir / "hyprpicker", """#!/usr/bin/env bash
exit 1
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-picker")])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "")
        self.assertFalse(self.wl_copy_log.exists())
        self.assertFalse(self.notify_log.exists())

    def test_picker_missing_tool(self):
        env_no_picker = self.env.copy()
        env_no_picker["GPS_HYPRPICKER_BIN"] = "/nonexistent/hyprpicker"
        res = subprocess.run(
            [str(SCRIPTS_DIR / "gps-picker")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env_no_picker,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("sudo pacman -S hyprpicker", res.stderr)

    def test_picker_hex_normalization(self):
        create_executable(self.bin_dir / "hyprpicker", """#!/usr/bin/env bash
echo "  e06c75  "
exit 0
""")
        res = self.run_cmd([str(SCRIPTS_DIR / "gps-picker")])
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout.strip(), "#E06C75")


class TestPrivacyDetectorRecorder(HermeticCaptureTestCase):
    def test_privacy_detector_detects_screen_recorder(self):
        import sys
        sys.path.insert(0, str(SCRIPTS_DIR))
        from privacy_detector import check_screen_recorder

        # 1. Inactive -> []
        items = check_screen_recorder(runtime_dir=str(self.runtime_dir))
        self.assertEqual(items, [])

        # 2. Fake active recording with current process PID
        state_dir = self.runtime_dir / "gps"
        state_dir.mkdir(parents=True, exist_ok=True)
        state_file = state_dir / "record-state.json"
        state_file.write_text(json.dumps({
            "recording": True,
            "pid": os.getpid(),
            "recorder": "python",
            "mode": "monitor",
        }), encoding="utf-8")

        items = check_screen_recorder(runtime_dir=str(self.runtime_dir))
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["kind"], "screen")
        self.assertEqual(items[0]["app"], "GPS Screen Recorder")
        self.assertEqual(items[0]["pid"], os.getpid())


if __name__ == "__main__":
    unittest.main()
