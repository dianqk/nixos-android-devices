"""Compile the actual added UFS API from the patch using simulated descriptors."""
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
patch = (root / 'pkgs/u-boot/patches/0008-mobile-ufs-boot-lun.patch').read_text()
chunk = patch.split('--- a/drivers/ufs/ufs-uclass.c', 1)[1]
source = '\n'.join(line[1:] for line in chunk.splitlines() if line.startswith('+') and not line.startswith('+++'))
with tempfile.TemporaryDirectory(dir=os.environ['MOBILE_TEST_TMP']) as directory:
    temporary = Path(directory)
    (temporary / 'mobile-ufs-api.c').write_text(source)
    executable = temporary / 'test'
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
                    f'-I{temporary}', str(root / 'tests/boot-actions-ufs.c'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
