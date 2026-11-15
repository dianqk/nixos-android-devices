#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Compile production address setup with a model of the HCI setup/open gate."""
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
    args = parser.parse_args()
    text = (args.source / 'connectivity/bt/mt66xx/btmtk_main.c').read_text()
    allocation = function(text, 'btmtk_allocate_hci_device')
    # Use the real registration quirk and callback, rather than assuming either.
    callback = re.search(r'hdev->setup\s*=\s*(\w+);', allocation)[1]
    quirk = '\n'.join(re.findall(
        r'hci_set_quirk\(hdev, HCI_QUIRK_NON_PERSISTENT_SETUP\);', allocation))
    production = '\n'.join(function(text, name) for name in
                           ['btmtk_t880_get_bdaddr', 'btmtk_t880_set_bdaddr', callback])
    fixture = Path(__file__).with_name('cases.c').read_text()
    with tempfile.TemporaryDirectory(prefix='t880-bt-address-') as tmp:
        root = Path(tmp)
        (root / 'production.h').write_text(production + '\nstatic void register_setup(struct hci_dev *hdev)\n{\n'
            + f'hdev->setup = {callback};\n' + quirk + '\n}\n')
        binary = root / 'test'
        subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                        '-I' + str(root), '-x', 'c', '-', '-o', str(binary)],
                       input=fixture, text=True, check=True)
        subprocess.run([str(binary)], check=True)
    print('MT6897 production address setup: initial/reopen/errors PASS')


if __name__ == '__main__':
    main()
