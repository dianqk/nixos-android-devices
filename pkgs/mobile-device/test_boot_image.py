"""Byte-level image validation; no external tools or hardware."""
import gzip
import struct
import unittest

from boot_image import inspect_image


def dtb(compatible):
    value = compatible.encode() + b'\0'
    structure = (struct.pack('>II', 1, 0) + struct.pack('>III', 3, len(value), 0)
                 + value + bytes(-len(value) % 4) + struct.pack('>II', 2, 9))
    strings = b'compatible\0'
    total = 56 + len(structure) + len(strings)
    return (struct.pack('>10I', 0xd00dfeed, total, 56, 56+len(structure), 40,
                        17, 16, 0, len(strings), len(structure))
            + bytes(16) + structure + strings)


def make_image(board='clover', recovery=True, version=0, compressed=True, extra_dtb=b'',
               ramdisk=None):
    tree = dtb(('lenovo,' if board == 'asphalt' else 'xiaomi,') + board) + extra_dtb
    raw = bytearray(128)
    raw[56:60] = b'ARM\x64'
    kernel = gzip.compress(bytes(raw), mtime=0) if compressed else bytes(raw)
    if version != 2:
        kernel += tree
    if ramdisk is None:
        ramdisk = gzip.compress(b'initrd', mtime=0)
    header = bytearray(4096)
    header[:8] = b'ANDROID!'
    for offset, value in [(8,len(kernel)),(16,len(ramdisk)),(36,4096),(40,version)]:
        struct.pack_into('<I',header,offset,value)
    if version >= 1:
        struct.pack_into('<I', header, 1644, 1660 if version==2 else 1648)
    if version == 2:
        struct.pack_into('<I',header,1648,len(tree))
    if recovery:
        text = b'rd.systemd.unit=mobile-recovery.target'
        header[64:64+len(text)] = text
    return (bytes(header) + kernel + bytes(-len(kernel)%4096)
            + ramdisk + bytes(-len(ramdisk)%4096) + (tree if version==2 else b''))


def fdt(tree):
    """Serialize {'props': {name: bytes}, 'nodes': {name: tree}} as an FDT."""
    strings, offsets = b'', {}
    def name_offset(name):
        nonlocal strings
        if name not in offsets:
            offsets[name] = len(strings)
            strings += name.encode() + b'\0'
        return offsets[name]
    def node(name, value):
        out = struct.pack('>I', 1) + name.encode() + b'\0'
        out += bytes(-len(out) % 4)
        for prop, data in value.get('props', {}).items():
            out += struct.pack('>III', 3, len(data), name_offset(prop)) + data + bytes(-len(data) % 4)
        for child, subtree in value.get('nodes', {}).items():
            out += node(child, subtree)
        return out + struct.pack('>I', 2)
    structure = node('', tree) + struct.pack('>I', 9)
    total = 56 + len(structure) + len(strings)
    return (struct.pack('>10I', 0xd00dfeed, total, 56, 56 + len(structure), 40,
                        17, 16, 0, len(strings), len(structure))
            + bytes(16) + structure + strings)


def text(value):
    return value.encode() + b'\0'


def fit(board='t880', bootargs='rd.systemd.unit=mobile-recovery.target', marker=b'ram-recovery',
        vendor='alldocube'):
    tree = fdt({'props': {'compatible': text(vendor + ',' + board)},
                'nodes': {'chosen': {'props': {'bootargs': text(bootargs)}}}})
    image = lambda kind, data, extra={}: {'props': {
        'type': text(kind), 'arch': text('arm64'), 'compression': text('none'),
        'data': data, **extra}}
    return fdt({'props': {'android-devices,payload': marker + b'\0'}, 'nodes': {
        'images': {'nodes': {'kernel': image('kernel_noload', b'kernel'),
                             'ramdisk': image('ramdisk', b'initrd'),
                             'fdt': image('flat_dt', tree)}},
        'configurations': {'props': {'default': text('recovery')}, 'nodes': {
            'recovery': {'props': {'kernel': text('kernel'), 'ramdisk': text('ramdisk'),
                                   'fdt': text('fdt')}}}}}})


def lz4_literals(data):
    """A valid legacy LZ4 frame storing data as literals only."""
    def block(chunk):
        n = len(chunk)
        token = bytes([min(n, 15) << 4])
        extra = b''
        if n >= 15:
            rest = n - 15
            extra = b'\xff' * (rest // 255) + bytes([rest % 255])
        return token + extra + chunk
    payload = block(data)
    return b'\x02\x21\x4c\x18' + struct.pack('<I', len(payload)) + payload


def make_v4_image(board='t880', payload=None, cmdline=b'', lz4=False, empty=False,
                  vendor='alldocube', gzipped=False):
    """Header v4 image with a U-Boot payload and its appended DTB."""
    raw = bytearray(128)
    raw[56:60] = b'ARM\x64'
    kernel = bytes(raw) + dtb(vendor + ',' + board)
    if lz4:
        kernel = lz4_literals(kernel)
    if gzipped:
        # Xiaomi ABL: the DTB follows the gzip stream of u-boot.bin.
        kernel = gzip.compress(kernel, mtime=0) + dtb(vendor + ',' + board)
    ramdisk = b'' if empty else payload if payload is not None else gzip.compress(b'unused', mtime=0)
    header = bytearray(4096)
    header[:8] = b'ANDROID!'
    for offset, value in [(8, len(kernel)), (12, len(ramdisk)), (20, 1584), (40, 4)]:
        struct.pack_into('<I', header, offset, value)
    header[44:44 + len(cmdline)] = cmdline
    return (bytes(header) + kernel + bytes(-len(kernel) % 4096)
            + ramdisk + bytes(-len(ramdisk) % 4096))


class ImageValidation(unittest.TestCase):
    def test_v4_firmware_and_recovery_payload(self):
        self.assertEqual(inspect_image(make_v4_image()), ('t880', False))
        self.assertEqual(inspect_image(make_v4_image(payload=fit())), ('t880', True))
        self.assertEqual(inspect_image(make_v4_image(lz4=True, empty=True)), ('t880', False))
        self.assertEqual(inspect_image(make_v4_image(lz4=True, payload=fit())), ('t880', True))
        marble = make_v4_image('marble', vendor='xiaomi', gzipped=True, empty=True)
        self.assertEqual(inspect_image(marble), ('marble', False))

    def test_v0_u_boot_image_with_recovery_fit(self):
        good = fit(board='aurora', vendor='xiaomi')
        for version in [0, 2]:
            with self.subTest(version=version):
                self.assertEqual(inspect_image(make_image(
                    'aurora', recovery=False, version=version, ramdisk=good)), ('aurora', True))
        for image in [
            make_image('aurora', recovery=True, ramdisk=good),
            make_image('aurora', recovery=False, ramdisk=fit(board='sheng', vendor='xiaomi')),
            make_image('aurora', recovery=False, ramdisk=fit(
                board='aurora', vendor='xiaomi', bootargs='rd.systemd.unit=initrd.target')),
            make_image('aurora', recovery=False, ramdisk=fit(
                board='aurora', vendor='xiaomi', marker=b'other')),
            make_image('aurora', recovery=False, ramdisk=good[:200]),
        ]:
            with self.subTest(size=len(image)), self.assertRaises(ValueError):
                inspect_image(image)

    def test_lz4_matches_and_rejects_corruption(self):
        from boot_image import lz4_block
        # token 0x14: 1 literal 'a', match length 4+4 at offset 1
        self.assertEqual(lz4_block(b'\x14a\x01\x00', 64), b'a' * 9)
        for bad in [b'\x14a\x02\x00', b'\x14a\x01', b'\xf0']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                lz4_block(bad, 64)
        with self.assertRaises(ValueError):
            inspect_image(make_v4_image(lz4=True)[:4096 + 20])

    def test_v4_recovery_payload_must_match_and_be_marked(self):
        for payload in [fit(board='other'), fit(marker=b'other'),
                        fit(bootargs='rd.systemd.unit=initrd.target'),
                        fit()[:200]]:
            with self.subTest(payload=payload[:60]), self.assertRaises(ValueError):
                inspect_image(make_v4_image(payload=payload))


    def test_boards_headers_and_compression(self):
        for board in ['clover','polaris','asphalt','sheng','aurora','unicorn']:
            for version in [0,1,2]:
                for compressed in [True,False]:
                    with self.subTest(board=board, version=version, compressed=compressed):
                        self.assertEqual(inspect_image(make_image(board, version=version, compressed=compressed)), (board,True))
        self.assertEqual(inspect_image(make_image(recovery=False)),('clover',False))

    def test_malformed_images(self):
        good = make_image()
        for bad in [b'not an image', good[:4096], good[:5000],
                    good[:36]+struct.pack('<I',0)+good[40:],
                    good[:40]+struct.pack('<I',4)+good[44:],
                    good[:24]+struct.pack('<I',128)+good[28:],
                    good.replace(b'compatible\0', b'not-board!\0')]:
            with self.subTest(size=len(bad)), self.assertRaises(ValueError):
                inspect_image(bad)

    def test_conflicting_board_dtbs(self):
        for compressed in [True,False]:
            with self.subTest(compressed=compressed), self.assertRaises(ValueError):
                inspect_image(make_image(extra_dtb=dtb('xiaomi,sheng'), compressed=compressed))

    def test_board_substring_is_not_identity(self):
        blob = make_image('polaris') + b'xiaomi,clover\0'
        self.assertEqual(inspect_image(blob),('polaris',True))


if __name__ == '__main__':
    unittest.main()
