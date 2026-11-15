"""Compile the actual added UFS API from the patches using simulated descriptors.

0008 adds the API; 0011 rewrites its descriptor reads and 0012 accepts
HPB-enabled LUs. Each later hunk is applied in order to the 0008 source (its
old side must occur exactly once)."""
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
patches = root / 'pkgs/u-boot/patches'


def ufs_chunk(name):
    return (patches / name).read_text().split('--- a/drivers/ufs/ufs-uclass.c', 1)[1]


source = '\n'.join(line[1:] for line in ufs_chunk('0008-mobile-ufs-boot-lun.patch').splitlines()
                   if line.startswith('+') and not line.startswith('+++')) + '\n'
hunks = []
for name in ['0011-mobile-ufs-descriptor-length.patch', '0012-mobile-ufs-hpb-lu-enable.patch']:
    found = ufs_chunk(name).split('\n@@ ')[1:]
    assert found, name
    hunks += found
for hunk in hunks:
    old, new = [], []
    for line in hunk.splitlines()[1:]:
        if line.startswith('diff --git') or line.startswith('-- '):
            break
        kind, text = (line[:1], line[1:]) if line else (' ', '')
        if kind in ' -':
            old.append(text)
        if kind in ' +':
            new.append(text)
    old, new = '\n'.join(old) + '\n', '\n'.join(new) + '\n'
    assert source.count(old) == 1, old
    source = source.replace(old, new)
with tempfile.TemporaryDirectory(dir=os.environ['MOBILE_TEST_TMP']) as directory:
    temporary = Path(directory)
    (temporary / 'mobile-ufs-api.c').write_text(source)
    executable = temporary / 'test'
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
                    f'-I{temporary}', str(root / 'tests/boot-actions-ufs.c'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
