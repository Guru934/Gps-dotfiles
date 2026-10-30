import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
from tests.helpers import HermeticTestCase

HELPER = REPO_ROOT / "scripts" / "pet-alert"
if not HELPER.exists():
    HELPER = Path.home() / ".local/bin/pet-alert"


class PetAlertHelperTests(HermeticTestCase):
    def run_helper(self, mode, payload=""):
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(self.hermetic.env, XDG_RUNTIME_DIR=runtime, PET_ALERT_WAIT_SECONDS="0")
            result = subprocess.run([str(HELPER), mode], input=payload, text=True,
                                    env=env, capture_output=True, check=True)
            path = Path(runtime) / "pet" / "alerts.jsonl"
            lines = path.read_text().splitlines() if path.exists() else []
            return result, [json.loads(line) for line in lines]

    def test_empty_and_malformed_input_are_noops(self):
        for payload in ("", "not json", "{}"):
            result, records = self.run_helper("codex", payload)
            self.assertEqual(result.stdout, "")
            self.assertEqual(records, [])

    def test_codex_permission_request_uses_documented_fields(self):
        repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        payload = json.dumps({
            "hook_event_name": "PermissionRequest",
            "session_id": "s1",
            "cwd": repo_dir,
            "tool_name": "Bash",
            "tool_input": {"command": "printf '%s' \"quoted\"", "description": "safe test"},
        })
        _, records = self.run_helper("codex", payload)
        self.assertEqual(records[0]["tool"], "codex")
        self.assertEqual(records[0]["session"], "s1")
        self.assertIn("printf", records[0]["detail"])
        self.assertEqual(records[0]["cwd"], repo_dir)
        self.assertEqual(records[0]["schema"], "pet-alert/v1")
        self.assertTrue(records[0]["respondable"])

    def test_codex_response_returns_documented_decision(self):
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(self.hermetic.env, XDG_RUNTIME_DIR=runtime, PET_ALERT_WAIT_SECONDS="2")
            payload = json.dumps({
                "hook_event_name": "PermissionRequest", "session_id": "s1",
                "turn_id": "r1", "cwd": "/tmp", "tool_name": "Bash",
                "tool_input": {"command": "echo safe"},
            })
            proc = subprocess.Popen([str(HELPER), "codex"], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, text=True, env=env)
            proc.stdin.write(payload)
            proc.stdin.close()
            queue = Path(runtime) / "pet/alerts.jsonl"
            for _ in range(40):
                if queue.exists() and queue.stat().st_size:
                    break
                time.sleep(0.05)
            record = json.loads(queue.read_text().splitlines()[0])
            result = subprocess.run([str(HELPER), "respond", record["token"], "allow"],
                                    env=env, check=True, capture_output=True, text=True)
            stdout, _ = proc.communicate(timeout=3)
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(json.loads(stdout)["hookSpecificOutput"]["decision"]["behavior"], "allow")
            self.assertEqual(result.stdout, "")

            records = [json.loads(line) for line in queue.read_text().splitlines()]
            self.assertEqual([record["type"] for record in records], ["ask"])

            subprocess.run([str(HELPER), "codex"], input=json.dumps({
                "hook_event_name": "PostToolUse", "session_id": "s1", "turn_id": "r1",
            }), text=True, env=env, check=True)
            records = [json.loads(line) for line in queue.read_text().splitlines()]
            self.assertEqual(records[-1]["event"], "PostToolUse")
            self.assertTrue(records[-1]["resolved"])

    def test_clear_matches_only_the_requested_alert(self):
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(os.environ, XDG_RUNTIME_DIR=runtime)
            ask = lambda ident, session: subprocess.run(
                [str(HELPER), "opencode"],
                input=json.dumps({"kind": "ask", "id": ident, "session": session,
                                  "title": "permission", "detail": "x", "cwd": "/tmp"}),
                text=True, env=env, check=True)
            ask("a", "one")
            ask("b", "two")
            subprocess.run([str(HELPER), "opencode"], input=json.dumps({
                "kind": "clear", "id": "a", "session": "one"}),
                text=True, env=env, check=True)
            records = [json.loads(line) for line in (Path(runtime) / "pet/alerts.jsonl").read_text().splitlines()]
            self.assertEqual([r["type"] for r in records], ["ask", "ask", "clear"])
            self.assertEqual(records[-1]["id"], "a")


if __name__ == "__main__":
    unittest.main()
