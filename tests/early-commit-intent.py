#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host-only selection context and immutable FDT copy; no storage backend."""
import ctypes as C
import importlib.util
import os
from pathlib import Path
import struct as S
import subprocess
import tempfile
import unittest
import zlib
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('fixture',ROOT/'tests/early-fdt-guard.py')
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
PROP=b'android-devices,boot-choice-intent\0'
class Observation(C.Structure):
    _fields_=[('sequence',C.c_uint64),('mode',C.c_uint)]
def record(g,seq,mode):
    p=bytearray(4096);p[:8]=b'BOOTREQ1';S.pack_into('<I',p,8,1);p[12:44]=g
    S.pack_into('<QII',p,44,seq,mode,0);S.pack_into('<I',p,60,zlib.crc32(p));return p
class Intent(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();cls.w=Path(cls.tmp.name)
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC','-O2',
                        *[str(ROOT/'tools/early-entry'/n) for n in ['request-observe.c','commit-intent.c','fdt-intent.c']],
                        '-o',str(cls.w/'intent.so')],check=True)
        cls.lib=C.CDLL(str(cls.w/'intent.so'));cls.g=bytes(range(32))
        cls.lib.eg_choice_route.argtypes=[C.POINTER(Observation),C.c_uint]
        cls.lib.eg_request_observe.argtypes=[C.c_void_p,C.c_void_p,C.POINTER(Observation)]
        cls.lib.eg_intent_encode.argtypes=[C.c_void_p,C.c_void_p,C.POINTER(Observation),C.c_uint]
        cls.lib.eg_intent_decode.argtypes=[C.c_void_p,C.c_void_p,C.POINTER(Observation),C.POINTER(C.c_uint)]
        cls.lib.eg_fdt_copy_intent.argtypes=[C.c_void_p,C.c_size_t,C.c_void_p,C.c_size_t,C.c_void_p]
        cls.lib.eg_fdt_copy_intent.restype=C.c_size_t
    @classmethod
    def tearDownClass(cls):cls.tmp.cleanup()
    def token(self,stored=1,selected=0,seq=7):
        out=C.create_string_buffer(80)
        self.assertEqual(self.lib.eg_intent_encode(out,self.g,C.byref(Observation(seq,stored)),selected),1)
        return out.raw
    def test_routes(self):
        for stored,selected,want in [(0,0,0),(1,1,1),(1,0,2),(0,1,3)]:
            self.assertEqual(self.lib.eg_choice_route(C.byref(Observation(9,stored)),selected),want)
            self.assertEqual(self.lib.eg_choice_route(C.byref(Observation(2**64-1,stored)),selected),want if stored==selected else 4)
        for seq,mode,selected in [(0,0,1),(1,2,0),(1,0,2)]:
            self.assertEqual(self.lib.eg_choice_route(C.byref(Observation(seq,mode)),selected),4)
    def test_observation(self):
        a=record(self.g,7,1);b=record(self.g,8,0);o=Observation(123,9)
        for data,ok,seq,mode in [(a+b,1,8,0),(a+bytes(4096),1,7,1),
                                (bytes(4096)+b,1,8,0),(a+a,0,0,0),
                                (bytes(8192),0,0,0),(record(bytes(32),1,1)*2,0,0,0)]:
            self.assertEqual(self.lib.eg_request_observe(bytes(data),self.g,C.byref(o)),ok)
            if ok:self.assertEqual((o.sequence,o.mode),(seq,mode))
        # CRC corruption, equal conflicting records and wrong generation refuse.
        a[70]=1
        for data in [a+a,record(self.g,8,1)+b,record(bytes([1])*32,1,1)*2]:
            self.assertEqual(self.lib.eg_request_observe(bytes(data),self.g,C.byref(o)),0)
    def test_token(self):
        t=self.token();o=Observation();s=C.c_uint()
        self.assertEqual(self.lib.eg_intent_decode(t,self.g,C.byref(o),C.byref(s)),1)
        self.assertEqual((o.sequence,o.mode,s.value),(7,1,0));self.assertEqual(t[68:76],bytes(8))
        for i in range(80):
            bad=bytearray(t);bad[i]^=1
            self.assertEqual(self.lib.eg_intent_decode(bytes(bad),self.g,C.byref(o),C.byref(s)),0)
        for offset,value in [(8,2),(12,81),(56,2),(60,1),(64,0),(68,1),(72,1)]:
            bad=bytearray(t);S.pack_into('<I',bad,offset,value);S.pack_into('<I',bad,76,0)
            S.pack_into('<I',bad,76,zlib.crc32(bad))
            self.assertEqual(self.lib.eg_intent_decode(bytes(bad),self.g,C.byref(o),C.byref(s)),0)
        self.assertEqual(self.lib.eg_intent_decode(t,bytes(32),C.byref(o),C.byref(s)),0)
        overlap=C.create_string_buffer(self.g+bytes(48),80)
        self.assertEqual(self.lib.eg_intent_encode(overlap,overlap,C.byref(Observation(7,1)),0),1)
        self.assertEqual(overlap.raw,t)
        for seq,mode,selected in [(0,1,0),(2**64-1,1,0),(1,2,0)]:
            out=C.create_string_buffer(b'x'*80,80)
            self.assertEqual(self.lib.eg_intent_encode(out,self.g,C.byref(Observation(seq,mode)),selected),0)
            self.assertEqual(out.raw,b'x'*80)
    def test_readonly_override(self):
        self.lib.eg_intent_encode_readonly.argtypes=[C.c_void_p,C.c_void_p,C.POINTER(Observation)]
        for mode in (0,1):
            for seq in (7,2**64-1):
                out=C.create_string_buffer(80)
                self.assertEqual(self.lib.eg_intent_encode_readonly(out,self.g,C.byref(Observation(seq,mode))),1)
                self.assertEqual(S.unpack_from('<III',out.raw,56),(mode,1,2))
                observed=Observation();selected=C.c_uint()
                self.assertEqual(self.lib.eg_intent_decode(out,self.g,C.byref(observed),C.byref(selected)),1)
                self.assertEqual((observed.sequence,observed.mode,selected.value),(seq,mode,1))
                bad=bytearray(out.raw);S.pack_into('<I',bad,60,0);S.pack_into('<I',bad,76,0)
                S.pack_into('<I',bad,76,zlib.crc32(bad))
                self.assertEqual(self.lib.eg_intent_decode(bytes(bad),self.g,C.byref(observed),C.byref(selected)),0)
    def test_noop(self):
        t=self.token(stored=1,selected=1,seq=2**64-1)
        self.assertEqual(S.unpack_from("<I",t,64)[0],0)
        o=Observation();selected=C.c_uint()
        self.assertEqual(self.lib.eg_intent_decode(t,self.g,C.byref(o),C.byref(selected)),1)
        self.assertEqual((o.sequence,o.mode,selected.value),(2**64-1,1,1))
    def copy(self,data,ok=True,capacity=2*1024*1024,mapped=None,misalign=False):
        src=C.create_string_buffer(bytes(data));dst=C.create_string_buffer(b'\xa5'*(2*1024*1024+32))
        address=C.addressof(dst)+16+int(misalign)
        n=self.lib.eg_fdt_copy_intent(src,len(data) if mapped is None else mapped,address,capacity,self.token())
        self.assertEqual(bool(n),ok)
        self.assertEqual(src.raw[:-1],bytes(data))
        self.assertEqual(dst.raw[:16],b'\xa5'*16)
        if not n:self.assertEqual(dst.raw[:-1],b'\xa5'*(2*1024*1024+32));return
        self.assertLessEqual(n,capacity);self.assertEqual(n%8,0)
        self.assertEqual(dst.raw[16+n:-1],b'\xa5'*(2*1024*1024+16-n))
        out=bytes(dst.raw[16:16+n]);self.check_inverse(bytes(data),out)
        return out
    def check_inverse(self,original,out):
        # Remove exactly the added property/name and undo four header words.
        so,st=S.unpack_from('>II',original,8);sn,ss=S.unpack_from('>II',original,32)
        newst=S.unpack_from('>I',out,12)[0];self.assertEqual(newst,st+92)
        marker=S.pack('>III',3,80,sn)+self.token()
        at=out.index(marker);self.assertEqual(out.count(marker),1)
        self.assertEqual(out[newst+sn:newst+sn+len(PROP)],PROP)
        stripped=bytearray(out[:at]+out[at+92:newst+sn]+out[newst+sn+len(PROP):])
        for off in [4,12,32,36]:stripped[off:off+4]=original[off:off+4]
        self.assertEqual(stripped[:len(original)],original)
        self.assertEqual(stripped[len(original):],bytes(len(stripped)-len(original)))
    def fixture(self,props=(),extra=()):
        return f.fixture(extra=[('chosen',[('bootargs',b'rootwait\0'),('linux,initrd-start',f.U64(0x88000000)),*props],()),*extra],reserve=[(0x90000000,4096)])
    def test_copy(self):
        out=self.copy(self.fixture());self.copy(out,False) # preexisting token
        self.copy(self.fixture(),False,capacity=128)
        self.copy(self.fixture(),False,misalign=True)
        self.copy(self.fixture(),False,mapped=39)
        self.copy(f.fixture(),False)
        self.copy(self.fixture(extra=[('chosen',[],())]),False)
        self.copy(self.fixture(props=[(PROP[:-1].decode(),bytes(80))]),False)
    def test_malformed(self):
        data=self.fixture()
        for off,val in [(0,0),(4,2**32-1),(8,41),(12,0),(16,41),(20,16),(24,18),(32,2**32-1),(36,2**32-1)]:
            bad=data.copy();S.pack_into('>I',bad,off,val);self.copy(bad,False)
        so=S.unpack_from('>I',data,8)[0]
        for val in [0,2,3,9,0xffffffff]:
            bad=data.copy();S.pack_into('>I',bad,so,val);self.copy(bad,False)
        for n in [0,39,len(data)-1]:self.copy(data[:n],False)
    def test_bounds_overlap(self):
        data=self.fixture();p=C.create_string_buffer(bytes(data)+bytes(1024));before=p.raw
        self.assertEqual(self.lib.eg_fdt_copy_intent(p,len(data),p,1024,self.token()),0)
        self.assertEqual(p.raw,before)
        out=C.create_string_buffer(b'\xa5'*(2*1024*1024+32))
        token=C.addressof(out)+16;C.memmove(token,self.token(),80);before=out.raw
        self.assertEqual(self.lib.eg_fdt_copy_intent(bytes(data),len(data),token,2*1024*1024,token),0)
        self.assertEqual(out.raw,before)
        # Largest permitted aligned output, retaining opaque source padding.
        limit=2*1024*1024;target=limit-92-len(PROP)
        data+=bytes(target-len(data));S.pack_into('>I',data,4,len(data))
        self.assertEqual(len(self.copy(data)),limit)
        data+=b'\0';S.pack_into('>I',data,4,len(data));self.copy(data,False)
    def test_real_fdt(self):
        path=os.environ.get('EARLY_INTENT_REAL_FDT')
        if not path:self.skipTest('set EARLY_INTENT_REAL_FDT to captured fixture (never read a device)')
        data=Path(path).read_bytes();self.copy(data)
if __name__=='__main__':unittest.main()
