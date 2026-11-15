#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Offline, deliberately nonbootable BOOT4/raw ARM64 research carrier.

Original implementation: no selector, entry patch, AVB rewrite or device I/O.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import sys

MAGIC = b'BOOT-CARRIER-V1\n'
HEADER = struct.Struct('<16sQQ32s32s32s')
LIMIT = 256 * 1024 * 1024
PAGE = 4096


def digest(data):
    return hashlib.sha256(data).digest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def align(value):
    return (value + PAGE - 1) // PAGE * PAGE


def span(data, offset, size, name):
    require(0 <= offset <= len(data) and 0 <= size <= len(data) - offset,
            f'{name}: out of bounds')
    return data[offset:offset + size]


def arm64(data):
    require(len(data) >= 64 and data[56:60] == b'ARM\x64', 'not a raw ARM64 Image')
    text, size, flags = struct.unpack_from('<QQQ', data, 8)
    require(text == 0, 'only zero text_offset is supported')
    require(len(data) <= size <= LIMIT, 'invalid ARM64 image_size')
    require(flags == 10, 'only little-endian, 4KiB, relocatable ARM64 flags=10 supported')
    # A PE-compatible Image has MZ in its first instruction and B at +4.
    entry = 4 if data[:2] == b'MZ' else 0
    instruction = struct.unpack_from('<I', data, entry)[0]
    require(instruction & 0xfc000000 == 0x14000000, 'entry is not an unconditional B')
    imm = instruction & 0x3ffffff
    target = entry + ((imm if imm < 0x2000000 else imm - 0x4000000) * 4)
    require(64 <= target < len(data), 'entry branch leaves stored kernel')
    return {'stored_bytes': len(data), 'image_size': size, 'text_offset': text,
            'flags': flags, 'entry_offset': entry, 'branch_target': target,
            'sha256': digest(data).hex()}


def boot4(data):
    require(PAGE <= len(data) <= LIMIT and data[:8] == b'ANDROID!',
            'not a bounded Android BOOT image')
    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from('<4I', data, 8)
    require(header_size == 1584 and struct.unpack_from('<I', data, 40)[0] == 4,
            'only BOOT header v4 (1584 bytes) supported')
    require(not any(data[24:40]), 'nonzero BOOT reserved words')
    signature_size = struct.unpack_from('<I', data, 1580)[0]
    require(kernel_size > 0 and ramdisk_size == 0 and signature_size == 0,
            'only kernel-only BOOT4 with no boot_signature supported')
    require(not any(data[header_size:PAGE]), 'nonzero header page padding')
    kernel_end = PAGE + kernel_size
    boot_end = align(kernel_end)
    span(data, 0, boot_end, 'BOOT pages')
    require(not any(data[kernel_end:boot_end]), 'nonzero kernel page padding')
    image = arm64(span(data, PAGE, kernel_size, 'kernel'))
    footer = data[-64:]
    avb = None
    if footer[:4] == b'AVBf':
        major, minor, original_size, offset, size = struct.unpack_from('>IIQQQ', footer, 4)
        require((major, minor) == (1, 0) and not any(footer[36:]), 'unsupported AVB footer')
        require(boot_end <= original_size <= offset and size >= 256,
                'AVB overlaps BOOT pages or has invalid length')
        require(offset <= len(data) - 64 and size <= len(data) - 64 - offset,
                'AVB overlaps footer or is truncated')
        vbmeta = span(data, offset, size, 'vbmeta')
        require(vbmeta[:4] == b'AVB0', 'invalid vbmeta magic')
        auth, aux = struct.unpack_from('>QQ', vbmeta, 12)
        require(256 + auth + aux == size, 'vbmeta block lengths disagree')
        avb = {'original_image_size': original_size, 'vbmeta_offset': offset,
               'vbmeta_size': size, 'algorithm': struct.unpack_from('>I', vbmeta, 28)[0],
               'policy': 'preserved byte-for-byte; NOT cryptographically verified'}
    else:
        # No guessing whether nonzero trailers are an undocumented signature.
        require(not any(data[boot_end:]), 'unknown nonzero tail without valid AVB footer')
    return {'bytes': len(data), 'sha256': digest(data).hex(), 'os_version_raw': os_version,
            'kernel': image, 'avb': avb}


def make_carrier(original, payload):
    boot4(original)
    arm64(payload)
    prefix = struct.pack('<16sQQ32s32s', MAGIC, len(original), len(payload),
                         digest(original), digest(payload))
    return prefix + digest(prefix) + original + payload


def unpack(data):
    require(len(data) >= HEADER.size, 'truncated carrier header')
    magic, original_size, payload_size, original_hash, payload_hash, checksum = HEADER.unpack_from(data)
    require(magic == MAGIC, 'not a v1 nonbootable carrier (or already patched input)')
    require(digest(data[:HEADER.size - 32]) == checksum, 'carrier header checksum mismatch')
    require(0 < original_size <= LIMIT and 0 < payload_size <= LIMIT, 'carrier size limit')
    require(len(data) == HEADER.size + original_size + payload_size, 'carrier length mismatch')
    original = span(data, HEADER.size, original_size, 'original')
    payload = span(data, HEADER.size + original_size, payload_size, 'payload')
    require(digest(original) == original_hash and digest(payload) == payload_hash,
            'carrier section hash mismatch')
    boot4(original)
    arm64(payload)
    return original, payload


def inspect(data):
    original, payload = unpack(data)
    info = boot4(original)
    candidate = align(info['kernel']['image_size'])
    return {'format': 'BOOT-CARRIER-V1', 'bootable': False, 'original': info,
            'payload': arm64(payload),
            'candidate_layout': {'payload_kernel_offset': candidate,
                                 'payload_stored_end': candidate + len(payload),
                                 'payload_image_end': candidate + arm64(payload)['image_size'],
                                 'status': 'arithmetic only, NOT a load allocation or workspace proof'},
            'avb_policy': 'no bytes changed, removed, resigned or trusted'}


def read_regular(path, maximum):
    # Refuse devices, pipes and symlinks; never use this tool on a partition.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode), 'input must be an ordinary non-symlink file')
        require(0 < info.st_size <= maximum, 'input size limit')
        data = stream.read(maximum + 1)
        require(len(data) == info.st_size, 'input changed length during read')
        return data


def write_new(path, data):
    # Exclusive creation also rejects aliases, hard links, symlinks and devices.
    # Never truncate an existing file, including a previous output.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        os.unlink(path)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    pack = sub.add_parser('pack', help='create NONBOOTABLE carrier, never a flashable image')
    pack.add_argument('--original', required=True, type=Path)
    pack.add_argument('--payload', required=True, type=Path, help='raw ARM64 payload, not boot.img')
    pack.add_argument('--output', required=True, type=Path)
    for name in ('inspect', 'restore'):
        command = sub.add_parser(name)
        command.add_argument('carrier', type=Path)
        if name == 'restore':
            command.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            require(args.output.suffix == '.bootcarrier', 'output must end in .bootcarrier, not .img')
            original = read_regular(args.original, LIMIT)
            payload = read_regular(args.payload, LIMIT)
            result = make_carrier(original, payload)
            report = inspect(result)
            write_new(args.output, result)
        else:
            carrier = read_regular(args.carrier, LIMIT * 2 + HEADER.size)
            report = inspect(carrier)
            if args.command == 'restore':
                original, _ = unpack(carrier)
                write_new(args.output, original)
        print(json.dumps(report, indent=2))
    except (ValueError, OSError) as error:
        parser.exit(1, f'error: {error}\n')


if __name__ == '__main__':
    main()
