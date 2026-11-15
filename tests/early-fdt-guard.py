#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Execute the freestanding parser against real serialized FDT token streams."""
import ctypes as C
from pathlib import Path
import struct as S
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
U32=lambda x:S.pack('>I', x)
U64=lambda x:S.pack('>Q', x)
PAD=lambda x:x+b'\0'*((-len(x))%4)
class Range(C.Structure):
    _fields_=[('base',C.c_uint64),('size',C.c_uint64)]
class Framebuffer(C.Structure):
    _fields_=[('base',C.c_uint64),('size',C.c_uint64),('width',C.c_uint32),('height',C.c_uint32),('stride',C.c_uint32),('rgb32',C.c_uint)]
class Handoff(C.Structure):
    _fields_=[('initrd',Range),('fb',Framebuffer),('model',C.c_void_p),('compatible',C.c_void_p),('board_id',C.c_void_p),('model_len',C.c_size_t),('compatible_len',C.c_size_t),('board_id_len',C.c_size_t),('bootargs',C.c_void_p),('bootargs_len',C.c_size_t)]
class Display(C.Structure):
    _fields_=[('fb',Framebuffer),('reservation',Range),('name',C.c_char_p),('matches',C.c_void_p)]
class Input(C.Structure):
    _fields_=[('blob',C.c_void_p),('mapped',C.c_size_t),('pa',C.c_uint64),
              ('banks',C.POINTER(Range)),('count',C.c_size_t),('image',Range),
              ('workspace',Range),('live',C.POINTER(Range)),('live_count',C.c_size_t),('allow_dynamic',C.c_void_p),('display',C.c_void_p),('handoff',C.c_void_p)]
def fixture(extra=(), reserve=(), mem=(0x80000000,0x10000000), cells=2):
    strings=bytearray(); tokens=bytearray()
    def begin(name): tokens.extend(U32(1)+PAD(name.encode()+b'\0'))
    def prop(name,data):
        off=len(strings); strings.extend(name.encode()+b'\0')
        tokens.extend(U32(3)+U32(len(data))+U32(off)+PAD(data))
    def end(): tokens.extend(U32(2))
    begin(''); prop('#address-cells',U32(cells)); prop('#size-cells',U32(2))
    begin('memory@80000000'); prop('device_type',b'memory\0'); prop('reg',U64(mem[0])+U64(mem[1])); end()
    for name,props,children in extra:
        begin(name)
        for k,v in props: prop(k,v)
        for cn,cp in children:
            begin(cn)
            for k,v in cp: prop(k,v)
            end()
        end()
    end(); tokens.extend(U32(9))
    r=b''.join(U64(a)+U64(b) for a,b in reserve)+b'\0'*16
    so=40+len(r); st=so+len(tokens); total=st+len(strings)
    return bytearray(b''.join(U32(x) for x in (0xd00dfeed,total,so,st,40,17,16,0,len(strings),len(tokens)))+r+tokens+strings)
class Guard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(); so=Path(cls.tmp.name)/'guard.so'
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC','-O2',
                        str(ROOT/'tools/early-entry/fdt-guard.c'),'-o',str(so)],check=True)
        cls.lib=C.CDLL(str(so)); cls.lib.eg_fdt_guard.argtypes=[C.POINTER(Input)]
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def check(self,data,expected=0,pa=0x81000000,mapped=None,live=(),image=None,allow=None,handoff=None,display=None):
        blob=C.create_string_buffer(bytes(data)); banks=(Range*1)(Range(0x80000000,0x10000000))
        live=(Range*len(live))(*(Range(*r) for r in live))
        i=Input(C.cast(blob,C.c_void_p),len(data) if mapped is None else mapped,pa,banks,1,
                Range(*(image or (0x82000000,0x400000))),Range(0x82300000,0x100000),live,len(live),C.cast(allow,C.c_void_p) if allow else None)
        if display is not None:i.display=C.addressof(display)
        if handoff is not None:i.handoff=C.addressof(handoff)
        self.assertEqual(self.lib.eg_fdt_guard(C.byref(i)),expected)
    def test_valid(self): self.check(fixture(),1)
    def test_framebuffer_descriptor(self):
        for fmt,valid in [(b'a8r8g8b8',1),(b'x8b8g8r8',4),(b'r5g6b5',0)]:
            out=Handoff()
            props=[('compatible',b'simple-framebuffer\0'),('reg',U64(0x88000000)+U64(0x2000000)),
                   ('width',U32(1440)),('height',U32(3168)),('stride',U32(5760)),('format',fmt+b'\0')]
            self.check(fixture(extra=[('framebuffer@88000000',props,())]),1,handoff=out)
            self.assertEqual(out.fb.rgb32,valid)
            if valid:self.assertEqual((out.fb.base,out.fb.size,out.fb.width,out.fb.height,out.fb.stride),
                                     (0x88000000,0x2000000,1440,3168,5760))
        # Descriptor extraction never weakens workspace protection.
        props[1]=('reg',U64(0x82300000)+U64(0x100000))
        self.check(fixture(extra=[('framebuffer@82300000',props,())]),0)
    def test_explicit_display(self):
        match=C.CFUNCTYPE(C.c_int,C.c_void_p)(lambda h:1)
        d=Display(Framebuffer(0x88000000,0x10000,64,64,256,1),Range(0x88000000,0x20000),b'scanout',C.cast(match,C.c_void_p))
        data=fixture(extra=[('reserved-memory',[('#address-cells',U32(2)),('#size-cells',U32(2)),('ranges',b'')],[('scanout',[('reg',U64(0x88000000)+U64(0x20000))])])])
        out=Handoff();self.check(data,1,display=d,handoff=out);self.assertEqual(out.fb.base,0x88000000)
        self.check(fixture(),0,display=d)
        self.check(data,0,display=d,live=[(0x88000000,1)])
        for field,value in [('base',0xfffffffffffffff0),('stride',0xffffffff),('rgb32',99),('height',8193),('size',0x30000)]:
            old=getattr(d.fb,field);setattr(d.fb,field,value);self.check(data,0,display=d);setattr(d.fb,field,old)
        reject=C.CFUNCTYPE(C.c_int,C.c_void_p)(lambda h:0);d.matches=C.cast(reject,C.c_void_p);self.check(data,0,display=d)
    def test_header(self):
        for off,val in [(0,0),(4,0xffffffff),(8,0xfffffffc),(12,40),(16,41),(20,18),(36,0xfffffffc)]:
            with self.subTest(off=off):
                b=fixture(); b[off:off+4]=U32(val); self.check(b)
        self.check(fixture(),mapped=39); self.check(fixture(),pa=0x8ffffff0)
    def test_geometry(self):
        self.check(fixture(cells=1)); self.check(fixture(mem=(0x80000000,0x1000)))
        self.check(fixture(mem=(0xfffffffffffffff0,0x100)))
        self.check(fixture(),image=(0xffffffffffff0000,0x20000))
    def test_reservations(self):
        self.check(fixture(reserve=[(0x82301000,0x1000)]))
        self.check(fixture(reserve=[(0xfffffffffffffff0,0x100)]))
        self.check(fixture(reserve=[(0x83000000,0x1000)]),1)
        b=fixture(); b[40:56]=U64(0x83000000)+U64(0x1000); self.check(b)
    def test_live_and_fdt(self):
        self.check(fixture(),pa=0x82300000)
        self.check(fixture(),live=[(0x82310000,0x10)])
        self.check(fixture(),live=[(0x83000000,0x10)],expected=1)
    def test_chosen(self):
        def dt(a,b): return fixture([('chosen',[('linux,initrd-start',a),('linux,initrd-end',b)],[])])
        self.check(dt(U64(0x83000000),U64(0x83100000)),1)
        self.check(dt(U64(0x82300000),U64(0x82400000)))
        self.check(dt(U64(10),U64(9))); self.check(dt(U32(1),U64(2)))
        self.check(fixture([('chosen',[('linux,initrd-start',U64(1))],[])]))
    def test_reserved_memory(self):
        def dt(props,more=()): return fixture([('reserved-memory',[
            ('#address-cells',U32(2)),('#size-cells',U32(2)),('ranges',b'')]+list(more),[('pool',props)])])
        self.check(dt([('reg',U64(0x83000000)+U64(0x1000))]),1)
        self.check(dt([('reg',U64(0x82300000)+U64(0x1000))]))
        self.check(dt([('size',U64(0x1000))])); self.check(dt([('reg',b'1234')]))
        self.check(dt([('reg',U64(0x83000000)+U64(1))],[('ranges',b'1234')]))
    def test_dynamic_policy_and_zero_reg(self):
        class Dynamic(C.Structure):
            _fields_=[('name',C.c_void_p),('compatible',C.c_void_p),
                ('name_len',C.c_size_t),('compatible_len',C.c_size_t),
                ('size',C.c_uint64),('no_map',C.c_uint),('reusable',C.c_uint),
                ('alignment',C.c_void_p),('alloc_ranges',C.c_void_p),
                ('alignment_len',C.c_size_t),('alloc_ranges_len',C.c_size_t)]
        @C.CFUNCTYPE(C.c_int,C.POINTER(Dynamic))
        def allow(ptr):
            n=ptr.contents
            return int(C.string_at(n.name,n.name_len)==b'pool' and n.size==4096 and
                C.string_at(n.compatible,n.compatible_len)==b'shared-dma-pool\0' and n.reusable and not n.no_map and
                n.alignment_len==8 and C.string_at(n.alignment,8)==U64(4096) and
                n.alloc_ranges_len==16 and C.string_at(n.alloc_ranges,16)==U64(0x80000000)+U64(0x10000000))
        def dt(name='pool',size=4096,extra=()):
            return fixture([('reserved-memory',[('#address-cells',U32(2)),
                ('#size-cells',U32(2)),('ranges',b'')],[(name,[('size',U64(size)),
                ('compatible',b'shared-dma-pool\0'),('reusable',b''),
                ('alignment',U64(4096)),('alloc-ranges',U64(0x80000000)+U64(0x10000000))]+list(extra))])])
        self.check(dt())
        self.check(dt(),1,allow=allow)
        self.check(dt('unknown'),allow=allow)
        self.check(dt(size=8192),allow=allow)
        for prop,values in [('alignment',[b'',U32(1),U64(8192)]),
                            ('alloc-ranges',[b'',U64(1),U64(0)+U64(1)])]:
            for value in values:
                self.check(dt(extra=[(prop,value)]),allow=allow) # duplicate
                # Also malformed/changed first property, not only duplicates.
                self.check(fixture([('reserved-memory',[('#address-cells',U32(2)),
                    ('#size-cells',U32(2)),('ranges',b'')],[('pool',[
                    ('size',U64(4096)),('compatible',b'shared-dma-pool\0'),
                    ('reusable',b''),(prop,value)])])]),allow=allow)
        self.check(dt(extra=[('reg',U64(0)+U64(0))]),allow=allow)
        self.check(dt(extra=[('size',U64(4096))]),allow=allow)
        self.check(fixture([('reserved-memory',[('#address-cells',U32(2)),
            ('#size-cells',U32(2)),('ranges',b'')],[('empty',
            [('reg',U64(0xffffffffffffffff)+U64(0))])])]),1)
    def test_framebuffer(self):
        for base,expected in [(0x83000000,1),(0x82300000,0)]:
            self.check(fixture([('framebuffer',[('compatible',b'simple-framebuffer\0'),
                 ('reg',U64(base)+U64(0x1000))],[])]),expected)
        self.check(fixture([('bus',[],[('fb',[('compatible',b'simple-framebuffer\0'),('reg',U64(0x83000000)+U64(1))])])]))
    def test_tokens_strings(self):
        b=fixture(); so=S.unpack_from('>I',b,8)[0]
        b[so:so+4]=U32(99); self.check(b)
        b=fixture(); b[-1]=65; self.check(b)
        b=fixture(); b[so+16:so+20]=U32(0xffffffff); self.check(b)
        for n in range(40,len(fixture())): self.check(fixture()[:n])
    def test_structural_rejects(self):
        self.check(fixture([('chosen',[],[]),('chosen',[],[])]))
        self.check(fixture([('reserved-memory@0',[],[])]))
        self.check(fixture([('other',[('device_type',b'memory\0')],[])]))
        self.check(fixture([('framebuffer',[('compatible',b'simple-framebuffer')],[])]))
        self.check(fixture([('chosen',[('#address-cells',U32(2)),('#size-cells',U32(2)),
            ('ranges',U32(1))],[('fb',[('compatible',b'simple-framebuffer\0'),
            ('reg',U64(0x83000000)+U64(1))])])]))
        b=fixture(); so=S.unpack_from('>I',b,8)[0]; st=S.unpack_from('>I',b,12)[0]
        # Missing root END_NODE, unexpected END_NODE, invalid property name offset.
        for off,val in [(st-8,4),(so,2),(so+16,0xfffffffc)]:
            m=bytearray(b); m[off:off+4]=U32(val); self.check(m)
        # A self-contained overdeep token stream: bounded before node array access.
        tokens=(U32(1)+b'\0'*4)*33+(U32(2)*33)+U32(9)
        head=b''.join(U32(x) for x in (0xd00dfeed,56+len(tokens),56,56+len(tokens),40,17,16,0,0,len(tokens)))
        self.check(head+b'\0'*16+tokens)
    def test_sanitizers(self):
        exe=Path(self.tmp.name)/'sanitized'
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-O1','-g',
            '-fsanitize=address,undefined','-fno-sanitize-recover=all',
            str(ROOT/'tests/early-fdt-guard-native.c'),
            str(ROOT/'tools/early-entry/fdt-guard.c'),'-o',str(exe)],check=True)
        complex_dt=fixture([('reserved-memory',[('#address-cells',U32(2)),
            ('#size-cells',U32(2)),('ranges',b'')],[('pool',[
            ('reg',U64(0x83000000)+U64(0x1000))])]),
            ('chosen',[('#address-cells',U32(2)),('#size-cells',U32(2)),
            ('linux,initrd-start',U64(0x84000000)),('linux,initrd-end',U64(0x84100000))],
            [('fb',[('compatible',b'simple-framebuffer\0'),
                    ('reg',U64(0x85000000)+U64(0x1000))])])],reserve=[(0x86000000,0x1000)])
        self.check(complex_dt,1)
        for data in (fixture(),complex_dt):
            result=subprocess.run([str(exe)],input=data,capture_output=True,check=True)
            self.assertIn(b'every-bit mutations passed',result.stdout)
    def test_mutations(self):
        # Every byte/bit mutation is run against an allocation of exactly totalsize.
        b=fixture()
        for i in range(len(b)):
            for bit in (1,128):
                m=bytearray(b); m[i]^=bit
                blob=C.create_string_buffer(bytes(m)); banks=(Range*1)(Range(0x80000000,0x10000000))
                inp=Input(C.cast(blob,C.c_void_p),len(m),0x81000000,banks,1,Range(0x82000000,0x400000),Range(0x82300000,0x100000),None,0)
                self.assertIn(self.lib.eg_fdt_guard(C.byref(inp)),(0,1))
if __name__=='__main__': unittest.main()
