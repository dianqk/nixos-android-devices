#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Explicit offline integration: BOOT_CHOICE_FIXTURES points to trusted host bundles."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(os.environ.get('BOOT_CHOICE_FIXTURES'), 'requires trusted offline fixtures')
class OwnedCLI(unittest.TestCase):
    def test_actual_source_bound_conversion(self):
        base = Path(os.environ['BOOT_CHOICE_FIXTURES'])
        cli = Path(os.environ.get('BOOT_CHOICE_NATIVE', ROOT / 'tools/boot-choice/target/release/boot-choice-native'))
        legacy = base / 'gui-dirty-boot4-v1'
        def call(*args, ok=True):
            p = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True)
            self.assertEqual(p.returncode == 0, ok, p.stdout + p.stderr)
            return p.stdout
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            owned, restored, android, noop = [d / n for n in ('owned', 'restored', 'android', 'noop')]
            call('owned-inspect', legacy / 'original.img', ok=False)
            call('owned-inspect', legacy / 'experiment.img', ok=False)
            call('owned-seal', legacy / 'catalog.json', legacy / 'original.img',
                 base / 'uboot-abi/u-boot.bin', base / 'uboot-abi/u-boot',
                 base / 'uboot-abi/source/.config', legacy / 'experiment.img', owned)
            info = call('owned-inspect', owned)
            generation = info.split('generation=')[1].split()[0]
            call('owned-request', owned, generation, '1', 'uboot', noop)
            self.assertEqual(owned.read_bytes(), noop.read_bytes())
            call('owned-request', owned, generation, '2', 'android', d / 'stale', ok=False)
            self.assertFalse((d / 'stale').exists())
            call('owned-request', owned, generation, '1', 'android', android)
            call('owned-restore', android, restored)
            digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
            self.assertEqual(digest(restored), digest(legacy / 'original.img'))
            # Create-new protects existing outputs; no overwrite even for a no-op.
            call('owned-restore', android, restored, ok=False)

if __name__ == '__main__':
    unittest.main()
