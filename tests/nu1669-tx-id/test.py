#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile the production GET05 transport against a byte-exact scripted receiver."""
import argparse
from pathlib import Path
import runpy
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--only-fod', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    block = runpy.run_path(str(root.parent / 'nu1669-wireless-provider/test.py'))['block']
    source = (args.source / 'drivers/power/supply/nu1669.c').read_text()
    header = (args.source / 'include/linux/power/nu1669.h').read_text()
    code = 'static atomic_t nu1669_bpp_uncertain = ATOMIC_INIT(0);\n' + block(header, 'nu1669_snapshot', True) + '\n' + block(source, 'nu1669', True) + '\n'
    names = ['nu1669_writeable_reg', 'nu1669_observe_presence', 'nu1669_live',
             'nu1669_read_info', 'nu1669_bpp_profile_valid', 'nu1669_bpp_context', 'nu1669_bpp_idle', 'nu1669_bpp_write', 'nu1669_prepare_bpp', 'nu1669_bpp_verify', 'nu1669_get_snapshot', 'nu1669_stop', 'nu1669_query_live',
             'nu1669_query_context', 'nu1669_query_flags', 'nu1669_query_idle',
             'nu1669_query_mailbox', 'nu1669_query_ack', 'nu1669_query_reply',
             'nu1669_query_tx_id', 'nu1669_query_tx_id_write', 'nu1669_last_tx_id_show',
             'nu1669_debugfs_remove', 'nu1669_fod_shadow_get', 'nu1669_fod_shadow_show']
    for name in names:
        code += block(source, name) + '\n'
    assert 'regmap_write' not in block(source, 'nu1669_fod_shadow_get')
    assert 'debugfs_create_file("fod_shadow", 0400' in source
    assert 'debugfs_create_file("query_tx_id", 0200' in source
    assert 'debugfs_create_file("last_tx_id", 0400' in source
    assert source.count('EXPORT_SYMBOL_GPL(') == 2
    assert 'IRQF_ONESHOT' not in source and 'gpiod_set_value' not in source
    defines = next(line for line in header.splitlines() if line.startswith('#define NU1669_BPP_POWER_FAULTS')) + '\n' + '\n'.join(line for line in source.replace('\\\n', '').splitlines()
                        if line.startswith('#define NU1669_'))
    with tempfile.TemporaryDirectory(prefix='nu1669-get05-') as directory:
        directory = Path(directory)
        (directory / 'production.c').write_text(code)
        (directory / 'production-defines.h').write_text(defines)
        output = directory / 'test'
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', '-pthread', '-I', str(directory),
                        str(root / 'test.c'), '-o', str(output)], check=True)
        subprocess.run([str(output)] + (['fod'] if args.only_fod else []), check=True, timeout=30)


if __name__ == '__main__':
    main()
