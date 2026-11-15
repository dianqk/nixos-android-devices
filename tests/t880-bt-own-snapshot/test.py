#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Compile actual bounded observation helper; exercise ownership hook order."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def block(text, pattern):
    match = re.search(pattern, text, re.M)
    assert match, pattern
    start = match.start()
    opened = text.index('{', start)
    level, end = 1, opened + 1
    while level:
        level += (text[end] == '{') - (text[end] == '}')
        end += 1
    if text[end:end + 1] == ';':
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--before', type=Path)
    args = parser.parse_args()
    source = (args.source / 'connectivity/bt/mt66xx/btif/btmtk_btif_main.c').read_text()
    base = (args.source / 'connectivity/bt/mt66xx/include/btif/platform_base.h').read_text()
    start = source.index('#if CONNAC20_CHIPID == 6897')
    end = source.index('\n#endif', start) + len('\n#endif')
    helper = source[start:end]
    # Read the real mapping types/indices, including their preprocessor arm.
    types = '\n'.join(block(base, pattern) for pattern in [
        r'^struct consys_reg_base_addr \{', r'^enum bt_base_addr_index \{',
        r'^struct bt_base_addr \{'])
    defines = '\n'.join(re.search(r'^#define ' + n + r'\s+[^\n]+', base, re.M)[0]
                        for n in ['CON_REG_INFRA_RGU_ADDR', 'CON_REG_INFRA_CFG_ADDR',
                                  'CON_REG_SPM_BASE_ADDR'])
    with tempfile.TemporaryDirectory(prefix='t880-own-snapshot-') as tmp:
        root = Path(tmp)
        (root / 'production.h').write_text(types + '\nstatic struct bt_base_addr bt_reg;\n' +
                                          defines + '\n' + helper)
        for chip, atf, dynamic in [(6897, 0, True), (6897, 1, True),
                                    (6886, 0, True), (6897, 0, False)]:
            flags = ['-DCONNAC20_CHIPID=' + str(chip), '-DCFG_BT_ATF_SUPPORT=' + str(atf)]
            if dynamic:
                flags += ['-DCONFIG_DYNAMIC_DEBUG=1']
            binary = root / ('helper-' + str(chip) + '-' + str(atf) + '-' + str(dynamic))
            subprocess.run([args.cc, '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror',
                            *flags, '-I' + str(root), str(Path(__file__).with_name('helper_cases.c')),
                            '-o', str(binary)], check=True)
            selected = chip == 6897 and atf == 0 and dynamic
            cases = ['off', 'ao', 'full', 'allowed-guards', 'rx-protected', 'tx-protected', 'map-fail',
                     'mapping', 'host-short', 'rgu-short', 'ao-independent', 'src-map-fail', 'width', 'cap', 'cap-full'] if selected else ['stub']
            for case in cases:
                subprocess.run([str(binary), case], check=True)
        test_callers(source, args.before, args.cc, root)
    print('production ownership observation helper/callers: PASS')


def test_callers(source, before, cc, root):
    # Implemented below; both full production functions, not a hardware model.
    path = Path(__file__).with_name('caller_cases.c')
    assert path.exists(), path
    names = ['btmtk_cif_fw_own_clr', 'btmtk_cif_fw_own_set']
    constants = '\n'.join(re.search(r'^#define ' + n + r'\s+[^\n]+', source, re.M)[0]
                          for n in ['LPCR_POLLING_RTY_LMT', 'LPCR_MASS_DUMP_LMT'])
    traces = {}
    for label, text in [('new', source)] + ([('old', before.read_text())] if before else []):
        functions = '\n'.join(block(text, r'^static int32_t ' + n + r'\(') for n in names)
        (root / 'callers.h').write_text(constants + '\n' + functions)
        binary = root / ('callers-' + label)
        subprocess.run([cc, '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror',
                        '-I' + str(root), str(path), '-o', str(binary)], check=True)
        if label == 'new':
            subprocess.run([str(binary)], check=True)
        traces[label] = subprocess.check_output([str(binary), '--trace'])
    if before:
        assert traces['old'] == traces['new'], 'ordinary request/poll/ACK/sleep/dump trace changed'
        print('actual old/new ordinary ownership traces: identical')


if __name__ == '__main__':
    main()
