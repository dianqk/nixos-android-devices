#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Exercise the actual MT6897 pre-release block and register-write helper."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def function(text, name):
    start = text.index(name + '(')
    start = text.rfind('\n', 0, start) + 1
    opened = text.index('{', start)
    level, end = 1, opened + 1
    while level:
        level += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--header', type=Path)
    args = parser.parse_args()
    directory = args.source / 'connectivity/bt/mt66xx/include/btif'
    header = (args.header or directory / 'platform_6897.h').read_text()
    helper = function((directory / 'platform_base.h').read_text(), 'bt_write_cr')
    # Preserve the production body; normalize only vendor declaration ordering.
    helper = helper.replace('static void inline ', 'static inline void ', 1)
    power = function(header, 'bgfsys_power_on')
    begin = power.index('/*clear fw own IRQ*/')
    end = power.index('/* clear host_csr debug bgfsys_on_top select */', begin)
    sequence = power[begin:end]
    # The original preprocessor arm, not an assumed universal power-on path.
    prefix = power[:begin]
    assert prefix.rfind('#if (CFG_BT_ATF_SUPPORT == 1)') > prefix.rfind('#endif')
    assert prefix.rfind('#else') > prefix.rfind('#if (CFG_BT_ATF_SUPPORT == 1)')
    assert power.index('#endif', end) > end
    names = ['BGF_IRQ_FW_OWN_SET_B', 'BGF_CPU_SW_RST_B',
             'BGF2AP_CONN_INFRA_ON_CCIF4_BGF2AP_PCCIF_ACK_ADDR']
    defines = '\n'.join(match[0] for name in names
                        if (match := re.search(r'^#define ' + name + r'\s+[^\n]+', header, re.M)))
    fixture = Path(__file__).with_name('cases.c').read_text()
    with tempfile.TemporaryDirectory(prefix='t880-bt-startup-') as tmp:
        root = Path(tmp)
        (root / 'production.h').write_text(defines + '\n' + helper +
            '\nstatic void production_start(void)\n{\n#if CFG_BT_ATF_SUPPORT == 0\n' +
            sequence + '\n#endif\n}\n')
        for mode in [0, 1]:
            binary = root / ('test' + str(mode))
            subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                            '-DCFG_BT_ATF_SUPPORT=' + str(mode), '-I' + str(root),
                            '-x', 'c', '-', '-o', str(binary)], input=fixture, text=True, check=True)
            subprocess.run([str(binary)], check=True)
    print('MT6897 startup ACK production sequence/helper: PASS')


if __name__ == '__main__':
    main()
