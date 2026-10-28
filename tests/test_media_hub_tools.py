import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
HELPER = ROOT / "scripts" / "media-hub-tools.py"
SPEC = importlib.util.spec_from_file_location("media_hub_tools", HELPER)
tools = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tools)


def fake_executable(mapping):
    def resolve(name):
        return mapping.get(name, "")
    return resolve


class ToolDetectionTests(unittest.TestCase):
    def test_status_reports_optional_tools_without_requiring_them(self):
        mapping = {
            "kitty": "/usr/bin/kitty",
            "ffplay": "/usr/bin/ffplay",
            "ffmpeg": "/usr/bin/ffmpeg",
            "ffprobe": "/usr/bin/ffprobe",
        }
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            result = tools.status_payload()
        self.assertTrue(result["ok"])
        self.assertFalse(result["aniReady"])
        self.assertEqual(result["aniCli"], "")
        self.assertEqual(result["terminals"][0]["id"], "kitty")
        self.assertEqual(result["players"][0]["id"], "ffplay")
        self.assertIn("ani-cli", result["guidance"]["aniCli"])
        self.assertNotIn("/home/", json.dumps(result))

    def test_ani_cli_missing_is_a_clear_failure(self):
        with patch.object(tools, "executable", return_value=""):
            with self.assertRaises(tools.ToolError) as caught:
                tools.ani_command()
        self.assertEqual(caught.exception.code, "ani_cli_missing")
        self.assertIn("Install ani-cli", caught.exception.message)

    def test_terminal_missing_does_not_invent_a_launcher(self):
        mapping = {"ani-cli": "/usr/bin/ani-cli"}
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            with self.assertRaises(tools.ToolError) as caught:
                tools.ani_command()
        self.assertEqual(caught.exception.code, "terminal_missing")

    def test_ani_cli_is_started_interactively_without_a_title_argument(self):
        mapping = {
            "ani-cli": "/usr/bin/ani-cli",
            "kitty": "/usr/bin/kitty",
        }
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            result = tools.ani_command()
        self.assertTrue(result["ok"])
        self.assertEqual(result["command"],
                         ["/usr/bin/kitty", "--title", "GPS ani-cli", "/usr/bin/ani-cli"])
        self.assertNotIn("Attack on Titan", result["command"])
        self.assertEqual(result["terminal"]["label"], "Kitty")

    def test_terminal_argument_arrays_are_explicit_for_other_emulators(self):
        mapping = {
            "ani-cli": "/usr/bin/ani-cli",
            "alacritty": "/usr/bin/alacritty",
        }
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            result = tools.ani_command()
        self.assertEqual(result["command"],
                         ["/usr/bin/alacritty", "-e", "/usr/bin/ani-cli"])


class LocalVideoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.video = Path(self.temp.name) / "episode 01.mp4"
        self.video.write_bytes(b"not a real video")
        self.other = Path(self.temp.name) / "notes.txt"
        self.other.write_text("no")

    def tearDown(self):
        self.temp.cleanup()

    def test_local_video_is_validated_and_kept_as_one_argument(self):
        mapping = {"ffplay": "/usr/bin/ffplay"}
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            result = tools.video_command(str(self.video))
        self.assertTrue(result["ok"])
        self.assertEqual(result["command"],
                         ["/usr/bin/ffplay", "-autoexit", str(self.video.resolve())])
        self.assertEqual(result["path"], str(self.video.resolve()))
        self.assertNotIn("episode 01.mp4;", " ".join(result["command"]))

    def test_file_url_and_relative_path_are_handled_safely(self):
        mapping = {"ffplay": "/usr/bin/ffplay"}
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            result = tools.video_command(self.video.as_uri())
            self.assertEqual(result["path"], str(self.video.resolve()))
            with self.assertRaises(tools.ToolError) as caught:
                tools.video_command("episode.mp4")
        self.assertEqual(caught.exception.code, "invalid_path")

    def test_unsupported_file_directory_and_missing_file_are_rejected(self):
        mapping = {"ffplay": "/usr/bin/ffplay"}
        with patch.object(tools, "executable", side_effect=fake_executable(mapping)):
            for value, code in (
                (str(self.other), "unsupported_file"),
                (self.temp.name, "not_file"),
                (str(Path(self.temp.name) / "missing.mp4"), "not_found"),
                ("", "invalid_path"),
                ("/tmp/" + ("x" * 5000) + ".mp4", "invalid_path"),
            ):
                with self.assertRaises(tools.ToolError) as caught:
                    tools.video_command(value)
                self.assertEqual(caught.exception.code, code)

    def test_missing_player_is_reported_without_launching_anything(self):
        with patch.object(tools, "executable", return_value=""):
            with self.assertRaises(tools.ToolError) as caught:
                tools.video_command(str(self.video))
        self.assertEqual(caught.exception.code, "player_missing")
        self.assertIn("MPV", caught.exception.message)

    def test_control_characters_are_rejected(self):
        with self.assertRaises(tools.ToolError) as caught:
            tools.safe_local_path(str(self.video) + "\x00")
        self.assertEqual(caught.exception.code, "invalid_path")


class CliTests(unittest.TestCase):
    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = tools.main(argv)
        return code, json.loads(output.getvalue())

    def test_status_cli_is_json(self):
        with patch.object(tools, "status_payload", return_value={"ok": True, "aniReady": False}):
            code, payload = self.run_main(["status"])
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["aniReady"])

    def test_failures_are_json_and_do_not_echo_paths(self):
        with patch.object(tools, "video_command", side_effect=tools.ToolError(
                "player_missing", "Install MPV or another supported local video player, then retry.")):
            code, payload = self.run_main(["video-command", "--path", "/tmp/private.mp4"])
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "player_missing")
        self.assertNotIn("/tmp/private.mp4", json.dumps(payload))


if __name__ == "__main__":
    unittest.main()
