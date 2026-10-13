#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("registry", ROOT / "pkgs/mobile/ssc-registry/generate.py")
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class RegistryTests(unittest.TestCase):
    def test_file_group_layout(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("MOBILE_TEST_TMP")) as temp:
            source = Path(temp) / "config"
            source.mkdir()
            value = {"imu": {"owner": "imu", ".bias": {
                "owner": "imu", "x": {"type": "flt", "ver": "1", "data": "0.125"}}}}
            for name in ("a.json", "b.json"):
                (source / name).write_text(json.dumps(value))
            (source / "excluded.json").write_text(json.dumps({"config": {"soc_id": ["other"]}, **value}))
            out = Path(temp) / "out"
            registry.generate(source, out, "MTP", "557", "4", "file-group")
            self.assertEqual((out / "etc/sensors/config/json.lst").read_text(), "a.json\nb.json\n")
            state = out / "seed"
            files = state / "registry/registry"
            listed = (state / "registry/parsed_file_list.csv").read_text().splitlines()
            self.assertEqual(set(listed), {"a.json.imu", "a.json.imu.bias", "b.json.imu", "b.json.imu.bias"})
            for filename in listed:
                group = filename.split(".json.", 1)[1]
                self.assertEqual(list(json.loads((files / filename).read_text())), [group])
            calibration = files / "a.json.imu.bias"
            calibrated = {"imu.bias": {"owner": "imu", "x": {"data": "-0.75", "ver": "2", "type": "flt"}}}
            calibration.write_text(json.dumps(calibrated))
            (files / "DIR").write_text("DIR")
            registry.normalize_state(state)
            self.assertEqual(json.loads(calibration.read_text()), calibrated)
            self.assertEqual((files / "DIR").read_text(), "DIR")
            self.assertEqual((state / "registry/parsed_file_list.csv").read_text().splitlines(), listed)

    def test_board_defaults(self):
        for board, platform, soc, version, sensor, axes in (
            ("asphalt", "MTP", "531", "7", "bmi3x0", [-1, 1, -1]),
            ("polaris", "POLARIS", "321", "2", "icm206xx", [-1, -1, 1]),
        ):
            with self.subTest(board=board), tempfile.TemporaryDirectory(dir=os.environ.get("MOBILE_TEST_TMP")) as temp:
                out = Path(temp) / "out"
                registry.generate(ROOT / f"pkgs/{board}/sensors/config", out, platform, soc, version)
                self.assertEqual((out / "seed/registry/sns_reg_version").read_bytes(), f"version={version}\0".encode())
                files = out / "seed/registry/registry"
                for file in files.iterdir():
                    data = json.loads(file.read_text())
                    self.assertEqual(list(data), [file.name])
                    for key, value in data[file.name].items():
                        if isinstance(value, dict) and value.get("type") == "grp":
                            self.assertTrue((files / (file.name + "." + key)).is_file())
                orient = json.loads((files / f"{sensor}_0_platform.orient").read_text())[f"{sensor}_0_platform.orient"]
                self.assertEqual([orient[axis]["data"] for axis in ("x", "y", "z")],
                                 [("+" if sign > 0 else "-") + axis for axis, sign in zip(("x", "y", "z"), axes)])
                self.assertNotIn("property=", (out / "etc/sensors/sns_reg_config").read_text())
                again = Path(temp) / "again"
                registry.generate(ROOT / f"pkgs/{board}/sensors/config", again, platform, soc, version)
                self.assertEqual({str(p.relative_to(out)): p.read_bytes() for p in out.rglob("*") if p.is_file()},
                                 {str(p.relative_to(again)): p.read_bytes() for p in again.rglob("*") if p.is_file()})

    def test_firmware_field_order(self):
        # Valid JSON can still crash the firmware's streaming registry parser:
        # data must not arrive before its type, or entries before their owner.
        value = {"group": {"sample": {"data": "1", "ver": "3", "type": "int"},
                           "owner": "driver"}}
        text = registry.dumps(value)
        self.assertEqual(json.loads(text), value)
        self.assertEqual(text, '{"group":{"owner":"driver","sample":{"type":"int","ver":"3","data":"1"}}}\n')
        self.assertEqual(registry.dumps(json.loads(text)), text)

    def test_existing_calibration_migration(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("MOBILE_TEST_TMP")) as temp:
            state = Path(temp)
            directory = state / "registry/registry"
            directory.mkdir(parents=True)
            file = directory / "calibration"
            value = {"calibration": {"bias": {"data": "-0.123456", "ver": "42", "type": "flt"}, "owner": "imu"}}
            file.write_text(json.dumps(value, sort_keys=True))
            file.chmod(0o640)
            stamp = directory.parent / "sns_reg_version"
            stamp.write_bytes(b"version=7\0")
            registry.normalize_state(state)
            self.assertEqual(json.loads(file.read_text()), value)
            self.assertEqual(file.stat().st_mode & 0o777, 0o640)
            self.assertEqual(stamp.read_bytes(), b"version=7\0")
            before = file.stat()
            registry.normalize_state(state)
            self.assertEqual(file.stat().st_ino, before.st_ino)
            self.assertEqual(file.stat().st_mtime_ns, before.st_mtime_ns)
            self.assertEqual(list(directory.iterdir()), [file])

    def test_merge_conflicts_and_paths(self):
        group = {"owner": "test", ".config": {"a": {"type": "int", "ver": "0", "data": "1"}}}
        result = {}
        registry.merge(result, {"test": group})
        registry.merge(result, {"test": group})
        registry.merge(result, {"test": {".config": {"b": {"type": "int", "data": "2"}}}})
        self.assertIn("b", result["test"][".config"])
        with self.assertRaisesRegex(ValueError, "conflicting"):
            registry.merge(result, {"test": {".config": {"a": {"data": "3"}}}})
        with self.assertRaisesRegex(ValueError, "unsafe"):
            registry.split("../escape", group, {})


class RotationTests(unittest.TestCase):
    def run_bridge(self, compositor, offset=0, output="DSI-1", fail=False, touch=None):
        with tempfile.TemporaryDirectory(dir=os.environ.get("MOBILE_TEST_TMP")) as temp:
            path = Path(temp)
            commands = path / "commands"
            monitor = path / "monitor-sensor"
            monitor.write_text("#!/bin/sh\nprintf '%s\\n' '=== Has accelerometer (orientation: right-up, tilt: unknown)' '    Accelerometer orientation changed: undefined' '    Accelerometer orientation changed: right-up' '    Accelerometer orientation changed: normal' '    Accelerometer orientation changed: left-up' '    Accelerometer orientation changed: left-up' '    Accelerometer orientation changed: bottom-up'\n")
            monitor.chmod(0o755)
            for name in ("swaymsg", "niri", "hyprctl"):
                mock = path / name
                mock.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
if sys.argv[1:3] == ['monitors', '-j']:
 print(json.dumps([dict(name='DSI-1',width=1080,height=2160,refreshRate=60.0,x=0,y=0,scale=1.5)]))
elif sys.argv[1:3] == ['devices', '-j']:
 print(json.dumps(dict(touch=[dict(name='internal-touch'),dict(name='external-usb-touch')])))
else:
 p=Path(os.environ['COMMANDS']); first=not p.exists()
 with p.open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
 if os.environ.get('FAIL_FIRST') == '1' and first: sys.exit(1)
''')
                mock.chmod(0o755)
            result = subprocess.run([sys.executable, str(ROOT / "pkgs/mobile/sensor-rotate/rotate.py"),
                                     "--compositor", compositor, "--output", output, "--offset", str(offset)]
                                    + (["--touch-device", touch] if touch else []),
                                    env={**os.environ, "PATH": f"{path}:{os.environ['PATH']}",
                                         "COMMANDS": str(commands), "FAIL_FIRST": str(int(fail))},
                                    capture_output=True, text=True, timeout=10)
            return result, [json.loads(line) for line in commands.read_text().splitlines()] if commands.exists() else []

    def test_all_compositors_initial_events_and_deduplication(self):
        result, calls = self.run_bridge("sway")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[-1] for c in calls], [f"output DSI-1 transform {angle}" for angle in (90, 0, 270, 180)])
        result, calls = self.run_bridge("niri")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[-1] for c in calls], ["270", "normal", "90", "180"])
        result, calls = self.run_bridge("hyprland")
        self.assertEqual(result.returncode, 0, result.stderr)
        for call, angle in zip(calls, (3, 0, 1, 2), strict=True):
            self.assertEqual(call[0], "eval")
            self.assertIn(f"transform={angle}", call[1])
            self.assertIn('mode="1080x2160@60.0"', call[1])
            self.assertIn("scale=1.5", call[1])

    def test_offset_and_failed_command_retry(self):
        result, calls = self.run_bridge("sway", offset=90, fail=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0], calls[1])
        self.assertEqual(calls[-1][-1], "output DSI-1 transform 90")

    def test_reject_ipc_injection(self):
        result, calls = self.run_bridge("sway", output="DSI-1; exit")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_touch_transform_and_ambiguous_devices(self):
        result, calls = self.run_bridge("hyprland", touch="internal-*")
        self.assertEqual(result.returncode, 0, result.stderr)
        touch_calls = [c for c in calls if c[1].startswith("hl.device")]
        self.assertEqual(len(touch_calls), 4)
        for call, angle in zip(touch_calls, (3, 0, 1, 2), strict=True):
            self.assertIn('name="internal-touch"', call[1])
            self.assertIn('output="DSI-1"', call[1])
            self.assertIn(f"transform={angle}", call[1])
        result, calls = self.run_bridge("hyprland", touch="*-touch")
        self.assertEqual(calls, [])
        self.assertIn("found 2", result.stderr)


if __name__ == "__main__":
    unittest.main()
