#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate Dodge's OEM A1901 ACF and extract its two Music register tables.

Container definitions: Linux sound/soc/codecs/aw88395/aw88395_data_type.h.
OEM format/checks:
https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750/blob/d50b305f7da9e14715a25120a4ac7b1a4b8b97c3/vendor/oplus/kernel/audio/codecs/aw882xx/aw882xx_bin_parse.c
"""
import argparse
from pathlib import Path
import struct

HEADER = struct.Struct('<I24s16s4s8I')
ENTRY = struct.Struct('<I16s4H9I')
REGISTERS = (*range(3, 0x20), *range(0x30, 0x39), *range(0x3a, 0x40), *range(0x50, 0x6e))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def crc8(data):
    crc = 0
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = (crc >> 1) ^ (0x8c if crc & 1 else 0)
    return crc


def extract(data):
    require(len(data) >= HEADER.size, 'truncated ACF header')
    ident, project, customer, version, author, size, count, offset, hdrver, *reserved = HEADER.unpack_from(data)
    require((ident, project.rstrip(b'\0'), customer.rstrip(b'\0'), version, author, size, count, offset, hdrver)
            == (0x0a15f908, b'A1901', b'awinic', b'\0\0\0\5', 2421, 256, 4, 80, 1), 'unsupported Dodge ACF header')
    require(not any(reserved), 'unexpected ACF header fields')
    require(offset + size <= len(data), 'truncated descriptor table')
    tables = {}
    ranges = []
    profiles = set()
    for index in range(count):
        kind, name, channel, bus, address, profile, dtype, length, start, crc, *res = ENTRY.unpack_from(data, offset + index * ENTRY.size)
        require((kind, name.rstrip(b'\0'), bus, address, dtype, length) == (2, b'aw88461', 0xffff, 0xffff, 4, 364), 'unsupported ACF descriptor')
        require(not any(res) and channel in (0, 1) and profile in (0, 10), 'unexpected ACF profile')
        require((channel, profile) not in profiles, 'duplicate ACF profile')
        profiles.add((channel, profile))
        require(start >= offset + size and start + length <= len(data), 'invalid ACF section extent')
        require(all(start >= end or start + length <= begin for begin, end in ranges), 'overlapping ACF sections')
        ranges.append((start, start + length))
        section = data[start:start + length]
        require(crc <= 255 and crc8(section) == crc, 'ACF section CRC mismatch')
        checksum, headerver, datatype, dataver, datalen, ui, chip, regwidth, valwidth, devaddr, *reserved_bin = struct.unpack_from('<6I8s3I4I', section)
        require(checksum == sum(section[4:]) & 0xffffffff, 'register binary checksum mismatch')
        require((headerver, datatype, dataver, datalen, chip.rstrip(b'\0'), regwidth, valwidth)
                == (0x01000000, 0, 1, 304, b'AW88461', 2, 2), 'unsupported register binary')
        require(not any(reserved_bin), 'unexpected binary header fields')
        require(struct.unpack_from('<I', section, 60)[0] == 75, 'incorrect register count')
        pairs = list(struct.iter_unpack('<HH', section[64:]))
        require(pairs[-1] == (0xff, 0), 'missing terminal metadata marker')
        pairs.pop()
        require(tuple(reg for reg, _ in pairs) == REGISTERS, 'incomplete or unsupported register table')
        require((dict(pairs)[6] >> 10) & 3 == channel + 1, 'wrong I2S channel')
        if profile == 0:
            tables[0x34 + channel] = b''.join(struct.pack('<HH', *pair) for pair in pairs)
    require(profiles == {(0, 0), (0, 10), (1, 0), (1, 10)}, 'missing profiles')
    require(sorted(ranges) == [(336, 700), (700, 1064), (1064, 1428), (1428, 1792)] and len(data) == 1792, 'unexpected trailing/gap data')
    return tables


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('acf', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        tables = extract(args.acf.read_bytes())
    except ValueError as error:
        parser.error(str(error))
    args.output.mkdir(parents=True, exist_ok=True)
    for address, table in tables.items():
        (args.output / f'aw882308-{address:02x}.bin').write_bytes(table)


if __name__ == '__main__':
    main()
