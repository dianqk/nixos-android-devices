#!/usr/bin/env python3
"""Exercise the stock-table decoder's trust boundaries without vendor binaries."""
import importlib.util
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('camera_tables', ROOT / 'tools/unicorn-camera-tables.py')
tables = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tables)


def container(entries):
    symbols = bytearray()
    payload = bytearray()
    for ident, name, data in entries:
        symbols += tables.SYMBOL.pack(ident, name.encode(), 0, 0, -1, len(payload), len(data))
        payload += data
    header = bytearray(204)
    header[:21] = b'QTI Chromatix Header\0'
    struct.pack_into('<II', header, 0xa0, 168, 3)
    struct.pack_into('<III', header, 168, 0, 204, len(symbols))
    struct.pack_into('<III', header, 180, 1, 204 + len(symbols), len(payload))
    struct.pack_into('<III', header, 192, 2, 204 + len(symbols) + len(payload), 0)
    data = header + symbols + payload + bytes(4)
    struct.pack_into('<I', data, 0x1c, len(data) - 4)
    return data


def registers(**overrides):
    fields = dict(slave=0, slave_ref=2, addr=0x1234, count=1, value_ref=3,
                  addr_width=2, data_width=1, operation=0, delays=1, delay_ref=4)
    fields.update(overrides)
    record = struct.pack('<10I', *fields.values())
    return container([(1, 'regSetting', record), (2, 'slaveAddr', b''),
                      (3, 'registerData', struct.pack('<I', 0x56)),
                      (4, 'delayUs', struct.pack('<I', 123))])


class DecoderTest(unittest.TestCase):
    def test_preserves_width_and_delay(self):
        self.assertEqual(tables.Module(registers()).registers(1, 1), [(0x1234, 0x56, 1, 123)])
        self.assertEqual(tables.Module(registers(data_width=2)).registers(1, 1), [(0x1234, 0x56, 2, 123)])

    def test_rejects_non_write_operations_and_bursts(self):
        for change in [dict(operation=1), dict(operation=3), dict(count=2),
                       dict(slave=0x20), dict(addr_width=1), dict(data_width=4),
                       dict(addr=0x10000), dict(delays=0)]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                tables.Module(registers(**change)).registers(1, 1)

    def test_rejects_register_count_mismatch(self):
        with self.assertRaises(ValueError):
            tables.Module(registers()).registers(1, 2)

    def test_rejects_duplicate_symbols(self):
        with self.assertRaises(ValueError):
            tables.Module(container([(1, 'first', b''), (1, 'second', b'')]))

    def test_rejects_out_of_bounds_payload(self):
        data = registers()
        struct.pack_into('<I', data, 204 + 52, len(data))
        with self.assertRaises(ValueError):
            tables.Module(data)

    def test_rejects_truncation_and_bad_header(self):
        for data in [registers()[:-1], bytearray(204)]:
            with self.assertRaises(ValueError):
                tables.Module(data)

    def test_rejects_reference_with_wrong_symbol_type(self):
        with self.assertRaises(ValueError):
            tables.Module(registers(value_ref=4)).registers(1, 1)


if __name__ == '__main__':
    unittest.main()
