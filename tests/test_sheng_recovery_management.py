#!/usr/bin/env python3
"""Exercise recovery image refusals and BCB requests without block devices."""
import hashlib
from pathlib import Path
import shlex
import struct
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
CHECK = REPO / 'devices/sheng/check-recovery-image.sh'
REQUEST = (REPO / 'devices/sheng/request-recovery.sh').read_text()
INSTALL = (REPO / 'devices/sheng/install-recovery.sh').read_text()


def fixture():
    # Minimal v17 FDT root compatible, followed by a complete unsigned AVB footer.
    compatible = b'xiaomi,sheng\0qcom,sm8550\0'
    structure = struct.pack('>IIIII', 1, 0, 3, len(compatible), 0) + compatible
    structure += bytes(-len(structure) % 4) + struct.pack('>II', 2, 9)
    strings = b'compatible\0'
    dt = struct.pack('>10I', 0xd00dfeed, 56 + len(structure) + len(strings),
                     56, 56 + len(structure), 40, 17, 16, 0, len(strings), len(structure))
    dt += bytes(16) + structure + strings
    data = bytearray(104857600)
    data[:8] = b'ANDROID!'
    struct.pack_into('<10I', data, 8, len(dt) + 8, 0x8000, 8, 0x1000000,
                     0, 0, 0x1e00000, 4096, 0, 0)
    cmd = b'rd.systemd.unit=mobile-recovery.target'
    data[64:64 + len(cmd)] = cmd
    data[4104:4104 + len(dt)] = dt
    vbmeta = 12288
    data[vbmeta:vbmeta + 4] = b'AVB0'
    struct.pack_into('>Q', data, vbmeta + 20, 192)
    struct.pack_into('>Q', data, vbmeta + 104, 176)
    desc = vbmeta + 256
    struct.pack_into('>QQQ', data, desc, 2, 160, vbmeta)
    data[desc + 24:desc + 30] = b'sha256'
    struct.pack_into('>IIII', data, desc + 56, 8, 0, 32, 0)
    data[desc + 132:desc + 140] = b'recovery'
    data[desc + 140:desc + 172] = hashlib.sha256(data[:vbmeta]).digest()
    struct.pack_into('>4sIIQQQ', data, len(data) - 64, b'AVBf', 1, 0, vbmeta, vbmeta, 448)
    return data


class Recovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=REPO / 'tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def image_check(self, data, allowed):
        image = self.root / 'recovery.img'
        image.write_bytes(data)
        result = subprocess.run(['sh', str(CHECK), str(image)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, allowed, result.stderr)

    def test_image_validation(self):
        data = fixture()
        self.image_check(data, True)
        for offset, value in [(64, b'other'), (data.index(b'xiaomi,sheng'), b'xiaomi,other'),
                              (8192, b'corrupt'), (len(data) - 64, b'bad!'),
                              (12288 + 256 + 132, b'bootxxxx')]:
            with self.subTest(offset=offset):
                changed = data[:]
                changed[offset:offset + len(value)] = value
                if offset != 8192:
                    changed[12288 + 396:12288 + 428] = hashlib.sha256(changed[:12288]).digest()
                self.image_check(changed, False)
        self.image_check(data[:-4096], False)

    def test_effective_cmdline_rejects_padding_and_conflicts(self):
        for cmdline in [b'rd.systemd.unit=initrd.target\0 rd.systemd.unit=mobile-recovery.target',
                        b'rd.systemd.unit=mobile-recovery.target rd.systemd.unit=initrd.target']:
            data = fixture()
            data[64:576] = cmdline.ljust(512, b'\0')
            data[12288 + 396:12288 + 428] = hashlib.sha256(data[:12288]).digest()
            self.image_check(data, False)

    def test_request_preserves_other_misc_bytes(self):
        body = REQUEST[REQUEST.index('scratch=$(mktemp'):]
        body = body.replace('/run/sheng-bcb.', str(self.root / 'bcb.'))
        for command, allowed in [(b'', True), (b'boot-recovery\0oader', True),
                                 (b'boot-fastboot', False), (b'boot-recovery!', False)]:
            for mode in ['--check', '--execute']:
                with self.subTest(command=command, mode=mode):
                    misc = self.root / 'misc'
                    before = command.ljust(32, b'\0') + b'BCB!' * ((4194304 - 32) // 4)
                    misc.write_bytes(before)
                    script = ('set -Eeuo pipefail\nfail() { echo "$*" >&2; exit 1; }\n'
                              f'target={shlex.quote(str(misc))}\nmode={mode}\n' + body)
                    result = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, allowed, result.stderr)
                    expected = b'boot-recovery'.ljust(32, b'\0') + before[32:] if allowed and mode == '--execute' else before
                    self.assertEqual(misc.read_bytes(), expected)

    def test_install_hashes_and_full_readback(self):
        data = fixture()
        image = self.root / 'image'; image.write_bytes(data)
        target = self.root / 'partition'
        original = bytes(len(data))
        old_hash = hashlib.sha256(original).hexdigest()
        image_hash = hashlib.sha256(data).hexdigest()
        body = INSTALL[INSTALL.index('[[ -f $image'):]
        for mode, old, new, allowed in [('--check', old_hash, image_hash, True),
                                        ('--execute', '0' * 64, image_hash, False),
                                        ('--execute', old_hash, '0' * 64, False),
                                        ('--execute', old_hash, image_hash, True)]:
            with self.subTest(mode=mode, old=old, new=new):
                target.write_bytes(original)
                variables = dict(mode=mode, target=str(target), image=str(image), old_hash=old,
                                 image_hash=new, SHENG_IMAGE_CHECK=str(CHECK))
                script = ('set -Eeuo pipefail\nfail() { echo "$*" >&2; exit 1; }\n' +
                          '\n'.join(f'{k}={shlex.quote(v)}' for k, v in variables.items()) + '\n' + body)
                result = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, allowed, result.stderr)
                self.assertEqual(target.read_bytes(), data if allowed and mode == '--execute' else original)


if __name__ == '__main__':
    unittest.main()
