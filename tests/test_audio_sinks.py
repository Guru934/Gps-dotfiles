"""Unit tests for audio-sinks.py helper."""

import json
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import importlib.machinery
import importlib.util

script_path = Path(__file__).resolve().parent.parent / "scripts" / "audio-sinks.py"
loader = importlib.machinery.SourceFileLoader("audio_sinks", str(script_path))
spec = importlib.util.spec_from_loader("audio_sinks", loader)
audio_sinks = importlib.util.module_from_spec(spec)
loader.exec_module(audio_sinks)


class TestAudioSinks(unittest.TestCase):
    SAMPLE_WPCTL_STATUS = """
PipeWire 'pipewire-0' [1.6.10, rice@cachyos-x8664, cookie:2403839383]
 └─ Clients:
        32. xdg-desktop-portal                  [1.6.10, rice@cachyos-x8664, pid:2902]

Audio
 ├─ Devices:
 │      45. 700 Series Chipset Family HD Audio  [alsa]
 │  
 ├─ Sinks:
 │      54. 700 Series Chipset Family HD Audio HDMI / DisplayPort 3 Output (Stereo) [vol: 1.00]
 │      55. 700 Series Chipset Family HD Audio HDMI / DisplayPort 2 Output (Stereo) [vol: 1.00]
 │  *   57. 700 Series Chipset Family HD Audio Speaker [vol: 0.26]
 │  
 ├─ Sources:
 │  *   58. 700 Series Chipset Family HD Audio Digital Microphone [vol: 1.00]
 │  
 └─ Streams:
"""

    def test_parse_wpctl_status(self):
        engine, sinks, default_id = audio_sinks.parse_wpctl_status(self.SAMPLE_WPCTL_STATUS)
        self.assertEqual(engine, "PipeWire 1.6.10")
        self.assertEqual(len(sinks), 3)
        self.assertEqual(default_id, 57)

        sink57 = next(s for s in sinks if s["id"] == 57)
        self.assertTrue(sink57["default"])
        self.assertEqual(sink57["name"], "700 Series Chipset Family HD Audio Speaker")

        sink54 = next(s for s in sinks if s["id"] == 54)
        self.assertFalse(sink54["default"])

    @patch("subprocess.run")
    def test_switch_sink_sets_default_and_moves_streams(self, mock_run):
        def run_side_effect(cmd, **kwargs):
            mock = MagicMock()
            mock.returncode = 0
            if cmd[:2] == ["wpctl", "set-default"]:
                return mock
            if cmd[:4] == ["pactl", "list", "short", "sink-inputs"]:
                mock.stdout = "101 57 12 pipewire\n102 57 15 pipewire\n"
                return mock
            if cmd[:2] == ["pactl", "move-sink-input"]:
                return mock
            return mock

        mock_run.side_effect = run_side_effect

        res = audio_sinks.switch_sink(54)
        self.assertTrue(res["ok"])
        self.assertEqual(res["target_id"], 54)
        self.assertEqual(res["streams_moved"], 2)


if __name__ == "__main__":
    unittest.main()
