#!/usr/bin/env python3
"""Host-only validation of Aurora firmware consumed by qcom_mdt_loader."""
import argparse
from pathlib import Path
import struct


def check(root, name, start, capacity):
    data = (root / (name + '.mdt')).read_bytes()
    assert data[:7] == b'\x7fELF\x01\x01\x01', 'expected little-endian ELF32 MDT'
    offset, = struct.unpack_from('<I', data, 28)
    entry_size, count = struct.unpack_from('<HH', data, 42)
    assert entry_size == 32 and offset + count * entry_size <= len(data)
    ranges = []
    files = 0
    for i in range(count):
        kind, _, _, address, file_size, memory_size, flags, _ = struct.unpack_from(
            '<8I', data, offset + i * entry_size)
        # Ignore Qualcomm hash segments, matching the kernel's MDT loader.
        if kind != 1 or not memory_size or flags & (7 << 24) == 2 << 24:
            continue
        assert memory_size >= file_size
        assert start <= address and address + memory_size <= start + capacity
        ranges.append((address, address + memory_size))
        if file_size:
            segment = root / f'{name}.b{i:02}'
            assert segment.stat().st_size == file_size, f'incomplete {segment.name}'
            files += 1
    assert ranges and min(a for a, _ in ranges) == start
    span = max(b for _, b in ranges) - start
    print(f'{name}: {files} load files, span {span:#x}, reservation {capacity:#x}')
    return span


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='directory containing adsp.mdt and its segments')
    parser.add_argument('--video', type=Path, help='optional complete VPU33 ELF image')
    parser.add_argument('--modem', type=Path,
                        help='optional directory containing modem, modem_dtb and ipa_fws MDTs')
    parser.add_argument('--adsp-variant', choices=('android14', 'android16'), default='android16')
    args = parser.parse_args()
    root = args.directory
    span, dtb_span = {'android14': (0x4080000, 0xf9bc), 'android16': (0x4680000, 0xfc0c)}[args.adsp_variant]
    assert check(root, 'adsp', 0x9df00000, span) == span
    assert check(root, 'adsp_dtb', 0x9de80000, 0x80000) == dtb_span
    if args.video:
        check_video(args.video)
    if args.modem:
        # Android 14 stock carve-outs, identical to sm8650.dtsi.
        check(args.modem, 'modem', 0x8bc00000, 0xf400000)
        check(args.modem, 'modem_dtb', 0x9b000000, 0x80000)
        check_relocatable(args.modem, 'ipa_fws', 0x10000)


def check_relocatable(root, name, capacity):
    """Check a relocatable split MDT, such as IPA GSI firmware, fits its region."""
    data = (root / (name + '.mdt')).read_bytes()
    assert data[:7] == b'\x7fELF\x01\x01\x01', 'expected little-endian ELF32 MDT'
    offset, = struct.unpack_from('<I', data, 28)
    entry_size, count = struct.unpack_from('<HH', data, 42)
    assert entry_size == 32 and offset + count * entry_size <= len(data)
    ranges = []
    for i in range(count):
        kind, _, _, address, file_size, memory_size, flags, _ = struct.unpack_from(
            '<8I', data, offset + i * entry_size)
        if kind != 1 or not memory_size or flags & (7 << 24) == 2 << 24:
            continue
        assert flags & (1 << 27), f'expected relocatable {name} firmware'
        assert memory_size >= file_size
        ranges.append((address, address + memory_size))
        if file_size:
            segment = root / f'{name}.b{i:02}'
            assert segment.stat().st_size == file_size, f'incomplete {segment.name}'
    assert ranges
    span = max(b for _, b in ranges) - min(a for a, _ in ranges)
    assert span <= capacity
    print(f'{name}: {len(ranges)} relocatable segments, span {span:#x}, reservation {capacity:#x}')


def check_video(path):
    data = path.read_bytes()
    assert data[:7] == b'\x7fELF\x01\x01\x01'
    offset, = struct.unpack_from('<I', data, 28)
    entry_size, count = struct.unpack_from('<HH', data, 42)
    assert entry_size == 32 and offset + count * entry_size <= len(data)
    ranges = []
    for i in range(count):
        kind, file_offset, _, address, size, memory_size, flags, _ = struct.unpack_from(
            '<8I', data, offset + i * entry_size)
        if kind != 1 or not memory_size or flags & (7 << 24) == 2 << 24:
            continue
        assert flags & (1 << 27), 'expected relocatable VPU firmware'
        assert memory_size >= size and file_offset + size <= len(data)
        ranges.append((address, address + memory_size))
    assert ranges
    start = min(a for a, _ in ranges)
    end = (max(b for _, b in ranges) + 4095) & ~4095
    assert start % 4096 == 0 and end - start == 0x800000
    print(f'{path.name}: {len(ranges)} load segments, relocated reservation 0x9bb00000+0x800000')


if __name__ == '__main__':
    main()
