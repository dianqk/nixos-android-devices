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


def make_image(board='clover', recovery=True, version=0, compressed=True, extra_dtb=b''):
    tree = dtb(('lenovo,' if board == 'asphalt' else 'xiaomi,') + board) + extra_dtb
    raw = bytearray(128)
    raw[56:60] = b'ARM\x64'
    kernel = gzip.compress(bytes(raw), mtime=0) if compressed else bytes(raw)
    if version != 2:
        kernel += tree
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


class ImageValidation(unittest.TestCase):
    def test_boards_headers_and_compression(self):
        for board in ['clover','polaris','asphalt','sheng']:
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
