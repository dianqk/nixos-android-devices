import importlib.util
import json
import socket
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("recovery_copy.py")
SPEC = importlib.util.spec_from_file_location("mobile_recovery_nix_copy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProgressTest(unittest.TestCase):
    def test_real_nix_copy_event_shape(self):
        sender, receiver = socket.socketpair()
        self.addCleanup(sender.close)
        self.addCleanup(receiver.close)
        progress = MODULE.Progress(sender)

        def event(**data):
            progress.accept("@nix " + json.dumps(data))

        event(action="start", id=10, level=3, parent=0, text="copying 1 paths", type=103)
        event(action="start", id=11, fields=["/nix/store/example", "daemon", "local://"], type=100)
        event(action="result", id=11, fields=[440, 440, 0, 0], type=105)
        event(action="result", id=10, fields=[1, 1, 0, 0], type=105)
        progress.report(force=True)
        self.assertEqual((progress.done, progress.total), (1, 1))
        self.assertEqual((progress.path_bytes, progress.path_total), (440, 440))
        receiver.settimeout(1)
        payload = receiver.recv(8192).decode()
        self.assertIn("stage\tCopying Nix store\n", payload)
        self.assertIn("progress\t1\t1\t440\t440\n", payload)

    def test_path_stop_completes_progress_when_parent_stays_at_zero(self):
        sender, receiver = socket.socketpair()
        self.addCleanup(sender.close)
        self.addCleanup(receiver.close)
        progress = MODULE.Progress(sender)

        def event(**data):
            progress.accept("@nix " + json.dumps(data))

        event(action="start", id=10, level=3, text="copying 1 paths", type=103)
        event(action="result", id=10, fields=[0, 1, 1, 0], type=105)
        event(action="start", id=11, fields=["/nix/store/example", "daemon", "unix://store"], type=100)
        event(action="result", id=11, fields=[440, 440, 0, 0], type=105)
        event(action="stop", id=11)
        event(action="stop", id=10)
        progress.finish()
        self.assertEqual((progress.done, progress.total), (1, 1))
        receiver.settimeout(1)
        self.assertIn("progress\t1\t1\t0\t0\n", receiver.recv(8192).decode())

    def test_interleaved_path_stops_are_each_counted_once(self):
        sender, receiver = socket.socketpair()
        self.addCleanup(sender.close)
        self.addCleanup(receiver.close)
        progress = MODULE.Progress(sender)

        def event(**data):
            progress.accept("@nix " + json.dumps(data))

        event(action="start", id=10, text="copying 2 paths", type=103)
        event(action="start", id=11, fields=["/nix/store/first"], type=100)
        event(action="start", id=12, fields=["/nix/store/second"], type=100)
        event(action="stop", id=11)
        event(action="stop", id=11)
        self.assertEqual((progress.done, progress.total), (1, 2))
        event(action="stop", id=12)
        self.assertEqual((progress.done, progress.total), (2, 2))


if __name__ == "__main__":
    unittest.main()
