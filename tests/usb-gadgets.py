"""Protocol/state and real file-operation tests; no phone or physical USB used."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pkgs/mobile/usb-gadgets"))
import touch
import backend
import storage


def decode(report):
    assert len(report) == 64 and report[0] == 1
    count, ticks = struct.unpack_from("<BH", report, 61)
    return [struct.unpack_from("<BBHH", report, 1 + 6 * i) for i in range(count)], ticks


class TouchTests(unittest.TestCase):
    def test_press_move_lift_and_reuse(self):
        state = touch.TouchState()
        frame = lambda contacts, tick: decode(state.frame({"contacts": contacts}, tick))
        self.assertEqual(frame([{"id": 4, "x": 12, "y": 30}], 65535), ([(1, 4, 12, 30)], 65535))
        records, ticks = frame([{"id": 4, "x": 90, "y": 40}, {"id": 1, "x": 0, "y": 32767}], 65536)
        self.assertEqual(ticks, 0)
        self.assertEqual(records, [(1, 1, 0, 32767), (1, 4, 90, 40)])
        records, _ = frame([{"id": 1, "x": 1, "y": 2}], 1)
        self.assertEqual(records, [(1, 1, 1, 2), (0, 4, 90, 40)])
        self.assertEqual(frame([], 2)[0], [(0, 1, 1, 2)])
        self.assertEqual(frame([], 3)[0], [])

    def test_ten_contacts_fit_one_packet(self):
        state = touch.TouchState()
        contacts = [{"id": i, "x": i * 100, "y": 32767} for i in range(10)]
        self.assertEqual(len(decode(state.frame({"contacts": contacts}))[0]), 10)
        self.assertEqual(len(decode(state.frame({"contacts": []}))[0]), 10)

    def test_invalid_frames_do_not_change_state(self):
        state = touch.TouchState()
        state.frame({"contacts": [{"id": 1, "x": 2, "y": 3}]})
        invalid = [{}, {"contacts": "bad"}, {"contacts": [{"id": 1, "x": -1, "y": 3}]},
                   {"contacts": [{"id": True, "x": 2, "y": 3}]},
                   {"contacts": [{"id": 10, "x": 2, "y": 3}]},
                   {"contacts": [{"id": 1, "x": 2, "y": 3}] * 2}]
        for frame in invalid:
            with self.assertRaises(ValueError):
                state.frame(frame)
            self.assertEqual(state.active, {1: (2, 3)})

    def test_feature_report_abi(self):
        data = touch.feature_report()
        self.assertEqual(len(data), 72)
        self.assertEqual(struct.unpack_from("=BBH", data), (2, 0, 2))
        self.assertEqual(data[4:6], bytes([2, 10]))


class StorageTests(unittest.TestCase):
    def test_create_preserves_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "disk.img"
            storage.create(image, 64)
            self.assertEqual(image.stat().st_size, 64 * 1024 * 1024)
            with image.open("rb") as file:
                self.assertEqual(file.read(512)[510:512], b"\x55\xaa")
            with image.open("r+b") as file:
                file.seek(4 * 1024 * 1024)
                file.write(b"keep existing data")
            with self.assertRaises(FileExistsError):
                storage.create(image, 64)
            with image.open("rb") as file:
                file.seek(4 * 1024 * 1024)
                self.assertEqual(file.read(18), b"keep existing data")
            self.assertEqual(list(Path(directory).iterdir()), [image])

    def test_image_lock_and_types(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "disk.img"
            image.write_bytes(bytes(512))
            # The loop check is independently exercised with real losetup in VM.
            with patch("backend.subprocess.run") as run:
                run.return_value.stdout = ""
                fd = backend.open_image(str(image), False)
                try:
                    with self.assertRaises(BlockingIOError):
                        backend.open_image(str(image), False)
                finally:
                    os.close(fd)
                run.return_value.stdout = "/dev/loop0: image"
                with self.assertRaisesRegex(ValueError, "loop"):
                    backend.open_image(str(image), False)
            link = Path(directory) / "link"
            link.symlink_to(image)
            with self.assertRaises(ValueError):
                backend.open_image(str(link), True)
            with self.assertRaises(ValueError):
                backend.open_image("/dev/null", True)


if __name__ == "__main__":
    unittest.main()
