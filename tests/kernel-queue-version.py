#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check kernel release parsing and the stable source-preparation guard."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('kernel_queue', Path(__file__).resolve().parents[1] / 'tools/kernel-queue.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

for sublevel, extra, expected in [('0', '', '7.3'), ('1', '', '7.3.1'), ('4', '', '7.3.4'),
                                  ('12', '', '7.3.12'), ('0', '-rc5', '7.3-rc5'),
                                  ('0', '-rc6', '7.3-rc6')]:
    makefile = f'VERSION = 7\nPATCHLEVEL = 3\nSUBLEVEL = {sublevel}\nEXTRAVERSION = {extra}\n'
    assert tool.release_version(makefile) == expected

for version in ['7.3.1', '7.3.4']:
    source = f'/nix/store/example-linux-{version}.tar.xz'
    contract = tool.NIX_POST_PATCH_731.replace('@SOURCE@', source)
    tool.check_post_patch(version, source, contract)
    for changed in [contract + '\nextra operation\n', contract.replace(tool.RANDSTRUCT_SALT, '/different-salt'),
                    contract.replace(source, '/other-source'), contract.replace('patchShebangs scripts', ''),
                    contract.replace('find . -type f', 'find drivers -type f')]:
        try:
            tool.check_post_patch(version, source, changed)
        except ValueError:
            pass
        else:
            raise AssertionError('changed preparation contract accepted')
print('release parsing and stable preparation guard passed')
