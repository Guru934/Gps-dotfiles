import json
import os
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
from privacy_detector import (
    MonitorParser, apply_pipewire_value, classify_pipewire, enumerate_v4l2,
    merge_items, privacy_items,
)


def node(ident, media, state="running", **props):
    return {"id": ident, "type": "PipeWire:Interface:Node", "info": {"state": state, "props": {"media.class": media, **props}}}


class PrivacyDetectorTests(unittest.TestCase):
    def test_pw_cat_input_audio_fixture_is_a_microphone_with_rate(self):
        pw_cat = node(1, "Stream/Input/Audio", **{
            "application.name": "pw-cat", "node.name": "pw-cat",
            "client.id": 7, "node.rate": "1/48000",
        })
        client = {"id": 7, "type": "PipeWire:Interface:Client", "info": {"props": {}}}
        items = classify_pipewire([pw_cat, client])
        self.assertEqual(items[0]["kind"], "mic")
        self.assertEqual(items[0]["app"], "pw-cat")
        self.assertIn("48000 Hz", items[0]["detail"])

    def test_active_and_idle_mic_and_real_metadata(self):
        active = node(1, "Audio/Stream", **{"application.name": "Meet", "application.process.id": 42,
                                               "media.name": "Digital Microphone", "audio.rate": 16000})
        idle = node(2, "Audio/Stream", state="idle", **{"application.name": "Idle"})
        items = classify_pipewire([active, idle])
        self.assertEqual(items[0]["kind"], "mic")
        self.assertEqual(items[0]["app"], "Meet")
        self.assertIn("16000 Hz", items[0]["detail"])
        self.assertEqual(len(items), 1)

    def test_monitor_and_cava_are_excluded(self):
        self.assertEqual(classify_pipewire([
            node(1, "Audio/Stream", **{"application.name": "cava", "node.name": "cava"}),
            node(2, "Audio/Stream", **{"application.name": "Browser", "target.object": 9}),
            node(9, "Audio/Sink", state="suspended", **{"node.name": "alsa_output.monitor"}),
        ]), [])

    def test_playback_idle_and_monitor_capture_are_not_microphones(self):
        self.assertEqual(classify_pipewire([
            node(1, "Stream/Input/Audio", state="idle", **{"application.name": "Idle"}),
            node(2, "Stream/Output/Audio", **{"application.name": "Player"}),
            node(3, "Stream/Input/Audio", **{"application.name": "Monitor", "media.role": "monitor",
                                                "node.name": "alsa_output.monitor"}),
            node(4, "Stream/Input/Audio", **{"application.name": "Sink capture", "target.object": 5}),
            node(5, "Audio/Sink", **{"node.name": "alsa_output.pci"}),
        ]), [])

    def test_camera_and_screen_are_distinguished(self):
        items = classify_pipewire([
            node(1, "Video/Stream", **{"application.name": "Webcam app", "media.role": "Camera", "node.name": "camera-stream"}),
            node(2, "Video/Source", **{"application.name": "Portal", "media.role": "Screen", "node.name": "xdph-screen-capture",
                                       "pipewire.access.portal.is_portal": "true"}),
            node(3, "Stream/Input/Video", **{"application.name": "V4L2 app", "device.api": "v4l2", "node.name": "v4l2-capture"}),
        ])
        self.assertEqual([i["kind"] for i in items], ["cam", "screen", "cam"])

    def test_realistic_full_screen_portal_metadata_is_screen_capture(self):
        items = classify_pipewire([node(1, "Video/Source", **{
            "application.name": "xdg-desktop-portal-hyprland",
            "node.name": "xdph_output",
            "node.description": "Wayland output capture",
            "stream.capture.type": "monitor",
            "portal.app_id": "org.example.Meeting",
        })])
        self.assertEqual([i["kind"] for i in items], ["screen"])

    def test_observed_hyprland_portal_source_without_role_is_screen_capture(self):
        portal = {
            "id": 38, "type": "PipeWire:Interface:Client",
            "info": {"props": {"application.name": "xdg-desktop-portal-hyprland"}},
        }
        source = node(86, "Video/Source", **{
            "client.id": 38,
            "node.name": "xdg-desktop-portal-hyprland",
            "media.name": "xdph-streaming-588018",
        })
        self.assertEqual([i["kind"] for i in classify_pipewire([portal, source])], ["screen"])

    def test_ambiguous_monitor_and_video_sources_are_not_screen(self):
        self.assertEqual(classify_pipewire([
            node(1, "Video/Stream", **{"application.name": "Player", "node.name": "alsa_output.monitor-video"}),
            node(2, "Video/Source", **{"application.name": "Unknown", "node.name": "monitor"}),
            node(3, "Video/Source", **{"application.name": "Unknown", "node.name": "desktop-video"}),
        ]), [])

    def test_unknown_video_is_not_claimed_as_screen(self):
        self.assertEqual(classify_pipewire([node(1, "Video/Stream", **{"application.name": "video"})]), [])

    def test_direct_v4l2_attribution_and_merge(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / "sys/class/video4linux/video9").mkdir(parents=True)
            (root / "sys/class/video4linux/video9/name").write_text("Test camera")
            proc = root / "proc/123/fd"; proc.mkdir(parents=True)
            os.symlink("/dev/video9", proc / "4")
            # Process metadata is optional; the device attribution must remain honest.
            items = enumerate_v4l2(str(root / "sys/class/video4linux"), str(root / "proc"), {"/dev/video9"})
            self.assertEqual(items[0]["kind"], "cam")
            self.assertEqual(items[0]["detail"], "Test camera")
            self.assertEqual(len(merge_items(items + items)), 1)

    def test_v4l2_camera_start_active_and_termination(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sys/class/video4linux/video0").mkdir(parents=True)
            (root / "sys/class/video4linux/video0/name").write_text("Integrated Camera")
            fd_dir = root / "proc/321/fd"
            fd_dir.mkdir(parents=True)
            link = fd_dir / "7"
            os.symlink("/dev/video0", link)
            active = enumerate_v4l2(str(root / "sys/class/video4linux"), str(root / "proc"), {"/dev/video0"})
            self.assertEqual([item["kind"] for item in active], ["cam"])
            link.unlink()
            self.assertEqual(enumerate_v4l2(str(root / "sys/class/video4linux"), str(root / "proc"), {"/dev/video0"}), [])

    def test_v4l2_capture_persists_across_unrelated_pipewire_updates(self):
        graph = {}
        active = {"id": 10, "type": "PipeWire:Interface:Node", "info": {
            "state": "running", "props": {"media.class": "Video/Stream", "media.role": "camera"}
        }}
        unrelated = {"id": 11, "type": "PipeWire:Interface:Node", "info": {
            "state": "running", "props": {"media.class": "Audio/Sink"}
        }}
        v4l2 = [{"kind": "cam", "app": "ffplay", "detail": "Test camera", "pid": 123,
                 "id": "v4l2:/dev/video9:123"}]
        apply_pipewire_value(graph, [active])
        self.assertEqual(privacy_items(graph, v4l2)[0]["app"], "ffplay")
        apply_pipewire_value(graph, [unrelated])
        self.assertEqual(privacy_items(graph, v4l2)[0]["app"], "ffplay")

    def test_partial_pipewire_updates_preserve_running_capture_metadata(self):
        graph = {}
        apply_pipewire_value(graph, [node(10, "Stream/Input/Audio", **{
            "application.name": "Meet", "node.rate": "1/48000"
        })])
        apply_pipewire_value(graph, [{"id": 10, "info": {"state": "running"}}])
        items = privacy_items(graph, [])
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["kind"], "mic")
        self.assertIn("48000 Hz", items[0]["detail"])

    def test_all_sensor_combinations_and_individual_removal(self):
        sensors = {
            "mic": node(1, "Stream/Input/Audio", **{"application.name": "Mic"}),
            "cam": node(2, "Video/Stream", **{"application.name": "Cam", "media.role": "camera"}),
            "screen": node(3, "Video/Source", **{"application.name": "Share", "media.role": "screen"}),
        }
        expected = [
            ({"mic"}, {"mic"}), ({"cam"}, {"cam"}), ({"screen"}, {"screen"}),
            ({"mic", "cam"}, {"mic", "cam"}),
            ({"mic", "screen"}, {"mic", "screen"}),
            ({"cam", "screen"}, {"cam", "screen"}),
            ({"mic", "cam", "screen"}, {"mic", "cam", "screen"}),
        ]
        for active, kinds in expected:
            graph = {sensors[k]["id"]: sensors[k] for k in active}
            self.assertEqual({i["kind"] for i in privacy_items(graph, [])}, kinds)
        graph = {obj["id"]: obj for obj in sensors.values()}
        apply_pipewire_value(graph, [{"id": 2, "info": None}])
        self.assertEqual({i["kind"] for i in privacy_items(graph, [])}, {"mic", "screen"})
        apply_pipewire_value(graph, [{"id": 1, "info": None}])
        self.assertEqual({i["kind"] for i in privacy_items(graph, [])}, {"screen"})
        apply_pipewire_value(graph, [{"id": 3, "info": None}])
        self.assertEqual(privacy_items(graph, []), [])

    def test_pipewire_node_removal_clears_capture(self):
        graph = {}
        active = {"id": 10, "type": "PipeWire:Interface:Node", "info": {
            "state": "running", "props": {"media.class": "Video/Stream", "media.role": "camera"}
        }}
        apply_pipewire_value(graph, [active])
        apply_pipewire_value(graph, [{"id": 10, "info": None}])
        self.assertEqual(privacy_items(graph, []), [])

    def test_pipewire_and_v4l2_reports_merge_without_duplicate_camera(self):
        pw = node(1, "Video/Stream", **{"application.name": "ffplay", "media.role": "camera",
                                        "application.process.id": 123, "node.name": "camera"})
        v4l2 = {"kind": "cam", "app": "ffplay", "detail": "Test camera", "pid": 123,
                "id": "v4l2:/dev/video9:123"}
        self.assertEqual(len(privacy_items({1: pw}, [v4l2])), 1)

    def test_unavailable_detector_has_no_privacy_items(self):
        self.assertEqual(privacy_items({}, []), [])

    def test_removal_and_malformed_monitor_frames(self):
        parser = MonitorParser()
        values = parser.feed("not-json")
        self.assertEqual(values, [])
        values = parser.feed(json.dumps([{ "id": 1, "info": {"props": {}}}]) + json.dumps([{ "id": 1, "info": None}]))
        self.assertEqual(len(values), 2)

    def test_multiple_clients_are_retained(self):
        items = classify_pipewire([
            node(1, "Audio/Stream", **{"application.name": "A", "application.process.id": 1}),
            node(2, "Audio/Stream", **{"application.name": "B", "application.process.id": 2}),
        ])
        self.assertEqual({i["app"] for i in items}, {"A", "B"})


if __name__ == "__main__":
    unittest.main()
