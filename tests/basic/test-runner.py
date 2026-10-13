#!/usr/bin/env python3
"""Offline checks of failure reporting, media validation and selective execution."""
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("basic", ROOT / "tests/basic/run.py")
basic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(basic)


class RunnerTests(unittest.TestCase):
    def test_ssh_preserves_remote_argument_boundaries(self):
        import shlex
        suite = basic.Suite("root@tablet", pathlib.Path("unused"),
                            ssh_config=pathlib.Path("config with spaces"))
        value = "spaces; $(not-a-command) 'quotes'"
        with patch.object(suite, "command", return_value="ok") as command:
            self.assertEqual(suite.shell("printf", "%s", value), "ok")
        args, timeout = command.call_args.args
        self.assertEqual(args[-2], "root@tablet")
        self.assertEqual(shlex.split(args[-1]), ["timeout", "-k", "3", "40", "printf", "%s", value])
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("config with spaces", args)
        self.assertEqual(timeout, 45)

    def test_ssh_upload_streams_exact_binary_content(self):
        import shlex
        base = pathlib.Path(os.environ.get("MOBILE_TEST_TMP", ROOT / "tmp")) / "basic-runner-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            source = pathlib.Path(directory) / "a 'video'.mp4"
            source.write_bytes(bytes(range(256)))
            suite = basic.Suite("tablet", pathlib.Path(directory))
            suite.remote = "/var/tmp/test space"
            def capture(args, timeout, stdin):
                self.assertEqual(stdin.read(), bytes(range(256)))
                self.assertEqual(shlex.split(args[-1]), ["cat", ">", suite.remote + "/" + source.name])
            with patch.object(suite, "command", side_effect=capture):
                suite.upload(source)

    def test_niri_session_environment_and_ambiguous_sockets(self):
        suite = basic.Suite("tablet", pathlib.Path("unused"))
        socket = "/run/user/1000/niri.wayland-1.123.sock"
        with patch.object(suite, "shell", side_effect=[socket, "1000", "demo",
                          "/run/user/1000/wayland-1", "ok"]) as shell:
            self.assertEqual(suite.session("niri", "msg", "--json", "outputs"), "ok")
            self.assertIn("NIRI_SOCKET=" + socket, shell.call_args.args)
            self.assertIn("WAYLAND_DISPLAY=wayland-1", shell.call_args.args)
            self.assertEqual(shell.call_args.args[:5], ("runuser", "-u", "demo", "--", "env"))
        for sockets in ("", socket + "\n/run/user/1001/niri.wayland-2.456.sock"):
            with patch.object(suite, "shell", return_value=sockets), self.assertRaises(RuntimeError):
                suite.session("niri", "msg", "--json", "outputs")

    def test_niri_display_active_mode_and_disabled_output(self):
        base = pathlib.Path(os.environ.get("MOBILE_TEST_TMP", ROOT / "tmp")) / "basic-runner-tests"
        base.mkdir(parents=True, exist_ok=True)
        outputs = {"DSI-1": {"logical": {"width": 800, "height": 1280},
                   "current_mode": 0, "modes": [{"width": 1600, "height": 2560}]},
                   "DP-1": {"logical": None, "current_mode": None, "modes": []}}
        with tempfile.TemporaryDirectory(dir=base) as directory:
            suite = basic.Suite("tablet", pathlib.Path(directory))
            with patch.object(suite, "session", return_value=json.dumps(outputs)), patch.object(suite, "shell"):
                suite.display()
            self.assertEqual(json.loads((suite.output / "outputs.json").read_text()), outputs)
            outputs["DSI-1"]["current_mode"] = None
            with patch.object(suite, "session", return_value=json.dumps(outputs)), self.assertRaises(RuntimeError):
                suite.display()

    def test_niri_gpu_restores_original_workspace_even_after_failure(self):
        suite = basic.Suite("tablet", pathlib.Path("unused"))
        workspaces = [{"id": 3, "idx": 2, "output": "DSI-1", "is_focused": True},
                      {"id": 4, "idx": 3, "output": "DSI-1", "is_focused": False},
                      {"id": 5, "idx": 4, "output": "DP-1", "is_focused": False}]
        current = [{**workspaces[0], "idx": 1}, workspaces[1]]
        for benchmark in ("GL_RENDERER: FD630\nglmark2 Score: 100", RuntimeError("benchmark failed")):
            replies = [json.dumps(workspaces), json.dumps([{"workspace_id": 3}]), "",
                       benchmark, json.dumps(current), "", ""]
            with patch.object(suite, "session", side_effect=replies) as session:
                if isinstance(benchmark, Exception):
                    with self.assertRaisesRegex(RuntimeError, "benchmark failed"):
                        suite.opengl()
                else:
                    suite.opengl()
                calls = [call.args for call in session.call_args_list]
                self.assertIn(("niri", "msg", "action", "focus-workspace", "3"), calls)
                self.assertEqual(calls[-2], ("niri", "msg", "action", "focus-monitor", "DSI-1"))
                self.assertEqual(calls[-1], ("niri", "msg", "action", "focus-workspace", "1"))

    def test_silent_eight_bit_media(self):
        info = {"streams": [{"codec_name": "h264", "pix_fmt": "yuv420p", "nb_frames": "10800"}], "format": {"duration": "180"}}
        self.assertEqual(basic.validate_media(info, "h264"), 10800)
        info["streams"][0]["pix_fmt"] = "yuv420p10le"
        with self.assertRaises(RuntimeError):
            basic.validate_media(info, "h264")
        info["streams"].append({"codec_type": "audio"})
        with self.assertRaises(RuntimeError):
            basic.validate_media(info, "h264")

    def test_software_gpu_rejected(self):
        for api, text in (("opengl", "GL_RENDERER: llvmpipe\nglmark2 Score: 100"),
                          ("vulkan", "Device Name: lavapipe\nvkmark Score: 100")):
            with self.subTest(api=api), self.assertRaises(RuntimeError):
                basic.validate_gpu(text, api)

    def test_gpu_must_complete(self):
        basic.validate_gpu("GL_RENDERER: FD630\nglmark2 Score: 100", "opengl")
        basic.validate_gpu("Device Name: Adreno 630\nvkmark Score: 100", "vulkan")
        with self.assertRaises(RuntimeError):
            basic.validate_gpu("GL_RENDERER: FD630", "opengl")

    def test_truncated_decode_rejected(self):
        info = {"streams": [{"codec_name": "h264", "pix_fmt": "yuv420p", "nb_frames": "10800"}], "format": {"duration": "180"}}
        base = pathlib.Path(os.environ.get("MOBILE_TEST_TMP", ROOT / "tmp")) / "basic-runner-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            suite = basic.Suite("test-host", pathlib.Path(directory))
            suite.remote = "/var/tmp/fixture"
            with patch.object(suite, "shell", side_effect=[json.dumps(info), "frame=10\nprogress=end\n"]) as call:
                with self.assertRaises(RuntimeError):
                    suite.decode("h264")
                self.assertIn("h264_v4l2m2m", call.call_args.args)

    def test_camera_probe_rejects_missing_and_unusable_pipelines(self):
        suite = basic.Suite("test-host", pathlib.Path("unused"), min_cameras=2)
        listing = "Available cameras:\n1: Internal back camera (/rear)\n2: Internal front camera (/front)\n"
        stream = "0: 1296x972-RGB888\n * Pixelformat: RGB888\n"
        with patch.object(suite, "shell", side_effect=[listing, stream, stream]) as call:
            suite.camera()
            self.assertEqual(call.call_count, 3)
        for replies in (["Available cameras:\n"],
                        ["Available cameras:\n1: Internal back camera (/rear)\n"],
                        [listing, stream, "No formats"]):
            with patch.object(suite, "shell", side_effect=replies), self.assertRaises(RuntimeError):
                suite.camera()

    def test_skip_and_continue_after_failure(self):
        base = pathlib.Path(os.environ.get("MOBILE_TEST_TMP", ROOT / "tmp")) / "basic-runner-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            output = pathlib.Path(directory) / "results"
            argv = ["run.py", "--ssh", "test-host", "--output", str(output), "--skip", "h264,hevc,vulkan,camera"]
            with patch.object(sys, "argv", argv), patch.object(basic.Suite, "shell", return_value="0\n"), \
                 patch.object(basic.Suite, "display"), \
                 patch.object(basic.Suite, "wifi", side_effect=basic.Inconclusive("Empty scan")), \
                 patch.object(basic.Suite, "bluetooth"), \
                 patch.object(basic.Suite, "audio", side_effect=RuntimeError("No PCM")), \
                 patch.object(basic.Suite, "opengl") as gl, patch.object(basic.Suite, "vulkan") as vk:
                self.assertEqual(basic.main(), 1)
                gl.assert_called_once()
                vk.assert_not_called()
            results = json.loads((output / "results.json").read_text())
            self.assertEqual(results["wifi"]["status"], "INCONCLUSIVE")
            self.assertEqual(results["audio"]["status"], "FAIL")
            self.assertEqual(results["vulkan"]["status"], "SKIP")
            self.assertEqual(results["camera"]["status"], "SKIP")


if __name__ == "__main__":
    unittest.main()
