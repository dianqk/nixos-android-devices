"""Compile the fixed U-Boot EFI loader with the actual hook and storage adapter."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ['MOBILE_UBOOT_SOURCE'])
source = source_path.read_text()
dp_source = (source_path.parent / 'efi_device_path.c').read_text()
dp_size = dp_source.split('efi_uintn_t efi_dp_size(', 1)[1].split('\n}\n', 1)[0]
dp_size = 'efi_uintn_t efi_dp_size(' + dp_size + '\n}\n'
patch = (root / 'pkgs/u-boot/patches/0009-mobile-qcom-ab-efi-confirm.patch').read_text()
chunk = patch.split('--- a/lib/efi_loader/efi_bootbin.c\n', 1)[1]
lines = chunk.splitlines()[2:]
before = '\n'.join(line[1:] for line in lines if line.startswith((' ', '-'))) + '\n'
after = '\n'.join(line[1:] for line in lines if line.startswith((' ', '+'))) + '\n'
assert source.count(before) == 1, 'Hook must apply exactly to the pinned EFI loader'
source = source.replace(before, after)
function = source.split('static efi_status_t efi_run_image(', 1)[1].split('\n}\n', 1)[0]
function = 'static efi_status_t efi_run_image(' + function + '\n}\n'

with tempfile.TemporaryDirectory(dir=os.environ['MOBILE_TEST_TMP']) as directory:
    temporary = Path(directory)
    for name in ('blk.h', 'malloc.h', 'memalign.h', 'ufs.h', 'u-boot/crc.h',
                 'efi_device_path.h', 'efi_loader.h'):
        path = temporary / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('/* Interfaces provided by the isolated fixture. */\n')
    (temporary / 'mobile_qcom_ab.h').write_text('#include "qcom-ab.h"\n')
    (temporary / 'mobile-efi-run-image.c').write_text(function)
    (temporary / 'mobile-efi-dp-size.c').write_text(dp_size)
    executable = temporary / 'test'
    command = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
               '-ffreestanding', '-fshort-wchar', f'-I{temporary}',
               f'-I{root / "pkgs/mobile-boot-action"}']
    command += os.environ['MOBILE_EFI_CFLAGS'].split()
    command += [str(root / 'tests/boot-actions-confirm.c'), '-o', str(executable)]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
