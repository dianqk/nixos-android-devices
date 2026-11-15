#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Fault-inject actual owned-pause functions, request transport and USB notifications."""
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
    assert 'qcom_battmgr_dodge_wireless_input_current_limit_set' not in source
    assert 'input_probe_owned' not in source
    assert 'debugfs_create_file("wireless_input_current_limit", 0400' in source
    assert re.search(r'qcom_battmgr_dodge_wireless_input_current_limit_get, NULL,', source)
    header = (args.source / 'include/linux/power/nu1669.h').read_text()
    types = block(header, r'^struct nu1669_snapshot \{') + '\n'
    types += block(source, r'^enum dodge_input_boot_state \{') + '\n'
    for name in ['qcom_battmgr_property_request', 'qcom_battmgr_message',
                 'qcom_battmgr_dodge_request']:
        types += block(source, r'^struct ' + name + r' \{') + '\n'
    names = ['qcom_battmgr_input_probe_event', 'qcom_battmgr_charge_event', 'qcom_battmgr_charge_get_behaviour',
             'qcom_battmgr_dodge_otg_request', 'qcom_battmgr_dodge_otg_reply',
             'qcom_battmgr_charge_transport_current', 'qcom_battmgr_charge_request',
             'qcom_battmgr_charge_raw_get', 'qcom_battmgr_charge_healthy',
             'qcom_battmgr_charge_current', 'qcom_battmgr_charge_same_receiver',
             'qcom_battmgr_charge_source',
             'qcom_battmgr_input_probe_unknown', 'qcom_battmgr_input_probe_send',
             'qcom_battmgr_input_probe_cleanup', 'qcom_battmgr_input_probe_current',
             'qcom_battmgr_input_probe_pause_confirmed', 'qcom_battmgr_input_probe_source', 'qcom_battmgr_input_probe_schedule',
             'qcom_battmgr_input_probe_worker', 'qcom_battmgr_input_probe_control',
             'qcom_battmgr_input_probe_close', 'qcom_battmgr_input_probe_write',
             'qcom_battmgr_charge_restore',
             'qcom_battmgr_charge_schedule', 'qcom_battmgr_charge_inhibit',
             'qcom_battmgr_bpp_hold', 'qcom_battmgr_bpp_samples', 'qcom_battmgr_bpp_voltage_vote', 'qcom_battmgr_bpp_source',
             'qcom_battmgr_bpp_votes', 'qcom_battmgr_automatic_step', 'wireless_care_hold_show', 'wireless_care_hold_store',
             'qcom_battmgr_charge_set_property', 'qcom_battmgr_charge_is_writeable',
             'qcom_battmgr_charge_worker', 'qcom_battmgr_charge_suspend',
             'qcom_battmgr_charge_resume', 'qcom_battmgr_charge_close',
             'qcom_battmgr_dodge_wireless_input_current_limit_get',
             'qcom_battmgr_dodge_otg_notification', 'qcom_battmgr_callback']
    production = 'static int qcom_battmgr_bpp_samples(struct qcom_battmgr *battmgr, bool restart);\nstatic void qcom_battmgr_bpp_voltage_vote(struct qcom_battmgr *battmgr);\nstatic bool qcom_battmgr_bpp_hold(struct qcom_battmgr *battmgr);\nstatic void qcom_battmgr_automatic_step(struct qcom_battmgr *battmgr);\nstatic atomic_t dodge_input_boot_state = ATOMIC_INIT(INPUT_BOOT_UNUSED);\n' + '\n'.join(block(source, r'^static [\w *]+\b' + name + r'\([^;{]*\)\n\{')
                           for name in names)
    defines = '\n'.join(line for line in source.splitlines() if line.startswith('#define '))
    defines += '\n' + next(line for line in header.splitlines() if line.startswith('#define NU1669_BPP_POWER_FAULTS'))
    root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='battmgr-owned-pause-') as directory:
        directory = Path(directory)
        (directory / 'production.c').write_text(production)
        (directory / 'production-types.h').write_text(types)
        (directory / 'production-defines.h').write_text(defines)
        output = directory / 'test'
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', '-I', str(directory),
                        str(root / 'test.c'), '-o', str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == '__main__':
    main()
