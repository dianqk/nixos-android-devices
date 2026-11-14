#!/usr/bin/env python3
"""Validate and extract IMX707 register data from the owner's stock module.

QTI Parameter Parser v3 container; the Unicorn sensor schema uses 268-byte
resolution records and 40-byte register records. No Android code is executed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


SYMBOL = struct.Struct('<I32sIIiII')
STOCK_SHA256 = '4ab05c4d4d24856ed48e7f61845d1d025ac2ba3d8b5b7400ae2eb1346dee40fc'


def words(data):
    if len(data) % 4:
        raise ValueError('unaligned word array')
    return struct.unpack(f'<{len(data) // 4}I', data)


class Module:
    def __init__(self, data):
        if len(data) < 204 or not data.startswith(b'QTI Chromatix Header\0'):
            raise ValueError('invalid QTI header')
        declared, = struct.unpack_from('<I', data, 0x1c)
        if declared + 4 != len(data):
            raise ValueError('invalid declared file size')
        table, count = struct.unpack_from('<II', data, 0xa0)
        if count != 3 or table + count * 12 > len(data):
            raise ValueError('invalid section table')
        sections = [struct.unpack_from('<III', data, table + i * 12) for i in range(count)]
        for i, (sid, off, size) in enumerate(sections):
            if sid != i or off + size > declared or off < table + count * 12:
                raise ValueError('invalid section bounds')
            if i and off != sections[i - 1][1] + sections[i - 1][2]:
                raise ValueError('overlapping or non-contiguous sections')
        _, soff, ssize = sections[0]
        _, poff, psize = sections[1]
        if ssize % SYMBOL.size:
            raise ValueError('invalid symbol record size')
        self.entries = {}
        for off in range(soff, soff + ssize, SYMBOL.size):
            sid, name, _, _, _, start, size = SYMBOL.unpack_from(data, off)
            if sid in self.entries or start + size > psize:
                raise ValueError('duplicate symbol or invalid payload bounds')
            self.entries[sid] = (name.split(b'\0', 1)[0].decode('ascii'),
                                 data[poff + start:poff + start + size])

    def payload(self, ident, name):
        actual, data = self.entries[ident]
        if actual != name:
            raise ValueError(f'{ident}: expected {name}, found {actual}')
        return data

    def scalar(self, ident, name):
        data = self.payload(ident, name)
        if len(data) != 4:
            raise ValueError(f'{ident}: expected u32')
        return int.from_bytes(data, 'little')

    def registers(self, ident, count):
        data = self.payload(ident, 'regSetting')
        if len(data) != count * 40:
            raise ValueError('register count/size mismatch')
        result = []
        for off in range(0, len(data), 40):
            slave, slave_ref, addr, ndata, value_ref, aw, dw, op, ndelay, delay_ref = words(data[off:off + 40])
            # These modules contain scalar writes, not bursts, polls or reads.
            if slave or self.payload(slave_ref, 'slaveAddr') or aw != 2 or dw not in (1, 2) or op or ndata != 1 or ndelay != 1:
                raise ValueError(f'unsupported register operation at {ident}+{off}')
            value = self.scalar(value_ref, 'registerData')
            delay = self.scalar(delay_ref, 'delayUs')
            if addr > 0xffff or value >= 1 << (8 * dw):
                raise ValueError('register address/data overflow')
            result.append((addr, value, dw, delay))
        return result


def extract(path):
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != STOCK_SHA256:
        raise ValueError(f'unrecognized stock module SHA-256: {digest}')
    module = Module(data)
    driver = words(module.payload(1, 'sensorDriverData'))
    power_up = words(module.payload(driver[19], 'powerSetting'))
    power_down = words(module.payload(driver[21], 'powerSetting'))
    if len(power_up) != driver[18] * 3 or len(power_down) != driver[20] * 3:
        raise ValueError('invalid sensor power sequence')
    init_records = words(module.payload(3356, 'initSettings'))
    # Init settings are alternatives keyed by sensorVersion, never concatenated.
    version, count, ref, aon, aon_ref, pre, pre_ref = init_records[:7]
    if version != 0 or aon or pre or module.payload(aon_ref, 'aonInitSetting') or module.payload(pre_ref, 'preInitSetting'):
        raise ValueError('unsupported init settings variant')
    init = module.registers(ref, count)
    resolutions = module.payload(29, 'resolutionData')
    if len(resolutions) != 12 * 268:
        raise ValueError('unexpected resolution record size')
    mode = words(resolutions[268:536])
    regs = module.registers(mode[29], mode[28])
    streams = words(module.payload(mode[7], 'streamConfiguration'))
    if (mode[10], mode[11], mode[14], mode[21], mode[25]) != (13536, 6450, 1176140000, 3, 1):
        raise ValueError('unexpected IMX707 mode timing or bus')
    if streams[2:8] != (0x2b, 0, 0, 4096, 3072, 10) or streams[17] != 0x30:
        raise ValueError('unexpected RAW10/PDAF streams')
    def table(name, entries):
        lines = [f'static const struct unicorn_reg {name}[] = {{']
        lines += [f'\t{{ CCI_REG{width * 8}(0x{addr:04x}), 0x{val:04x}, {delay} }},'
                  for addr, val, width, delay in entries]
        return '\n'.join(lines + ['};', ''])
    header = ('/* SPDX-License-Identifier: GPL-2.0-only */\n'
              '/* Generated by tools/unicorn-camera-tables.py; stock mode index 1.\n'
              f' * Source SHA-256: {digest}\n */\n\n')
    header += table('imx707_init', init) + '\n' + table('imx707_mode', regs)
    provenance = dict(file=path.name, sha256=digest, mode=1,
                      init_writes=len(init), mode_writes=len(regs),
                      init_register_ids=[init_records[2]], sensor_version=version,
                      mode_register_id=mode[29],
                      power_up=[power_up[i:i + 3] for i in range(0, len(power_up), 3)],
                      power_down=[power_down[i:i + 3] for i in range(0, len(power_down), 3)],
                      hts=mode[10], vts=mode[11], output_pixel_clock=mode[14],
                      settle_field=mode[24], settle_register_count=mode[24], trios=mode[21],
                      auxiliary_data_type='0x30 (filtered by CSID RAW10 DT match)')
    return header, provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock_module', type=Path)
    parser.add_argument('--header', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    header, provenance = extract(args.stock_module)
    args.header.write_text(header)
    args.manifest.write_text(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    main()
