#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host-only carrier safety and synthetic BOOT4 tests; no device access."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('carrier', Path(__file__).resolve().parents[1] / 'tools/boot-image-carrier.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def raw(pe=False):
    data = bytearray(256)
    struct.pack_into('<I', data, 0, 0x14000010)
    if pe:
        data[:4] = bytes.fromhex('4d5a40fa')
        struct.pack_into('<I', data, 4, 0x1400000f)
    struct.pack_into('<QQQ', data, 8, 0, 4096, 10)
    data[56:60] = b'ARM\x64'
    return bytes(data)


def boot(avb=False):
    data = bytearray(8192)
    data[:8] = b'ANDROID!'
    struct.pack_into('<4I', data, 8, 256, 0, 0, 1584)
    struct.pack_into('<I', data, 40, 4)
    data[4096:4352] = raw(True)
    if avb:
        vbmeta = bytearray(256)
        vbmeta[:4] = b'AVB0'
        data += vbmeta
        data += b'nonzero preserved tail'
        footer = bytearray(64)
        footer[:4] = b'AVBf'
        struct.pack_into('>IIQQQ', footer, 4, 1, 0, 8192, 8192, 256)
        data += footer
    return bytes(data)


class CarrierTests(unittest.TestCase):
    def rejects(self, operation, data):
        with self.assertRaises(ValueError):
            operation(data)

    def test_roundtrip_and_layout(self):
        for avb in (False, True):
            original = boot(avb)
            carrier = tool.make_carrier(original, raw())
            self.assertNotEqual(carrier[:8], b'ANDROID!')
            self.assertEqual(tool.unpack(carrier), (original, raw()))
            report = tool.inspect(carrier)
            self.assertFalse(report['bootable'])
            self.assertEqual(report['candidate_layout']['payload_kernel_offset'], 4096)
            self.assertEqual(report['original']['kernel']['branch_target'], 64)
            self.assertEqual(bool(report['original']['avb']), avb)

    def test_carrier_corruption(self):
        carrier = tool.make_carrier(boot(True), raw())
        for offset in (0, 16, 32, 64, 96, 128, len(carrier) - 1):
            changed = bytearray(carrier)
            changed[offset] ^= 1
            self.rejects(tool.unpack, changed)
        for changed in (carrier[:-1], carrier + b'\0', carrier[:127]):
            self.rejects(tool.unpack, changed)
        prefix = struct.pack('<16sQQ32s32s', tool.MAGIC, 2**64 - 1, 1, b'\0'*32, b'\0'*32)
        self.rejects(tool.unpack, prefix + tool.digest(prefix))
        self.rejects(lambda data: tool.make_carrier(data, raw()), carrier)

    def test_boot_rejections(self):
        for offset, value in ((8, 2**32-1), (12, 1), (20, 1580), (24, 1),
                              (40, 3), (1580, 1), (1600, 1), (4352, 1)):
            changed = bytearray(boot())
            struct.pack_into('<I', changed, offset, value)
            self.rejects(tool.boot4, changed)
        for changed in (boot()[:4096], boot() + b'unknown', b'BOOT-CARRIER-V1\n'):
            self.rejects(tool.boot4, changed)

    def test_avb_bounds_and_preservation(self):
        original = boot(True)
        for offset, value in ((-60, 2), (-52, 0), (-44, 4096), (-36, 2**64-1)):
            changed = bytearray(original)
            struct.pack_into('>Q' if offset in (-52, -44, -36) else '>I', changed,
                             len(changed) + offset, value)
            self.rejects(tool.boot4, changed)
        changed = bytearray(original)
        struct.pack_into('>Q', changed, 8192 + 12, 2**64-1)
        self.rejects(tool.boot4, changed)
        changed = bytearray(original)
        changed[8192] = 0
        self.rejects(tool.boot4, changed)

    def test_arm64_rejections(self):
        for offset, value in ((0, 0), (8, 4096), (16, 1), (24, 0), (56, 0)):
            changed = bytearray(raw())
            struct.pack_into('<I', changed, offset, value)
            self.rejects(tool.arm64, changed)
        changed = bytearray(raw())
        struct.pack_into('<I', changed, 0, 0x17ffffff)  # backwards out of file
        self.rejects(tool.arm64, changed)
        self.rejects(tool.arm64, raw()[:63])

    def test_cli(self):
        script = Path(tool.__file__)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original, payload = root / 'original.img', root / 'payload.bin'
            original.write_bytes(boot(True))
            payload.write_bytes(raw())
            output = root / 'test.bootcarrier'
            args = [sys.executable, str(script), 'pack', '--original', str(original),
                    '--payload', str(payload), '--output', str(output)]
            self.assertEqual(subprocess.run(args, capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(args, capture_output=True).returncode, 0)
            bad_extension = args[:-1] + [str(root / 'bad.img')]
            self.assertNotEqual(subprocess.run(bad_extension, capture_output=True).returncode, 0)
            self.assertFalse((root / 'bad.img').exists())
            restored = root / 'restored.img'
            result = subprocess.run([sys.executable, str(script), 'restore', str(output),
                                     '--output', str(restored)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(restored.read_bytes(), original.read_bytes())
            changed = bytearray(output.read_bytes())
            changed[-1] ^= 1
            output.write_bytes(changed)
            result = subprocess.run([sys.executable, str(script), 'restore', str(output),
                                     '--output', str(root / 'corrupt.img')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'corrupt.img').exists())

    def test_filesystem_safety(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'original.img'
            path.write_bytes(boot())
            with self.assertRaises(FileExistsError):
                tool.write_new(path, b'destructive')
            link = Path(directory) / 'alias'
            link.symlink_to(path)
            with self.assertRaises(OSError):
                tool.read_regular(link, tool.LIMIT)
            with self.assertRaises(FileExistsError):
                tool.write_new(link, b'destructive')
            with self.assertRaises(ValueError):
                tool.read_regular(path, 10)
            self.assertEqual(path.read_bytes(), boot())
            output = Path(directory) / 'new.bootcarrier'
            tool.write_new(output, b'new')
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
