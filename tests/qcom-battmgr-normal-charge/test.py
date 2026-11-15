#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Fault-inject the actual Dodge raw GET getter, serialized transport and matcher."""
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
    production = block(source, r'^struct qcom_battmgr_property_request \{') + '\n'
    production += block(source, r'^struct qcom_battmgr_message \{') + '\n'
    for name in ['qcom_battmgr_dodge_otg_request', 'qcom_battmgr_dodge_otg_reply',
                 'qcom_battmgr_dodge_normal_charge_enable_get',
                 'qcom_battmgr_dodge_wireless_input_current_limit_get',
                 'qcom_battmgr_dodge_normal_charge_limits_get',
                 'qcom_battmgr_dodge_debugfs_remove']:
        production += block(source, r'^static [\w *]+\b' + name + r'\(') + '\n'
    names = ['BATTMGR_BAT_PROPERTY_GET', 'BATTMGR_USB_PROPERTY_SET',
             'DODGE_USB_OTG_VBUS_ENABLE', 'BATT_CHG_CTRL_EN', 'BATTMGR_STRING_LEN',
             'BATTMGR_CHEMISTRY_LEN', 'BATTMGR_WLS_PROPERTY_GET', 'DODGE_WLS_INPUT_CURR_LIMIT', 'BATT_CHG_CTRL_LIM', 'BATT_VOLT_MAX']
    defines = '\n'.join(line for line in source.splitlines()
                        if any(re.match(r'#define ' + name + r'\s', line) for name in names))
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
