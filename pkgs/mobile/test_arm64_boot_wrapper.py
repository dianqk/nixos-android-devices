import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location(
    "wrapper", Path(__file__).with_name("arm64-boot-wrapper.py"))
wrapper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wrapper)


class BootWrapperTests(unittest.TestCase):
    def image(self):
        image = bytearray(8192)
        struct.pack_into("<IIQQQ", image, 0, 0xD503201F, 0x14000010,
                         0, 65536, 0xA)
        image[56:60] = b"ARM\x64"
        image[4096:] = bytes(range(256)) * 16
        return bytes(image)

    def test_entry_branch_alignment_and_memory_reservation(self):
        image = self.image()
        for offset in (4096, 524288, 2093056):
            with self.subTest(offset=offset):
                result = wrapper.wrap_image(image, offset)
                instruction = struct.unpack_from("<I", result)[0]
                self.assertEqual(instruction & 0xFC000000, 0x14000000)
                target = (instruction & 0x03FFFFFF) * 4
                self.assertEqual(offset + target, 2 * 1024 * 1024)
                self.assertEqual(result[target:], image)
                self.assertEqual(struct.unpack_from("<Q", result, 16)[0],
                                 target + 65536)
                self.assertEqual(struct.unpack_from("<Q", result, 24)[0], 0xA)
                self.assertEqual(result[60:64], bytes(4))  # no EFI entry

    def test_reject_invalid_offsets_and_images(self):
        for offset in (-4096, 0, 1, 4097, 2097152):
            with self.assertRaises(ValueError):
                wrapper.wrap_image(self.image(), offset)
        for field, value in ((8, 524288), (16, 4096), (24, 1)):
            image = bytearray(self.image())
            struct.pack_into("<Q", image, field, value)
            with self.assertRaises(ValueError):
                wrapper.wrap_image(image, 524288)
        for image in (b"", bytes(8192)):
            with self.assertRaises(ValueError):
                wrapper.wrap_image(image, 524288)


if __name__ == "__main__":
    unittest.main()
