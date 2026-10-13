"""Compile the actual storage adapter with in-memory interfaces; no hardware I/O."""
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(dir=os.environ['MOBILE_TEST_TMP']) as directory:
    temporary = Path(directory)
    for name in ('blk.h', 'malloc.h', 'memalign.h', 'ufs.h', 'u-boot/crc.h'):
        path = temporary / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('/* Interfaces are provided by the isolated fixture. */\n')
    (temporary / 'mobile_qcom_ab.h').write_text('#include "qcom-ab.h"\n')
    command = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
               '-ffreestanding', '-fshort-wchar', f'-I{temporary}',
               f'-I{root / "pkgs/mobile-boot-action"}']
    command += os.environ['MOBILE_EFI_CFLAGS'].split()
    executable = temporary / 'test'
    command += [str(root / 'tests/boot-actions-ab-adapter.c'), '-o', str(executable)]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
