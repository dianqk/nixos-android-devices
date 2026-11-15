#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Production initrd parser: raw flat vendor text + SYNTHETIC runtime/trailer.

Fixture contains generic build-time assignments only. This is not a captured
OEM initrd/trailer, nor proof of bootloader concatenation on any device.
"""
import ctypes as C
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get('BOOTCONFIG_SOURCE', ROOT/'tools/early-entry/bootconfig.c'))
RAW = (ROOT/'tests/fixtures/bootconfig-flat.conf').read_bytes()

def frame(text, pad=0):
    return b'ramfs'+text+struct.pack('<II', len(text), sum(text))+b'#BOOTCONFIG\n'+bytes(pad)

class Bootconfig(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(); cls.w = Path(cls.tmp.name)
        subprocess.run(['cc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror',
                        '-I'+str(ROOT/'tools/early-entry'),str(SOURCE),'-o',str(cls.w/'parser.so')],check=True)
        cls.parse = C.CDLL(str(cls.w/'parser.so')).eg_bootconfig_slot
        cls.parse.argtypes = [C.c_void_p,C.c_size_t]
        class Report(C.Structure):
            _fields_=[('error',C.c_uint),('byte',C.c_uint),('offset',C.c_size_t)]
        cls.Report=Report
        cls.report=C.CDLL(str(cls.w/'parser.so')).eg_bootconfig_slot_report
        cls.report.argtypes=[C.c_void_p,C.c_size_t,C.POINTER(Report)]
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def check(self, data, want):
        buf=C.create_string_buffer(data); before=buf.raw
        self.assertEqual(self.parse(buf,len(data)),want,repr(data[:150]))
        r=self.Report(99,99,99)
        self.assertEqual(self.report(buf,len(data),C.byref(r)),want)
        self.assertEqual(r.error==0,bool(want))
        if not want:
            self.assertLessEqual(r.offset,len(data))
            self.assertEqual(r.byte,data[r.offset] if r.offset<len(data) else 0)
        self.assertEqual(buf.raw,before)
    def test_report_reasons_and_offsets(self):
        good=b'androidboot.slot_suffix=_a\n'
        cases=[(b'',1),(frame(good)[:-1]+b'x',2),
               (frame(good)+b'x',3),(frame(b''),4),
               (frame(b'foo=x\n'),14),
               (frame(good+b'.foo=x\n'),8),(frame(good+b'foo:x\n'),9),
               (frame(good+b'foo=\xff\n'),10),(frame(good+good),11),
               (frame(b'androidboot.slot_suffix=_c\n'),12),
               (frame(good+b'foo="x"bad\n'),13)]
        bad=bytearray(frame(good));bad[-20:-16]=struct.pack('<I',0xffffffff)
        cases.append((bytes(bad),4))
        bad=bytearray(frame(good));bad[-20:-16]=struct.pack('<I',len(good)+6)
        cases.append((bytes(bad),5))
        bad=bytearray(frame(good));bad[-16]^=1;cases.append((bytes(bad),6))
        for data,error in cases:
            self.check(data,0)
            r=self.Report();buf=C.create_string_buffer(data)
            self.assertEqual(self.report(buf,len(data),C.byref(r)),0)
            self.assertEqual(r.error,error,repr(data))
        data=frame(good+b'foo=\xff\n');buf=C.create_string_buffer(data);r=self.Report()
        self.report(buf,len(data),C.byref(r))
        self.assertEqual(r.offset,data.index(b'\xff'));self.assertEqual(r.byte,255)
        r=self.Report(99,99,99)
        self.assertEqual(self.report(None,100,C.byref(r)),0)
        self.assertEqual((r.error,r.offset,r.byte),(1,0,0))
    def test_raw_build_time_with_synthetic_slot(self):
        for suffix,want in [(b'_a',1),(b'_b',2)]:
            for value in [suffix,b'"'+suffix+b'"']:
                for pad in range(4):
                    self.check(frame(RAW+b'androidboot.slot_suffix='+value+b'\n\0',pad),want)
        self.check(frame(RAW+b'\0'),0) # no fabricated default
    def test_whitespace_and_quoted_spaces(self):
        self.check(frame(b' \tfoo = "two words" \t\n\n\tandroidboot.slot_suffix\t=\t_a \t\n\0'),1)
        self.check(frame(b'androidboot.slot_suffix="_b"'),2)
        self.check(frame(b'androidboot.slot_suffix=_a\0\0'),1)
    def test_kernel_nul_terminates_text_not_checksum(self):
        # User observed old reason07 and byteB7 near the payload end. These
        # inputs model that condition, NOT a captured OEM raw initrd.
        for slot,want in [(b'_a',1),(b'_b',2)]:
            good=b'androidboot.slot_suffix='+slot
            for ending in [b'\0',b'\n\0',b'\nfoo=x\0',b'\nfoo="x"\0']:
                for tail in [b'\xb7',bytes(range(256)),b'androidboot.slot_suffix=_c\n',
                             b'androidboot.slot_suffix=_a\nandroidboot.slot_suffix=_b\n']:
                    valid=frame(good+ending+tail)
                    self.check(valid,want)
                    # Opaque suffix is still fully covered by the checksum.
                    bad=bytearray(valid);bad[-21]^=1;self.check(bytes(bad),0)
            # Slot/valid text AFTER NUL must never grant slot provenance.
            self.check(frame(b'foo=x\n\0'+good+b'\n'),0)
            self.check(frame(b'\0'+good+b'\n'),0)
            # NUL does not rescue incomplete grammar before it.
            self.check(frame(good+b'\nfoo="unterminated\0"\n'),0)
            self.check(frame(b'androidboot.slot_suffix=\0'+slot),0)
            self.check(frame(b'androidboot.slot_suffix="'+slot+b'\0"'),0)
            self.check(frame(good+b'\n'+good+b'\n\0\xb7'),0)
    def test_duplicates_and_unsupported_grammar(self):
        good=b'androidboot.slot_suffix=_a\n'
        for extra in [good,b'androidboot.slot_suffix="_a"\n',b'androidboot.slot_suffix=_b\n',
                      b'androidboot.slot_suffix+=_b\n',b'androidboot.slot_suffix:=_b\n',
                      b'androidboot..slot_suffix=_b\n',b'androidboot.slot_suffix.=_b\n',
                      b'.androidboot.slot_suffix=_b\n',b'androidboot { slot_suffix=_b; }\n',
                      b'foo=x # comment\n',b'foo=x;bar=y\n',b'foo=x,y\n',b'foo=[x]\n',b'foo=x=y\n',
                      b'foo="x" trailing\n',b'foo=two words\n',b'foo=\n',b'foo="unterminated\n',
                      b'foo=x\\\ny\n',b'foo=\xff\n',b'foo=x\r\n']:
            self.check(frame(good+extra+b'\0'),0)
        for value in [b'_c',b'a',b'_aa',b'"_a "',b"'_a'",b'',b'"_a\\"']:
            self.check(frame(b'androidboot.slot_suffix='+value+b'\n\0'),0)
        self.check(frame(b'other.androidboot.slot_suffix=_a\n\0'),0)
    def test_framing_and_bounds(self):
        valid=frame(b'androidboot.slot_suffix=_a\n\0')
        for n in range(20): self.check(bytes(n),0)
        self.check(valid+b'\x01',0); self.check(valid+bytes(4),0)
        for offset in [-1,-13,-17]:
            bad=bytearray(valid); bad[offset]^=1; self.check(bytes(bad),0)
        for size in [0,32767,0xffffffff]:
            bad=bytearray(valid);struct.pack_into('<I',bad,len(bad)-20,size);self.check(bytes(bad),0)
        self.check(frame(b'x'*32767),0)
        # Prefixes may be arbitrary ramdisk bytes; truncated trailers must fail.
        for n in range(1,20): self.check(valid[:-n],0)
    def test_sanitized_short_ranges(self):
        (self.w/'san.c').write_text('''#include "bootconfig.h"
#include <assert.h>
#include <string.h>
int main(void){unsigned char b[128]={0};
for(unsigned n=0;n<128;n++)assert(!eg_bootconfig_slot(b,n));
memcpy(b+108,"#BOOTCONFIG\\n",12);memset(b+100,255,8);
assert(!eg_bootconfig_slot(b,120));return 0;}''')
        subprocess.run(['cc','-fsanitize=address,undefined','-I'+str(ROOT/'tools/early-entry'),str(self.w/'san.c'),str(SOURCE),'-o',str(self.w/'san')],check=True)
        subprocess.run([str(self.w/'san')],check=True)

if __name__=='__main__': unittest.main()
