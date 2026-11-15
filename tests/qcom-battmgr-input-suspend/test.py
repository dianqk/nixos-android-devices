#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Validate the actual optional gauge decoder and fresh input-suspend getter."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def block(source, pattern):
    match = re.search(pattern, source, re.M)
    if not match:
        raise AssertionError(pattern)
    end = source.index('{', match.start()) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    if source[end:end + 1] == ';':
        end += 1
    return source[match.start():end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    source = (args.source / 'drivers/power/supply/qcom_battmgr.c').read_text()
    production = ''
    for name in ['qcom_battmgr_dodge_request', 'qcom_battmgr_dodge_response']:
        production += block(source, r'^struct ' + name + r' \{') + '\n'
    for name in ['qcom_battmgr_dodge_decode', 'qcom_battmgr_dodge_decode_input_suspend',
                 'qcom_battmgr_charge_transport_current',
                 'qcom_battmgr_dodge_normal_input_suspend_get',
                 'qcom_battmgr_dodge_decode_voltage_samples',
                 'qcom_battmgr_dodge_normal_voltage_samples_get']:
        production += block(source, r'^static [\w *]+\b' + name + r'\(') + '\n'
    defines = '\n'.join(line for line in source.splitlines() if line.startswith('#define '))
    root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='battmgr-normal-charge-') as directory:
        directory = Path(directory)
        (directory / 'production.c').write_text(production)
        (directory / 'production-defines.h').write_text(defines)
        output = directory / 'test'
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', '-I', str(directory),
                        str(root / 'test.c'), '-o', str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == '__main__':
    main()
