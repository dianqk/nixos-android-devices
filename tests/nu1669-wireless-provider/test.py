#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host fault injection into actual receiver/provider authorization functions.

Use --source with a kernel tree containing the registered Dodge queue. This
compiles the production C function bodies with mocked GPIO/I2C/GLINK/workqueue
boundaries; it does not simulate driver-core binding, IRQ hardware or firmware.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def block(source, name, structure=False):
    pattern = (r'^struct ' + name + r' \{' if structure else
               r'^(?:static )?[\w *]+\b' + name + r'\(')
    match = re.search(pattern, source, re.M)
    if not match:
        raise AssertionError(name)
    start = match.start()
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end + int(structure)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    rx = (args.source / 'drivers/power/supply/nu1669.c').read_text()
    bm = (args.source / 'drivers/power/supply/qcom_battmgr.c').read_text()
    functions = block((args.source / 'include/linux/power/nu1669.h').read_text(),
                      'nu1669_snapshot', True) + '\n'
    functions += block(rx, 'nu1669', True) + '\n'
    for name in ['nu1669_observe_presence', 'nu1669_live', 'nu1669_read_info',
                 'nu1669_get_property', 'nu1669_bpp_verify', 'nu1669_get_snapshot', 'firmware_state_show', 'nu1669_online', 'nu1669_poll',
                 'nu1669_connected_irq_primary', 'nu1669_connected_irq', 'nu1669_stop', 'nu1669_suspend',
                 'nu1669_resume']:
        functions += block(rx, name) + '\n\n'
    for name in ['qcom_battmgr_wireless_present', 'qcom_battmgr_wireless_notifier',
                 'qcom_battmgr_wireless_unregister', 'qcom_battmgr_dodge_pd_current',
                 'qcom_battmgr_dodge_pd_valid', 'qcom_battmgr_dodge_pd_property',
                 'qcom_battmgr_dodge_otg_allowed', 'qcom_battmgr_dodge_otg_worker']:
        functions += block(bm, name) + '\n\n'
    with tempfile.TemporaryDirectory(prefix='nu1669-provider-') as tmp:
        tmp = Path(tmp)
        (tmp / 'production-defines.h').write_text('\n'.join(
            line for line in rx.replace('\\\n', '').splitlines() if line.startswith('#define NU1669_')) + '\n')
        (tmp / 'production.c').write_text(functions)
        output = tmp / 'test'
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', '-I', str(tmp),
                        str(root / 'test.c'), '-o', str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == '__main__':
    main()
