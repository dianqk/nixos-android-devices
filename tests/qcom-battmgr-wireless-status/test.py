#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile actual Dodge STATUS routing, qualification and gauge decoding."""
import argparse
from pathlib import Path
import runpy
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    block = runpy.run_path(str(root.parent / 'qcom-battmgr-charge-behaviour/test.py'))['block']
    source = (args.source / 'drivers/power/supply/qcom_battmgr.c').read_text()
    header = (args.source / 'include/linux/power/nu1669.h').read_text()
    types = block(header, r'^struct nu1669_snapshot \{') + '\n'
    for name in ['qcom_battmgr_property_request', 'qcom_battmgr_dodge_request', 'qcom_battmgr_dodge_response']:
        types += block(source, r'^struct ' + name + r' \{') + '\n'
    names = ['qcom_battmgr_request_property', 'qcom_battmgr_dodge_decode',
             'qcom_battmgr_dodge_status_receiver', 'qcom_battmgr_dodge_wireless_status',
             'qcom_battmgr_dodge_get_property']
    code = '\n'.join(block(source, r'^static [\w *]+\b' + name + r'\([^;{]*\)\n\{') for name in names)
    defines = '\n'.join(line for line in source.splitlines() if line.startswith('#define '))
    with tempfile.TemporaryDirectory(prefix='dodge-status-') as directory:
        directory = Path(directory)
        (directory / 'types.h').write_text(types)
        (directory / 'production.c').write_text(code)
        (directory / 'defines.h').write_text(defines)
        output = directory / 'test'
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', '-I', str(directory), str(root / 'test.c'), '-o', str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == '__main__':
    main()
