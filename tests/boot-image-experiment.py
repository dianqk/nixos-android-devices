#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host-only embedding tests; no device access."""
import importlib.util
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('experiment', ROOT / 'tools/boot-image-experiment.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'tests/boot-image-carrier.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


def inputs():
    # Tiny but structurally real ELF64/RELA/separate-DTB pair. Every symbol and
    # stack size is resolved by the production parser, not a supplied manifest.
    raw = bytearray(fixtures.raw())
    dtb = b'\xd0\x0d\xfe\xed' + struct.pack('>I', 40) + bytes(32)
    names = ['_start', '__bss_start', '__bss_end', '_end', 'save_boot_params']
    values = [0, 256, 512, 256, 64]
    strings = b'\0' + b''.join(name.encode() + b'\0' for name in names)
    sym = bytes(24)
    for name, value in zip(names, values):
        sym += struct.pack('<IBBHQQ', strings.index(name.encode()), 0x10, 0, 1, value, 0)
    sections = [('', b'', 0, 0), ('.text', bytes(raw), 0, 1),
                ('.rela.dyn', b'', 256, 4), ('.symtab', sym, 0, 2),
                ('.strtab', strings, 0, 3)]
    shnames = b'\0' + b''.join(name.encode() + b'\0' for name, *_ in sections[1:]) + b'.shstrtab\0'
    sections.append(('.shstrtab', shnames, 0, 3))
    elf = bytearray(64)
    elf[:7] = b'\x7fELF\x02\x01\x01'
    struct.pack_into('<H', elf, 18, 183)
    headers = []
    for name, data, addr, kind in sections:
        offset = len(elf)
        elf += data
        headers.append(struct.pack('<IIQQQQIIQQ', shnames.index(name.encode()) if name else 0,
                                   kind, 0, addr, offset, len(data),
                                   4 if name == '.symtab' else 0, 0, 1,
                                   24 if name == '.symtab' else 0))
    struct.pack_into('<Q', elf, 40, len(elf))
    struct.pack_into('<HHH', elf, 58, 64, len(headers), 5)
    elf += b''.join(headers)
    config = b'CONFIG_ARM64=y\nCONFIG_POSITION_INDEPENDENT=y\nCONFIG_OF_SEPARATE=y\nCONFIG_SAVE_PREV_BL_FDT_ADDR=y\nCONFIG_TEXT_BASE=0\nCONFIG_SYS_INIT_SP_BSS_OFFSET=3840\n'
    original = fixtures.boot() + bytes(256 * 1024 - 8192)
    return original, bytes(raw) + dtb, bytes(elf), config


class ExperimentTests(unittest.TestCase):
    def test_owned_plan_is_prelink_and_bounded(self):
        original, raw, elf, config = inputs()
        original = bytearray(original)
        struct.pack_into("<I", original, 8, 8192)
        struct.pack_into("<Q", original, 4112, 8192)
        original = bytes(original)
        info = tool.c.boot4(original); abi = tool.elf_layout(elf, raw, config)
        old = tool.selector_binding(original, raw, elf, config, info, abi)
        new = tool.selector_binding(original, raw, elf, config, info, abi, True)
        layout = tool.owned_layout.plan(original, old['symbols']['eg_image_end'])
        self.assertEqual(new['symbols']['eg_image_end']+4096, layout['body'])
        self.assertEqual(new['symbols']['eg_workspace_end'], new['symbols']['eg_image_end'])
        self.assertEqual(old['request_generation'], new['request_generation'])
        self.assertGreater(new['symbols']['eg_image_end'], old['symbols']['eg_image_end'])
        with self.assertRaises(ValueError): tool.owned_layout.plan(original, len(original))
        with self.assertRaises(ValueError): tool.owned_layout.plan(original, 1)
        with self.assertRaises(ValueError): tool.build(original, raw, elf, config, owned=True)

    def test_layout_and_instructions(self):
        original, raw, elf, config = inputs()
        image, report = tool.build(original, raw, elf, config)
        self.assertEqual(report['selector_offset'], 4096)
        self.assertEqual(report['payload_offset'], 8192)
        self.assertEqual(report['stack_top_offset'], 12288)
        self.assertEqual(struct.unpack_from('<I', image, 8)[0], 12288)
        self.assertEqual(struct.unpack_from('<Q', image, 4096 + 16)[0], 12288)
        self.assertEqual(image[4096:4100], original[4096:4100])
        self.assertEqual(image[4096 + 8192:4096 + 8192 + len(raw)], raw)
        # Default selector is B to next B, which targets the original Android.
        code = image[8192:8216]
        self.assertEqual(struct.unpack_from('<I', code)[0], 0x14000001)
        self.assertEqual(code[4:8], tool.branch(4100, 64))
        words = struct.unpack('<6I', code)
        self.assertEqual(words[4], 0x9100013f)  # MOV SP,x9, diagnostic only
        imm = ((words[2] >> 5) & 0x7ffff) * 4 | ((words[2] >> 29) & 3)
        if imm & (1 << 20):
            imm -= 1 << 21
        for base in (0, 0x80000000, 0x100000000):
            stack = ((base + 4104) & ~4095) + imm * 4096 + ((words[3] >> 10) & 4095)
            self.assertEqual(stack, base + 12288)
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'entry.bin'
            path.write_bytes(code)
            if platform.machine() == 'aarch64' and shutil.which('objdump'):
                listing = subprocess.check_output(['objdump', '-D', '-b', 'binary', '-m', 'aarch64', str(path)], text=True)
                self.assertIn('mov\tsp, x9', listing)

    def test_reject_mismatch_and_overflow(self):
        original, raw, elf, config = inputs()
        for changed in (raw[:-1], raw[:80] + b'X' + raw[81:]):
            with self.assertRaises(ValueError):
                tool.build(original, changed, elf, config)
        with self.assertRaises(ValueError):
            tool.build(original, raw, elf, config.replace(b'3840', b'4096'))
        with self.assertRaises(ValueError):
            tool.build(original, raw, elf, config + b'CONFIG_BLOBLIST=y\n')
        with self.assertRaises(ValueError):
            tool.branch(4, 1 << 28)
        with self.assertRaises(ValueError):
            tool.build(original[:8192], raw, elf, config)

    @unittest.skipUnless(shutil.which('avbtool'), 'requires host avbtool')
    def test_cli_roundtrip_corruption_and_aliases(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            original, raw, elf, config = inputs()
            args = [sys.executable, str(ROOT / 'tools/boot-image-experiment.py'), 'pack']
            for name, data in zip(('original', 'payload', 'elf', 'config'), (original, raw, elf, config)):
                (root / name).write_bytes(data)
                args += ['--' + name, str(root / name)]
            output = root / 'out'
            args += ['--output-dir', str(output), '--allow-unsigned-avb-none']
            def run(command, ok=True):
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, ok, result.stderr)
            run(args)
            run(args, False)  # never overwrite an existing directory
            restored = root / 'restored'
            restore = [sys.executable, str(ROOT / 'tools/boot-image-experiment.py'), 'restore', str(output), '--output', str(restored)]
            run(restore)
            self.assertEqual(restored.read_bytes(), original)
            run(restore, False)
            restored.unlink()
            restored.symlink_to(root / 'original')
            run(restore, False)
            image = output / 'experiment.img'
            data = bytearray(image.read_bytes())
            data[10000] ^= 1
            image.write_bytes(data)
            run(restore, False)
            self.assertEqual((root / 'original').read_bytes(), original)
            # Also reject corruption of the saved original, independently.
            image.write_bytes(bytes(byte ^ 1 if i == 10000 else byte for i, byte in enumerate(data)))
            (output / 'original.img').write_bytes(original[:-1] + b'X')
            run(restore, False)
            # Refuse source symlinks before emitting output.
            (root / 'payload').unlink()
            (root / 'payload').symlink_to(root / 'original')
            run(args, False)


if __name__ == '__main__':
    unittest.main()
