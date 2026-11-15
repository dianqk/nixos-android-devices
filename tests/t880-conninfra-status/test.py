#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Compile the actual connsys ATF wrappers and framework power paths on the host."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def block(source, pattern):
    match = re.search(pattern, source, re.M)
    if not match:
        raise AssertionError(pattern)
    start = match.start()
    opened = source.index('{', match.start())
    level = 1
    end = opened + 1
    while level:
        level += (source[end] == '{') - (source[end] == '}')
        end += 1
    if source[end:end + 1] == ';':
        end += 1
    return source[start:end]


def function(source, name):
    return block(source, r'^(?:static )?(?:int|void) ' + name + r'\(')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--legacy-only', action='store_true')
    parser.add_argument('--wrappers-only', action='store_true')
    args = parser.parse_args()
    platform = args.source / 'connectivity/conninfra/conn_drv/connv2/platform'
    header = (platform / 'include/consys_hw.h').read_text()
    infra = (args.source / 'connectivity/conninfra/include/conninfra.h').read_text()
    framework = (platform / 'consys_hw.c').read_text()
    atf = (platform / 'mt6897/mt6897_atf.c').read_text()
    ops = (platform / 'mt6897/mt6897_ops.c').read_text()
    smc = (platform / 'include/connsys_smc.h').read_text()
    have_status = 'consys_plt_spi_master_cfg_status' in header
    types = header[header.index('typedef int(*'):header.index('struct conninfra_dev_cb')]
    enums = sorted(set(re.findall(r'enum (\w+)', types)))
    types = '\n'.join(block(infra, r'^enum consys_drv_type \{')
                      if n == 'consys_drv_type' else 'enum ' + n + ' { mock_' + n + ' };'
                      for n in enums) + '\n' + types
    types += '\n' + block(header, r'^struct consys_hw_env \{')
    smc = '\n'.join(line for line in smc.splitlines() if not line.startswith('#include '))
    bindings = block(ops, r'^struct consys_hw_ops_struct g_consys_hw_ops_mt6897_atf =')
    binding_lines = [line for line in bindings.splitlines()
                     if re.search(r'\.consys_plt_(?:spi_master|a_die)_cfg', line)]
    assert len(binding_lines) == 2
    for line in binding_lines:
        assert ('_status =' in line) == have_status
    constants = '\n'.join(line for line in infra.splitlines()
                          if re.match(r'#define CONNINFRA_POWER_ON_(?:D_DIE|A_DIE|CONFIG)_FAIL\b', line))
    names = ['consys_hw_get_clock_schematic', 'consys_hw_pwr_on', 'consys_hw_pwr_off']
    if have_status:
        names[0:0] = ['consys_hw_spi_master_cfg', 'consys_hw_a_die_cfg']
    functions = '\n\n'.join(function(framework, name) for name in names)
    wrappers = '\n\n'.join(function(atf, name) for name in [
        'consys_init_atf_data_mt6897_atf', 'connsys_spi_master_cfg_mt6897_atf',
        'connsys_a_die_cfg_mt6897_atf', 'connsys_low_power_setting_mt6897_atf'])
    source = Path(__file__).with_name('status_cases.c').read_text()
    for name, value in {
        'TYPES': types, 'SMC': smc, 'CONSTANTS': constants, 'ATF': wrappers,
        'ROLLBACK_ENUM': block(framework, r'^enum conninfra_pwr_on_rollback_type \{'),
        'FRAMEWORK': functions, 'BINDINGS': '\n'.join(binding_lines),
    }.items():
        source = source.replace('@PRODUCTION_' + name + '@', value)
    assert '@PRODUCTION_' not in source
    with tempfile.TemporaryDirectory(prefix='conninfra-status-') as temp:
        temp = Path(temp)
        (temp / 'test.c').write_text(source)
        flags = ['-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror']
        if not have_status:
            # The original SPI wrapper accepts next_status but never uses it.
            flags += ['-Wno-unused-parameter']
        subprocess.run([args.cc, *flags, '-DHAVE_STATUS=' + str(int(have_status)),
                        str(temp / 'test.c'), '-o', str(temp / 'test')], check=True)
        if args.legacy_only:
            subprocess.run([str(temp / 'test'), 'legacy'], check=True)
        elif args.wrappers_only:
            subprocess.run([str(temp / 'test'), 'wrappers'], check=True)
        else:
            subprocess.run([str(temp / 'test')], check=True)
            subprocess.run([str(temp / 'test'), 'wrappers', '-5'], check=True)


if __name__ == '__main__':
    main()
