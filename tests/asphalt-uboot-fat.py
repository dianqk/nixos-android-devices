#!/usr/bin/env python3
"""Read a 1 GiB / 4096-byte-sector ESP using pinned U-Boot sandbox.

Requires sfdisk, mkfs.fat, fsck.fat, mtools and the tests/uboot-fat-sandbox.nix
output directory as the only argument. Uses project tmp/ files, no block device,
loop mount or privileges. Test data are not executable EFI/kernel images.
"""
import hashlib
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
FIRMWARE = Path(sys.argv[1]).resolve()


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


(REPO / 'tmp').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='asphalt-fat-', dir=REPO / 'tmp') as name:
    work = Path(name)
    fat, disk = work / 'boot.fat', work / 'disk.img'
    with fat.open('wb') as f:
        f.truncate(1024 ** 3)
    with disk.open('wb') as f:
        f.truncate(1024 ** 3 + 2 * 1024 ** 2)
    run('mkfs.fat', '-F', '32', '-S', '4096', '-s', '1', '-n', 'LINUX_BOOT', str(fat))
    run('mmd', '-i', str(fat), '::EFI', '::EFI/BOOT', '::EFI/nixos')
    rng = random.Random(8475)
    expected = {}
    for index, (path, size) in enumerate([
        ('EFI/BOOT/BOOTAA64.EFI', 4097),
        ('EFI/nixos/kernel.efi', 43 * 1024 ** 2 + 31),
        ('EFI/nixos/initrd', 45 * 1024 ** 2 + 127),
    ]):
        source = work / f'input-{index}'
        content = rng.randbytes(size)
        source.write_bytes(content)
        expected[path] = hashlib.sha256(content).hexdigest()
        run('mcopy', '-i', str(fat), str(source), '::' + path)
    run('fsck.fat', '-vn', str(fat))
    run('sfdisk', '--sector-size', '4096', '--no-reread', '--no-tell-kernel',
        '--wipe', 'never', '--wipe-partitions', 'never', str(disk),
        input=b'label: gpt\nunit: sectors\nstart=256, size=262144, type=U, name="linux-boot"\n')
    run('dd', 'if=' + str(fat), 'of=' + str(disk), 'bs=1M', 'seek=1',
        'conv=notrunc,sparse', 'status=none')
    run('sfdisk', '--sector-size', '4096', '--verify', str(disk))
    # The same host driver exercises both 4K block devices and FAT's 4K/512
    # mismatch path (the second bind is the standalone FAT file).
    for blocksize, source, part in [(4096, disk, '${bootpart}'), (512, fat, '0')]:
        commands = [f'host bind test {source} {blocksize}', 'host info']
        if blocksize == 4096:
            commands.append('part number host 0 linux-boot bootpart')
        for index, path in enumerate(expected):
            dest = work / f'output-{blocksize}-{index}'
            commands += [f'fatload host 0:{part} 1000000 {path}',
                         f'host save hostfs - 1000000 {dest} ${{filesize}}']
        commands.append('poweroff')
        result = run(str(FIRMWARE / 'u-boot'), '-d', str(FIRMWARE / 'u-boot.dtb'),
                     '-c', '; '.join(commands), cwd=work,
                     env=os.environ | {'SDL_VIDEODRIVER': 'dummy'})
        log = REPO / 'tmp' / f'asphalt-uboot-fat-{blocksize}.log'
        log.write_bytes(result.stdout + result.stderr)
        for index, digest in enumerate(expected.values()):
            assert hashlib.sha256((work / f'output-{blocksize}-{index}').read_bytes()).hexdigest() == digest
        print(f'U-Boot FAT readback verified: {blocksize}-byte blocks, 1 GiB FAT32, EFI/kernel/initrd paths')
